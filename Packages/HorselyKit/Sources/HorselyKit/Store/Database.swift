import Foundation
import GRDB

/// Baza SQLite aplikacji (research R3, data-model.md §2): `DatabasePool` (WAL) w kontenerze App Group, wyłączona z kopii iCloud,
/// z ochroną plików `completeUntilFirstUserAuthentication`. Schemat startuje od razu w kształcie 2.0.1 (migracja `v1`) —
/// iOS nie ma wersji 1.x, więc nie ma migracji z pamięci podręcznej.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try AppDatabase.migrator().migrate(writer)
    }

    /// Baza w pliku `Horsely/horsely.sqlite` w podanym katalogu (w aplikacji — kontener App Group).
    public static func open(in directory: URL) throws -> AppDatabase {
        let folder = directory.appendingPathComponent("Horsely", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try protect(folder)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        let pool = try DatabasePool(path: folder.appendingPathComponent("horsely.sqlite").path, configuration: configuration)
        return try AppDatabase(writer: pool)
    }

    /// Baza w pamięci — testy.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    /// Katalog App Group; `nil`, gdy aplikacja nie ma tego uprawnienia (np. testy `swift test` na macOS).
    public static func appGroupDirectory(identifier: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Wyłączenie z kopii iCloud i ochrona plików (NFR-M-04).
    static func protect(_ folder: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = folder
        try url.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
        #endif
    }

    // MARK: Schemat

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // Rekordy w kształcie eksportu programu: kolumny indeksowane + treść JSON (`body`).
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

            // Konie rekordu (zakup wielu koni) — zapytania po koniu.
            try db.create(table: "record_horse") { t in
                t.column("type", .text).notNull()
                t.column("id", .text).notNull()
                t.column("horseId", .text).notNull()
                t.primaryKey(["type", "id", "horseId"])
            }
            try db.create(index: "record_horse_horse", on: "record_horse", columns: ["horseId"])

            try db.create(table: "local_file") { t in
                t.column("attachmentId", .text).notNull()
                t.column("kind", .text).notNull() // Original / Thumbnail
                t.column("relativePath", .text).notNull()
                t.column("sizeBytes", .integer).notNull()
                t.column("sha256", .text).notNull()
                t.column("lastOpenedAt", .text)
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.primaryKey(["attachmentId", "kind"])
            }
            try db.create(index: "local_file_opened", on: "local_file", columns: ["lastOpenedAt"])

            try db.create(table: "queue_operation") { t in
                t.column("id", .text).primaryKey() // stały UUID — Idempotency-Key
                t.column("seq", .integer).notNull().unique()
                t.column("kind", .text).notNull()
                t.column("recordType", .text)
                t.column("recordId", .text)
                t.column("baseVersion", .integer)
                t.column("payload", .text)
                t.column("fileRef", .text)
                t.column("dependsOn", .text) // JSON listy id
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
                t.column("outcome", .text).notNull() // Sent / AlreadyHandled / ConflictResolved
                t.column("summary", .text).notNull() // bez treści wpisów
                t.column("at", .text).notNull()
            }
            try db.create(index: "queue_history_at", on: "queue_history", columns: ["at"])

            try db.create(table: "conflict") { t in
                t.column("id", .text).primaryKey()
                t.column("operationId", .text)
                t.column("recordType", .text).notNull()
                t.column("recordId", .text).notNull()
                t.column("kind", .text).notNull() // EditEdit / EditDelete / DeleteEdit
                t.column("mine", .text)
                t.column("theirs", .text)
                t.column("theirsVersion", .integer)
                t.column("trashBatchId", .text)
                t.column("trashBatchSize", .integer)
                t.column("detectedAt", .text).notNull()
                t.column("resolvedAt", .text)
                t.column("resolution", .text) // KeepMine / AcceptTheirs
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
                t.column("trustMode", .text).notNull() // Pinned / TrustedIssuer / PlainHttpConfirmed
                t.column("certSha256", .text)
                t.column("issuerSummary", .text)
                t.column("isRemote", .boolean).notNull().defaults(to: false)
                t.column("lastOkAt", .text)
                t.column("heldUntil", .text)
                t.column("heldReason", .text)
            }
            try db.create(index: "address_position", on: "address", columns: ["position"])
        }
        // Kolejka 2.0 (T084): identyfikator tworzonego rekordu dla operacji zależnych, konie do rozpoznania stajni, opis bez treści
        // wpisu i `id` nadane przez program. `fileRef` niesie plik załącznika (JSON), `lastError` — problem programu (JSON).
        migrator.registerMigration("v2") { db in
            try db.alter(table: "queue_operation") { t in
                t.add(column: "localRef", .text)
                t.add(column: "horseRefs", .text)
                t.add(column: "summary", .text).notNull().defaults(to: "")
                t.add(column: "resultId", .text)
            }
        }
        return migrator
    }
}
