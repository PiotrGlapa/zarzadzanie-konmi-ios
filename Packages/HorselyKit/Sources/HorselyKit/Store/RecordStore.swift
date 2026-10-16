import Foundation
import GRDB
import HorselyCore

/// Wiersz magazynu (`local_record`): kolumny indeksowane i rekord w kształcie eksportu jako JSON (`body`). Rekord dekoduje się na
/// żądanie (`record()`) — listy po kolumnach nie płacą za dekodowanie reszty.
///
/// - `baseVersion`: wersja z programu, od której zaczęła się lokalna zmiana (tryb online)
/// - `deletedAt`: kosz — tylko tryb samodzielny
/// - `deletionBatchId`: id korzenia partii usunięcia
public struct StoredRecord: Sendable, Hashable {
    public let type: RecordType
    public let id: String
    public var version: Int
    public let horseId: String?
    public let dateKey: LocalDate?
    public let ownerId: String?
    public var deletedAt: LocalDateTime?
    public var deletionBatchId: String?
    public var syncState: SyncState
    public var baseVersion: Int?
    public let body: String
    let createdAt: LocalDateTime
    let updatedAt: LocalDateTime
    private let givenHorseIds: [String]?

    init(
        type: RecordType, id: String, version: Int, createdAt: LocalDateTime, updatedAt: LocalDateTime, horseId: String?, dateKey: LocalDate?,
        ownerId: String?, horseIds: [String]?, deletedAt: LocalDateTime?, deletionBatchId: String?, syncState: SyncState, baseVersion: Int?, body: String
    ) {
        self.type = type
        self.id = id
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.horseId = horseId
        self.dateKey = dateKey
        self.ownerId = ownerId
        self.givenHorseIds = horseIds
        self.deletedAt = deletedAt
        self.deletionBatchId = deletionBatchId
        self.syncState = syncState
        self.baseVersion = baseVersion
        self.body = body
    }

    /// Wiersz z rekordu; `dateKey` — gdy rekord nie wyznacza go sam (start bez daty dziedziczy datę zawodów).
    public static func of(
        _ record: some LocalRecord, syncState: SyncState, baseVersion: Int? = nil, dateKey: LocalDate? = nil,
        deletedAt: LocalDateTime? = nil, deletionBatchId: String? = nil
    ) throws -> StoredRecord {
        StoredRecord(
            type: record.recordType, id: record.id, version: record.version, createdAt: record.createdAt, updatedAt: record.updatedAt,
            horseId: record.primaryHorseId, dateKey: dateKey ?? record.dateKey, ownerId: record.parentId, horseIds: record.horseIds,
            deletedAt: deletedAt, deletionBatchId: deletionBatchId, syncState: syncState, baseVersion: baseVersion,
            body: try RecordCodec.encodeString(record)
        )
    }

    public func record() throws -> any LocalRecord {
        try RecordCodec.decode(type, from: body)
    }

    /// Rekord danego rodzaju; `nil`, gdy treść jest innego typu.
    public func record<R: LocalRecord>(as _: R.Type) throws -> R? {
        try record() as? R
    }

    /// Konie rekordu (tabela `record_horse`); gdy nie podano — z rekordu.
    public var horseIds: [String] {
        givenHorseIds ?? ((try? record().horseIds) ?? [])
    }

    public var isDeleted: Bool { deletedAt != nil }
}

/// Zbiór operacji na magazynie w jednej transakcji bazy. Tworzony tylko wewnątrz `RecordStore.write`/`read`. Każda transakcja
/// zapisu, w której coś zapisano, zwiększa licznik zmian dokładnie raz (kopia automatyczna, przypomnienie o kopii).
public struct RecordAccess {
    let db: Database
    fileprivate let state: WriteState

    final class WriteState {
        var dirty = false
    }

    private static let chunk = 400 // limit zmiennych SQLite (999)

    // MARK: Zapis

