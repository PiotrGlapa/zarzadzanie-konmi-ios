// Rytm i intensywność ruchu z okna próbek akcelerometru — port 1:1 `CadenceAnalyzer.kt` Androida 3.0.2
// (`core/src/main/kotlin/pl/glapa/zk/core/ride/CadenceAnalyzer.kt`). Czysta, deterministyczna funkcja.

import Foundation

/// Próbka akcelerometru: `tNanos` — znacznik czasu zdarzenia (ns), `x`, `y`, `z` — przyspieszenie w **m/s²** (z grawitacją albo bez —
/// analiza odejmuje średnią modułu, więc stała składowa grawitacji nie wpływa na wynik).
///
/// Kontrakt jednostek: `CadenceAnalyzer` dostaje zawsze m/s², tak jak na Androidzie. Core Motion (`CMDeviceMotion.userAcceleration`)
/// podaje przyspieszenie w jednostkach g — źródło próbek na iOS buduje `AccelSample` przez ``fromG(tNanos:x:y:z:)``, które mnoży
/// przez 9,80665 przed analizą.
public struct AccelSample: Equatable, Sendable {
    /// Przyspieszenie normalne (m/s² na 1 g) — mnożnik zamiany g → m/s².
    public static let standardGravity: Double = 9.80665

    public let tNanos: Int64
    public let x: Float
    public let y: Float
    public let z: Float

    public init(tNanos: Int64, x: Float, y: Float, z: Float) {
        self.tNanos = tNanos
        self.x = x
        self.y = y
        self.z = z
    }

    /// Próbka z wartości w g (np. `userAcceleration` z Core Motion): `x`, `y`, `z` × 9,80665 → m/s². Mnożenie w `Double`,
    /// potem zawężenie do `Float` (jak w próbkach Androida).
    public static func fromG(tNanos: Int64, x: Double, y: Double, z: Double) -> AccelSample {
        AccelSample(
            tNanos: tNanos,
            x: Float(x * standardGravity),
            y: Float(y * standardGravity),
            z: Float(z * standardGravity)
        )
    }
}

/// Ruch w jednym oknie akcelerometru: `cadence` — rytm kroków (1/min) albo `nil`, gdy w oknie nie ma wyraźnego rytmu
/// (za mało punktów, dziura w danych, brak ruchu, szum); `intensity` — intensywność ruchu: RMS drgań (m/s²), 0 dla pustego okna.
public struct WindowMotion: Equatable, Sendable {
    public let cadence: Double?
    public let intensity: Double

    public init(cadence: Double?, intensity: Double) {
        self.cadence = cadence
        self.intensity = intensity
    }
}

/// Rytm i intensywność ruchu z okna próbek akcelerometru (ścieżka nagrania jazdy). Algorytm jak na Androidzie (kroki w tej kolejności):
///
/// 1. **Czyszczenie.** Odrzuć próbki z NaN/nieskończonym składnikiem; posortuj stabilnie po `tNanos`; z próbek o tym samym czasie
///    zostaw pierwszą. Pusta lista → `WindowMotion(cadence: nil, intensity: 0)`.
/// 2. **Moduł** `m = sqrt(x² + y² + z²)` (m/s²) w `Double` (próbki `Float` rozszerzane przed obliczeniami).
/// 3. **Intensywność** = RMS odchylenia `m` od średniej (0 dla n < 2); liczona zawsze, także gdy rytm wyjdzie `nil`.
/// 4. **Dziura** większa niż 1 s między próbkami albo n < 2 → rytm `nil`.
/// 5. **Przepróbkowanie do 50 Hz** (siatka od pierwszej próbki, krok 20 000 000 ns, interpolacja liniowa modułu); N < 150 → rytm `nil`.
/// 6. **Odjęcie średniej**; energia ≤ 1e-9 → rytm `nil`.
/// 7. **Autokorelacja znormalizowana** `r(k) = Σ x[i]·x[i+k] / E` (E — energia całej serii) dla przesunięć 15…75 próbek
///    (0,3–1,5 s; liczona też dla 14 i 76 do interpolacji).
/// 8. **Maksimum** — przy remisie wygrywa mniejsze przesunięcie; `r < 0,4` → rytm `nil`.
/// 9. **Interpolacja paraboliczna** (`delta` ograniczone do ±0,5), `lag = (kMax + delta) / 50` s, `cadence = 60 / lag` (1/min).
public enum CadenceAnalyzer {
    /// Minimalna liczba punktów przepróbkowanej serii (3 s przy 50 Hz), aby szacować rytm.
    public static let minPoints = 150

    /// Częstotliwość przepróbkowania (Hz).
    public static let resampleHz = 50

    /// Najmniejsza wartość znormalizowanej autokorelacji maksimum, od której rytm jest uznany za wyraźny.
    public static let minPeak = 0.4

    /// Zabezpieczenie numeryczne: energia serii (po odjęciu średniej) nie większa niż ta wartość to seria stała, rytm `nil`.
    public static let minEnergy = 1e-9

