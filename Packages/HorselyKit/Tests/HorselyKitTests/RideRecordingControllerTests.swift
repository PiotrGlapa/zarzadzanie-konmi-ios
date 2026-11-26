import CoreLocation
import Foundation
import GRDB
import HorselyCore
import Synchronization
import Testing
@testable import HorselyKit

/// Kontroler nagrywania (Task 15 = Android `RideRecordingControllerTest.kt`, `RideRecordingServiceTest.kt`, `ServiceRestartWithoutPermissionTest.kt`,
/// `AccelWindowBufferTest.kt`): udawane źródła lokalizacji, ruchu i baterii, sterowany zegar i PRAWDZIWY `RideSessionStore` na pliku bazy
/// w katalogu tymczasowym. „Zabicie procesu” to porzucenie kontrolera (bez `finish`) i nowy kontroler z nowym sklepem na tym samym pliku.
/// Tiki woła test (`tickInterval: nil`); punkty i próbki idą przez strumienie źródeł, a test czeka, aż kontroler je obsłuży.
struct RideRecordingControllerTests {
    private let params: EffectiveRideParameters = RideParameters.resolve(RideDefaults.builtIn, nil)
    private let grom = HorseRef(id: "h1", name: "Grom", passportNumber: nil)

    // MARK: Pomocnicze

    /// Jedna sekunda jazdy: czas, punkt GPS i tik tym samym zegarem.
    private func second(_ h: ControllerHarness, _ controller: RideRecordingController, _ s: Int, accuracy: Double = 5.0, source: FakeLocationSource? = nil) async {
        h.clock.millis = START + Int64(s) * 1_000
        await h.emit(goodFix(s, accuracy: accuracy), to: controller, via: source)
        await controller.tick()
    }

    private func latestSnapshot(_ controller: RideRecordingController) async -> RideSnapshot? {
        var iterator = controller.snapshots.makeAsyncIterator()
        return await iterator.next()
    }

    // MARK: Wymagane testy Task 15

    /// Android: `points from the location source are flushed on the shared clock`. Zapis co 5 s (`.flushDue`), więc w bazie jest zawsze
    /// wszystko sprzed ≥ 5 s — z zapasem spełnia Review Focus 2 (punkty zapisane ≥ 10 s wcześniej przetrwają zabicie procesu).
    @Test func pointsFlowToStoreEvery10s() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        let id = try await controller.start(horse: grom, params: params)
        #expect(h.locations.active)
        #expect(h.locations.backgroundActive)
        #expect(h.motion.active)
        #expect(h.battery.monitoring)
        #expect(controller.isRunning)
        #expect(controller.activeSessionId == id)

        for s in 1...30 {
            await second(h, controller, s)
            let saved = Set(try await store.load(sessionId: id).track.points.map(\.tMillis))
            if s >= 6 {
                let older = (1...(s - 5)).map { START + Int64($0) * 1_000 }
                #expect(Set(older).isSubset(of: saved), "w \(s). sekundzie brakuje punktów sprzed ≥ 5 s")
            }
            if s >= 10 {
                let olderThan10 = (1...(s - 9)).map { START + Int64($0) * 1_000 }
                #expect(Set(olderThan10).isSubset(of: saved))
            }
        }

