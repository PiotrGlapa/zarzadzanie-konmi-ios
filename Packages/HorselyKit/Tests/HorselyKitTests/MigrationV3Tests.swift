import Foundation
import GRDB
import HorselyCore
import Testing
@testable import HorselyKit

/// Baza `v3` (Task 6 = Android Task 5): migracja `v2 → v3` produkcyjnym migratorem `AppDatabase`, magazyn tras w `RecordStore`
/// (Android `Migration3To4Test` i `RecordingModelTest`: `the store keeps tracks apart from records`,
/// `clear removes tracks and hard delete of a recording removes its track`, `a track rolls back with its transaction`)
/// oraz schemat sesji nagrywania 1:1 z `Migration3To4.kt`.
struct MigrationV3Tests {
    private let stamp = LocalDateTime(year: 2026, month: 9, day: 1, hour: 10)!
    private let rideTables = ["local_track", "ride_session", "ride_point", "ride_media"]

    private struct Boom: Error {}

    private func count(_ table: String, in database: AppDatabase) throws -> Int {
        try database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
    }

    /// Nagranie jazdy z treningu `t1` konia `h1` (chwile UTC jak w kontrakcie).
    private func recording(_ id: String) -> LocalTrainingRecording {
        let started = InstantText.parse("2026-09-01T08:00:00Z")!
        return Recording(
            id: id, trainingId: "t1", version: 1, createdAt: started, updatedAt: started,
            startedAt: started, endedAt: started.addingTimeInterval(3600), timeZone: "Europe/Warsaw",
            totalSeconds: 3600, movingSeconds: 3000, stoppedSeconds: 600, pausedSeconds: 0, distanceMeters: 5000,
            avgMovingSpeedKmh: Decimal(string: "15")!, maxSpeedKmh: Decimal(string: "25")!, elevationGainM: 100, elevationLossM: 80, minAltitudeM: 100, maxAltitudeM: 200,
            walkSeconds: 1200, walkMeters: 1500, trotSeconds: 1500, trotMeters: 2500, canterSeconds: 300, canterMeters: 800,
            canterCount: 1, longestCanterSeconds: 300, longestCanterMeters: 800, loadPoints: Decimal(string: "75.5")!,
            gaitThresholdsUsed: RideDefaults.builtIn.thresholds, loadParamsUsed: RideDefaults.builtIn.load,
            accelerometerUsed: false, weatherStatus: .none, trimmedStartSeconds: 0, trimmedEndSeconds: 0, algorithmVersion: 1,
            source: ["platform": .string("ios")], trackFormat: "zk-track/1", pointCount: 3600, segments: []
        ).toRecord(horseId: "h1", trainingDate: LocalDate(year: 2026, month: 9, day: 1)!)
    }

    private func session(_ id: String, distanceMeters: Int = 0) -> RideSessionRow {
        RideSessionRow(
            id: id, horseId: "h1", horseName: "Grom", state: "Recording", startedAtMillis: 1000, endedAtMillis: nil, timeZone: "Europe/Warsaw",
            pausesJson: "[]", thresholdsJson: "{}", loadJson: "{}", accelerometerUsed: 0, lastFlushMillis: 1000,
            distanceMeters: distanceMeters, activeSeconds: 0
        )
    }

    private func point(_ sessionId: String, seq: Int) -> RidePointRow {
        RidePointRow(sessionId: sessionId, seq: seq, tMillis: seq * 1000, lat: 52.0, lon: 21.0, altM: nil, speedMs: nil, hAccM: nil, vAccM: nil, cadence: nil, intensity: nil)
    }

    private func media(_ sessionId: String) -> RideMediaRow {
        RideMediaRow(sessionId: sessionId, uri: "file:///ride/1.jpg", contentType: "image/jpeg", capturedAtMillis: 1500, lat: nil, lon: nil)
    }

    // MARK: Migracja

