import Foundation

/// Wiersz do odczytu przez reguły: rekord, dzień porządkujący (start bez daty dziedziczy datę zawodów) i znacznik kosza.
public struct SourceRow: Sendable {
    public let record: any LocalRecord
    public let dateKey: LocalDate?
    public let isDeleted: Bool
    public let deletionBatchId: String?

    public init(record: any LocalRecord, dateKey: LocalDate?, isDeleted: Bool = false, deletionBatchId: String? = nil) {
        self.record = record
        self.dateKey = dateKey
        self.isDeleted = isDeleted
        self.deletionBatchId = deletionBatchId
    }
}

/// Odczyt rekordów dla reguł, widoków i raportów — te same zapytania co `LocalStore` w Androidzie, ale synchroniczne (rdzeń nie ma
/// asynchroniczności; magazyn SQLite wywołuje reguły wewnątrz jednej transakcji odczytu lub zapisu).
public protocol RecordSource {
    /// Wiersze rodzaju po dniu rosnąco, potem `id`. `horseId` obejmuje też rekordy z wieloma końmi (zakup); `from` i `to` włączone.
    func query(_ type: RecordType, horseId: String?, from: LocalDate?, to: LocalDate?, includeDeleted: Bool) throws -> [SourceRow]

    func get(_ type: RecordType, id: String) throws -> SourceRow?

    /// Rekordy podrzędne: starty zawodów, załączniki właściciela, terminy ze źródła.
    func byOwner(_ type: RecordType, ownerId: String, includeDeleted: Bool) throws -> [SourceRow]

    /// Partia usunięcia (kosz).
    func byBatch(_ batchId: String) throws -> [SourceRow]
}

public extension RecordSource {
    func query(_ type: RecordType, horseId: String? = nil, from: LocalDate? = nil, to: LocalDate? = nil) throws -> [SourceRow] {
        try query(type, horseId: horseId, from: from, to: to, includeDeleted: false)
    }

    func byOwner(_ type: RecordType, ownerId: String) throws -> [SourceRow] {
        try byOwner(type, ownerId: ownerId, includeDeleted: false)
    }

    /// Rekordy poza koszem w rodzaju `R`.
    func records<R: LocalRecord>(_ type: RecordType, as _: R.Type = R.self, horseId: String? = nil, from: LocalDate? = nil, to: LocalDate? = nil) throws -> [R] {
        try query(type, horseId: horseId, from: from, to: to).compactMap { $0.record as? R }
    }

    /// Rekord poza koszem.
    func find<R: LocalRecord>(_ type: RecordType, id: String, as _: R.Type = R.self) throws -> R? {
        guard let row = try get(type, id: id), !row.isDeleted else { return nil }
        return row.record as? R
    }
}

/// Źródło w pamięci — testy i pliki wzorcowe programu (`ExportDocument`); zachowuje się jak magazyn SQLite.
public final class InMemoryRecordSource: RecordSource {
    private struct Key: Hashable {
        let type: RecordType
        let id: String
    }

    private var rows: [Key: SourceRow] = [:]

    public init(rows: [SourceRow] = []) {
        for row in rows { self.rows[Key(type: row.record.recordType, id: row.record.id)] = row }
    }

    public convenience init(document: ExportDocument) {
        self.init(rows: document.records.map { SourceRow(record: $0.record, dateKey: $0.dateKey) })
    }

    public func upsert(_ row: SourceRow) {
        rows[Key(type: row.record.recordType, id: row.record.id)] = row
    }

    public func remove(_ type: RecordType, id: String) {
        rows[Key(type: type, id: id)] = nil
    }

    private static func ordered(_ rows: [SourceRow]) -> [SourceRow] {
        rows.sorted { lhs, rhs in
            switch (lhs.dateKey, rhs.dateKey) {
            case let (left?, right?) where left != right: return left < right
            case (nil, .some): return true
            case (.some, nil): return false
            default: return lhs.record.id < rhs.record.id
            }
        }
    }

    public func query(_ type: RecordType, horseId: String?, from: LocalDate?, to: LocalDate?, includeDeleted: Bool) throws -> [SourceRow] {
        Self.ordered(rows.values.filter { row in
            guard row.record.recordType == type, includeDeleted || !row.isDeleted else { return false }
            if let horseId, row.record.primaryHorseId != horseId, !row.record.horseIds.contains(horseId) { return false }
            if let from, (row.dateKey.map { $0 < from } ?? true) { return false }
            if let to, (row.dateKey.map { $0 > to } ?? true) { return false }
            return true
        })
    }

    public func get(_ type: RecordType, id: String) throws -> SourceRow? {
        rows[Key(type: type, id: id)]
    }

    public func byOwner(_ type: RecordType, ownerId: String, includeDeleted: Bool) throws -> [SourceRow] {
        Self.ordered(rows.values.filter { $0.record.recordType == type && $0.record.parentId == ownerId && (includeDeleted || !$0.isDeleted) })
    }

    public func byBatch(_ batchId: String) throws -> [SourceRow] {
        rows.values.filter { $0.deletionBatchId == batchId }.sorted {
            ($0.record.recordType.rawValue, $0.record.id) < ($1.record.recordType.rawValue, $1.record.id)
        }
    }
}
