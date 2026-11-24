import Foundation
import GRDB
import Testing
@testable import HorselyKit
@testable import HorselyCore

/// Testy migracji v2 → v3: tworzenie tabel ride, zapis/odczyt tras, czyszczenie magazynu.
@Test func migrationV2ToV3KeepsRecordsAndCreatesRideTables() throws {
    // 1. Stwórz bazę z migracją v1 (tabela local_record)
    let queue = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
        try db.create(table: "local_record") { t in
            t.column("type", .text).notNull()
            t.column("id", .text).notNull()
            t.column("version", .integer).notNull()
            t.column("createdAt", .text).notNull()
            t.column("updatedAt", .text).notNull()
            t.column("horseId", .text)
            t.column("dateKey", .text)
            t.column("ownerId", .text)
            t.column("deletedAt", .text)
            t.column("deletionBatchId", .text)
            t.column("syncState", .text).notNull()
            t.column("baseVersion", .integer)
            t.column("body", .text).notNull()
            t.primaryKey(["type", "id"])
        }
        try db.create(index: "local_record_type_horse_date", on: "local_record", columns: ["type", "horseId", "dateKey"])
        try db.create(index: "local_record_type_date", on: "local_record", columns: ["type", "dateKey"])
        try db.create(index: "local_record_type_owner", on: "local_record", columns: ["type", "ownerId"])
        try db.create(index: "local_record_batch", on: "local_record", columns: ["deletionBatchId"])
        try db.create(index: "local_record_state", on: "local_record", columns: ["syncState"])

        try db.create(table: "record_horse") { t in
            t.column("type", .text).notNull()
            t.column("id", .text).notNull()
            t.column("horseId", .text).notNull()
            t.primaryKey(["type", "id", "horseId"])
        }
        try db.create(index: "record_horse_horse", on: "record_horse", columns: ["horseId"])

        try db.create(table: "local_file") { t in
            t.column("attachmentId", .text).notNull()
            t.column("kind", .text).notNull()
            t.column("relativePath", .text).notNull()
            t.column("sizeBytes", .integer).notNull()
            t.column("sha256", .text).notNull()
            t.column("lastOpenedAt", .text)
            t.column("pinned", .boolean).notNull().defaults(to: false)
            t.primaryKey(["attachmentId", "kind"])
        }
        try db.create(index: "local_file_opened", on: "local_file", columns: ["lastOpenedAt"])

        try db.create(table: "queue_operation") { t in
            t.column("id", .text).primaryKey()
            t.column("seq", .integer).notNull().unique()
            t.column("kind", .text).notNull()
            t.column("recordType", .text)
            t.column("recordId", .text)
            t.column("baseVersion", .integer)
            t.column("payload", .text)
            t.column("fileRef", .text)
            t.column("dependsOn", .text)
            t.column("state", .text).notNull()
            t.column("attempts", .integer).notNull().defaults(to: 0)
            t.column("nextAttemptAt", .text)
            t.column("lastError", .text)
            t.column("countBefore", .integer)
            t.column("createdAt", .text).notNull()
            t.column("updatedAt", .text).notNull()
        }
        try db.create(index: "queue_operation_state_seq", on: "queue_operation", columns: ["state", "seq"])

        try db.create(table: "queue_history") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("operationId", .text).notNull()
            t.column("kind", .text).notNull()
            t.column("outcome", .text).notNull()
            t.column("summary", .text).notNull()
            t.column("at", .text).notNull()
        }
        try db.create(index: "queue_history_at", on: "queue_history", columns: ["at"])

        try db.create(table: "conflict") { t in
            t.column("id", .text).primaryKey()
            t.column("operationId", .text)
            t.column("recordType", .text).notNull()
            t.column("recordId", .text).notNull()
            t.column("kind", .text).notNull()
            t.column("mine", .text)
            t.column("theirs", .text)
            t.column("theirsVersion", .integer)
            t.column("trashBatchId", .text)
            t.column("trashBatchSize", .integer)
            t.column("detectedAt", .text).notNull()
            t.column("resolvedAt", .text)
            t.column("resolution", .text)
        }
        try db.create(index: "conflict_resolved", on: "conflict", columns: ["resolvedAt"])

        try db.create(table: "local_meta") { t in
            t.column("key", .text).primaryKey()
            t.column("value", .text).notNull()
        }

        try db.create(table: "address") { t in
            t.column("id", .text).primaryKey()
            t.column("url", .text).notNull()
            t.column("position", .integer).notNull()
            t.column("trustMode", .text).notNull()
            t.column("certSha256", .text)
            t.column("issuerSummary", .text)
            t.column("isRemote", .boolean).notNull().defaults(to: false)
            t.column("lastOkAt", .text)
            t.column("heldUntil", .text)
            t.column("heldReason", .text)
        }
        try db.create(index: "address_position", on: "address", columns: ["position"])
    }
    // v2 — bez zmian
    migrator.registerMigration("v2") { db in
        try db.alter(table: "queue_operation") { t in
            t.add(column: "localRef", .text)
            t.add(column: "horseRefs", .text)
            t.add(column: "summary", .text).notNull().defaults(to: "")
            t.add(column: "resultId", .text)
        }
    }
    try migrator.migrate(queue)

    // 2. Wstaw rekord do v1 — symulacja bazy z v2
    try queue.write { db in
        let now = Date()
        let body = try JSONEncoder().encode(["test": "value"])
        let nowISO = ISO8601DateFormatter().string(from: now)
        try db.execute(
            sql: "INSERT INTO local_record (type, id, version, createdAt, updatedAt, syncState, body) VALUES (?, ?, ?, ?, ?, ?, ?)",
            arguments: [
                "Training", "rec-1", 0,
                nowISO, nowISO,
                "Pending", String(data: body, encoding: .utf8)!
            ]
        )
    }

    // 3. Załóż migrację v3 na tej samej bazie
    var v3Migrator = DatabaseMigrator()
    v3Migrator.registerMigration("v3") { db in
        try db.create(table: "local_track") { t in
            t.column("recordingId", .text).primaryKey()
            t.column("version", .integer).notNull()
            t.column("format", .text).notNull()
            t.column("data", .blob).notNull()
        }

        try db.create(table: "ride_session") { t in
            t.column("id", .text).primaryKey()
            t.column("horseId", .text).notNull()
            t.column("horseName", .text).notNull()
            t.column("state", .text).notNull()
            t.column("startedAtMillis", .integer).notNull()
            t.column("endedAtMillis", .integer)
            t.column("timeZone", .text).notNull()
            t.column("pausesJson", .text)
            t.column("thresholdsJson", .text)
            t.column("loadJson", .text)
            t.column("accelerometerUsed", .integer).notNull().defaults(to: 0)
            t.column("lastFlushMillis", .integer).notNull()
            t.column("distanceMeters", .integer).notNull().defaults(to: 0)
            t.column("activeSeconds", .integer).notNull().defaults(to: 0)
        }

        try db.create(table: "ride_point") { t in
            t.column("sessionId", .text).notNull()
            t.column("seq", .integer).notNull()
            t.column("tMillis", .integer).notNull()
            t.column("lat", .real).notNull()
            t.column("lon", .real).notNull()
            t.column("altM", .real)
            t.column("speedMs", .real)
            t.column("hAccM", .real)
            t.column("vAccM", .real)
            t.column("cadence", .real)
            t.column("intensity", .real)
            t.primaryKey(["sessionId", "seq"])
        }
        try db.create(index: "ride_point_session_seq", on: "ride_point", columns: ["sessionId", "seq"])

        try db.create(table: "ride_media") { t in
            t.column("sessionId", .text).notNull()
            t.column("uri", .text).notNull()
            t.column("contentType", .text).notNull()
            t.column("capturedAtMillis", .integer).notNull()
            t.column("lat", .real)
            t.column("lon", .real)
            t.primaryKey(["sessionId", "uri"])
        }
    }
    try v3Migrator.migrate(queue)

    // 4. Weryfikacja — rekord nadal istnieje
    try queue.read { db in
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_record") ?? 0
        #expect(count == 1)
    }

    // 5. Nowe tabele istnieją i są puste
    try queue.read { db in
        let trackCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_track") ?? 0
        #expect(trackCount == 0)
        let sessionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ride_session") ?? 0
        #expect(sessionCount == 0)
        let pointCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ride_point") ?? 0
        #expect(pointCount == 0)
        let mediaCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ride_media") ?? 0
        #expect(mediaCount == 0)
    }
}