        let loaded = try await store.load(sessionId: id)
        #expect(loaded.track.points.count == 30)
        let first = try #require(loaded.track.points.first)
        #expect(first.tMillis == START + 1_000)
        #expect(first.lat == 52.0001)
        #expect(first.lon == 21.0)
        #expect(first.hAccM == 5.0)
        #expect(first.cadence == nil)
        #expect(first.intensity == nil)
        #expect(loaded.session.state == .recording)
        // 29 odcinków po 0,0001° szerokości (≈ 11,12 m) — pierwszy punkt to kotwica.
        #expect(loaded.session.distanceMeters == 322)
        #expect(loaded.session.lastFlushMillis == START + 30_000)
    }

    /// Przybliżona lokalizacja blokuje start z wyjaśnieniem (Review Focus 3, kryterium 10.4): nic nie powstaje i nic nie działa.
    @Test func reducedAccuracyBlocksStart() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        h.locations.authorization = .reducedAccuracy

        await #expect(throws: RideStartError.reducedAccuracy) {
            _ = try await controller.start(horse: grom, params: params)
        }
        #expect(try await store.unfinished() == nil)
        #expect(!h.locations.active)
        #expect(!h.locations.backgroundActive)
        #expect(h.locations.starts == 0)
        #expect(!h.motion.active)
        #expect(!h.battery.monitoring)
        #expect(!controller.isRunning)
        #expect(h.logs.lines == ["Start zablokowany: tylko przybliżona lokalizacja"])
    }

    /// Odmowa lokalizacji blokuje start; brak decyzji — też (interfejs musi najpierw zapytać).
    @Test func deniedBlocksStart() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        h.locations.authorization = .denied

        await #expect(throws: RideStartError.locationDenied) {
            _ = try await controller.start(horse: grom, params: params)
        }
        h.locations.authorization = .notDetermined
        await #expect(throws: RideStartError.locationNotDetermined) {
            _ = try await controller.start(horse: grom, params: params)
        }
        #expect(try await store.unfinished() == nil)
        #expect(h.locations.starts == 0)
        #expect(!h.motion.active)
        #expect(!controller.isRunning)
        #expect(h.logs.lines == ["Start zablokowany: brak zgody na lokalizację"])
    }

    /// Cofnięcie zgody w trakcie jazdy (sprawdzane przy tiku): bieżące, jeszcze niezapisane punkty trafiają do bazy, sesja jest `.interrupted`,
    /// źródła i bateria wyłączone, powiadomienie „Nagrywanie przerwane — …”.
    @Test(arguments: [LocationAuthorization.denied, .reducedAccuracy, .notDetermined])
    func authorizationRevokedMarksInterrupted(_ revoked: LocationAuthorization) async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        let id = try await controller.start(horse: grom, params: params)
        for s in 1...3 { await second(h, controller, s) }
        #expect(try await store.load(sessionId: id).track.points.isEmpty, "przed 5 s nic nie jest jeszcze zapisane")

        h.locations.authorization = revoked
        h.clock.millis = START + 4_000
        await controller.tick()

        let loaded = try await store.load(sessionId: id)
        #expect(loaded.session.state == .interrupted)
        #expect(loaded.track.points.map(\.tMillis) == [START + 1_000, START + 2_000, START + 3_000])
        #expect(try await store.unfinished()?.state == .interrupted)
        #expect(!h.locations.active)
        #expect(!h.locations.backgroundActive)
        #expect(!h.motion.active)
        #expect(!h.battery.monitoring)
        #expect(!controller.isRunning)
        #expect(controller.activeSessionId == nil)
        #expect(h.alerts.bodies == ["Nagrywanie przerwane — otwórz aplikację, aby zapisać jazdę"])
        #expect(h.logs.lines.contains { $0.hasPrefix("Cofnięto zgodę na lokalizację") && $0.contains("punkty 3") })
        #expect(await latestSnapshot(controller)?.state == .interrupted)

        // Dalsze tiki i punkty nie ruszają przerwanej jazdy.
        await controller.tick()
        h.locations.emit(goodFix(9))
        #expect(await controller.finish() == nil)
        #expect(try await store.load(sessionId: id).track.points.count == 3)
    }

    /// Android: `a killed process continues after restart and the gap is not active time` + `sticky restart with the permission continues the
    /// ride and counts the gap as a pause`. Nowy proces: `prepareRelaunch()` (synchronicznie, przy starcie aplikacji) odtwarza sesję aktywności
    /// w tle i wznawia odbiór GPS; luka po zabiciu jest pauzą.
    @Test func relaunchWithActiveSessionResumesUpdates() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let firstStore = try h.openStore()
        let first = h.controller(firstStore)
        let id = try await first.start(horse: grom, params: params)
        for s in 1...20 { await second(h, first, s) }
        // Zabicie: kontroler zostaje porzucony (bez finish) — nowy proces widzi tylko to, co już zapisano.
        let savedAtKill = try await firstStore.load(sessionId: id).track.points.count
        #expect(savedAtKill == 20)

        h.clock.millis = START + 120_000
        let locations = FakeLocationSource()
        let motion = FakeMotionSource()
        let restarted = h.controller(try h.openStore(), locations: locations, motion: motion)
        let relaunch = try #require(restarted.prepareRelaunch())
        #expect(locations.backgroundBegun == 1, "sesja aktywności w tle odtworzona synchronicznie, przed zakończeniem uruchamiania")
        await relaunch.value

        #expect(locations.active)
        #expect(motion.active)
        #expect(h.battery.monitoring)
        #expect(restarted.isRunning)
        #expect(restarted.activeSessionId == id)
        let store = try h.openStore()
        #expect(try await store.load(sessionId: id).session.state == .recording)
        #expect(h.logs.lines.contains { $0.hasPrefix("Ponowne uruchomienie: wznowiono jazdę w stanie Recording") && $0.contains("punkty 20") })

        await h.emit(goodFix(30), to: restarted, via: locations)
        h.clock.millis = START + 121_000
        await h.emit(goodFix(31), to: restarted, via: locations)
        #expect(await restarted.finish() == id)

        let loaded = try await store.load(sessionId: id)
        #expect(loaded.session.state == .finished)
        #expect(loaded.track.pauses == [Pause(startMillis: START + 20_000, endMillis: START + 120_000)], "luka po zabiciu to pauza")
        #expect(loaded.restoreRecorder().snapshot().activeSeconds == 21, "luka 100 s nie liczy się do czasu aktywnego")
        #expect(loaded.track.points.count == savedAtKill + 2)
    }

    /// Android: `finish flushes the last points sets Finished and notifies` + `finish action stops service and sets state Finished`.
    @Test func finishStopsSourcesAndSetsFinished() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        let id = try await controller.start(horse: grom, params: params)
        for s in 1...8 { await second(h, controller, s) }
        h.clock.millis = START + 9_000
        #expect(await controller.finish() == id)

        let loaded = try await store.load(sessionId: id)
        #expect(loaded.session.state == .finished)
        #expect(loaded.session.endedAt == Date(timeIntervalSince1970: TimeInterval(START + 9_000) / 1000))
        #expect(loaded.track.points.count == 8, "punkty niezapisane przy zakończeniu też trafiają do bazy")
        #expect(try await store.unfinished()?.state == .finished)
        #expect(!h.locations.active)
        #expect(!h.locations.backgroundActive)
        #expect(!h.motion.active)
        #expect(!h.battery.monitoring)
        #expect(!controller.isRunning)
        #expect(controller.activeSessionId == nil)
        #expect(h.alerts.bodies.isEmpty)
        let last = await latestSnapshot(controller)
        #expect(last?.activeSeconds == 9)
        #expect(last?.state == .finished, "ostatnia migawka mówi o zakończeniu (Live Activity, Task 16)")
        #expect(h.logs.lines.contains { $0.hasPrefix("Koniec nagrywania — czas jazdy 9 s, punkty 8, dokładność 5 m") })
        #expect(await controller.finish() == nil, "drugie zakończenie nic nie robi")
    }

    /// Dziennik diagnostyczny (prawdziwy `DiagnosticLog` w pliku): wpisy stanu z czasem, liczbą punktów i dokładnością, ale bez współrzędnych
    /// i nazwy konia — na ścieżce start → słaby GPS → bateria (ostrzeżenie budowane z tekstów) → pauza → wznowienie → zabicie →
    /// ponowne uruchomienie → cofnięcie zgody (powiadomienie) → nowa jazda → koniec.
    @Test func diagnosticLogHasNoCoordinatesOrHorseName() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let log = DiagnosticLog(directory: h.directory.appendingPathComponent("Logs"), dates: FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 5)!))
        let write: @Sendable (String) -> Void = { log.log(RideRecordingController.logCategory, $0) }
        let horse = HorseRef(id: "h9", name: "Iskierka Gniada", passportNumber: "PL-123")
        let krakow: @Sendable (Int, Double) -> LocationSample = { step, accuracy in
            LocationSample(lat: 50.0647 + Double(step) * 0.0001, lon: 19.9450, altM: 219.5, speedMs: 2.2, hAccM: accuracy)
        }
        let store = try h.openStore()
        let controller = h.controller(store, log: write)
        let id = try await controller.start(horse: horse, params: params)
        for s in 1...6 {
            h.clock.millis = START + Int64(s) * 1_000
            await h.emit(krakow(s, 4.6), to: controller)
            await controller.tick()
        }
        for s in 7...38 {
            h.clock.millis = START + Int64(s) * 1_000
            await h.emit(krakow(s, 40.0), to: controller)
            await controller.tick()
        }
        h.clock.millis = START + 39_000
        await h.emit(krakow(39, 4.6), to: controller)
        h.battery.level = 15
        await controller.tick()
        h.clock.millis = START + 40_000
        await controller.pause()
        h.clock.millis = START + 50_000
        await controller.resume()
        h.clock.millis = START + 51_000
        await h.emit(krakow(40, 4.6), to: controller)
        await controller.tick()

        // Zabicie i ponowne uruchomienie, potem cofnięcie zgody.
        h.clock.millis = START + 90_000
        let locations = FakeLocationSource()
        let restarted = h.controller(try h.openStore(), locations: locations, log: write)
        await restarted.prepareRelaunch()?.value
        h.clock.millis = START + 91_000
        await h.emit(krakow(41, 4.6), to: restarted, via: locations)
        locations.authorization = .denied
        await restarted.tick()

        // Nowa jazda po odrzuceniu poprzedniej i zwykłe zakończenie.
        try await store.discard(sessionId: id)
        h.clock.millis = START + 200_000
        let fresh = h.controller(try h.openStore(), log: write)
        _ = try await fresh.start(horse: horse, params: params)
        h.clock.millis = START + 201_000
        await h.emit(krakow(50, 4.6), to: fresh)
        h.clock.millis = START + 202_000
        await fresh.finish()

        let text = log.text()
        for expected in [
            "Start nagrywania", "Słaby GPS", "Koniec słabego GPS", "Bateria 15%", "Pauza", "Wznowienie", "Ponowne uruchomienie",
            "Cofnięto zgodę na lokalizację", "Koniec nagrywania", "Słaby GPS — czas jazdy 37 s, punkty 37, dokładność 40 m",
            "Koniec słabego GPS — czas jazdy 39 s, punkty 39, dokładność 5 m", "Start nagrywania — czas jazdy 0 s, punkty 0, dokładność brak",
        ] {
            #expect(text.contains(expected), "brak wpisu „\(expected)”")
        }
        for forbidden in ["Iskierka", "Gniada", "PL-123", "50.06", "50,06", "19.94", "19,94", "19.945", "219"] {
            #expect(!text.contains(forbidden), "dziennik zawiera „\(forbidden)”")
        }
        #expect(log.entries().allSatisfy { $0.contains("\t\(RideRecordingController.logCategory)\t") })

        // Ścieżka powiadomień: ostrzeżenia też są bez współrzędnych; nazwa konia jest tylko w treści bieżącego stanu (Live Activity).
        #expect(h.alerts.bodies == [
            "Słaby sygnał GPS", "Bateria 15% — nagrywanie trwa, podłącz telefon albo zakończ jazdę.",
            "Nagrywanie przerwane — otwórz aplikację, aby zapisać jazdę",
        ])
        for body in h.alerts.bodies {
            #expect(!body.contains("50,06") && !body.contains("50.06") && !body.contains("Iskierka"))
        }
        let content = RideNotificationContent.contentText(
            horseName: horse.name, snapshot: RideSnapshot(state: .recording, activeSeconds: 600, distanceMeters: 1_250, speedKmh: 12, gait: .trot, weakGps: false),
            texts: .stringsXml
        )
        #expect(content == "Iskierka Gniada · 10 min · 1,3 km · kłus")
        #expect(!log.text().contains(content))
    }

    // MARK: Ruling Task 12: grawitacja

    /// Spoczynek: `userAcceleration` = 0, `gravity` = 1 g w dowolnym kierunku → moduł próbki ≈ 1 g = 9,80665 m/s² (z samego
    /// `userAcceleration` byłoby 0).
    @Test func deviceMotionAtRestGivesOneGravity() {
        let sample = DeviceMotionConversion.sample(
            timestamp: 1.5, userAcceleration: MotionVector(x: 0, y: 0, z: 0), gravity: MotionVector(x: 0, y: -0.6, z: -0.8)
        )
        let magnitude = (Double(sample.x) * Double(sample.x) + Double(sample.y) * Double(sample.y) + Double(sample.z) * Double(sample.z)).squareRoot()
        #expect(abs(magnitude - 9.80665) < 1e-4)
        #expect(sample.tNanos == 1_500_000_000)
        #expect(sample.x == 0)
        #expect(abs(Double(sample.y) - -0.6 * 9.80665) < 1e-5)

        let moving = DeviceMotionConversion.sample(
            timestamp: 2, userAcceleration: MotionVector(x: 0.1, y: 0.2, z: 0.05), gravity: MotionVector(x: 0, y: 0, z: -1)
        )
        #expect(abs(Double(moving.x) - 0.1 * 9.80665) < 1e-5)
        #expect(abs(Double(moving.y) - 0.2 * 9.80665) < 1e-5)
        #expect(abs(Double(moving.z) - -0.95 * 9.80665) < 1e-5)
    }

    /// Drganie 1,25 Hz (75 kroków/min) w `userAcceleration` na osi pionowej: z grawitacją analizator widzi 75/min; bez grawitacji moduł
    /// to wyprostowany sinus i rytm wychodzi podwojony (150/min) — dlatego źródło ruchu dodaje `gravity`.
    @Test func cadenceNeedsGravityFromDeviceMotion() throws {
        func samples(gravityZ: Double) -> [AccelSample] {
            (0...250).map { i in
                let t = Double(i) * 0.02
                return DeviceMotionConversion.sample(
                    timestamp: 100 + t, userAcceleration: MotionVector(x: 0, y: 0, z: 0.1 * sin(2 * Double.pi * 1.25 * t)),
                    gravity: MotionVector(x: 0, y: 0, z: gravityZ)
                )
            }
        }
        let withGravity = try #require(CadenceAnalyzer.analyze(samples(gravityZ: -1)).cadence)
        #expect(withGravity > 72 && withGravity < 78, "rytm 1,25 Hz = 75/min, jest \(withGravity)")
        let withoutGravity = try #require(CadenceAnalyzer.analyze(samples(gravityZ: 0)).cadence)
        #expect(withoutGravity > 145 && withoutGravity < 155, "bez grawitacji rytm podwojony, jest \(withoutGravity)")
    }

    // MARK: Task 14 M5: ponowienie tej samej partii

    /// Gdy zapis do bazy się nie uda po `drainUnsaved()`, oddane punkty nie giną: następny zapis wysyła tę samą partię razem z nowymi.
    /// Prawdziwy sklep; błąd wywołuje wyzwalacz SQLite na `ride_point` (cała transakcja `flush` się cofa).
    @Test func failedFlushRetriesTheSameBatch() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let database = try #require(h.opened.last)
        try await database.writer.write { db in
            try db.execute(sql: "CREATE TABLE test_switch (failing INTEGER NOT NULL)")
            try db.execute(sql: "INSERT INTO test_switch VALUES (1)")
            try db.execute(sql: """
                CREATE TRIGGER test_fail_points BEFORE INSERT ON ride_point WHEN (SELECT failing FROM test_switch) = 1
                BEGIN SELECT RAISE(ABORT, 'test'); END
                """)
        }
        let controller = h.controller(store)
        let id = try await controller.start(horse: grom, params: params)
        for s in 1...5 { await second(h, controller, s) }
        #expect(try await store.load(sessionId: id).track.points.isEmpty, "zapis w 5. sekundzie się nie udał")
        #expect(h.logs.lines.contains { $0.hasPrefix("Zapis jazdy nie powiódł się (") && $0.hasSuffix("— ponowię przy następnym zapisie") })

        try await database.writer.write { db in try db.execute(sql: "UPDATE test_switch SET failing = 0") }
        for s in 6...10 { await second(h, controller, s) }

        let points = try await store.load(sessionId: id).track.points
        #expect(points.map(\.tMillis) == (1...10).map { START + Int64($0) * 1_000 }, "partia z nieudanego zapisu dotarła razem z nowymi punktami")
        #expect(points.map(\.lat) == (1...10).map { 52.0 + Double($0) * 0.0001 })
        #expect(try await store.load(sessionId: id).session.lastFlushMillis == START + 10_000)
    }

    // MARK: Task 13 M5: nieznany stan z bazy

    /// Nieznany stan sesji w bazie to `.interrupted`: przy starcie aplikacji nie jest wznawiany (czeka na „Zapisz / Odrzuć”) i nic się nie wywraca.
    @Test func unknownSessionStateIsTreatedAsInterruptedOnRelaunch() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let id = try await store.start(horse: grom, params: params, startedAtMillis: START)
        let database = try #require(h.opened.last)
        try await database.writer.write { db in try db.execute(sql: "UPDATE ride_session SET state = 'Bzdura'") }
        #expect(store.activeSessionStateNow() == .interrupted)

        let controller = h.controller(store)
        #expect(controller.prepareRelaunch() == nil)
        await controller.resumeAfterRelaunch()
        #expect(!controller.isRunning)
        #expect(!h.locations.active)
        #expect(h.locations.backgroundBegun == 0)
        #expect(try await store.unfinished()?.state == .interrupted)
        #expect(try await store.unfinished()?.sessionId == id)
        #expect(h.alerts.bodies.isEmpty)
    }

    // MARK: Pozostałe testy Androida

    /// Android: `sticky restart without location permission marks session interrupted and notifies` (`ServiceRestartWithoutPermissionTest`).
    @Test func relaunchWithoutPermissionMarksInterruptedAndNotifies() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let firstStore = try h.openStore()
        let first = h.controller(firstStore)
        let id = try await first.start(horse: grom, params: params)
        for s in 1...6 { await second(h, first, s) }

        h.clock.millis = START + 60_000
        let locations = FakeLocationSource(authorization: .denied)
        let restarted = h.controller(try h.openStore(), locations: locations)
        let relaunch = try #require(restarted.prepareRelaunch())
        #expect(locations.backgroundBegun == 0, "bez zgody nie zaczynamy aktywności w tle")
        await relaunch.value

        let loaded = try await firstStore.load(sessionId: id)
        #expect(loaded.session.state == .interrupted)
        #expect(loaded.track.points.count == 5, "punkty zapisane przed zabiciem zostają")
        #expect(!locations.active)
        #expect(locations.starts == 0, "bez uprawnienia nie słuchamy GPS")
        #expect(!restarted.isRunning)
        #expect(h.alerts.bodies == ["Nagrywanie przerwane — otwórz aplikację, aby zapisać jazdę"])
        #expect(h.logs.lines.contains("Ponowne uruchomienie: brak zgody na dokładną lokalizację (odmowa) — jazda przerwana"))
    }

    /// Android: `sticky restart with nothing to continue just stops` + `sticky restart of a finished ride … stops`; sesja przerwana (np. po
    /// zamknięciu przesunięciem) też nie jest wznawiana.
    @Test func relaunchWithNothingToContinueDoesNothing() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        #expect(controller.prepareRelaunch() == nil)
        await controller.resumeAfterRelaunch()
        #expect(!h.locations.active)

        let id = try await store.start(horse: grom, params: params, startedAtMillis: START)
        for state in [RideState.finished, .interrupted] {
            try await store.setState(sessionId: id, state: state)
            #expect(controller.prepareRelaunch() == nil)
            await controller.resumeAfterRelaunch()
            #expect(!controller.isRunning)
            #expect(h.locations.starts == 0)
            #expect(h.locations.backgroundBegun == 0)
            #expect(try await store.load(sessionId: id).session.state == state)
        }
        #expect(h.alerts.bodies.isEmpty)
    }

    /// Android: `a paused ride stays paused after restart`. Sesja aktywności w tle wraca (żeby „Wznów” z ekranu blokady mógł uruchomić GPS).
    @Test func pausedRideStaysPausedAfterRelaunch() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let first = h.controller(store)
        let id = try await first.start(horse: grom, params: params)
        for s in 1...6 { await second(h, first, s) }
        h.clock.millis = START + 7_000
        await first.pause()

        h.clock.millis = START + 60_000
        let locations = FakeLocationSource()
        let restarted = h.controller(try h.openStore(), locations: locations)
        await restarted.prepareRelaunch()?.value
        #expect(!locations.active, "pauza użytkownika przetrwa restart")
        #expect(locations.backgroundActive)
        #expect(restarted.isRunning)
        #expect(await latestSnapshot(restarted)?.state == .paused)
        #expect(try await store.load(sessionId: id).session.state == .paused)

        h.clock.millis = START + 70_000
        await restarted.resume()
        #expect(locations.active)
        #expect(try await store.load(sessionId: id).session.state == .recording)
    }

    /// Android: `pause stops the sensors and is persisted and resume starts them and drops the half window` + `pause and resume actions switch
    /// the button and the state`.
    @Test func pauseStopsSensorsAndResumeDropsTheHalfWindow() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        let id = try await controller.start(horse: grom, params: params)

        // 4 s próbek przed pauzą (okno niepełne).
        for i in 0..<200 {
            h.clock.millis = START + Int64(i) * 20
            await h.emit(motion: AccelSample(tNanos: Int64(i) * 20_000_000, x: 0, y: 0, z: Float(9.81 + sin(2 * Double.pi * 2.5 * Double(i) * 0.02))), to: controller)
        }
        await second(h, controller, 4)
        h.clock.millis = START + 4_500
        await controller.pause()
        #expect(!h.locations.active)
        #expect(h.locations.backgroundActive, "iOS: sesja aktywności w tle zostaje na czas pauzy")
        #expect(!h.motion.active)
        let paused = try await store.load(sessionId: id)
        #expect(paused.session.state == .paused)
        #expect(paused.track.pauses.count == 1)
        #expect(paused.track.pauses.first?.startMillis == START + 4_500)
        #expect(await latestSnapshot(controller)?.state == .paused)

        h.clock.millis = START + 60_000
        await controller.resume()
        #expect(h.locations.active)
        #expect(h.motion.active)
        #expect(try await store.load(sessionId: id).session.state == .recording)

        // 2 s po wznowieniu: bez zerowania bufora okno 5 s zamknęłoby się na próbkach sprzed pauzy.
        for i in 0..<100 {
            h.clock.millis = START + 60_000 + Int64(i) * 20
            if i == 0 { await h.emit(goodFix(10), to: controller) }
            await h.emit(motion: AccelSample(tNanos: Int64(300 + i) * 20_000_000, x: 0, y: 0, z: 9.81), to: controller)
        }
        await controller.finish()

        let points = try await store.load(sessionId: id).track.points
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.intensity == nil }, "okno z próbek sprzed pauzy nie może się domknąć po wznowieniu")
    }

    /// Android: `accelerometer windows of 5 seconds add cadence and intensity to the closing point`.
    @Test func accelerometerWindowsAddCadenceAndIntensityToTheClosingPoint() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        let id = try await controller.start(horse: grom, params: params)

        // 50 Hz przez 6 s, rytm 2,5 Hz (150/min); punkt GPS co sekundę.
        for i in 0...300 {
            h.clock.millis = START + Int64(i) * 20
            if i % 50 == 0 && i > 0 { await h.emit(goodFix(i / 50), to: controller) }
            let t = Double(i) * 0.02
            await h.emit(motion: AccelSample(tNanos: Int64(i) * 20_000_000, x: 0, y: 0, z: Float(9.81 + sin(2 * Double.pi * 2.5 * t))), to: controller)
            if i % 50 == 0 { await controller.tick() }
        }
        await controller.finish()

        let loaded = try await store.load(sessionId: id)
        let withMotion = loaded.track.points.filter { $0.intensity != nil }
        #expect(withMotion.map(\.tMillis) == [START + 5_000], "okno 5 s kończy się w punkcie GPS z 5. sekundy")
        let cadence = try #require(withMotion.first?.cadence)
        #expect(cadence > 145 && cadence < 155, "rytm 2,5 Hz = 150/min, jest \(cadence)")
        #expect(loaded.session.accelerometerUsed)
    }

    /// Android: `auto finish after 8 hours saves the last points and sets Finished`.
    @Test func autoFinishAfter8HoursSavesTheLastPointsAndSetsFinished() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        let id = try await controller.start(horse: grom, params: params)
        for s in 1...3 { await second(h, controller, s) }
        h.clock.millis = START + 8 * 3_600_000
        await controller.tick()

        let loaded = try await store.load(sessionId: id)
        #expect(loaded.session.state == .finished)
        #expect(loaded.track.points.count == 3)
        #expect(!h.locations.active)
        #expect(!h.locations.backgroundActive)
        #expect(!controller.isRunning)
        #expect(h.alerts.bodies == ["Nagrywanie zakończone po 8 godzinach."])
        #expect(h.logs.lines.contains { $0.hasPrefix("Koniec nagrywania po 8 godzinach") })
        // Dalsze zdarzenia nie ruszają zakończonej jazdy.
        h.locations.emit(goodFix(99))
        await controller.tick()
        #expect(h.alerts.bodies.count == 1)
        #expect(await controller.finish() == nil)
    }

    /// Android: `battery low is reported once with the level`. Bateria monitorowana tylko w trakcie nagrywania (odpowiednik blokady procesora
    /// Androida `the recording holds a partial wake lock until the ride ends`).
    @Test func batteryLowIsReportedOnceWithTheLevel() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        #expect(!h.battery.monitoring)
        _ = try await controller.start(horse: grom, params: params)
        #expect(h.battery.monitoring)
        h.battery.level = 15
        await second(h, controller, 1)
        await second(h, controller, 2)
        h.battery.level = 14
        await second(h, controller, 3)
        #expect(h.alerts.bodies == ["Bateria 15% — nagrywanie trwa, podłącz telefon albo zakończ jazdę."])
        await controller.finish()
        #expect(!h.battery.monitoring)
    }

    /// Android: `weak gps is reported in the snapshot`; na iOS także powiadomienie lokalne, zdejmowane po powrocie sygnału.
    @Test func weakGpsIsReportedInTheSnapshotAndAsAnAlert() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        _ = try await controller.start(horse: grom, params: params)
        for s in 1...32 { await second(h, controller, s, accuracy: 40.0) }
        #expect(await latestSnapshot(controller)?.weakGps == true)
        #expect(h.alerts.bodies == ["Słaby sygnał GPS"])
        #expect(h.alerts.removed.isEmpty)

        await second(h, controller, 33)
        #expect(await latestSnapshot(controller)?.weakGps == false)
        #expect(h.alerts.removed == [.weakGps])
    }

    /// Android: `interrupt saves the last points and marks the session Interrupted` (iOS: `applicationWillTerminate` po zamknięciu przesunięciem).
    @Test func interruptSavesTheLastPointsAndMarksTheSessionInterrupted() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        let id = try await controller.start(horse: grom, params: params)
        for s in 1...3 { await second(h, controller, s) }

        await controller.interrupt()

        let loaded = try await store.load(sessionId: id)
        #expect(loaded.session.state == .interrupted)
        #expect(loaded.track.points.count == 3)
        #expect(!h.locations.active)
        #expect(!h.locations.backgroundActive)
        #expect(!controller.isRunning)
        #expect(h.alerts.bodies.isEmpty, "przerwanie przez zamknięcie aplikacji nie wysyła powiadomienia")
        // Po przerwaniu ponowne uruchomienie nie wznawia jazdy — czeka „Zapisz / Odrzuć”.
        #expect(controller.prepareRelaunch() == nil)
    }

    /// Android: `a second start while recording keeps the service in foreground` — drugi start nie rusza nagrywanej jazdy.
    @Test func secondStartWhileRecordingIsRefused() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        let id = try await controller.start(horse: grom, params: params)
        await #expect(throws: RideStartError.alreadyRecording) {
            _ = try await controller.start(horse: grom, params: params)
        }
        #expect(controller.activeSessionId == id)
        #expect(h.locations.starts == 1)
        // Niezapisana poprzednia jazda blokuje start w innym kontrolerze (sklep: jedna sesja naraz).
        await #expect(throws: RideSessionError.onlyOneActiveSession) {
            _ = try await h.controller(store, locations: FakeLocationSource()).start(horse: grom, params: params)
        }
    }

    // MARK: AccelWindowBuffer (Android: AccelWindowBufferTest)

    private func accel(_ ms: Int64) -> AccelSample { AccelSample(tNanos: ms * 1_000_000, x: 0, y: 0, z: 9.81) }

    /// Android: `window is returned when the samples span 5 seconds`.
    @Test func windowIsReturnedWhenTheSamplesSpan5Seconds() throws {
        var buffer = AccelWindowBuffer()
        for ms in stride(from: Int64(0), to: 5_000, by: 20) { #expect(buffer.add(accel(ms)) == nil) }
        let window = try #require(buffer.add(accel(5_000)))
        #expect(window.count == 251)
        #expect(window.first?.tNanos == 0)
        #expect(window.last?.tNanos == 5_000_000_000)
    }

    /// Android: `next window starts empty`.
    @Test func nextWindowStartsEmpty() {
        var buffer = AccelWindowBuffer()
        for ms in stride(from: Int64(0), through: 5_000, by: 20) { _ = buffer.add(accel(ms)) }
        for ms in stride(from: Int64(5_020), through: 9_980, by: 20) { #expect(buffer.add(accel(ms)) == nil) }
        #expect(buffer.add(accel(10_020)) != nil)
    }

    /// Android: `clear drops the collected samples`.
    @Test func clearDropsTheCollectedSamples() {
        var buffer = AccelWindowBuffer()
        for ms in stride(from: Int64(0), to: 4_000, by: 20) { _ = buffer.add(accel(ms)) }
        buffer.clear()
        for ms in stride(from: Int64(10_000), to: 13_000, by: 20) { #expect(buffer.add(accel(ms)) == nil) }
    }

    // MARK: LocationSample z CLLocation

    /// `CLLocation` → punkt: wartości ujemne (nieznane w Core Location) to `nil`, ujemna dokładność pozioma — punkt nieważny.
    @Test func locationSampleMapsUnknownValuesToNil() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let full = try #require(LocationSample(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52.1, longitude: 21.2), altitude: 101.5, horizontalAccuracy: 4.5, verticalAccuracy: 3,
            course: 0, speed: 2.5, timestamp: date
        )))
        #expect(full == LocationSample(lat: 52.1, lon: 21.2, altM: 101.5, speedMs: 2.5, hAccM: 4.5))
        #expect(full.trackPoint(tMillis: START) == TrackPoint(tMillis: START, lat: 52.1, lon: 21.2, altM: 101.5, speedMs: 2.5, hAccM: 4.5, cadence: nil, intensity: nil))

        let partial = try #require(LocationSample(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52.1, longitude: 21.2), altitude: 101.5, horizontalAccuracy: 30, verticalAccuracy: -1,
            course: -1, speed: -1, timestamp: date
        )))
        #expect(partial == LocationSample(lat: 52.1, lon: 21.2, altM: nil, speedMs: nil, hAccM: 30))

        #expect(LocationSample(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52.1, longitude: 21.2), altitude: 0, horizontalAccuracy: -1, verticalAccuracy: -1,
            course: -1, speed: -1, timestamp: date
        )) == nil)
    }
}

