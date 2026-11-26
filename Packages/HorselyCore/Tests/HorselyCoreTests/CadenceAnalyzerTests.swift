// Testy CadenceAnalyzer — port testów Androida 3.0.2 `core/src/test/.../ride/CadenceAnalyzerTest.kt` (rytm i intensywność z okien
// akcelerometru): te same syntetyczne generatory, szum z deterministycznego generatora (SplitMix64 ze stałym ziarnem; Android używa
// innego LCG, więc wartości szumu są inne — asercje nie zależą od ziarna, zob. `noiseGivesNilCadence`).
// Pominięto test szumu kolorowego AR(1) na dokładnie 150 próbkach dla 20 ziaren: jego wynik zależy od konkretnego generatora.

import Testing
import Foundation
@testable import HorselyCore

private let gravity = 9.81

/// Deterministyczny generator SplitMix64 — wartości w [-1, 1).
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53) * 2.0 - 1.0
    }
}

private func ns(_ seconds: Double) -> Int64 { Int64((seconds * 1_000_000_000.0).rounded()) }

/// Telefon z grawitacją na osi z i drganiem pionowym o częstotliwości `hz` (amplituda `amplitude` m/s²).
private func sine(count: Int, hz: Double, amplitude: Double = 2.0, rateHz: Double = 50.0) -> [AccelSample] {
    (0..<count).map { i in
        let t = Double(i) / rateHz
        return AccelSample(tNanos: ns(t), x: 0, y: 0, z: Float(gravity + amplitude * sin(2.0 * Double.pi * hz * t)))
    }
}

private func expectCadence(_ motion: WindowMotion, near expected: Double, tolerance: Double = 2.0, _ note: String = "", sourceLocation: SourceLocation = #_sourceLocation) throws {
    let cadence = try #require(motion.cadence, "brak rytmu (nil). \(note)", sourceLocation: sourceLocation)
    #expect(abs(cadence - expected) <= tolerance, "rytm \(cadence), oczekiwano \(expected) ±\(tolerance). \(note)", sourceLocation: sourceLocation)
}

@Test func sineAt2_5HzGives150PerMinute() throws {
    let motion = CadenceAnalyzer.analyze(sine(count: 400, hz: 2.5))
    try expectCadence(motion, near: 150.0)
    // RMS sinusa o amplitudzie 2 m/s² to 2/sqrt(2).
    #expect(abs(motion.intensity - 2.0 / 2.0.squareRoot()) <= 0.05, "intensywność \(motion.intensity)")
}

@Test func sineAt2_5HzWithUnevenTimestampsStillGives150PerMinute() throws {
    // Odstępy na przemian 15 i 25 ms (średnio 20 ms), próbki wciąż leżą na tym samym sinusie.
    var t = 0.0
    var samples: [AccelSample] = []
    for i in 0..<400 {
        samples.append(AccelSample(tNanos: ns(t), x: 0, y: 0, z: Float(gravity + 2.0 * sin(2.0 * Double.pi * 2.5 * t))))
        t += i % 2 == 0 ? 0.015 : 0.025
    }
    try expectCadence(CadenceAnalyzer.analyze(samples), near: 150.0)
}

@Test func sineAtOtherRatesAndSampleFrequencyGivesMatchingCadence() throws {
    try expectCadence(CadenceAnalyzer.analyze(sine(count: 400, hz: 2.0)), near: 120.0)
    try expectCadence(CadenceAnalyzer.analyze(sine(count: 500, hz: 1.5)), near: 90.0)
    // Inna częstotliwość próbkowania (100 Hz) — wynik taki sam po przepróbkowaniu do 50 Hz.
    try expectCadence(CadenceAnalyzer.analyze(sine(count: 800, hz: 2.5, rateHz: 100.0)), near: 150.0)
}

@Test(arguments: [150, 200, 400])
func windowLengthsAllGive150PerMinute(count: Int) throws {
    try expectCadence(CadenceAnalyzer.analyze(sine(count: count, hz: 2.5)), near: 150.0, "n=\(count)")
}