// MARK: - trackRoundTrip

@Test func trackRoundTrip() throws {
    let queue = try DatabaseQueue()
    try queue.write { db in
        try db.create(table: "local_track") { t in
            t.column("recordingId", .text).primaryKey()
            t.column("version", .integer).notNull()
            t.column("format", .text).notNull()
            t.column("data", .blob).notNull()
        }
    }

    let recordingId = "ride-001"
    let version = 1
    let format = "zk-track/1"
    let trackData = Data([0x1F, 0x8B, 0x08, 0x00]) // gzip header

    // Zapis
    try queue.write { db in
        try db.execute(
            sql: "INSERT INTO local_track (recordingId, version, format, data) VALUES (?, ?, ?, ?)",
            arguments: [recordingId, version, format, trackData]
        )
    }

    // Odczyt
    let track = try queue.read { db in
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM local_track WHERE recordingId = ?", arguments: [recordingId]) else {
            return nil
        }
        return StoredTrack(
            recordingId: row["recordingId"] as String,
            version: row["version"] as Int,
            format: row["format"] as String,
            data: row["data"] as Data
        )
    }

    #expect(track != nil)
    #expect(track!.recordingId == recordingId)
    #expect(track!.version == version)
    #expect(track!.format == format)
    #expect(track!.data == trackData)
}

