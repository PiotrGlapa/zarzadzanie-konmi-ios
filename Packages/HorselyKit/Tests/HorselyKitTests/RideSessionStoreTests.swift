import Foundation
import GRDB
import HorselyCore
import Synchronization
import Testing
@testable import HorselyKit

/// Zapis sesji nagrywania na bieżąco i odzyskiwanie (Task 14 = Android Task 13, `RideSessionRecoveryTest.kt` + `RideSessionDaoTest.kt`):
/// zabicie procesu nie gubi tego, co zapisano wcześniej. „Zabicie procesu” to zamknięcie bazy i otwarcie nowej na TYM SAMYM pliku
/// (prawdziwy plik `horsely.sqlite` w katalogu tymczasowym, nie `:memory:`) z nowym `RideSessionStore` i nową maszyną nagrywania.
///
/// Wszystkie 15 testów `RideSessionRecoveryTest.kt` jest zportowanych (nazwy angielskie Androida w komentarzach `///`), do tego trzy testy
/// `RideSessionDaoTest.kt` na poziomie sklepu oraz testy własne iOS: oczyszczanie błędnych pauz i punktów z bazy (Task 13 M2), nieznany
/// stan (M5), uszkodzone progi, przeżycie sesji po czyszczeniu magazynu i odtworzeniu kopii, strumień paska NAG-01.
struct RideSessionStoreTests {
    private let params: EffectiveRideParameters = RideParameters.resolve(RideDefaults.builtIn, nil)
    private let grom = HorseRef(id: "h1", name: "Grom", passportNumber: nil)
    private let iskra = HorseRef(id: "h2", name: "Iskra", passportNumber: nil)

    // MARK: Pomocnicze

    private func location(_ second: Int, _ step: Int) -> TrackPoint {
        TrackPoint(
            tMillis: START + Int64(second) * 1_000, lat: 52.0 + Double(step) * 0.0001, lon: 21.0, altM: 100.0, speedMs: 2.2, hAccM: 5.0,
            cadence: nil, intensity: nil
        )
    }

    /// Maszyna, która dostała punkty co 5 s od `from` do `to` sekundy jazdy.
    private func ride(_ recorder: RideRecorder, from: Int, to: Int) {
        for second in stride(from: from, through: to, by: 5) { recorder.onLocation(location(second, second / 5)) }
    }

    private func newRecorder() -> RideRecorder {
        RideRecorder(startedAtMillis: START, thresholds: params.thresholds)
    }

    private func flush(_ store: RideSessionStore, _ id: String, _ recorder: RideRecorder) async throws {
        try await store.flush(sessionId: id, points: recorder.drainUnsaved(), snapshot: recorder.snapshot(), pauses: recorder.pauses())
    }