// MARK: - Środowisko testów

private let START: Int64 = 1_790_000_000_000

/// Punkt GPS o dobrej dokładności, przesunięty na północ o `step` × ok. 11 m (jak `goodFix` w Androidzie).
private func goodFix(_ step: Int, accuracy: Double = 5.0) -> LocationSample {
    LocationSample(lat: 52.0 + Double(step) * 0.0001, lon: 21.0, altM: 100.0, speedMs: 2.2, hAccM: accuracy)
}

extension RideNotificationTexts {
    /// Teksty przepisane ze `strings.xml` Androida 3.0.2 (format po `sync-strings.ps1`) — pakiet nie ma katalogu aplikacji; zgodność
    /// z katalogiem sprawdza `RideNotificationTextTests` w `AppSnapshotTests`.
    static let stringsXml = RideNotificationTexts(
        title: "Nagrywanie jazdy", weakGps: "Słaby sygnał GPS", paused: "pauza", gaitStop: "postój", gaitWalk: "stęp", gaitTrot: "kłus",
        gaitCanter: "galop", durationMinutes: "%1$lld min", durationHoursMinutes: "%1$lld h %2$02lld min", distanceKm: "%1$@ km",
        batteryLow: "Bateria %1$lld%% — nagrywanie trwa, podłącz telefon albo zakończ jazdę.", autoFinished: "Nagrywanie zakończone po 8 godzinach.",
        interrupted: "Nagrywanie przerwane — otwórz aplikację, aby zapisać jazdę"
    )
}