    /// Baza 2.x: produkcyjny migrator `AppDatabase` zatrzymany na `v2`, rekord i licznik zmian zapisane kodem magazynu.
    private func databaseAtV2(with row: StoredRecord) throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator().migrate(queue, upTo: "v2")
        try queue.write { db in
            let access = RecordAccess(db: db, state: RecordAccess.WriteState())
            try access.upsert([row])
            try access.setMeta(RecordStore.changeCounterKey, "7")
        }
        return queue
    }

    private func existingTables(_ names: [String], in queue: DatabaseQueue) throws -> [String] {
        try queue.read { db in try names.filter { try db.tableExists($0) } }
    }

    @Test func migrationV2ToV3KeepsRecordsAndCreatesRideTables() async throws {
        let note = LocalNote(id: "n1", createdAt: stamp, updatedAt: stamp, version: 2, horseId: "h1", noteDate: LocalDate(year: 2026, month: 9, day: 1)!, title: "Notatka")
        let row = try StoredRecord.of(note, syncState: .synced)
        let queue = try databaseAtV2(with: row)
        #expect(try existingTables(rideTables, in: queue).isEmpty, "w v2 nie ma tabel jazd")

        // Otwarcie kodem 3.0 dokańcza migrację.
        let database = try AppDatabase(writer: queue)
        let store = RecordStore(database: database)
        #expect(try existingTables(rideTables, in: queue) == rideTables)

        let stored = try #require(try await store.get(.note, id: "n1"))
        #expect(stored.version == 2)
        #expect(stored.body == row.body)
        #expect(try stored.record(as: LocalNote.self)?.title == "Notatka")
        #expect(try await store.changeCounter() == 7)
        for table in rideTables {
            #expect(try count(table, in: database) == 0, "\(table)")
        }
    }

    @Test func rideTablesFollowTheAndroidSchema() throws {
        let database = try AppDatabase.inMemory()
        let (notNull, foreignKeys, extraIndexes) = try database.writer.read { db in
            let notNull = try db.columns(in: "ride_session").filter(\.isNotNull).map(\.name)
            let foreignKeys = try ["ride_point", "ride_media"].map { table in
                try Row.fetchAll(db, sql: "SELECT \"table\", \"on_delete\" FROM pragma_foreign_key_list(?)", arguments: [table])
                    .map { row -> String in
                        let parent: String = row["table"]
                        let onDelete: String = row["on_delete"]
                        return "\(table)->\(parent):\(onDelete)"
                    }
            }.flatMap { $0 }
            let extraIndexes = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'ride_point' AND sql IS NOT NULL")
            return (notNull, foreignKeys, extraIndexes)
        }
        // Jak w `Migration3To4.kt`: tylko `endedAtMillis` może być puste.
        #expect(Set(notNull) == [
            "id", "horseId", "horseName", "state", "startedAtMillis", "timeZone", "pausesJson", "thresholdsJson", "loadJson",
            "accelerometerUsed", "lastFlushMillis", "distanceMeters", "activeSeconds",
        ])
        #expect(foreignKeys == ["ride_point->ride_session:CASCADE", "ride_media->ride_session:CASCADE"])
        #expect(extraIndexes.isEmpty, "klucz główny (sessionId, seq) wystarcza")
    }

    // MARK: Trasy w magazynie

    @Test func trackRoundTrip() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let track = StoredTrack(recordingId: "r1", version: 3, format: "zk-track/1", data: Data([1, 2, 3, 0, 0xFF]))

        try await store.putTrack(track)

        #expect(try await store.track(recordingId: "r1") == track)
        #expect(try await store.track(recordingId: "r2") == nil)
    }

    /// Android: `the store keeps tracks apart from records`.
    @Test func theStoreKeepsTracksApartFromRecords() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let track = StoredTrack(recordingId: "r1", version: 2, format: "zk-track/1", data: Data([1, 2, 3]))

        #expect(try await store.track(recordingId: "r1") == nil)
        try await store.putTrack(track)
        let read = try #require(try await store.track(recordingId: "r1"))
        #expect(read == track)
        #expect(read.data == Data([1, 2, 3]))
        #expect(try await store.count(.trainingRecording) == 0)

        var newer = track
        newer.version = 3
        newer.data = Data([9])
        try await store.putTrack(newer)
        #expect(try await store.track(recordingId: "r1")?.version == 3)
        #expect(try await store.track(recordingId: "r1")?.data == Data([9]))

        try await store.deleteTrack(recordingId: "r1")
        #expect(try await store.track(recordingId: "r1") == nil)
        try await store.deleteTrack(recordingId: "r1")
    }

    /// Plan Task 6 `clearRemovesTracks`: czyszczenie magazynu usuwa trasy, sesje nagrywania, punkty i pliki z jazdy.
    @Test func clearRemovesTracks() async throws {
        let database = try AppDatabase.inMemory()
        let store = RecordStore(database: database)
        let sessions = RideSessionStore(db: database.writer)
        try await store.putTrack(StoredTrack(recordingId: "r1", version: 1, format: "zk-track/1", data: Data([1])))
        try await store.putTrack(StoredTrack(recordingId: "r2", version: 1, format: "zk-track/1", data: Data([2])))
        try await sessions.saveSession(session("s1"))
        try await sessions.insertPoints([point("s1", seq: 0), point("s1", seq: 1)])
        try await sessions.insertMedia(media("s1"))
        #expect(try await store.track(recordingId: "r2") != nil)

        try await store.write { try $0.clear() }

        #expect(try await store.track(recordingId: "r1") == nil)
        #expect(try await store.track(recordingId: "r2") == nil)
        #expect(try await sessions.session(id: "s1") == nil)
        #expect(try await sessions.points(sessionId: "s1").isEmpty)
        #expect(try await sessions.media(sessionId: "s1").isEmpty)
        for table in rideTables {
            #expect(try count(table, in: database) == 0, "\(table)")
        }
    }

    /// Android: `clear removes tracks and hard delete of a recording removes its track`.
    @Test func hardDeleteOfARecordingRemovesItsTrack() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let local = recording("rec-1")
        try await store.upsert([try StoredRecord.of(local, syncState: .synced)])
        try await store.putTrack(StoredTrack(recordingId: local.id, version: 1, format: "zk-track/1", data: Data([1])))
        try await store.putTrack(StoredTrack(recordingId: "inny", version: 1, format: "zk-track/1", data: Data([2])))

        try await store.write { try $0.deleteHard(.trainingRecording, id: local.id) }
        #expect(try await store.get(.trainingRecording, id: local.id) == nil)
        #expect(try await store.track(recordingId: local.id) == nil, "trwałe usunięcie nagrania usuwa trasę")
        #expect(try await store.track(recordingId: "inny") != nil)

        try await store.write { try $0.clear() }
        #expect(try await store.track(recordingId: "inny") == nil, "clear czyści też trasy")
    }

    /// Android `deleteState`: rekordy usuwane według stanu zabierają trasy swoich nagrań.
    @Test func deletingRecordsByStateRemovesTheirTracks() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        try await store.upsert([
            try StoredRecord.of(recording("projected"), syncState: .projected),
            try StoredRecord.of(recording("synced"), syncState: .synced),
        ])
        try await store.putTrack(StoredTrack(recordingId: "projected", version: 1, format: "zk-track/1", data: Data([1])))
        try await store.putTrack(StoredTrack(recordingId: "synced", version: 1, format: "zk-track/1", data: Data([2])))

        try await store.write { try $0.deleteState(.projected) }

        #expect(try await store.track(recordingId: "projected") == nil)
        #expect(try await store.track(recordingId: "synced") != nil)
    }

    /// Android: `a track rolls back with its transaction`.
    @Test func aTrackRollsBackWithItsTransaction() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        try await store.putTrack(StoredTrack(recordingId: "r1", version: 1, format: "zk-track/1", data: Data([1])))
        let counter = try await store.changeCounter()

        do {
            try await store.write { access in
                try access.putTrack(StoredTrack(recordingId: "r1", version: 2, format: "zk-track/1", data: Data([2])))
                try access.deleteTrack(recordingId: "r1")
                throw Boom()
            }
            Issue.record("transakcja powinna się nie udać")
        } catch is Boom {}

        #expect(try await store.track(recordingId: "r1")?.version == 1)
        #expect(try await store.changeCounter() == counter)
    }

    @Test func aTrackWriteRaisesTheChangeCounter() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        try await store.putTrack(StoredTrack(recordingId: "r1", version: 1, format: "zk-track/1", data: Data([1])))
        #expect(try await store.changeCounter() == 1)
        try await store.deleteTrack(recordingId: "r1")
        #expect(try await store.changeCounter() == 2)
    }

    // MARK: Sesje nagrywania

    @Test func deletingASessionCascadesToItsPointsAndMedia() async throws {
        let database = try AppDatabase.inMemory()
        let sessions = RideSessionStore(db: database.writer)
        try await sessions.saveSession(session("s1"))
        try await sessions.saveSession(session("s2"))
        try await sessions.insertPoints([point("s1", seq: 0), point("s2", seq: 0)])
        try await sessions.insertMedia(media("s1"))

        try await sessions.deleteSession(id: "s1")

        #expect(try await sessions.points(sessionId: "s1").isEmpty)
        #expect(try await sessions.media(sessionId: "s1").isEmpty)
        #expect(try await sessions.points(sessionId: "s2").count == 1)
    }

    @Test func savingASessionAgainKeepsItsPoints() async throws {
        let database = try AppDatabase.inMemory()
        let sessions = RideSessionStore(db: database.writer)
        try await sessions.saveSession(session("s1"))
        try await sessions.insertPoints([point("s1", seq: 0), point("s1", seq: 1)])
        try await sessions.insertMedia(media("s1"))

        try await sessions.saveSession(session("s1", distanceMeters: 120))

        #expect(try await sessions.session(id: "s1")?.distanceMeters == 120)
        #expect(try await sessions.points(sessionId: "s1").map(\.seq) == [0, 1])
        #expect(try await sessions.media(sessionId: "s1").count == 1)
    }

    @Test func aPointOfAMissingSessionIsRejected() async throws {
        let sessions = RideSessionStore(db: try AppDatabase.inMemory().writer)
        await #expect(throws: DatabaseError.self) {
            try await sessions.insertPoints([point("brak", seq: 0)])
        }
    }
}