    /// Wstawia lub zastępuje wiersze (z tabelą `record_horse`).
    public func upsert(_ rows: [StoredRecord]) throws {
        guard !rows.isEmpty else { return }
        state.dirty = true
        for group in Dictionary(grouping: rows, by: \.type) {
            let ids = group.value.map(\.id)
            for part in stride(from: 0, to: ids.count, by: Self.chunk).map({ Array(ids[$0..<min($0 + Self.chunk, ids.count)]) }) {
                try db.execute(
                    sql: "DELETE FROM record_horse WHERE type = ? AND id IN (\(Self.placeholders(part.count)))",
                    arguments: Self.arguments([group.key.rawValue] + part)
                )
            }
        }
        for row in rows {
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO local_record
                (type, id, version, createdAt, updatedAt, horseId, dateKey, ownerId, deletedAt, deletionBatchId, syncState, baseVersion, body)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    row.type.rawValue, row.id, row.version, row.createdAt.description, row.updatedAt.description, row.horseId,
                    row.dateKey?.description, row.ownerId, row.deletedAt?.description, row.deletionBatchId, row.syncState.rawValue,
                    row.baseVersion, row.body,
                ]
            )
            for horse in Set(row.horseIds) {
                try db.execute(sql: "INSERT OR REPLACE INTO record_horse (type, id, horseId) VALUES (?, ?, ?)", arguments: [row.type.rawValue, row.id, horse])
            }
        }
    }

    /// Usuwa wiersz bezpowrotnie (trwałe usunięcie, uzgodnienie, zastąpienie `id`).
    public func deleteHard(_ type: RecordType, id: String) throws {
        state.dirty = true
        try db.execute(sql: "DELETE FROM record_horse WHERE type = ? AND id = ?", arguments: [type.rawValue, id])
        try db.execute(sql: "DELETE FROM local_record WHERE type = ? AND id = ?", arguments: [type.rawValue, id])
    }

    /// Usuwa wszystkie wiersze danego stanu (np. `Projected` przed uzgadnianiem).
    public func deleteState(_ syncState: SyncState) throws {
        state.dirty = true
        try db.execute(
            sql: "DELETE FROM record_horse WHERE (type || ':' || id) IN (SELECT type || ':' || id FROM local_record WHERE syncState = ?)",
            arguments: [syncState.rawValue]
        )
        try db.execute(sql: "DELETE FROM local_record WHERE syncState = ?", arguments: [syncState.rawValue])
    }

    /// Czyści cały magazyn rekordów (zmiana trybu; odtworzenie kopii zastępuje całość w jednej transakcji).
    public func clear() throws {
        state.dirty = true
        try db.execute(sql: "DELETE FROM record_horse")
        try db.execute(sql: "DELETE FROM local_record")
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        state.dirty = true
        if let value {
            try db.execute(sql: "INSERT OR REPLACE INTO local_meta (key, value) VALUES (?, ?)", arguments: [key, value])
        } else {
            try db.execute(sql: "DELETE FROM local_meta WHERE key = ?", arguments: [key])
        }
    }

    // MARK: Odczyt

    public func get(_ type: RecordType, id: String) throws -> StoredRecord? {
        try Row.fetchOne(db, sql: "SELECT * FROM local_record WHERE type = ? AND id = ?", arguments: [type.rawValue, id]).map(Self.stored)
    }

    /// Wiersze rodzaju po `dateKey` rosnąco, potem `id`. `horseId` obejmuje też rekordy z wieloma końmi (zakup); `from` i `to` są
    /// włączone. Rekordy z kosza tylko przy `includeDeleted`.
    public func query(_ type: RecordType, horseId: String? = nil, from: LocalDate? = nil, to: LocalDate? = nil, includeDeleted: Bool = false) throws -> [StoredRecord] {
        var sql = "SELECT * FROM local_record WHERE type = ?"
        var arguments: [(any DatabaseValueConvertible)?] = [type.rawValue]
        if !includeDeleted { sql += " AND deletedAt IS NULL" }
        if let horseId {
            sql += " AND (horseId = ? OR id IN (SELECT id FROM record_horse WHERE type = ? AND horseId = ?))"
            arguments += [horseId, type.rawValue, horseId]
        }
        if let from {
            sql += " AND dateKey >= ?"
            arguments.append(from.description)
        }
        if let to {
            sql += " AND dateKey <= ?"
            arguments.append(to.description)
        }
        sql += " ORDER BY dateKey, id"
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).map(Self.stored)
    }

    /// Rekordy podrzędne: starty zawodów, załączniki właściciela, terminy ze źródła.
    public func byOwner(_ type: RecordType, ownerId: String, includeDeleted: Bool = false) throws -> [StoredRecord] {
        let sql = "SELECT * FROM local_record WHERE type = ? AND ownerId = ?" + (includeDeleted ? "" : " AND deletedAt IS NULL") + " ORDER BY dateKey, id"
        return try Row.fetchAll(db, sql: sql, arguments: [type.rawValue, ownerId]).map(Self.stored)
    }

    /// Partia usunięcia (kosz trybu samodzielnego).
    public func byBatch(_ batchId: String) throws -> [StoredRecord] {
        try Row.fetchAll(db, sql: "SELECT * FROM local_record WHERE deletionBatchId = ? ORDER BY type, id", arguments: [batchId]).map(Self.stored)
    }

    /// Rekordy w danym stanie synchronizacji (wszystkie rodzaje albo jeden).
    public func withState(_ syncState: SyncState, type: RecordType? = nil) throws -> [StoredRecord] {
        if let type {
            return try Row.fetchAll(db, sql: "SELECT * FROM local_record WHERE syncState = ? AND type = ? ORDER BY id", arguments: [syncState.rawValue, type.rawValue]).map(Self.stored)
        }
        return try Row.fetchAll(db, sql: "SELECT * FROM local_record WHERE syncState = ? ORDER BY type, id", arguments: [syncState.rawValue]).map(Self.stored)
    }

    /// Wiersze z koszem (`deletedAt ≠ nil`).
    public func trashed() throws -> [StoredRecord] {
        try Row.fetchAll(db, sql: "SELECT * FROM local_record WHERE deletedAt IS NOT NULL ORDER BY deletedAt, id").map(Self.stored)
    }

    /// Metadane wierszy rodzaju — klucz to `id`; `ids` ogranicza do wybranych (świeże dane do uzgadniania paczki).
    public func metas(_ type: RecordType, ids: [String]? = nil) throws -> [String: RecordMeta] {
        let select = "SELECT id, version, syncState, baseVersion, (deletedAt IS NOT NULL) AS deleted FROM local_record WHERE type = ?"
        var rows: [Row] = []
        if let ids {
            for start in stride(from: 0, to: ids.count, by: Self.chunk) {
                let part = Array(ids[start..<min(start + Self.chunk, ids.count)])
                rows += try Row.fetchAll(db, sql: select + " AND id IN (\(Self.placeholders(part.count)))", arguments: Self.arguments([type.rawValue] + part))
            }
        } else {
            rows = try Row.fetchAll(db, sql: select, arguments: [type.rawValue])
        }
        var result: [String: RecordMeta] = [:]
        for row in rows {
            let id: String = row["id"]
            let rawState: String = row["syncState"]
            result[id] = RecordMeta(version: row["version"], syncState: SyncState(rawValue: rawState) ?? .local, baseVersion: row["baseVersion"], deleted: row["deleted"])
        }
        return result
    }

    public func count(_ type: RecordType, includeDeleted: Bool = false) throws -> Int {
        let sql = "SELECT COUNT(*) FROM local_record WHERE type = ?" + (includeDeleted ? "" : " AND deletedAt IS NULL")
        return try Int.fetchOne(db, sql: sql, arguments: [type.rawValue]) ?? 0
    }

    public func meta(_ key: String) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM local_meta WHERE key = ?", arguments: [key])
    }

    public func changeCounter() throws -> Int64 {
        try meta(RecordStore.changeCounterKey).flatMap(Int64.init) ?? 0
    }

    // MARK: Pomocnicze

    static func stored(_ row: Row) throws -> StoredRecord {
        let rawType: String = row["type"]
        let rawState: String = row["syncState"]
        guard let type = RecordType(rawValue: rawType), let state = SyncState(rawValue: rawState) else {
            throw StoreError.corruptRow("type=\(rawType) syncState=\(rawState)")
        }
        let created: String = row["createdAt"]
        let updated: String = row["updatedAt"]
        guard let createdAt = LocalDateTime(created), let updatedAt = LocalDateTime(updated) else { throw StoreError.corruptRow("daty rekordu \(rawType)") }
        let dateKey: String? = row["dateKey"]
        let deletedAt: String? = row["deletedAt"]
        return StoredRecord(
            type: type, id: row["id"], version: row["version"], createdAt: createdAt, updatedAt: updatedAt, horseId: row["horseId"],
            dateKey: dateKey.flatMap { LocalDate($0) }, ownerId: row["ownerId"], horseIds: nil, deletedAt: deletedAt.flatMap { LocalDateTime($0) },
            deletionBatchId: row["deletionBatchId"], syncState: state, baseVersion: row["baseVersion"], body: row["body"]
        )
    }

    static func arguments(_ values: [String]) -> StatementArguments {
        StatementArguments(values.map { Optional<any DatabaseValueConvertible>($0) })
    }

    static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }
}