/// Zegar sterowany z testu (epoka, ms) — wspólny dla kontrolera i sklepu.
private final class ControllerClock: Sendable {
    private let value: Mutex<Int64>

    init(_ start: Int64) {
        value = Mutex(start)
    }

    var millis: Int64 {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }

    var millisProvider: @Sendable () -> Int64 { { [self] in self.millis } }
    var dateProvider: @Sendable () -> Date { { [self] in Date(timeIntervalSince1970: TimeInterval(self.millis) / 1000) } }
}

/// Zaślepka źródła lokalizacji: test sam „nadaje” punkty przez `emit`.
private final class FakeLocationSource: LocationSource {
    private struct State {
        var authorization: LocationAuthorization
        var continuation: AsyncStream<LocationSample>.Continuation?
        var background = false
        var backgroundBegun = 0
        var starts = 0
    }

    private let state: Mutex<State>

    init(authorization: LocationAuthorization = .whenInUse) {
        state = Mutex(State(authorization: authorization))
    }

    var authorization: LocationAuthorization {
        get { state.withLock { $0.authorization } }
        set { state.withLock { $0.authorization = newValue } }
    }

    var active: Bool { state.withLock { $0.continuation != nil } }
    var backgroundActive: Bool { state.withLock { $0.background } }
    var backgroundBegun: Int { state.withLock { $0.backgroundBegun } }
    var starts: Int { state.withLock { $0.starts } }

