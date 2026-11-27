// Testy maszyny stanów nagrywania jazdy — port `RideRecorderTest.kt` z Androida 3.0.2 (wszystkie 30 testów): czas podawany jawnie,
// więc testy są deterministyczne. Brak testów pominiętych; żaden nie używa generatora liczb losowych.

import Testing
import Foundation
@testable import HorselyCore

@Suite struct RideRecorderTests {
    private let thresholds = GaitThresholds(stopMaxKmh: 1.5, walkMaxKmh: 7, trotMaxKmh: 15)
    private let t0: Int64 = 1_700_000_000_000

    /// `Math.round(double)` z Javy: `floor(x + 0,5)`.
    private func javaRound(_ x: Double) -> Int64 { Int64((x + 0.5).rounded(.down)) }

    /// 0,00001° szerokości geograficznej to ok. 1,11 m — krok „marszu" 1 punkt na sekundę to ok. 4 km/h.
    private func point(
        _ sec: Double,
        step: Int = 0,
        hAcc: Double? = 5.0,
        speedMs: Double? = nil,
        lonStep: Int = 0
    ) -> TrackPoint {
        TrackPoint(
            tMillis: t0 + javaRound(sec * 1000.0),
            lat: 52.0 + Double(step) * 0.00001,
            lon: 21.0 + Double(lonStep) * 0.00001,
            altM: nil,
            speedMs: speedMs,
            hAccM: hAcc,
            cadence: nil,
            intensity: nil
        )
    }

    private func at(_ sec: Double) -> Int64 { t0 + javaRound(sec * 1000.0) }

    private func recorder() -> RideRecorder { RideRecorder(startedAtMillis: t0, thresholds: thresholds) }

    private var oneStep: Double { haversineMeters(52.0, 21.0, 52.00001, 21.0) }