public enum StoreError: Error, Equatable {
    case corruptRow(String)
    case notFound(String)
}

/// Magazyn lokalny rekordów (research R2, R3): jedna tabela rekordów w kształcie eksportu, niepodzielne zapisy, licznik zmian,
/// obserwacja zmian jako `AsyncSequence`. Każda metoda `write` to jedna transakcja SQLite (rekord + skutki + licznik).
public final class RecordStore: Sendable {
    static let changeCounterKey = "changeCounter"

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Wykonuje `block` w jednej transakcji — albo wszystkie zmiany, albo żadna. Licznik zmian rośnie raz, gdy coś zapisano.
    public func write<T: Sendable>(_ block: @Sendable @escaping (RecordAccess) throws -> T) async throws -> T {
        try await database.writer.write { db in
            let access = RecordAccess(db: db, state: RecordAccess.WriteState())
            let result = try block(access)
            if access.state.dirty {
                let current = try Int64(access.meta(Self.changeCounterKey) ?? "0") ?? 0
                try db.execute(sql: "INSERT OR REPLACE INTO local_meta (key, value) VALUES (?, ?)", arguments: [Self.changeCounterKey, String(current + 1)])
            }
            return result
        }
    }

    public func read<T: Sendable>(_ block: @Sendable @escaping (RecordAccess) throws -> T) async throws -> T {
        try await database.writer.read { db in
            try block(RecordAccess(db: db, state: RecordAccess.WriteState()))
        }
    }

