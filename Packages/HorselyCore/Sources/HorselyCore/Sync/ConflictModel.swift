import Foundation

/// Rodzaj konfliktu wykrytego przy wysyłce (research R6, contracts/android/mode-and-sync.md §3 i §6).
public enum ConflictKind: String, Codable, Sendable, CaseIterable {
    /// Zmieniłem rekord i ktoś zmienił go w programie (`409` na `PUT`).
    case editEdit = "EditEdit"
    /// Zmieniłem rekord, a w programie został usunięty (`404` na `PUT`).
    case editDelete = "EditDelete"
    /// Usunąłem rekord, a w programie został zmieniony.
    case deleteEdit = "DeleteEdit"
}

/// Rozstrzygnięcie użytkownika (FR-SYN2-07).
public enum ConflictResolution: String, Codable, Sendable {
    case keepMine = "KeepMine"
    case acceptTheirs = "AcceptTheirs"
}

/// Konflikt zmiany (tabela `conflict`). `mine` i `theirs` — rekordy w kształcie eksportu (JSON): `mine` `nil` przy usunięciu,
/// `theirs` `nil`, gdy rekord usunięto w programie. `trashBatchId` — partia kosza programu z rekordem (`EditDelete`).
public struct Conflict: Hashable, Sendable, Identifiable {
    public var id: String
    public var operationId: String
    public var recordType: RecordType
    public var recordId: String
    public var kind: ConflictKind
    public var mine: String?
    public var theirs: String?
    public var theirsVersion: Int?
    public var trashBatchId: String?
    public var trashBatchSize: Int?
    public var detectedAt: Date
    public var resolvedAt: Date?
    public var resolution: ConflictResolution?

    public init(
        id: String, operationId: String, recordType: RecordType, recordId: String, kind: ConflictKind, mine: String?, theirs: String?,
        theirsVersion: Int?, trashBatchId: String? = nil, trashBatchSize: Int? = nil, detectedAt: Date, resolvedAt: Date? = nil,
        resolution: ConflictResolution? = nil
    ) {
        self.id = id
        self.operationId = operationId
        self.recordType = recordType
        self.recordId = recordId
        self.kind = kind
        self.mine = mine
        self.theirs = theirs
        self.theirsVersion = theirsVersion
        self.trashBatchId = trashBatchId
        self.trashBatchSize = trashBatchSize
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
        self.resolution = resolution
    }

    public var isOpen: Bool { resolvedAt == nil }
}

/// Wiersz porównania „Moja” / „Z programu” na ekranie konfliktu: pole, obie wartości jako tekst, wyróżnienie różnicy.
public struct ConflictFieldDiff: Hashable, Sendable {
    public let field: String
    public let mine: String?
    public let theirs: String?

    public var differs: Bool { mine != theirs }
}

public enum ConflictDiff {
    /// Pola techniczne pomijane w porównaniu.
    static let ignored: Set<String> = ["id", "createdAt", "updatedAt", "version"]

    /// Porównanie płaskie pól obu rekordów (zagnieżdżone tablice i obiekty jako tekst JSON), w stałej kolejności kluczy.
    public static func fields(mine: String?, theirs: String?) -> [ConflictFieldDiff] {
        let left = mine.flatMap { JSONValue.object($0) } ?? [:]
        let right = theirs.flatMap { JSONValue.object($0) } ?? [:]
        let keys = Set(left.keys).union(right.keys).subtracting(ignored).sorted()
        return keys.compactMap { key in
            let a = display(left[key])
            let b = display(right[key])
            if a == nil && b == nil { return nil }
            return ConflictFieldDiff(field: key, mine: a, theirs: b)
        }
    }

    private static func display(_ value: JSONValue?) -> String? {
        guard let value, !value.isNull else { return nil }
        switch value {
        case let .array(items) where items.isEmpty: return nil
        case .array, .object: return value.text()
        default: return value.stringValue
        }
    }
}