    private func rowCount(_ table: String, sessionId: String, in database: AppDatabase) async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE sessionId = '\(sessionId)'") ?? 0
        }
    }

    private func pointRow(_ sessionId: String, offset: Int) -> RidePointRow {
        RidePointRow(sessionId: sessionId, seq: offset, tMillis: offset, lat: 52.0, lon: 21.0, altM: nil, speedMs: nil, hAccM: 5.0, vAccM: nil, cadence: nil, intensity: nil)
    }

    private func sessionRow(_ id: String, state: String, startedAt: Int64) -> RideSessionRow {
        RideSessionRow(
            id: id, horseId: "h1", horseName: "Grom", state: state, startedAtMillis: startedAt, endedAtMillis: nil, timeZone: "Europe/Warsaw",
            pausesJson: "[]", thresholdsJson: "{}", loadJson: "{}", accelerometerUsed: 0, lastFlushMillis: startedAt, distanceMeters: 0, activeSeconds: 0
        )
    }

    /// Błąd rzucony przez `body` albo `nil`, gdy się udało.
    private func failure<T>(_ body: () async throws -> T) async -> (any Error)? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error
        }
    }

    // MARK: Android: RideSessionRecoveryTest

    /// Android: `flushed points survive a new repository instance`.
    @Test func flushedPointsSurviveNewStore() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let first = try harness.openDatabase()
        let store = harness.store(first)
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 30)
        let expected = recorder.drainUnsaved()
        harness.clock.millis = START + 30_000
        try await store.flush(sessionId: id, points: expected, snapshot: recorder.snapshot(), pauses: recorder.pauses())
        try first.writer.close()

        let loaded = try await harness.newProcessStore().load(sessionId: id)

        #expect(expected.count == 6)
        #expect(loaded.track.points == expected)
        #expect(loaded.track.startedAtMillis == START)
        #expect(loaded.session.horse.name == "Grom")
        #expect(loaded.session.horse.id == "h1")
        #expect(loaded.session.timeZone == "Europe/Warsaw")
        #expect(loaded.params == params)
        #expect(loaded.session.state == .recording)
        #expect(loaded.session.activeSeconds == 30)
        #expect(loaded.session.lastFlushMillis == START + 30_000)
    }

    /// Android: `unfinished ride reports horse time and distance`.
    @Test func unfinishedRideReportsHorseTimeAndDistance() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let first = try harness.openDatabase()
        let store = harness.store(first)
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 120)
        try await flush(store, id, recorder)
        let expectedDistance = recorder.snapshot().distanceMeters
        try first.writer.close()

        let unfinished = try #require(try await harness.newProcessStore().unfinished())

        #expect(unfinished.sessionId == id)
        #expect(unfinished.horseName == "Grom")
        #expect(unfinished.startedAt == Date(timeIntervalSince1970: TimeInterval(START) / 1000))
        #expect(unfinished.distanceMeters == expectedDistance)
        #expect(unfinished.distanceMeters > 200)
        #expect(unfinished.state == .recording)
        #expect(!unfinished.damaged)
    }

    /// Android: `discard removes points and media rows`.
    @Test func discardRemovesPointsAndMedia() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let database = try harness.openDatabase()
        let store = harness.store(database)
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 20)
        try await flush(store, id, recorder)
        try await store.addMedia(sessionId: id, uri: "file:///ride/1.jpg", contentType: "image/jpeg", capturedAt: Date(timeIntervalSince1970: TimeInterval(START + 10_000) / 1000), lat: 52.0, lon: 21.0)
        try await store.addMedia(sessionId: id, uri: "file:///ride/2.mp4", contentType: "video/mp4", capturedAt: Date(timeIntervalSince1970: TimeInterval(START + 15_000) / 1000), lat: nil, lon: nil)
        #expect(try await rowCount("ride_point", sessionId: id, in: database) == 4)
        #expect(try await rowCount("ride_media", sessionId: id, in: database) == 2)

        try await store.discard(sessionId: id)

        #expect(try await rowCount("ride_point", sessionId: id, in: database) == 0)
        #expect(try await rowCount("ride_media", sessionId: id, in: database) == 0)
        #expect(try await store.session(id: id) == nil)
        #expect(try await store.unfinished() == nil)
    }

    /// Android: `only one active session`.
    @Test func onlyOneActiveSession() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let first = try await store.start(horse: grom, params: params)

        let refused = await failure { try await store.start(horse: iskra, params: params) }
        #expect(refused as? RideSessionError == .onlyOneActiveSession)
        #expect(try await store.unfinished()?.sessionId == first)

        try await store.discard(sessionId: first)
        let second = try await store.start(horse: iskra, params: params)

        #expect(second != first)
        #expect(try await store.unfinished()?.horseName == "Iskra")
    }

    /// Android: `a finished but unsaved ride blocks a new start until it is discarded`.
    @Test func aFinishedButUnsavedRideBlocksANewStartUntilItIsDiscarded() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let first = try await store.start(horse: grom, params: params)
        try await store.setState(sessionId: first, state: .finished)

        let refused = await failure { try await store.start(horse: iskra, params: params) }

        let error = try #require(refused as? RideSessionError)
        #expect(error == .onlyOneActiveSession)
        #expect(error.localizedDescription.contains("zapisz"))
        #expect(try await store.unfinished()?.sessionId == first)
        try await store.discard(sessionId: first)
        let next = try await store.start(horse: iskra, params: params)
        #expect(next != first)
    }

    /// Android: `finished but unsaved ride is reported after a new process`.
    @Test func finishedButUnsavedRideIsReportedAfterANewProcess() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let first = try harness.openDatabase()
        let store = harness.store(first)
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 120)
        harness.clock.millis = START + 120_000
        try await flush(store, id, recorder)
        try await store.setState(sessionId: id, state: .finished)
        let expectedDistance = recorder.snapshot().distanceMeters
        try first.writer.close()

        let fresh = try harness.newProcessStore()
        let unfinished = try #require(try await fresh.unfinished())

        #expect(unfinished.sessionId == id)
        #expect(unfinished.state == .finished)
        #expect(unfinished.distanceMeters == expectedDistance)
        #expect(try await fresh.load(sessionId: id).track.points.count == 24)
        #expect(try await fresh.load(sessionId: id).session.endedAt == Date(timeIntervalSince1970: TimeInterval(START + 120_000) / 1000))
        // Nie jest już „w toku”: pasek NAG-01 go nie pokazuje.
        #expect(await firstSnapshot(fresh.observeActive()) == nil)
    }

    /// Android: `observeActive emits null after the ride is finished`.
    @Test func observeActiveEmitsNilAfterTheRideIsFinished() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 20)
        try await flush(store, id, recorder)
        #expect(await firstSnapshot(store.observeActive()) != nil)

        try await store.setState(sessionId: id, state: .finished)

        #expect(await firstSnapshot(store.observeActive()) == nil)
    }

    /// Android: `the recorder start time given to start keeps flush and restore consistent`.
    @Test func theRecorderStartTimeGivenToStartKeepsFlushAndRestoreConsistent() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let first = try harness.openDatabase()
        let store = harness.store(first)
        // Zegar sklepu wskazuje kilka ms później niż start maszyny — liczy się jawnie podany startedAtMillis.
        let startedAt = START - 7
        harness.clock.millis = START + 25
        let id = try await store.start(horse: grom, params: params, startedAtMillis: startedAt)
        let recorder = RideRecorder(startedAtMillis: startedAt, thresholds: params.thresholds)
        var early = location(0, 0)
        early.tMillis = startedAt + 2
        recorder.onLocation(early)
        ride(recorder, from: 5, to: 60)
        try await flush(store, id, recorder)
        try first.writer.close()

        let loaded = try await harness.newProcessStore().load(sessionId: id)
        let restored = loaded.restoreRecorder()

        #expect(loaded.track.startedAtMillis == startedAt)
        #expect(loaded.track.points.count == 13)
        #expect(restored.snapshot().activeSeconds == recorder.snapshot().activeSeconds)
        #expect(restored.snapshot().distanceMeters == recorder.snapshot().distanceMeters)
    }

    /// Android: `a point from before the session start fails clearly and changes nothing`.
    @Test func aPointFromBeforeTheSessionStartFailsClearlyAndChangesNothing() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        // Sklep sam bierze czas startu z zegara (START), a maszyna powstała 7 ms wcześniej — rozjazd źródeł czasu.
        let id = try await store.start(horse: grom, params: params)
        let before = try await store.session(id: id)
        let recorder = RideRecorder(startedAtMillis: START - 7, thresholds: params.thresholds)
        var early = location(0, 0)
        early.tMillis = START - 5
        recorder.onLocation(early)

        let refused = await failure { try await flush(store, id, recorder) }

        let error = try #require(refused as? RideSessionError)
        #expect(error == .pointOutsideSession(offsetMillis: -5))
        #expect(error.localizedDescription.contains("startedAtMillis"))
        #expect(try await store.session(id: id) == before)
        #expect(try await store.points(sessionId: id).isEmpty)
    }

    /// Android: `a process killed between flushes loses only what was not flushed and the ride can continue`.
    @Test func aProcessKilledBetweenFlushesLosesOnlyWhatWasNotFlushedAndTheRideCanContinue() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let first = try harness.openDatabase()
        let store = harness.store(first)
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 60)
        harness.clock.millis = START + 60_000
        try await flush(store, id, recorder)
        let flushedDistance = recorder.snapshot().distanceMeters
        // Punkty z ostatnich sekund przed zabiciem procesu nie zostały zapisane.
        ride(recorder, from: 65, to: 70)
        try first.writer.close()

        let fresh = try harness.newProcessStore()
        let unfinished = try #require(try await fresh.unfinished())
        try await fresh.setState(sessionId: id, state: .interrupted)
        let loaded = try await fresh.load(sessionId: id)
        let restored = loaded.restoreRecorder()

        #expect(unfinished.distanceMeters == flushedDistance)
        #expect(loaded.track.points.count == 12)
        #expect(loaded.session.state == .interrupted)
        #expect(restored.snapshot().state == .paused)
        #expect(restored.snapshot().distanceMeters == flushedDistance)
        // Wznowienie po przerwaniu dopisuje punkty od końca zapisanych i zapis ich nie dubluje.
        restored.resume(tMillis: START + 100_000)
        restored.onLocation(location(105, 21))
        harness.clock.millis = START + 105_000
        try await flush(fresh, id, restored)
        let after = try await fresh.load(sessionId: id)
        #expect(after.track.points.count == 13)
        #expect(after.session.state == .recording)
        #expect(after.track.pauses == [Pause(startMillis: START + 60_000, endMillis: START + 100_000)])
    }

    /// Android: `a point completed with motion after the flush replaces its row`.
    @Test func aPointCompletedWithMotionAfterTheFlushReplacesItsRow() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 15)
        try await flush(store, id, recorder)
        #expect(try await store.load(sessionId: id).session.accelerometerUsed == false)

        recorder.onMotion(tMillis: START + 15_000, WindowMotion(cadence: 62.5, intensity: 1.25))
        ride(recorder, from: 20, to: 20)
        let second = recorder.drainUnsaved()
        try await store.flush(sessionId: id, points: second, snapshot: recorder.snapshot(), pauses: recorder.pauses())

        let saved = try await store.points(sessionId: id)
        // Cztery wiersze (nie pięć): punkt z 15 s wrócił z `drainUnsaved()` drugi raz i trafił na ten sam wiersz.
        #expect(second.count == 2)
        #expect(saved.count == 4)
        #expect(saved.map(\.seq) == [5_000, 10_000, 15_000, 20_000])
        #expect(saved[2].cadence == 62.5)
        #expect(saved[2].intensity == 1.25)
        #expect(saved[1].cadence == nil)
        #expect(try await store.load(sessionId: id).session.accelerometerUsed)
    }

    /// Android: `flush keeps state pauses and flush time with the points in one transaction`.
    @Test func flushKeepsStatePausesAndFlushTimeWithThePointsInOneTransaction() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 20)
        recorder.pause(tMillis: START + 25_000)
        harness.clock.millis = START + 26_000
        try await flush(store, id, recorder)

        let row = try #require(try await store.session(id: id))
        #expect(row.state == "Paused")
        #expect(row.lastFlushMillis == START + 26_000)
        #expect(row.pausesJson.contains("\(START + 25_000)"))
        #expect(try await store.points(sessionId: id).count == 4)

        // Zły punkt (przed startem sesji) przerywa zapis w całości: stan, pauzy i czas zapisu zostają jak były.
        var broken = location(30, 6)
        broken.tMillis = START - 1
        var snapshot = recorder.snapshot()
        snapshot.state = .recording
        snapshot.distanceMeters = 999
        harness.clock.millis = START + 40_000
        let refused = await failure { try await store.flush(sessionId: id, points: [broken], snapshot: snapshot, pauses: []) }

        #expect(refused as? RideSessionError == .pointOutsideSession(offsetMillis: -1))
        #expect(try await store.session(id: id) == row)
        #expect(try await store.points(sessionId: id).count == 4)
    }

    /// Android: `a paused ride keeps its pause and unfinished reports it`.
    @Test func aPausedRideKeepsItsPauseAndUnfinishedReportsIt() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let first = try harness.openDatabase()
        let store = harness.store(first)
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 20)
        recorder.pause(tMillis: START + 25_000)
        harness.clock.millis = START + 26_000
        try await flush(store, id, recorder)
        try first.writer.close()

        let fresh = try harness.newProcessStore()
        let restored = try await fresh.load(sessionId: id).restoreRecorder()

        #expect(restored.snapshot().state == .paused)
        #expect(restored.snapshot().distanceMeters == recorder.snapshot().distanceMeters)
        #expect(restored.snapshot().activeSeconds == recorder.snapshot().activeSeconds)
        #expect(try await fresh.unfinished()?.distanceMeters == recorder.snapshot().distanceMeters)
        #expect(try await fresh.unfinished()?.state == .paused)
    }

    /// Android: `observeActive follows the persisted session and ends with it`.
    @Test func observeActiveFollowsThePersistedSessionAndEndsWithIt() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        #expect(await firstSnapshot(store.observeActive()) == nil)

        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 30)
        try await flush(store, id, recorder)

        let snapshot = try #require(await firstSnapshot(store.observeActive()))
        #expect(snapshot.state == .recording)
        // Migawka na żywo z `flush` jest bogatsza niż kolumny sesji (prędkość, chód).
        #expect(snapshot == recorder.snapshot())
        #expect(snapshot.speedKmh != nil)

        try await store.discard(sessionId: id)
        #expect(await firstSnapshot(store.observeActive()) == nil)
    }

    /// Android: `loading or flushing a missing session fails clearly`.
    @Test func loadingOrFlushingAMissingSessionFailsClearly() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())

        let loadFailure = await failure { try await store.load(sessionId: "brak") }
        let flushFailure = await failure { try await store.flush(sessionId: "brak", points: [], snapshot: newRecorder().snapshot(), pauses: []) }
        let stateFailure = await failure { try await store.setState(sessionId: "brak", state: .finished) }

        #expect(loadFailure as? RideSessionError == .sessionNotFound("brak"))
        #expect(flushFailure as? RideSessionError == .sessionNotFound("brak"))
        #expect(stateFailure as? RideSessionError == .sessionNotFound("brak"))
    }

    // MARK: Android: RideSessionDaoTest (na poziomie sklepu)

    /// Android `RideSessionDaoTest`: `the active session is the one that is not finished` (+ `pendingSession`: niezakończona przed zakończoną).
    @Test func theActiveSessionIsTheLatestOneThatIsNotFinished() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        #expect(try await store.activeSession() == nil)
        try await store.saveSession(sessionRow("done", state: "Finished", startedAt: 500))
        #expect(try await store.activeSession() == nil)
        #expect(try await store.unfinished()?.sessionId == "done")
        #expect(try await store.unfinished()?.state == .finished)

        try await store.saveSession(sessionRow("live", state: "Paused", startedAt: 2_000))

        #expect(try await store.activeSession()?.id == "live")
        #expect(try await store.unfinished()?.sessionId == "live")
        try await store.saveSession(sessionRow("live", state: "Finished", startedAt: 2_000))
        #expect(try await store.activeSession() == nil)
        #expect(try await store.unfinished()?.sessionId == "live", "wśród zakończonych — najpóźniej rozpoczęta")
    }

    /// Android `RideSessionDaoTest`: `points and media are returned in order and appending is idempotent`.
    @Test func mediaAreReturnedInOrderAndTheSameUriReplacesTheEntry() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let id = try await store.start(horse: grom, params: params)
        func at(_ ms: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(START + ms) / 1000) }
        try await store.addMedia(sessionId: id, uri: "file:///ride/2.mp4", contentType: "video/mp4", capturedAt: at(6_000), lat: nil, lon: nil)
        try await store.addMedia(sessionId: id, uri: "file:///ride/1.jpg", contentType: "image/jpeg", capturedAt: at(5_000), lat: 52.1, lon: 21.1)
        try await store.addMedia(sessionId: id, uri: "file:///ride/1.jpg", contentType: "image/jpeg", capturedAt: at(5_500), lat: 52.2, lon: 21.2)

        let loaded = try await store.load(sessionId: id)

        #expect(loaded.media.map(\.uri) == ["file:///ride/1.jpg", "file:///ride/2.mp4"])
        #expect(loaded.media[0] == RideMedia(uri: "file:///ride/1.jpg", contentType: "image/jpeg", capturedAt: at(5_500), latitude: 52.2, longitude: 21.2))
        #expect(loaded.media[1].latitude == nil)
        #expect(loaded.media[1].longitude == nil)
        #expect(try await store.mediaUris(sessionId: id) == ["file:///ride/1.jpg", "file:///ride/2.mp4"])
        #expect(Set(try await store.allMediaUris()) == ["file:///ride/1.jpg", "file:///ride/2.mp4"])

        let missing = await failure { try await store.addMedia(sessionId: "brak", uri: "file:///x", contentType: "image/jpeg", capturedAt: at(0), lat: nil, lon: nil) }
        #expect(missing is DatabaseError, "plik sesji, której nie ma, łamie klucz obcy")
    }

    /// Android `RideSessionDaoTest`: `points ... appending is idempotent` — powtórzony zapis tego samego punktu nie dubluje wierszy.
    @Test func flushingTheSamePointsAgainDoesNotDuplicateRows() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 15)
        let points = recorder.drainUnsaved()

        try await store.flush(sessionId: id, points: points, snapshot: recorder.snapshot(), pauses: [])
        try await store.flush(sessionId: id, points: points, snapshot: recorder.snapshot(), pauses: [])

        #expect(try await store.points(sessionId: id).map(\.seq) == [5_000, 10_000, 15_000])
    }

    // MARK: Zakończenie sesji

    @Test func theEndTimeIsKeptOnceSet() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let id = try await store.start(horse: grom, params: params)

        // Jawny koniec (odzyskanie po zabiciu procesu: ostatnia aktywność z trasy) wygrywa z chwilą zapisu.
        harness.clock.millis = START + 90_000
        try await store.setState(sessionId: id, state: .finished, endedAtMillis: START + 12_345)
        #expect(try await store.load(sessionId: id).session.endedAt == Date(timeIntervalSince1970: TimeInterval(START + 12_345) / 1000))

        // Ustawiony koniec się nie zmienia, także przy kolejnym zapisie migawki `.finished`.
        let recorder = newRecorder()
        var snapshot = recorder.snapshot()
        snapshot.state = .finished
        try await store.flush(sessionId: id, points: [], snapshot: snapshot, pauses: [])
        try await store.setState(sessionId: id, state: .finished)
        #expect(try await store.load(sessionId: id).session.endedAt == Date(timeIntervalSince1970: TimeInterval(START + 12_345) / 1000))
        #expect(try await store.load(sessionId: id).session.state == .finished)
    }

    @Test func aFinishedSnapshotInFlushStoresTheEndTimeFromTheClock() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        var snapshot = recorder.snapshot()
        snapshot.state = .finished
        harness.clock.millis = START + 30_000

        try await store.flush(sessionId: id, points: [], snapshot: snapshot, pauses: [])

        #expect(try await store.load(sessionId: id).session.endedAt == Date(timeIntervalSince1970: TimeInterval(START + 30_000) / 1000))
        #expect(try await store.activeSession() == nil)
    }

    // MARK: Parametry jazdy

    @Test func customParametersSurviveTheRoundTripExactly() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let first = try harness.openDatabase()
        let store = harness.store(first)
        let profile = RideProfile(
            gaitWalkMaxKmh: Decimal(string: "7.3"), loadWeightTrot: Decimal(string: "2.55"), loadClimbPer10m: Decimal(string: "0.1"), loadWarnPercent: 20
        )
        let custom = RideParameters.resolve(RideDefaults.builtIn, profile)
        #expect(custom.ownFields == ["gaitWalkMaxKmh", "loadWeightTrot", "loadClimbPer10m", "loadWarnPercent"])
        let id = try await store.start(horse: grom, params: custom)
        try first.writer.close()

        let loaded = try await harness.newProcessStore().load(sessionId: id)

        #expect(loaded.params == custom)
        #expect(loaded.params.thresholds.walkMaxKmh == Decimal(string: "7.3"))
        #expect(loaded.params.load.weightTrot == Decimal(string: "2.55"))
        #expect(loaded.params.load.climbPer10m == Decimal(string: "0.1"))
        #expect(loaded.params.warnPercent == 20)
        #expect(loaded.params.ownFields == custom.ownFields)
    }

    // MARK: Błędne dane z bazy (Task 13 M2 i M5)

    /// Pauzy odwrócone, sprzed startu i poza zakresem oraz punkty z absurdalnym czasem nie mogą przepełnić arytmetyki Int64 maszyny:
    /// są pomijane, czas ostatniego zapisu przycinany, a jazda wraca i da się ją odtworzyć.
    @Test func malformedPausesAndPointsAreSanitizedOnLoad() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let database = try harness.openDatabase()
        let store = harness.store(database)
        let id = try await store.start(horse: grom, params: params)
        let hostile = """
        [{"startMillis":9223372036854775807,"endMillis":-9223372036854775808},\
        {"startMillis":\(START + 10_000),"endMillis":\(START + 5_000)},\
        {"startMillis":\(START + 20_000),"endMillis":\(START + 30_000)},\
        {"startMillis":1000,"endMillis":2000},\
        {"startMillis":\(START + 40_000),"endMillis":9223372036854775807}]
        """
        try await harness.sql(database, "UPDATE ride_session SET state = 'Paused', pausesJson = '\(hostile)', lastFlushMillis = 9223372036854775807 WHERE id = '\(id)'")
        try await store.insertPoints([
            pointRow(id, offset: 5_000),
            pointRow(id, offset: Int.max),
            pointRow(id, offset: -5),
            pointRow(id, offset: Int(Int32.max) + 1),
        ])

        let loaded = try await store.load(sessionId: id)

        #expect(loaded.track.pauses == [Pause(startMillis: START + 20_000, endMillis: START + 30_000)])
        #expect(loaded.track.points.map(\.tMillis) == [START + 5_000])
        #expect(loaded.session.lastFlushMillis == START + Int64(Int32.max))
        #expect(loaded.session.state == .paused)
        let snapshot = loaded.restoreRecorder().snapshot()
        #expect(snapshot.state == .paused)
        // Otwarta pauza zaczyna się w START + 20 s, więc do tej chwili jazda była aktywna.
        #expect(snapshot.activeSeconds == 20)
        let unfinished = try #require(try await store.unfinished())
        #expect(unfinished.damaged)
        #expect(unfinished.state == .paused)
        #expect(unfinished.distanceMeters == 0)
    }

    @Test func aStartTimeOutsideTheSaneRangeMakesTheSessionCorruptButStillDiscardable() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let database = try harness.openDatabase()
        let store = harness.store(database)
        let id = try await store.start(horse: grom, params: params)
        try await harness.sql(database, "UPDATE ride_session SET startedAtMillis = -1, distanceMeters = 321 WHERE id = '\(id)'")

        let refused = await failure { try await store.load(sessionId: id) }
        let unfinished = try #require(try await store.unfinished())

        #expect(refused as? RideSessionError == .corruptSession(id))
        #expect(unfinished.damaged)
        #expect(unfinished.distanceMeters == 321)
        #expect(unfinished.state == .recording)
        try await store.discard(sessionId: id)
        #expect(try await store.unfinished() == nil)
    }

    @Test func unreadableThresholdsMakeTheRideDamagedButItCanBeDiscarded() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let database = try harness.openDatabase()
        let store = harness.store(database)
        let id = try await store.start(horse: grom, params: params)
        try await store.addMedia(sessionId: id, uri: "file:///ride/1.jpg", contentType: "image/jpeg", capturedAt: Date(timeIntervalSince1970: 1), lat: nil, lon: nil)
        try await harness.sql(database, "UPDATE ride_session SET thresholdsJson = '{}', distanceMeters = 321, state = 'Interrupted' WHERE id = '\(id)'")

        let refused = await failure { try await store.load(sessionId: id) }
        let unfinished = try #require(try await store.unfinished())

        #expect(refused as? RideSessionError == .corruptSession(id))
        #expect(unfinished.damaged)
        #expect(unfinished.distanceMeters == 321, "dystans z kolumny zapisanej przy ostatnim zapisie")
        #expect(unfinished.state == .interrupted)
        #expect(try await store.mediaUris(sessionId: id) == ["file:///ride/1.jpg"], "pliki sesji da się wyliczyć także dla uszkodzonego wiersza")
        try await store.discard(sessionId: id)
        #expect(try await store.unfinished() == nil)
        #expect(try await rowCount("ride_media", sessionId: id, in: database) == 0)
    }

    @Test func anUnknownStateLoadsAsInterruptedAndTheSessionIsNotDropped() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let database = try harness.openDatabase()
        let store = harness.store(database)
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 60)
        try await flush(store, id, recorder)
        try await harness.sql(database, "UPDATE ride_session SET state = 'Zepsuty' WHERE id = '\(id)'")

        let loaded = try await store.load(sessionId: id)
        let unfinished = try #require(try await store.unfinished())
        let refused = await failure { try await store.start(horse: iskra, params: params) }

        #expect(loaded.session.state == .interrupted)
        #expect(loaded.track.points.count == 12)
        #expect(loaded.restoreRecorder().snapshot().state == .paused)
        #expect(unfinished.sessionId == id)
        #expect(unfinished.state == .interrupted)
        #expect(unfinished.damaged)
        #expect(unfinished.distanceMeters == recorder.snapshot().distanceMeters)
        #expect(refused as? RideSessionError == .onlyOneActiveSession, "nieznany stan nadal jest niezakończoną sesją")
        let snapshot = try #require(await firstSnapshot(store.observeActive()))
        #expect(snapshot.state == .interrupted)
        #expect(snapshot.distanceMeters == recorder.snapshot().distanceMeters)

        // Znany stan zapisany przy kolejnym zapisie naprawia wiersz.
        try await store.setState(sessionId: id, state: .interrupted)
        #expect(try await store.unfinished()?.damaged == false)
    }

    @Test func aPointWithAnExtremeTimeIsRejectedWithoutTrappingAndChangesNothing() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let id = try await store.start(horse: grom, params: params)
        let before = try await store.session(id: id)
        var earliest = location(5, 1)
        earliest.tMillis = Int64.min
        var farFuture = location(5, 1)
        farFuture.tMillis = START + 3_000_000_000
        let snapshot = newRecorder().snapshot()

        let underflow = await failure { try await store.flush(sessionId: id, points: [location(5, 1), earliest], snapshot: snapshot, pauses: []) }
        let tooLate = await failure { try await store.flush(sessionId: id, points: [farFuture], snapshot: snapshot, pauses: []) }

        #expect(underflow as? RideSessionError == .pointOutsideSession(offsetMillis: Int64.max))
        #expect(tooLate as? RideSessionError == .pointOutsideSession(offsetMillis: 3_000_000_000))
        #expect(try await store.session(id: id) == before)
        #expect(try await store.points(sessionId: id).isEmpty, "także poprawny punkt sprzed błędnego nie został zapisany")
    }

    // MARK: Czyszczenie magazynu i odtworzenie kopii nie ruszają sesji (jak Android)

    @Test func anUnfinishedSessionSurvivesClearingTheRecordStore() async throws {
        let database = try AppDatabase.inMemory()
        let records = RecordStore(database: database)
        let store = RideSessionStore(db: database.writer, now: { Date(timeIntervalSince1970: TimeInterval(START) / 1000) })
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 20)
        try await flush(store, id, recorder)
        try await store.addMedia(sessionId: id, uri: "file:///ride/1.jpg", contentType: "image/jpeg", capturedAt: Date(timeIntervalSince1970: 1), lat: nil, lon: nil)
        try await records.putTrack(StoredTrack(recordingId: "r1", version: 1, format: "zk-track/1", data: Data([1])))

        try await records.write { try $0.clear() }

        #expect(try await records.track(recordingId: "r1") == nil, "trasy nagrań znikają")
        #expect(try await store.unfinished()?.sessionId == id)
        let loaded = try await store.load(sessionId: id)
        #expect(loaded.track.points.count == 4)
        #expect(loaded.media.count == 1)
    }

    @Test func anUnfinishedSessionSurvivesRestoringABackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-ride-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let records = RecordStore(database: database)
        let store = RideSessionStore(db: database.writer, now: { Date(timeIntervalSince1970: TimeInterval(START) / 1000) })
        let files = try LocalFileStore(root: root.appendingPathComponent("Files", isDirectory: true))
        let service = BackupService(
            store: records, files: files, workDirectory: root.appendingPathComponent("Work", isDirectory: true), appVersion: "3.0.0",
            dates: FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 9)!)
        )
        let stamp = LocalDateTime(year: 2026, month: 10, day: 9, hour: 18, minute: 30)!
        let horse = LocalHorse(id: "h1", createdAt: stamp, updatedAt: stamp, version: 3, name: "Grom", passportNumber: nil)
        try await records.upsert([try StoredRecord.of(horse, syncState: .local)])
        let file = root.appendingPathComponent("kopia.zkkopia")
        _ = try await service.write(to: file, password: nil, attachmentsCacheMb: 200)
        let id = try await store.start(horse: grom, params: params)
        let recorder = newRecorder()
        ride(recorder, from: 5, to: 20)
        try await flush(store, id, recorder)

        let prepared = try service.prepare(file, password: nil)
        defer { service.discard(prepared) }
        _ = try await service.apply(prepared)

        #expect(try await records.get(.horse, id: "h1") != nil)
        #expect(try await store.unfinished()?.sessionId == id)
        #expect(try await store.load(sessionId: id).track.points.count == 4)
    }

    // MARK: Pasek NAG-01 — strumień

    @Test func observeActiveEmitsAsTheSessionChanges() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let store = harness.store(try harness.openDatabase())
        let collector = Collector(store.observeActive())
        defer { collector.stop() }
        #expect(await collector.waitUntil { $0.count == 1 })
        #expect(collector.values == [nil])

        let id = try await store.start(horse: grom, params: params)
        #expect(await collector.waitUntil { values in values.contains { $0?.state == .recording } })

        let recorder = newRecorder()
        ride(recorder, from: 5, to: 30)
        try await flush(store, id, recorder)
        let expected = recorder.snapshot()
        #expect(await collector.waitUntil { values in values.last.map { $0 == expected } ?? false })

        try await store.setState(sessionId: id, state: .finished)
        #expect(await collector.waitUntil { values in values.last.map { $0 == nil } ?? false })
        #expect(collector.values.contains { $0?.activeSeconds == 30 })
    }
}