    func updates() -> AsyncStream<LocationSample> {
        let (stream, continuation) = AsyncStream<LocationSample>.makeStream()
        let previous = state.withLock { current -> AsyncStream<LocationSample>.Continuation? in
            let old = current.continuation
            current.continuation = continuation
            current.background = true
            current.starts += 1
            return old
        }
        previous?.finish()
        return stream
    }

    func stopUpdates() {
        state.withLock { current -> AsyncStream<LocationSample>.Continuation? in
            defer { current.continuation = nil }
            return current.continuation
        }?.finish()
    }

    func stop() {
        stopUpdates()
        state.withLock { $0.background = false }
    }

    func beginBackgroundActivity() {
        state.withLock { current in
            current.background = true
            current.backgroundBegun += 1
        }
    }

    func emit(_ sample: LocationSample) {
        _ = state.withLock { $0.continuation }?.yield(sample)
    }
}

/// Zaślepka akcelerometru.
private final class FakeMotionSource: MotionSource {
    private let continuation = Mutex<AsyncStream<AccelSample>.Continuation?>(nil)

    var active: Bool { continuation.withLock { $0 != nil } }

    func samples() -> AsyncStream<AccelSample> {
        let (stream, new) = AsyncStream<AccelSample>.makeStream()
        continuation.withLock { $0 = new }
        return stream
    }