@Test func signalWithStrongerHalfRateComponentGivesItsLongerPeriod() throws {
    // Składniki 2,5 Hz (amplituda 1,0) i 1,25 Hz (1,4): okres sygnału to 0,8 s, więc maksimum autokorelacji
    // jest przy 0,8 s (75/min); przy 0,4 s autokorelacja jest ujemna.
    let samples = (0..<500).map { i -> AccelSample in
        let t = Double(i) / 50.0
        let v = 1.0 * sin(2.0 * Double.pi * 2.5 * t) + 1.4 * sin(2.0 * Double.pi * 1.25 * t)
        return AccelSample(tNanos: ns(t), x: 0, y: 0, z: Float(gravity + v))
    }
    try expectCadence(CadenceAnalyzer.analyze(samples), near: 75.0)
}

@Test func globalMaximumWinsOverAnEarlierAlmostAsHighPeak() throws {
    // Okres 0,8 s z silną drugą harmoniczną (2,5 Hz, amplituda 1,5) i słabą podstawową (1,25 Hz, 0,24): po tłumieniu klasycznej
    // normalizacji maksimum globalne (okno 600 próbek) leży przy 0,8 s — literalne maksimum, nie „pierwszy szczyt”.
    let samples = (0..<600).map { i -> AccelSample in
        let t = Double(i) / 50.0
        let v = 1.5 * sin(2.0 * Double.pi * 2.5 * t) + 0.24 * sin(2.0 * Double.pi * 1.25 * t)
        return AccelSample(tNanos: ns(t), x: 0, y: 0, z: Float(gravity + v))
    }
    try expectCadence(CadenceAnalyzer.analyze(samples), near: 75.0)
}

@Test func noiseGivesNilCadence() {
    // Szum biały (500 próbek): znormalizowana autokorelacja dla przesunięć 15–75 ma odchylenie ok. 1/sqrt(500) ≈ 0,045, a maksimum
    // z 61 przesunięć to najwyżej ok. 3–4 odchylenia (≈ 0,15–0,2) — daleko poniżej progu 0,4 (ok. 9 odchyleń), więc wynik nie zależy
    // od ziarna generatora. Moduł wektora jest w przybliżeniu liniową funkcją szumu osi z (grawitacja 9,81 ≫ szum x, y), też białą.
    var rng = SplitMix64(seed: 42)
    var samples: [AccelSample] = []
    for i in 0..<500 {
        let x = Float(rng.next())
        let y = Float(rng.next())
        let z = Float(gravity + 2.0 * rng.next())
        samples.append(AccelSample(tNanos: ns(Double(i) / 50.0), x: x, y: y, z: z))
    }
    let motion = CadenceAnalyzer.analyze(samples)
    #expect(motion.cadence == nil, "rytm \(String(describing: motion.cadence))")
    #expect(motion.intensity > 0.5, "szum ma wyraźną intensywność: \(motion.intensity)")
}

@Test func phoneAtRestGivesNilAndNearZeroIntensity() {
    let still = (0..<400).map { i in AccelSample(tNanos: ns(Double(i) / 50.0), x: 0, y: 0, z: Float(gravity)) }
    let rest = CadenceAnalyzer.analyze(still)
    #expect(rest.cadence == nil)
    #expect(abs(rest.intensity) <= 1e-6, "intensity=\(rest.intensity)")

    // Spoczynek z drobnym szumem czujnika (ok. 0,01 m/s²): szum biały, autokorelacja znacznie poniżej progu 0,4.
    var rng = SplitMix64(seed: 7)
    var noisy: [AccelSample] = []
    for i in 0..<400 {
        noisy.append(AccelSample(tNanos: ns(Double(i) / 50.0), x: 0, y: 0, z: Float(gravity + 0.01 * rng.next())))
    }
    let noisyRest = CadenceAnalyzer.analyze(noisy)
    #expect(noisyRest.cadence == nil)
    #expect(noisyRest.intensity < 0.02, "intensity=\(noisyRest.intensity)")
}

@Test func tooFewSamplesGivesNil() {
    #expect(CadenceAnalyzer.analyze(sine(count: 149, hz: 2.5)).cadence == nil)
    #expect(CadenceAnalyzer.analyze(sine(count: 100, hz: 2.5)).cadence == nil)
    // Intensywność liczona mimo to.
    #expect(CadenceAnalyzer.analyze(sine(count: 100, hz: 2.5)).intensity > 1.0)
}