// MARK: - Środowisko testów

private let START: Int64 = 1_790_000_000_000

/// Zegar sklepu sterowany z testu (epoka, ms).
private final class TestClock: Sendable {
    private let value: Mutex<Int64>

    init(_ start: Int64) {
        value = Mutex(start)
    }

    var millis: Int64 {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }

    var provider: @Sendable () -> Date {
        { [self] in Date(timeIntervalSince1970: TimeInterval(self.millis) / 1000) }
    }
}

/// Katalog bazy w katalogu tymczasowym i otwieranie jej od nowa („nowy proces”).
private final class Harness {
    let clock = TestClock(START)
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-ride-\(UUID().uuidString)", isDirectory: true)
    private var opened: [AppDatabase] = []

    /// Baza z prawdziwego pliku `Horsely/horsely.sqlite` (pula WAL jak w aplikacji).
    func openDatabase() throws -> AppDatabase {
        let database = try AppDatabase.open(in: directory)
        opened.append(database)
        return database
    }

    func store(_ database: AppDatabase) -> RideSessionStore {
        RideSessionStore(db: database.writer, now: clock.provider, timeZone: "Europe/Warsaw")
    }

    /// Nowa „instancja procesu”: baza z pliku i świeży sklep.
    func newProcessStore() throws -> RideSessionStore {
        store(try openDatabase())
    }