// MARK: - clearRemovesTracks

@Test func clearRemovesTracks() throws {
    let queue = try DatabaseQueue()
    try queue.write { db in
        try db.create(table: "local_track") { t in
            t.column("recordingId", .text).primaryKey()
            t.column("version", .integer).notNull()
            t.column("format", .text).notNull()
            t.column("data", .blob).notNull()
        }
        try db.create(table: "ride_session") { t in
            t.column("id", .text).primaryKey()
            t.column("horseId", .text).notNull()
            t.column("horseName", .text).notNull()
            t.column("state", .text).notNull()
            t.column("startedAtMillis", .integer).notNull()
            t.column("endedAtMillis", .integer)
            t.column("timeZone", .text).notNull()
            t.column("pausesJson", .text)
            t.column("thresholdsJson", .text)
            t.column("loadJson", .text)
            t.column("accelerometerUsed", .integer).notNull().defaults(to: 0)
            t.column("lastFlushMillis", .integer).notNull()
            t.column("distanceMeters", .integer).notNull().defaults(to: 0)
            t.column("activeSeconds", .integer).notNull().defaults(to: 0)
        }
        try db.create(table: "ride_point") { t in
            t.column("sessionId", .text).notNull()
            t.column("seq", .integer).notNull()
            t.column("tMillis", .integer).notNull()
            t.column("lat", .real).notNull()
            t.column("lon", .real).notNull()
            t.column("altM", .real)
            t.column("speedMs", .real)
            t.column("hAccM", .real)
            t.column("vAccM", .real)
            t.column("cadence", .real)
            t.column("intensity", .real)
            t.primaryKey(["sessionId", "seq"])
        }
        try db.create(table: "ride_media") { t in
            t.column("sessionId", .text).notNull()
            t.column("uri", .text).notNull()
            t.column("contentType", .text).notNull()
            t.column("capturedAtMillis", .integer).notNull()
            t.column("lat", .real)
            t.column("lon", .real)
            t.primaryKey(["sessionId", "uri"])
        }
    }

    // Wstaw dane
    try queue.write { db in
        try db.execute(
            sql: "INSERT INTO local_track (recordingId, version, format, data) VALUES (?, ?, ?, ?)",
            arguments: ["ride-1", 1, "zk-track/1", Data()]
        )
        try db.execute(
            sql: "INSERT INTO ride_session (id, horseId, horseName, state, startedAtMillis, timeZone, lastFlushMillis) VALUES (?, ?, ?, ?, ?, ?, ?)",
            arguments: ["sess-1", "horse-1", "Kongo", "Recording", 1000, "Europe/Warsaw", 1000]
        )
        try db.execute(
            sql: "INSERT INTO ride_point (sessionId, seq, tMillis, lat, lon) VALUES (?, ?, ?, ?, ?)",
            arguments: ["sess-1", 0, 0, 52.0, 21.0]
        )
        try db.execute(
            sql: "INSERT INTO ride_media (sessionId, uri, contentType, capturedAtMillis) VALUES (?, ?, ?, ?)",
            arguments: ["sess-1", "content://uri/1", "image/jpeg", 1000]
        )
    }

    // Usunięcie tras i sesji (jak w clearStore)
    try queue.write { db in
        try db.execute(sql: "DELETE FROM ride_point")
        try db.execute(sql: "DELETE FROM ride_media")
        try db.execute(sql: "DELETE FROM ride_session")
        try db.execute(sql: "DELETE FROM local_track")
    }

    // Weryfikacja — wszystko puste
    try queue.read { db in
        #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_track") ?? 0 == 0)
        #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ride_session") ?? 0 == 0)
        #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ride_point") ?? 0 == 0)
        #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ride_media") ?? 0 == 0)
    }
}

// MARK: - StoredTrack

/// Struktura trasy zapisanej w bazie.
struct StoredTrack: Sendable, Equatable {
    let recordingId: String
    let version: Int
    let format: String
    let data: Data
}
