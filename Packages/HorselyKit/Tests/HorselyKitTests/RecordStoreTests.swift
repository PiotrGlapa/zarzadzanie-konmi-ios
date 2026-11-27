import Foundation
import GRDB
import HorselyCore
import Testing
@testable import HorselyKit

/// Magazyn rekordów (T017): zapis i odczyt rekordów wszystkich rodzajów, indeksy, `record_horse` dla zakupu wielu koni,
/// transakcja rekord + licznik zmian, obserwacja zmian.
struct RecordStoreTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 5, hour: 10)!

    private func date(_ day: Int, month: Int = 10) -> LocalDate { LocalDate(year: 2026, month: month, day: day)! }

    private func makeStore() throws -> RecordStore {
        RecordStore(database: try AppDatabase.inMemory())
    }

    private func horse(_ id: String, name: String = "Grom") -> LocalHorse {
        LocalHorse(id: id, createdAt: stamp, updatedAt: stamp, version: 1, name: name, passportNumber: "PL-\(id)")
    }

    private func training(_ id: String, horse: String, day: Int) -> LocalTraining {
        LocalTraining(id: id, createdAt: stamp, updatedAt: stamp, version: 1, horseId: horse, trainingDate: date(day), trainingTypeId: "type-1", durationMinutes: 45)
    }

    /// Nagranie jazdy treningu (chwile UTC jak w kontrakcie, bez `trackData`).
    private func recording(_ id: String, training: String, horse: String, day: Int) -> LocalTrainingRecording {
        let started = InstantText.parse("2026-10-\(String(format: "%02d", day))T08:00:00Z")!
        return Recording(
            id: id, trainingId: training, version: 1, createdAt: started, updatedAt: started,
            startedAt: started, endedAt: started.addingTimeInterval(3600), timeZone: "Europe/Warsaw",
            totalSeconds: 3600, movingSeconds: 3000, stoppedSeconds: 600, pausedSeconds: 0, distanceMeters: 5000,
            avgMovingSpeedKmh: Decimal(string: "15")!, maxSpeedKmh: Decimal(string: "25")!, elevationGainM: 100, elevationLossM: 80, minAltitudeM: 100, maxAltitudeM: 200,
            walkSeconds: 1200, walkMeters: 1500, trotSeconds: 1500, trotMeters: 2500, canterSeconds: 300, canterMeters: 800,
            canterCount: 1, longestCanterSeconds: 300, longestCanterMeters: 800, loadPoints: Decimal(string: "75.5")!,
            gaitThresholdsUsed: RideDefaults.builtIn.thresholds, loadParamsUsed: RideDefaults.builtIn.load,
            accelerometerUsed: false, weatherStatus: .none, trimmedStartSeconds: 0, trimmedEndSeconds: 0, algorithmVersion: 1,
            source: ["platform": .string("ios")], trackFormat: "zk-track/1", pointCount: 3600, segments: []
        ).toRecord(horseId: horse, trainingDate: date(day))
    }

    private func purchase(_ id: String, horses: [String], day: Int) -> LocalPurchase {
        LocalPurchase(
            id: id, createdAt: stamp, updatedAt: stamp, version: 1, purchaseDate: date(day), productName: "Siano", categoryId: "cat-1",
            totalAmount: Money(string: "100.01")!, assignment: horses.count > 1 ? .multipleHorses : .singleHorse, horseIds: horses
        )
    }

    // MARK: Zapis i odczyt wszystkich rodzajów

    @Test func storesAndReadsEveryRecordType() async throws {
        let store = try makeStore()
        let records: [any LocalRecord] = [
            LocalDictionaryItem(id: "d1", createdAt: stamp, updatedAt: stamp, dictionaryType: .trainingType, value: "Skoki", sortOrder: 1),
            LocalContact(id: "c1", createdAt: stamp, updatedAt: stamp, name: "Anna", types: [.trainer, .rider]),
            horse("h1"),
            LocalVetVisit(id: "v1", createdAt: stamp, updatedAt: stamp, horseId: "h1", visitDateTime: stamp, visitTypeId: "vt"),
            LocalFarrierVisit(id: "f1", createdAt: stamp, updatedAt: stamp, horseId: "h1", visitDate: date(3), serviceId: "s"),
            LocalPhysioVisit(id: "p1", createdAt: stamp, updatedAt: stamp, horseId: "h1", visitDate: date(4)),
            LocalSpecialistVisit(id: "s1", createdAt: stamp, updatedAt: stamp, horseId: "h1", visitDate: date(5), specialistTypeId: "st"),
            LocalCompetition(id: "k1", createdAt: stamp, updatedAt: stamp, name: "Puchar", dateFrom: date(6)),
            LocalCompetitionStart(id: "cs1", createdAt: stamp, updatedAt: stamp, competitionId: "k1", horseId: "h1"),
            purchase("z1", horses: ["h1"], day: 7),
            LocalNote(id: "n1", createdAt: stamp, updatedAt: stamp, horseId: "h1", noteDate: date(8), title: "Notatka"),
            training("t1", horse: "h1", day: 9),
            LocalReminder(id: "r1", createdAt: stamp, updatedAt: stamp, horseId: "h1", kind: .farrier, dueDate: date(20), title: "Kowal", sourceId: "f1"),
            LocalAttachment(id: "a1", createdAt: stamp, updatedAt: stamp, ownerType: .note, ownerId: "n1", horseId: "h1", fileName: "a.jpg", contentType: "image/jpeg", sizeBytes: 10, sha256: "abc"),
            recording("tr1", training: "t1", horse: "h1", day: 9),
            LocalHorseRideProfile(horseId: "h1", profile: RideProfile(gaitStopMaxKmh: Decimal(string: "0.5")!, gaitWalkMaxKmh: Decimal(string: "4.5")!, gaitTrotMaxKmh: Decimal(string: "8.0")!, loadWeightWalk: Decimal(string: "0.1")!, loadWeightTrot: Decimal(string: "0.3")!, loadWeightCanter: Decimal(string: "0.6")!, loadClimbPer10m: Decimal(string: "1.0")!, loadWarnPercent: 5, heavyRidePoints: 1), createdAt: stamp, updatedAt: stamp, version: 1),
            LocalRideDefaults(defaults: RideDefaults(gaitStopMaxKmh: Decimal(string: "0.5")!, gaitWalkMaxKmh: Decimal(string: "4.5")!, gaitTrotMaxKmh: Decimal(string: "8.0")!, loadWeightWalk: Decimal(string: "0.1")!, loadWeightTrot: Decimal(string: "0.3")!, loadWeightCanter: Decimal(string: "0.6")!, loadClimbPer10m: Decimal(string: "1.0")!, loadWarnPercent: 5, heavyRidePoints: 1, recordedRideTrainingTypeId: "trening-nagranie", version: 1), createdAt: stamp, updatedAt: stamp),
        ]
        #expect(Set(records.map(\.recordType)) == Set(RecordType.allCases))

        try await store.upsert(try records.map { try StoredRecord.of($0, syncState: .local) })

        for record in records {
            let stored = try #require(try await store.get(record.recordType, id: record.id), "\(record.recordType)")
            #expect(stored.syncState == .local)
            #expect(stored.version == record.version)
            let decoded = try stored.record()
            #expect(try RecordCodec.encode(decoded) == RecordCodec.encode(record))
        }
    }

    // MARK: Indeksy

    @Test func indexColumnsComeFromTheRecord() async throws {
        let store = try makeStore()
        try await store.upsert([try StoredRecord.of(training("t1", horse: "h1", day: 9), syncState: .local)])
        let stored = try #require(try await store.get(.training, id: "t1"))
        #expect(stored.horseId == "h1")
        #expect(stored.dateKey == date(9))
        #expect(stored.ownerId == nil)

        let reminder = LocalReminder(id: "r1", createdAt: stamp, updatedAt: stamp, horseId: "h1", kind: .vet, dueDate: date(20), title: "Wet", sourceId: "v1")
        try await store.upsert([try StoredRecord.of(reminder, syncState: .local)])
        let owned = try await store.read { try $0.byOwner(.reminder, ownerId: "v1") }
        #expect(owned.map(\.id) == ["r1"])
    }

    @Test func startsInheritTheCompetitionDateWhenGivenAnExplicitDateKey() async throws {
        let store = try makeStore()
        let start = LocalCompetitionStart(id: "cs1", createdAt: stamp, updatedAt: stamp, competitionId: "k1", horseId: "h1")
        try await store.upsert([try StoredRecord.of(start, syncState: .local, dateKey: date(6))])
        #expect(try await store.get(.competitionStart, id: "cs1")?.dateKey == date(6))
        let byOwner = try await store.read { try $0.byOwner(.competitionStart, ownerId: "k1") }
        #expect(byOwner.count == 1)
    }

    @Test func queryFiltersByHorseAndDateRangeAndSortsByDate() async throws {
        let store = try makeStore()
        let rows = try [
            training("t3", horse: "h1", day: 12), training("t1", horse: "h1", day: 2), training("t2", horse: "h2", day: 5), training("t4", horse: "h1", day: 20),
        ].map { try StoredRecord.of($0, syncState: .local) }
        try await store.upsert(rows)

        #expect(try await store.query(.training).map(\.id) == ["t1", "t2", "t3", "t4"])
        #expect(try await store.query(.training, horseId: "h1").map(\.id) == ["t1", "t3", "t4"])
        #expect(try await store.query(.training, horseId: "h1", from: date(5), to: date(12)).map(\.id) == ["t3"])
        #expect(try await store.query(.training, from: date(5), to: date(12)).map(\.id) == ["t2", "t3"])
    }

    // MARK: record_horse

    @Test func aPurchaseOfManyHorsesIsFoundByEachHorse() async throws {
        let store = try makeStore()
        try await store.upsert([
            try StoredRecord.of(purchase("z1", horses: ["h1", "h2"], day: 3), syncState: .local),
            try StoredRecord.of(purchase("z2", horses: ["h3"], day: 4), syncState: .local),
        ])
        #expect(try await store.query(.purchase, horseId: "h1").map(\.id) == ["z1"])
        #expect(try await store.query(.purchase, horseId: "h2").map(\.id) == ["z1"])
        #expect(try await store.query(.purchase, horseId: "h3").map(\.id) == ["z2"])
        #expect(try await store.query(.purchase, horseId: "h4").isEmpty)

        // Zmiana koni zakupu zastępuje wpisy w `record_horse`.
        try await store.upsert([try StoredRecord.of(purchase("z1", horses: ["h3"], day: 3), syncState: .local)])
        #expect(try await store.query(.purchase, horseId: "h1").isEmpty)
        #expect(try await store.query(.purchase, horseId: "h3").map(\.id) == ["z1", "z2"])
    }

    // MARK: Stany, kosz, usuwanie

    @Test func stateAndTrashQueries() async throws {
        let store = try makeStore()
        let when = stamp
        try await store.upsert([
            try StoredRecord.of(horse("h1"), syncState: .synced),
            try StoredRecord.of(horse("h2", name: "Iskra"), syncState: .pending, baseVersion: 1),
            try StoredRecord.of(training("t1", horse: "h1", day: 1), syncState: .projected),
            try StoredRecord.of(training("t2", horse: "h1", day: 2), syncState: .local, deletedAt: when, deletionBatchId: "batch-1"),
        ])
        #expect(try await store.read { try $0.withState(.pending) }.map(\.id) == ["h2"])
        #expect(try await store.read { try $0.withState(.projected, type: .training) }.map(\.id) == ["t1"])
        #expect(try await store.read { try $0.trashed() }.map(\.id) == ["t2"])
        #expect(try await store.read { try $0.byBatch("batch-1") }.map(\.id) == ["t2"])
        // Kosz nie wchodzi do zwykłych zapytań.
        #expect(try await store.query(.training).map(\.id) == ["t1"])
        #expect(try await store.query(.training, includeDeleted: true).map(\.id) == ["t1", "t2"])
        #expect(try await store.count(.training) == 1)
        #expect(try await store.count(.training, includeDeleted: true) == 2)

        try await store.write { try $0.deleteState(.projected) }
        #expect(try await store.get(.training, id: "t1") == nil)
        try await store.write { try $0.deleteHard(.training, id: "t2") }
        #expect(try await store.count(.training, includeDeleted: true) == 0)
    }

    @Test func metasDescribeRowsWithoutTheirBody() async throws {
        let store = try makeStore()
        try await store.upsert([
            try StoredRecord.of(horse("h1"), syncState: .synced),
            try StoredRecord.of(horse("h2", name: "Iskra"), syncState: .pending, baseVersion: 3),
        ])
        let metas = try await store.read { try $0.metas(.horse) }
        #expect(metas["h1"] == RecordMeta(version: 1, syncState: .synced, baseVersion: nil, deleted: false))
        #expect(metas["h2"] == RecordMeta(version: 1, syncState: .pending, baseVersion: 3, deleted: false))
        let some = try await store.read { try $0.metas(.horse, ids: ["h2", "brak"]) }
        #expect(Set(some.keys) == ["h2"])
    }

    @Test func clearRemovesEveryRecordAndItsHorses() async throws {
        let store = try makeStore()
        try await store.upsert([try StoredRecord.of(purchase("z1", horses: ["h1", "h2"], day: 3), syncState: .local)])
        try await store.write { try $0.clear() }
        #expect(try await store.count(.purchase) == 0)
        #expect(try await store.query(.purchase, horseId: "h1").isEmpty)
    }

    // MARK: Transakcja i licznik zmian

    @Test func theChangeCounterRisesOncePerWriteTransaction() async throws {
        let store = try makeStore()
        #expect(try await store.changeCounter() == 0)

        try await store.write { access in
            try access.upsert([try StoredRecord.of(horse("h1"), syncState: .local)])
            try access.upsert([try StoredRecord.of(horse("h2", name: "Iskra"), syncState: .local)])
            try access.setMeta("a", "b")
        }
        #expect(try await store.changeCounter() == 1)

        try await store.upsert([try StoredRecord.of(horse("h3", name: "Burza"), syncState: .local)])
        #expect(try await store.changeCounter() == 2)

        // Odczyt i pusty zapis nie zmieniają licznika.
        _ = try await store.query(.horse)
        try await store.upsert([])
        #expect(try await store.changeCounter() == 2)
    }

    @Test func aFailedTransactionLeavesNoTraceAndNoCounterChange() async throws {
        let store = try makeStore()
        struct Boom: Error {}
        do {
            try await store.write { access in
                try access.upsert([try StoredRecord.of(horse("h1"), syncState: .local)])
                throw Boom()
            }
            Issue.record("transakcja powinna się nie udać")
        } catch is Boom {}
        #expect(try await store.count(.horse) == 0)
        #expect(try await store.changeCounter() == 0)
    }

    @Test func metaValuesAreStoredAndRemoved() async throws {
        let store = try makeStore()
        try await store.setMeta("sync.dataStamp", "2026-10-05T10:00:00")
        #expect(try await store.meta("sync.dataStamp") == "2026-10-05T10:00:00")
        try await store.setMeta("sync.dataStamp", nil)
        #expect(try await store.meta("sync.dataStamp") == nil)
    }

    // MARK: Obserwacja

    @Test func observationEmitsAfterEachChange() async throws {
        let store = try makeStore()
        var iterator = store.observe(.horse).makeAsyncIterator()
        #expect(try await iterator.next()?.count == 0)

        try await store.upsert([try StoredRecord.of(horse("h1"), syncState: .local)])
        #expect(try await iterator.next()?.map(\.id) == ["h1"])

        try await store.upsert([try StoredRecord.of(horse("h2", name: "Iskra"), syncState: .local)])
        #expect(try await iterator.next()?.count == 2)
    }

    @Test func changeCounterObservationEmitsNewValues() async throws {
        let store = try makeStore()
        var iterator = store.observeChanges().makeAsyncIterator()
        #expect(try await iterator.next() == 0)
        try await store.upsert([try StoredRecord.of(horse("h1"), syncState: .local)])
        #expect(try await iterator.next() == 1)
    }

    // MARK: Schemat

    @Test func migrationV1CreatesEveryTable() throws {
        let database = try AppDatabase.inMemory()
        let tables = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'")
        }
        #expect(Set(tables) == ["local_record", "record_horse", "local_file", "queue_operation", "queue_history", "conflict", "local_meta", "address", "local_track", "ride_session", "ride_point", "ride_media"])
    }
}