    func sql(_ database: AppDatabase, _ statement: String) async throws {
        try await database.writer.write { db in try db.execute(sql: statement) }
    }

    func cleanUp() {
        for database in opened { try? database.writer.close() }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Zbiera wartości strumienia w tle; test czeka na warunek z limitem czasu zamiast wisieć na pustym strumieniu.
private final class Collector<T: Sendable>: Sendable {
    private let state = Mutex<[T]>([])
    private let task = Mutex<Task<Void, Never>?>(nil)

    init(_ stream: AsyncStream<T>) {
        let running = Task { [self] in
            for await value in stream { state.withLock { $0.append(value) } }
        }
        task.withLock { $0 = running }
    }

    var values: [T] { state.withLock { $0 } }

    func waitUntil(seconds: Double = 20, _ predicate: @Sendable ([T]) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if predicate(values) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return predicate(values)
    }

    func stop() {
        task.withLock { $0?.cancel() }
    }
}

/// Pierwsza wartość strumienia paska NAG-01 (`nil` — brak niezakończonej sesji); brak emisji w 20 s to błąd testu.
private func firstSnapshot(_ stream: AsyncStream<RideSnapshot?>) async -> RideSnapshot? {
    let collector = Collector(stream)
    defer { collector.stop() }
    guard await collector.waitUntil({ !$0.isEmpty }) else {
        Issue.record("Strumień nic nie wyemitował w 20 s")
        return nil
    }
    return collector.values.first ?? nil
}