    func stop() {
        continuation.withLock { current -> AsyncStream<AccelSample>.Continuation? in
            defer { current = nil }
            return current
        }?.finish()
    }

    func emit(_ sample: AccelSample) {
        _ = continuation.withLock { $0 }?.yield(sample)
    }
}

/// Bateria sterowana z testu.
private final class FakeBattery: BatteryMonitor {
    private struct State {
        var level: Int? = 80
        var monitoring = false
    }

    private let state = Mutex(State())

    var level: Int? {
        get { state.withLock { $0.level } }
        set { state.withLock { $0.level = newValue } }
    }

    var monitoring: Bool { state.withLock { $0.monitoring } }

    func start() { state.withLock { $0.monitoring = true } }
    func stop() { state.withLock { $0.monitoring = false } }
    func percent() async -> Int? { state.withLock { $0.monitoring ? $0.level : nil } }
}

/// Zbiera ostrzeżenia zamiast wysyłać je do `UNUserNotificationCenter`.
private final class AlertRecorder: RideAlertPoster {
    private struct State {
        var posted: [RideAlert] = []
        var removed: [RideAlert.Kind] = []
    }

    private let state = Mutex(State())

    var bodies: [String] { state.withLock { $0.posted.map(\.body) } }
    var removed: [RideAlert.Kind] { state.withLock { $0.removed } }