    // MARK: Skróty

    public func upsert(_ rows: [StoredRecord]) async throws {
        try await write { try $0.upsert(rows) }
    }

    public func get(_ type: RecordType, id: String) async throws -> StoredRecord? {
        try await read { try $0.get(type, id: id) }
    }

    public func query(_ type: RecordType, horseId: String? = nil, from: LocalDate? = nil, to: LocalDate? = nil, includeDeleted: Bool = false) async throws -> [StoredRecord] {
        try await read { try $0.query(type, horseId: horseId, from: from, to: to, includeDeleted: includeDeleted) }
    }

    public func count(_ type: RecordType, includeDeleted: Bool = false) async throws -> Int {
        try await read { try $0.count(type, includeDeleted: includeDeleted) }
    }

    public func changeCounter() async throws -> Int64 {
        try await read { try $0.changeCounter() }
    }

    public func meta(_ key: String) async throws -> String? {
        try await read { try $0.meta(key) }
    }

    public func setMeta(_ key: String, _ value: String?) async throws {
        try await write { try $0.setMeta(key, value) }
    }

    // MARK: Obserwacja

    /// Aktywne (poza koszem) wiersze rodzaju; emituje po każdej zmianie.
    public func observe(_ type: RecordType) -> AsyncValueObservation<[StoredRecord]> {
        ValueObservation
            .tracking { db in try RecordAccess(db: db, state: RecordAccess.WriteState()).query(type) }
            .values(in: database.writer)
    }

    /// Licznik zmian jako strumień — odświeżanie widoków składanych z wielu rodzajów rekordów.
    public func observeChanges() -> AsyncValueObservation<Int64> {
        ValueObservation
            .tracking { db in try RecordAccess(db: db, state: RecordAccess.WriteState()).changeCounter() }
            .removeDuplicates()
            .values(in: database.writer)
    }
}