@Test func windowOfExactly150SamplesIsEnough() throws {
    try expectCadence(CadenceAnalyzer.analyze(sine(count: 150, hz: 2.5)), near: 150.0, tolerance: 3.0)
}

@Test func degenerateInputDoesNotCrash() throws {
    #expect(CadenceAnalyzer.analyze([]) == WindowMotion(cadence: nil, intensity: 0.0))
    #expect(CadenceAnalyzer.analyze([AccelSample(tNanos: 0, x: 1, y: 2, z: 3)]) == WindowMotion(cadence: nil, intensity: 0.0))

    // Wszystkie próbki identyczne, także w tym samym czasie i bez ruchu.
    let identical = (0..<300).map { _ in AccelSample(tNanos: 1_000, x: 0.3, y: 0.4, z: 9.8) }
    #expect(CadenceAnalyzer.analyze(identical) == WindowMotion(cadence: nil, intensity: 0.0))
    let sameValue = (0..<300).map { i in AccelSample(tNanos: Int64(i) * 20_000_000, x: 0.3, y: 0.4, z: 9.8) }
    #expect(CadenceAnalyzer.analyze(sameValue).cadence == nil)

    // NaN i nieskończoność są pomijane, próbki w odwrotnej kolejności sortowane.
    let bad = Array(sine(count: 400, hz: 2.5).reversed())
        + [AccelSample(tNanos: 5, x: .nan, y: 0, z: 0), AccelSample(tNanos: 6, x: 0, y: .infinity, z: 0)]
    try expectCadence(CadenceAnalyzer.analyze(bad), near: 150.0)
}

@Test func gapInDataGivesNilCadenceAndHugeWindowDoesNotBlowUp() {
    let head = sine(count: 200, hz: 2.5)
    let tail = sine(count: 200, hz: 2.5).map { AccelSample(tNanos: $0.tNanos + ns(30.0), x: $0.x, y: $0.y, z: $0.z) }
    #expect(CadenceAnalyzer.analyze(head + tail).cadence == nil)
    // Bardzo długie okno (10 minut) też daje rytm.
    #expect(CadenceAnalyzer.analyze(sine(count: 30_000, hz: 2.5)).cadence != nil)
}

@Test func analysisIsDeterministic() {
    var rng = SplitMix64(seed: 99)
    var samples: [AccelSample] = []
    for i in 0..<400 {
        let t = Double(i) / 50.0
        let jitter = 0.003 * rng.next()
        let noise = 0.3 * rng.next()
        samples.append(AccelSample(tNanos: ns(t + jitter), x: 0, y: 0, z: Float(gravity + 2.0 * sin(2.0 * Double.pi * 2.5 * t) + noise)))
    }
    #expect(CadenceAnalyzer.analyze(samples) == CadenceAnalyzer.analyze(Array(samples)))
}

@Test func fromGConvertsGToMetresPerSecondSquared() {
    // Core Motion podaje g; analizator dostaje m/s² (× 9,80665). Wartości w g mają być z grawitacją (userAcceleration + gravity).
    let sample = AccelSample.fromG(tNanos: 5, x: 1.0, y: 0.0, z: -0.5)
    #expect(sample.tNanos == 5)
    #expect(sample.x == Float(9.80665))
    #expect(sample.y == 0)
    #expect(sample.z == Float(-4.903325))
}

@Test func samplesFromGGiveIntensityInMetresPerSecondSquared() throws {
    // Grawitacja 1 g na osi z i drganie 0,2 g (wejście musi zawierać grawitację: moduł drgania bez niej na jednej osi byłby wyprostowanym sinusem). Po przeliczeniu to 0,2 · 9,80665 m/s², RMS = amplituda / sqrt(2); rytm bez zmian.
    let samples = (0..<400).map { i -> AccelSample in
        let t = Double(i) / 50.0
        return AccelSample.fromG(tNanos: ns(t), x: 0, y: 0, z: 1.0 + 0.2 * sin(2.0 * Double.pi * 2.5 * t))
    }
    let motion = CadenceAnalyzer.analyze(samples)
    try expectCadence(motion, near: 150.0)
    let expected = 0.2 * AccelSample.standardGravity / 2.0.squareRoot()
    #expect(abs(motion.intensity - expected) <= 0.05, "intensywność \(motion.intensity), oczekiwano \(expected)")
}