    func post(_ alert: RideAlert) async { state.withLock { $0.posted.append(alert) } }
    func remove(_ kind: RideAlert.Kind) async { state.withLock { $0.removed.append(kind) } }
}

/// Wpisy dziennika kontrolera (bez pliku).
private final class LogLines: Sendable {
    private let state = Mutex<[String]>([])

    var lines: [String] { state.withLock { $0 } }

    var append: @Sendable (String) -> Void { { [self] line in self.state.withLock { $0.append(line) } } }
}

/// Katalog bazy w katalogu tymczasowym, zaślepki i fabryka kontrolerów.
private final class ControllerHarness: @unchecked Sendable {
    let clock = ControllerClock(START)
    let locations = FakeLocationSource()
    let motion = FakeMotionSource()
    let battery = FakeBattery()
    let alerts = AlertRecorder()
    let logs = LogLines()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-ride-controller-\(UUID().uuidString)", isDirectory: true)
    private(set) var opened: [AppDatabase] = []

    /// Nowa „instancja procesu”: baza z prawdziwego pliku i świeży sklep (ten sam zegar).
    func openStore() throws -> RideSessionStore {
        let database = try AppDatabase.open(in: directory)
        opened.append(database)
        return RideSessionStore(db: database.writer, now: clock.dateProvider, timeZone: "Europe/Warsaw")
    }