    private func expectClose(
        _ actual: Double, _ expected: Double, tolerance: Double, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual - expected) <= tolerance, "jest \(actual), oczekiwano \(expected) ±\(tolerance)", sourceLocation: sourceLocation)
    }

    private func relative(_ points: [TrackPoint]) -> [Int64] { points.map { $0.tMillis - t0 } }

    // MARK: - Pauza

    @Test func pauseExcludesTimeAndPoints() {
        let r = recorder()
        r.onLocation(point(0.0, step: 0))
        r.onLocation(point(5.0, step: 5))
        r.onLocation(point(10.0, step: 10))
        r.pause(tMillis: at(10.0))
        // W pauzie punkty są odrzucane (także daleko od ostatniego).
        r.onLocation(point(15.0, step: 5000))
        #expect(r.snapshot().state == .paused)
        r.resume(tMillis: at(20.0))
        r.onLocation(point(21.0, step: 5011))
        r.onLocation(point(22.0, step: 5012))
        r.tick(tMillis: at(30.0), batteryPercent: nil)

        let snap = r.snapshot()
        #expect(snap.state == .recording)
        // 30 s od startu minus 10 s pauzy.
        #expect(snap.activeSeconds == 20)
        // Dystans: tylko odcinki przed pauzą (10 kroków) i po niej (1 krok); skok przez pauzę się nie liczy.
        expectClose(Double(snap.distanceMeters), 10 * oneStep + oneStep, tolerance: 1.0)

        let stored = r.drainUnsaved()
        #expect(relative(stored) == [0, 5000, 10_000, 21_000, 22_000])
        #expect(r.pauses() == [Pause(startMillis: at(10.0), endMillis: at(20.0))])
    }

    @Test func pointJustBeforePauseEndDeliveredLateIsRejected() {
        let r = recorder()
        r.onLocation(point(0.0))
        r.pause(tMillis: at(5.0))
        r.resume(tMillis: at(15.0))
        r.onLocation(point(12.0)) // znacznik z czasu pauzy
        r.onLocation(point(16.0))
        #expect(relative(r.drainUnsaved()) == [0, 16_000])
    }

    // MARK: - Słaby GPS

    @Test func weakGpsAfter30sOfPoorAccuracy() {
        let r = recorder()
        r.onLocation(point(1.0, step: 0))
        // Same słabe punkty (dokładność 40 m) co sekundę.
        for s in 2...31 {
            let events = r.onLocation(point(Double(s), step: s, hAcc: 40.0))
            #expect(!events.contains(.weakGpsStarted), "przed upływem 30 s: \(s)")
        }
        // Dokładnie 30 s od ostatniego dobrego punktu to jeszcze nie „> 30 s".
        #expect(r.tick(tMillis: at(31.0), batteryPercent: nil).filter { $0 == .weakGpsStarted }.isEmpty)
        #expect(r.snapshot().weakGps == false)

        #expect(r.tick(tMillis: at(31.001), batteryPercent: nil).filter { $0 == .weakGpsStarted } == [.weakGpsStarted])
        #expect(r.snapshot().weakGps == true)
        // Powtórne tiki nie powtarzają zdarzenia.
        #expect(!r.tick(tMillis: at(40.0), batteryPercent: nil).contains(.weakGpsStarted))
        // Słaby punkt nie kończy stanu słabego GPS i nie liczy się do dystansu.
        #expect(!r.onLocation(point(41.0, step: 41, hAcc: 40.0)).contains(.weakGpsEnded))
        #expect(r.snapshot().distanceMeters == 0)

        // Dobry punkt kończy stan.
        #expect(r.onLocation(point(42.0, step: 42)).filter { $0 == .weakGpsEnded } == [.weakGpsEnded])
        #expect(r.snapshot().weakGps == false)
    }

    @Test func weakGpsFromTheVeryStartWhenNoGoodPointArrives() {
        let r = recorder()
        #expect(!r.tick(tMillis: at(30.0), batteryPercent: nil).contains(.weakGpsStarted))
        #expect(r.tick(tMillis: at(30.5), batteryPercent: nil).contains(.weakGpsStarted))
    }

    @Test func weakGpsTimerDoesNotRunDuringPause() {
        let r = recorder()
        r.onLocation(point(1.0))
        r.pause(tMillis: at(2.0))
        #expect(!r.tick(tMillis: at(200.0), batteryPercent: nil).contains(.weakGpsStarted))
        r.resume(tMillis: at(300.0))
        #expect(!r.tick(tMillis: at(320.0), batteryPercent: nil).contains(.weakGpsStarted))
        #expect(r.tick(tMillis: at(330.5), batteryPercent: nil).contains(.weakGpsStarted))
    }

    // MARK: - Bateria, 8 h, zapis

    @Test func batteryWarningOnceAt15Percent() {
        let r = recorder()
        #expect(!r.tick(tMillis: at(1.0), batteryPercent: 16).contains(.batteryLow))
        #expect(!r.tick(tMillis: at(2.0), batteryPercent: nil).contains(.batteryLow))
        #expect(r.tick(tMillis: at(3.0), batteryPercent: 15).filter { $0 == .batteryLow }.count == 1)
        #expect(!r.tick(tMillis: at(4.0), batteryPercent: 14).contains(.batteryLow))
        #expect(!r.tick(tMillis: at(5.0), batteryPercent: 5).contains(.batteryLow))
    }

    @Test func autoFinishAfter8Hours() {
        let r = recorder()
        let eight: Int64 = 8 * 3600 * 1000
        #expect(!r.tick(tMillis: t0 + eight - 1, batteryPercent: nil).contains(.autoFinished))
        #expect(r.snapshot().state == .recording)
        #expect(r.tick(tMillis: t0 + eight, batteryPercent: nil).filter { $0 == .autoFinished }.count == 1)
        #expect(r.snapshot().state == .finished)
        // Po zakończeniu: bez dalszych zdarzeń i punktów.
        #expect(r.tick(tMillis: t0 + eight + 1000, batteryPercent: 10).isEmpty)
        #expect(r.onLocation(point(Double(eight) / 1000.0 + 2.0)).isEmpty)
        #expect(r.drainUnsaved().isEmpty)
    }

    @Test func autoFinishClosesAnOpenPause() {
        let r = recorder()
        let eight: Int64 = 8 * 3600 * 1000
        r.pause(tMillis: at(10.0))
        r.tick(tMillis: t0 + eight, batteryPercent: nil)
        #expect(r.pauses() == [Pause(startMillis: at(10.0), endMillis: t0 + eight)])
        #expect(r.snapshot().activeSeconds == 10)
    }

    @Test func flushDueAtMostEvery10s() {
        let r = recorder()
        r.onLocation(point(0.0))
        #expect(!r.tick(tMillis: at(4.999), batteryPercent: nil).contains(.flushDue))
        #expect(r.tick(tMillis: at(5.0), batteryPercent: nil).contains(.flushDue))
        // Do czasu zapisu zdarzenie się powtarza (usługa mogła je przeoczyć).
        #expect(r.tick(tMillis: at(6.0), batteryPercent: nil).contains(.flushDue))
        #expect(r.drainUnsaved().count == 1)
        #expect(!r.tick(tMillis: at(10.999), batteryPercent: nil).contains(.flushDue))
        #expect(r.tick(tMillis: at(11.0), batteryPercent: nil).contains(.flushDue))

        // Cykl z tikami co sekundę i zapisem po każdym `flushDue`: odstęp między zapisami nigdy nie przekracza 10 s.
        let r2 = recorder()
        var lastFlush: Int64 = 0
        var maxGap: Int64 = 0
        for s in 1...120 {
            let events = r2.tick(tMillis: at(Double(s)), batteryPercent: nil)
            if events.contains(.flushDue) {
                r2.drainUnsaved()
                maxGap = max(maxGap, Int64(s) * 1000 - lastFlush)
                lastFlush = Int64(s) * 1000
            }
        }
        #expect(maxGap <= 10_000, "maxGap=\(maxGap)")
        #expect(lastFlush >= 115_000)
    }

    @Test func flushDueAlsoComesWithALocation() {
        let r = recorder()
        r.onLocation(point(0.0))
        #expect(r.onLocation(point(5.0, step: 1)).contains(.flushDue))
    }

    // MARK: - Skoki GPS

    @Test func jumpAbove70KmhIsNotCountedIntoDistance() {
        let r = recorder()
        r.onLocation(point(0.0, step: 0))
        r.onLocation(point(1.0, step: 1))
        // ok. 11 km w 1 s
        r.onLocation(point(2.0, step: 100_000))
        r.onLocation(point(3.0, step: 2))
        expectClose(Double(r.snapshot().distanceMeters), 2 * oneStep, tolerance: 1.0)
        // Punkt ze skokiem zostaje w śladzie (ślad jest surowy; filtruje go dopiero statystyka jazdy).
        #expect(r.drainUnsaved().count == 4)
    }

    @Test func aSingleOutlierRejectsOnlyThatPoint() {
        let r = recorder()
        r.onLocation(point(0.0, step: 0))
        r.onLocation(point(1.0, step: 1))
        r.onLocation(point(2.0, step: 100_000))
        // Następny punkt jest spójny z kotwicą (nie z odrzuconym) — jest liczony, a licznik skoków zerowany.
        r.onLocation(point(3.0, step: 2))
        r.onLocation(point(4.0, step: 3))
        expectClose(Double(r.snapshot().distanceMeters), 3 * oneStep, tolerance: 1.0)
    }

    @Test func aLastingShiftOfCoordinatesMovesTheAnchorAndDistanceGrowsAgain() {
        let r = recorder()
        for s in 0...4 { r.onLocation(point(Double(s), step: s)) }
        // Trwałe przesunięcie o ok. 200 m (zimny start GPS): 100 punktów co sekundę, każdy o krok dalej.
        for s in 5...104 { r.onLocation(point(Double(s), step: s + 180)) }
        // 4 kroki przed przesunięciem + 98 po nim: pierwszy punkt po przesunięciu jest odrzucony, drugi (spójny z nim) przesuwa kotwicę
        // bez doliczania dystansu przez lukę.
        expectClose(Double(r.snapshot().distanceMeters), 102 * oneStep, tolerance: 1.5)
    }

    @Test func threeConsecutiveJumpsMoveTheAnchorEvenWhenTheyDisagreeWithEachOther() {
        let r = recorder()
        r.onLocation(point(0.0, step: 0))
        r.onLocation(point(1.0, step: 1))
        r.onLocation(point(2.0, step: 100_000))
        r.onLocation(point(3.0, step: 300_000))
        r.onLocation(point(4.0, step: 500_000)) // trzecie odrzucenie z rzędu → kotwica tutaj, bez dystansu
        r.onLocation(point(5.0, step: 500_001))
        expectClose(Double(r.snapshot().distanceMeters), 2 * oneStep, tolerance: 1.0)
    }

    @Test func restoreAfterALastingShiftGivesTheSameDistanceAsLive() {
        let live = recorder()
        for s in 0...4 { live.onLocation(point(Double(s), step: s, speedMs: 1.1)) }
        for s in 5...60 { live.onLocation(point(Double(s), step: s + 180, speedMs: 1.1)) }
        live.tick(tMillis: at(60.0), batteryPercent: nil)
        let saved = live.drainUnsaved()
        let restored = RideRecorder.restore(
            session: RideRestoreState(startedAtMillis: t0, thresholds: thresholds, state: .recording, lastFlushMillis: at(60.0)),
            points: saved,
            pauses: live.pauses()
        )
        #expect(live.snapshot() == restored.snapshot())
        // Kontynuacja po odtworzeniu liczy się tak samo.
        let more = point(61.0, step: 61 + 180, speedMs: 1.1)
        live.onLocation(more)
        restored.onLocation(more)
        #expect(live.snapshot().distanceMeters == restored.snapshot().distanceMeters)
    }

    // MARK: - Prędkość i chód

    @Test func gaitFollowsSmoothedSpeedAndThresholds() throws {
        let r = recorder()
        #expect(r.snapshot().gait == nil)
        #expect(r.snapshot().speedKmh == nil)
        // 1 m/s = 3,6 km/h → stęp
        for s in 0...4 { r.onLocation(point(Double(s), step: s, speedMs: 1.0)) }
        #expect(r.snapshot().gait == .walk)
        expectClose(try #require(r.snapshot().speedKmh), 3.6, tolerance: 0.001)
        // 3 m/s = 10,8 km/h → kłus (po trzech próbkach mediana już 3 m/s)
        for s in 5...7 { r.onLocation(point(Double(s), step: s, speedMs: 3.0)) }
        #expect(r.snapshot().gait == .trot)
        // 6 m/s = 21,6 km/h → galop
        for s in 8...10 { r.onLocation(point(Double(s), step: s, speedMs: 6.0)) }
        #expect(r.snapshot().gait == .canter)
        // 0,2 m/s = 0,72 km/h → postój
        for s in 11...13 { r.onLocation(point(Double(s), step: s, speedMs: 0.2)) }
        #expect(r.snapshot().gait == .stop)
    }

    @Test func gaitUsesDistanceWhenPointHasNoSpeed() throws {
        let r = recorder()
        // ok. 11,12 m / 1 s ≈ 40 km/h między punktami ze skokiem 0,0001°.
        for s in 0...4 { r.onLocation(point(Double(s), step: s * 10)) }
        let v = haversineMeters(52.0, 21.0, 52.0001, 21.0) * 3.6
        expectClose(try #require(r.snapshot().speedKmh), v, tolerance: 0.01)
        #expect(r.snapshot().gait == .canter)
    }

    @Test func noSpeedAndGaitWhilePausedOrWeak() throws {
        let r = recorder()
        for s in 0...4 { r.onLocation(point(Double(s), step: s, speedMs: 3.0)) }
        r.pause(tMillis: at(5.0))
        #expect(r.snapshot().speedKmh == nil)
        #expect(r.snapshot().gait == nil)
        r.resume(tMillis: at(6.0))
        // Po wznowieniu stara prędkość nie obowiązuje, dopóki nie przyjdą nowe punkty.
        #expect(r.snapshot().speedKmh == nil)
        for s in 6...8 { r.onLocation(point(Double(s), step: s, speedMs: 3.0)) }
        expectClose(try #require(r.snapshot().speedKmh), 10.8, tolerance: 0.001)
        r.tick(tMillis: at(40.0), batteryPercent: nil)
        #expect(r.snapshot().weakGps == true)
        #expect(r.snapshot().speedKmh == nil)
        #expect(r.snapshot().gait == nil)
    }

    // MARK: - Dane ruchu (okna akcelerometru)

    @Test func motionGoesToThePointClosingTheWindow() throws {
        let r = recorder()
        for s in 0...6 { r.onLocation(point(Double(s), step: s)) }
        r.onMotion(tMillis: at(5.0), WindowMotion(cadence: 150.0, intensity: 1.25))
        let stored = r.drainUnsaved()
        #expect(stored.count == 7)
        #expect(stored[5].cadence == 150.0)
        #expect(stored[5].intensity == 1.25)
        #expect(stored[4].cadence == nil)
        #expect(stored[6].cadence == nil)

        // Okno zamknięte między punktami: dostaje je ostatni punkt nie późniejszy niż koniec okna.
        r.onLocation(point(7.0, step: 7))
        r.onMotion(tMillis: at(7.4), WindowMotion(cadence: nil, intensity: 0.5))
        let next = r.drainUnsaved()
        #expect(relative(next) == [7_000])
        let single = try #require(next.first)
        #expect(single.cadence == nil)
        #expect(single.intensity == 0.5)
    }

    @Test func motionAfterFlushAmendsTheSavedPointAndDeliversItAgain() {
        let r = recorder()
        for s in 0...4 { r.onLocation(point(Double(s), step: s)) }
        #expect(r.drainUnsaved().count == 5)
        r.onMotion(tMillis: at(4.0), WindowMotion(cadence: 120.0, intensity: 2.0))
        r.onLocation(point(5.0, step: 5))
        let again = r.drainUnsaved()
        #expect(relative(again) == [4_000, 5_000])
        #expect(again[0].cadence == 120.0)
        #expect(again[1].cadence == nil)
    }

    @Test func motionWithoutAPointInRangeOrInPauseIsIgnored() throws {
        let r = recorder()
        r.onMotion(tMillis: at(5.0), WindowMotion(cadence: 150.0, intensity: 1.0))
        r.onLocation(point(6.0))
        r.onMotion(tMillis: at(5.0), WindowMotion(cadence: 150.0, intensity: 1.0)) // przed pierwszym punktem
        let drained = r.drainUnsaved()
        #expect(drained.count == 1)
        let first = try #require(drained.first)
        #expect(first.cadence == nil)
        r.pause(tMillis: at(7.0))
        r.onMotion(tMillis: at(8.0), WindowMotion(cadence: 150.0, intensity: 1.0)) // w pauzie
        #expect(r.drainUnsaved().isEmpty)
    }

    @Test func windowAcrossAPauseDoesNotTouchThePointBeforeThePause() throws {
        let r = recorder()
        for s in 0...8 { r.onLocation(point(Double(s), step: s)) }
        r.onMotion(tMillis: at(5.0), WindowMotion(cadence: 150.0, intensity: 1.0)) // poprawne okno punktu 5 s
        r.pause(tMillis: at(8.0))
        r.resume(tMillis: at(10.0))
        r.drainUnsaved()
        // Okno kończy się po wznowieniu, ale przed pierwszym nowym punktem: ostatni punkt ≤ t jest sprzed pauzy (8 s).
        r.onMotion(tMillis: at(10.2), WindowMotion(cadence: 90.0, intensity: 0.1))
        #expect(r.drainUnsaved().isEmpty) // nic nie uzupełnione, nic ponownie do zapisu
        r.onLocation(point(11.0, step: 11))
        r.onMotion(tMillis: at(11.0), WindowMotion(cadence: 100.0, intensity: 0.3)) // okno kończące się w nowym punkcie działa
        let stored = r.drainUnsaved()
        #expect(relative(stored) == [11_000])
        let first = try #require(stored.first)
        #expect(first.cadence == 100.0)
    }

    @Test func windowAcrossAPauseLeavesEarlierPointMotionIntact() {
        let r = recorder()
        for s in 0...8 { r.onLocation(point(Double(s), step: s)) }
        r.onMotion(tMillis: at(8.0), WindowMotion(cadence: 150.0, intensity: 1.0))
        r.drainUnsaved()
        r.pause(tMillis: at(8.5))
        r.resume(tMillis: at(10.0))
        r.onMotion(tMillis: at(10.2), WindowMotion(cadence: nil, intensity: 0.0))
        r.onLocation(point(11.0, step: 11))
        let stored = r.drainUnsaved()
        #expect(relative(stored) == [11_000])
    }

    @Test func firstWindowWinsWhenTwoWindowsCloseOnTheSamePoint() {
        let r = recorder()
        for s in 0...2 { r.onLocation(point(Double(s), step: s)) }
        r.onMotion(tMillis: at(5.0), WindowMotion(cadence: 150.0, intensity: 1.5))
        // Przerwa w GPS dłuższa niż okno: drugie okno (nawet z rytmem nil) nie nadpisuje pierwszego.
        r.onMotion(tMillis: at(10.0), WindowMotion(cadence: nil, intensity: 0.2))
        r.onMotion(tMillis: at(15.0), WindowMotion(cadence: 90.0, intensity: 0.7))
        let stored = r.drainUnsaved()
        #expect(stored.count == 3)
        #expect(stored[2].cadence == 150.0)
        #expect(stored[2].intensity == 1.5)
        // Także po zapisie: odrzucone okno nie trafia do uzupełnionych.
        r.onMotion(tMillis: at(20.0), WindowMotion(cadence: 60.0, intensity: 0.9))
        #expect(r.drainUnsaved().isEmpty)
    }

    // MARK: - Odtwarzanie

    @Test func restoreKeepsMotionDataOfPoints() {
        let original = recorder()
        for s in 0...6 { original.onLocation(point(Double(s), step: s)) }
        original.onMotion(tMillis: at(5.0), WindowMotion(cadence: 140.0, intensity: 1.1))
        original.tick(tMillis: at(6.0), batteryPercent: nil)
        let saved = original.drainUnsaved()
        let restored = RideRecorder.restore(
            session: RideRestoreState(startedAtMillis: t0, thresholds: thresholds, state: .recording, lastFlushMillis: at(6.0)),
            points: saved,
            pauses: original.pauses()
        )
        // Okno już zajęte punkt 5 s: po odtworzeniu nie jest nadpisywane, a nie ma niczego do ponownego zapisu.
        restored.onMotion(tMillis: at(5.5), WindowMotion(cadence: 60.0, intensity: 9.0))
        #expect(restored.drainUnsaved().isEmpty)
        #expect(saved[5].cadence == 140.0)
        #expect(saved[5].intensity == 1.1)
    }

    @Test func restoreContinuesDistanceAndActiveTime() {
        let original = recorder()
        let points = (0...20).map { point(Double($0), step: $0, speedMs: 2.0) }
        for p in points.prefix(8) { original.onLocation(p) }
        original.pause(tMillis: at(8.0))
        original.resume(tMillis: at(10.0))
        for p in points.dropFirst(10) { original.onLocation(p) }
        original.tick(tMillis: at(20.0), batteryPercent: nil)
        let saved = original.drainUnsaved()
        let before = original.snapshot()
        let pauses = original.pauses()

        let restored = RideRecorder.restore(
            session: RideRestoreState(startedAtMillis: t0, thresholds: thresholds, state: .recording, lastFlushMillis: at(20.0)),
            points: saved,
            pauses: pauses
        )
        #expect(before == restored.snapshot())
        #expect(restored.drainUnsaved().isEmpty)

        // Kontynuacja: oryginał i odtworzony zachowują się tak samo.
        let more = point(21.0, step: 21, speedMs: 2.0)
        original.onLocation(more)
        restored.onLocation(more)
        original.tick(tMillis: at(22.0), batteryPercent: nil)
        restored.tick(tMillis: at(22.0), batteryPercent: nil)
        #expect(original.snapshot() == restored.snapshot())
        #expect(restored.snapshot().distanceMeters > before.distanceMeters)
        #expect(restored.snapshot().activeSeconds > before.activeSeconds)
        #expect(relative(restored.drainUnsaved()) == [21_000])
    }

    @Test func restoreKeepsPausedStateAndItsOpenPause() {
        let original = recorder()
        for s in 0...3 { original.onLocation(point(Double(s), step: s)) }
        original.pause(tMillis: at(4.0))
        original.tick(tMillis: at(9.0), batteryPercent: nil)
        let saved = original.drainUnsaved()
        let pauses = original.pauses()
        #expect(pauses == [Pause(startMillis: at(4.0), endMillis: at(9.0))])

        let restored = RideRecorder.restore(
            session: RideRestoreState(startedAtMillis: t0, thresholds: thresholds, state: .paused, lastFlushMillis: at(9.0)),
            points: saved,
            pauses: pauses
        )
        #expect(restored.snapshot().state == .paused)
        #expect(restored.snapshot().activeSeconds == 4)
        restored.onLocation(point(10.0, step: 10)) // nadal w pauzie
        restored.resume(tMillis: at(15.0))
        restored.tick(tMillis: at(20.0), batteryPercent: nil)
        // 20 s − pauza 4..15 s = 9 s
        #expect(restored.snapshot().activeSeconds == 9)
        #expect(restored.pauses() == [Pause(startMillis: at(4.0), endMillis: at(15.0))])
        #expect(restored.drainUnsaved().isEmpty)
    }

    @Test func restoreOfInterruptedRideResumesFromLastFlushAsPause() {
        let original = recorder()
        for s in 0...9 { original.onLocation(point(Double(s), step: s)) }
        original.tick(tMillis: at(10.0), batteryPercent: nil)
        let saved = original.drainUnsaved()

        let restored = RideRecorder.restore(
            session: RideRestoreState(startedAtMillis: t0, thresholds: thresholds, state: .interrupted, lastFlushMillis: at(10.0)),
            points: saved,
            pauses: []
        )
        #expect(restored.snapshot().state == .paused)
        #expect(restored.snapshot().activeSeconds == 10)
        // Luka po ostatnim zapisie (aplikacja nie działała) nie wlicza się do czasu aktywnego.
        restored.resume(tMillis: at(100.0))
        restored.tick(tMillis: at(105.0), batteryPercent: nil)
        #expect(restored.snapshot().activeSeconds == 15)
        #expect(restored.pauses() == [Pause(startMillis: at(10.0), endMillis: at(100.0))])
    }

    @Test func restoreOfFinishedRideStaysFinished() {
        let restored = RideRecorder.restore(
            session: RideRestoreState(startedAtMillis: t0, thresholds: thresholds, state: .finished, lastFlushMillis: at(50.0)),
            points: [],
            pauses: []
        )
        #expect(restored.snapshot().state == .finished)
        #expect(restored.onLocation(point(60.0)).isEmpty)
        #expect(restored.snapshot().activeSeconds == 50)
    }

    // MARK: - Przejścia niedozwolone

    @Test func illegalTransitionsAreIgnored() {
        let r = recorder()
        r.resume(tMillis: at(1.0)) // nie jest w pauzie
        #expect(r.pauses().isEmpty)
        r.pause(tMillis: at(2.0))
        r.pause(tMillis: at(3.0)) // już w pauzie
        r.resume(tMillis: at(4.0))
        #expect(r.pauses() == [Pause(startMillis: at(2.0), endMillis: at(4.0))])
    }
}