    /// Najdłuższa dopuszczalna przerwa między próbkami surowymi (ns); dłuższa daje rytm `nil`.
    public static let maxGapNanos: Int64 = 1_000_000_000

    private static let stepNanos: Int64 = 1_000_000_000 / Int64(resampleHz)
    // 0,3 s i 1,5 s przy 50 Hz (round(0,3·50) i round(1,5·50)).
    private static let minLag = 15
    private static let maxLag = 75

    /// Analizuje okno próbek (m/s²). Te same próbki dają zawsze ten sam wynik.
    public static func analyze(_ samples: [AccelSample]) -> WindowMotion {
        let clean = normalize(samples)
        if clean.isEmpty { return WindowMotion(cadence: nil, intensity: 0.0) }

        let magnitudes = clean.map(magnitude)
        return WindowMotion(cadence: cadence(clean, magnitudes), intensity: rms(magnitudes))
    }

    /// Odrzuca próbki nieskończone/NaN oraz o powtórzonym czasie, sortuje stabilnie po czasie.
    private static func normalize(_ samples: [AccelSample]) -> [AccelSample] {
        // Stabilność jawnie (rosnąco po czasie, remis → kolejność wejścia), bez polegania na gwarancjach `sorted`.
        let sorted = samples
            .filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.tNanos != rhs.element.tNanos ? lhs.element.tNanos < rhs.element.tNanos : lhs.offset < rhs.offset
            }
            .map { $0.element }
        var result: [AccelSample] = []
        result.reserveCapacity(sorted.count)
        for sample in sorted {
            if let last = result.last, last.tNanos == sample.tNanos { continue }
            result.append(sample)
        }
        return result
    }

    private static func magnitude(_ sample: AccelSample) -> Double {
        let x = Double(sample.x)
        let y = Double(sample.y)
        let z = Double(sample.z)
        return (x * x + y * y + z * z).squareRoot()
    }

    /// RMS odchylenia od średniej.
    private static func rms(_ values: [Double]) -> Double {
        if values.count < 2 { return 0.0 }
        let average = mean(values)
        var sum = 0.0
        for value in values {
            let d = value - average
            sum += d * d
        }
        return (sum / Double(values.count)).squareRoot()
    }

    /// Średnia liczona względem pierwszego elementu (stabilność numeryczna; dla stałej serii wynik dokładny).
    private static func mean(_ values: [Double]) -> Double {
        let first = values[0]
        var sum = 0.0
        for value in values { sum += value - first }
        return first + sum / Double(values.count)
    }

    private static func cadence(_ clean: [AccelSample], _ magnitudes: [Double]) -> Double? {
        if clean.count < 2 { return nil }
        for i in 1..<clean.count where clean[i].tNanos - clean[i - 1].tNanos > maxGapNanos {
            return nil
        }
        var series = resample(clean, magnitudes)
        if series.count < minPoints { return nil }

        let seriesMean = mean(series)
        for i in series.indices { series[i] -= seriesMean }
        var energy = 0.0
        for value in series { energy += value * value }
        if energy <= minEnergy { return nil }

        var r = [Double](repeating: 0.0, count: maxLag + 2)
        for k in (minLag - 1)...(maxLag + 1) { r[k] = autocorrelation(series, lag: k) / energy }

        var best = minLag
        for k in (minLag + 1)...maxLag where r[k] > r[best] { best = k }
        if r[best] < minPeak { return nil }

        let a = r[best - 1]
        let b = r[best]
        let c = r[best + 1]
        let denominator = a - 2.0 * b + c
        let delta = abs(denominator) < 1e-12 ? 0.0 : min(max(0.5 * (a - c) / denominator, -0.5), 0.5)
        let lagSeconds = (Double(best) + delta) / Double(resampleHz)
        return 60.0 / lagSeconds
    }

    private static func autocorrelation(_ x: [Double], lag: Int) -> Double {
        var dot = 0.0
        for i in 0..<(x.count - lag) { dot += x[i] * x[i + lag] }
        return dot
    }

    /// Przepróbkowanie liniowe modułu do siatki 50 Hz zaczynającej się w pierwszej próbce (arytmetyka całkowita na nanosekundach).
    private static func resample(_ clean: [AccelSample], _ magnitudes: [Double]) -> [Double] {
        let t0 = clean[0].tNanos
        let count = Int((clean[clean.count - 1].tNanos - t0) / stepNanos + 1)
        var out = [Double](repeating: 0.0, count: count)
        var j = 0
        for k in 0..<count {
            let t = t0 + Int64(k) * stepNanos
            while j < clean.count - 2 && clean[j + 1].tNanos <= t { j += 1 }
            let ta = clean[j].tNanos
            let tb = clean[j + 1].tNanos
            let fraction = min(max(Double(t - ta) / Double(tb - ta), 0.0), 1.0)
            out[k] = magnitudes[j] + (magnitudes[j + 1] - magnitudes[j]) * fraction
        }
        return out
    }
}