    func controller(
        _ store: RideSessionStore, locations: FakeLocationSource? = nil, motion: FakeMotionSource? = nil, log: (@Sendable (String) -> Void)? = nil
    ) -> RideRecordingController {
        RideRecordingController(
            store: store, locations: locations ?? self.locations, motion: motion ?? self.motion, battery: battery,
            notifier: LocalRideNotifier(texts: .stringsXml, poster: alerts), clock: clock.millisProvider, log: log ?? logs.append,
            tickInterval: nil
        )
    }

    /// Nadaje punkt i czeka, aż kontroler go obsłuży (łącznie z zapisem, gdy był należny).
    func emit(_ sample: LocationSample, to controller: RideRecordingController, via source: FakeLocationSource? = nil) async {
        let before = await controller.receivedLocations
        (source ?? locations).emit(sample)
        let handled = await waitUntil { await controller.receivedLocations > before }
        #expect(handled, "kontroler nie odebrał punktu")
    }

    /// Nadaje próbkę ruchu i czeka, aż kontroler ją obsłuży.
    func emit(motion sample: AccelSample, to controller: RideRecordingController) async {
        let before = await controller.receivedMotionSamples
        motion.emit(sample)
        let handled = await waitUntil { await controller.receivedMotionSamples > before }
        #expect(handled, "kontroler nie odebrał próbki ruchu")
    }

    private func waitUntil(_ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    func cleanUp() {
        for database in opened { try? database.writer.close() }
        try? FileManager.default.removeItem(at: directory)
    }
}
