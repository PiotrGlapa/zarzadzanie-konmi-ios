import Foundation

/// Powód konfliktu `409` — tak samo jak w programie (`ConflictReason`).
public enum ConflictReason: String, Sendable, Equatable {
    case versionMismatch = "VersionMismatch"
    case unique = "Unique"
    case inUse = "InUse"
    case invalidState = "InvalidState"
}

/// Odrzucenie operacji przez reguły; odpowiada odpowiedzi `400`/`404`/`409` programu.
public enum RuleProblem: Equatable, Sendable {
    /// `400`: pola → komunikaty (klucze jak w JSON programu: `passportNumber`, `medications[0].name`); ostrzeżenia nie blokują zapisu.
    case validation(errors: [String: [String]], warnings: [String: [String]] = [:])
    /// `409`.
    case conflict(reason: ConflictReason, message: String)
    /// `404`: rekord (albo partia kosza) nie istnieje lub jest w koszu.
    case notFound(what: String, id: String)

    /// Pierwszy komunikat do pokazania, gdy ekran nie ma osobnego miejsca przy polu.
    public var message: String {
        switch self {
        case let .validation(errors, _): errors.values.first?.first ?? Messages.invalidValue
        case let .conflict(_, message): message
        case .notFound: Messages.recordChanged
        }
    }
}

public enum EffectKind: String, Sendable, Equatable {
    case created, updated, trashed, restored
}

/// Rekord zmieniony przez operację; `primary` — rekord, który wskazał użytkownik (reszta to skutki reguł, np. termin).
public struct RecordEffect: Equatable, Sendable {
    public let type: RecordType
    public let id: String
    public let kind: EffectKind
    public let primary: Bool

    public init(type: RecordType, id: String, kind: EffectKind, primary: Bool) {
        self.type = type
        self.id = id
        self.kind = kind
        self.primary = primary
    }
}

/// Zapis zaplanowany przez reguły; magazyn stosuje je w jednej transakcji (rekord + skutki + licznik zmian).
public struct PlannedWrite: Sendable {
    public let record: any LocalRecord
    public let dateKey: LocalDate?
    public let deletedAt: LocalDateTime?
    public let deletionBatchId: String?
    public let primary: Bool

    public init(record: any LocalRecord, dateKey: LocalDate?, deletedAt: LocalDateTime? = nil, deletionBatchId: String? = nil, primary: Bool) {
        self.record = record
        self.dateKey = dateKey
        self.deletedAt = deletedAt
        self.deletionBatchId = deletionBatchId
        self.primary = primary
    }
}

/// Wynik operacji reguł.
public enum RuleOutcome: Sendable {
    case saved(RuleSaved)
    case rejected(RuleProblem)

    public var saved: RuleSaved? {
        if case let .saved(saved) = self { return saved }
        return nil
    }

    public var problem: RuleProblem? {
        if case let .rejected(problem) = self { return problem }
        return nil
    }
}

public struct RuleSaved: Sendable {
    /// Zapisany rekord główny (`nil` przy usunięciu).
    public let record: (any LocalRecord)?
    public let writes: [PlannedWrite]
    public let effects: [RecordEffect]
    public let warnings: [String: [String]]
    /// Partia kosza przy usunięciu.
    public let batchId: String?
}

/// Odrzucenie operacji przerywa jej wykonanie (cały plan zapisu jest wtedy porzucany).
struct RuleFailure: Error {
    let problem: RuleProblem
}

/// Jedna operacja zapisu: odczyt z uwzględnieniem zapisów już zaplanowanych, numeracja wersji (tryb samodzielny), lista skutków.
/// Nic nie jest zapisywane przez sesję — zapisy zwraca `RuleSaved`.
final class RuleSession {
    let now: LocalDateTime
    let today: LocalDate
    let settings: RuleSettings
    private let base: RecordSource
    private let idGenerator: () -> String
    private(set) var writes: [PlannedWrite] = []
    private(set) var effects: [RecordEffect] = []
    private(set) var warnings: [String: [String]] = [:]

    private struct Key: Hashable {
        let type: RecordType
        let id: String
    }

    private var staged: [Key: SourceRow] = [:]

    init(source: RecordSource, now: LocalDateTime, settings: RuleSettings, newId: @escaping () -> String) {
        base = source
        self.now = now
        today = now.date
        self.settings = settings
        idGenerator = newId
    }

    func newId() -> String { idGenerator() }

    /// Źródło bez zapisów tej operacji — do sprawdzeń użycia rekordów (także z kosza).
    var sourceForDeepChecks: RecordSource { base }

    func reject(_ problem: RuleProblem) -> RuleFailure { RuleFailure(problem: problem) }

    func invalid(_ field: String, _ message: String) -> RuleFailure {
        RuleFailure(problem: .validation(errors: [field: [message]]))
    }

    func notFound(_ what: String, _ id: String) -> RuleFailure {
        RuleFailure(problem: .notFound(what: what, id: id))
    }

    func conflict(_ reason: ConflictReason, _ message: String) -> RuleFailure {
        RuleFailure(problem: .conflict(reason: reason, message: message))
    }

    /// Odrzuca treść z błędami walidacji; ostrzeżenia zbiera do wyniku.
    func check(_ report: ValidationReport) throws {
        if report.hasErrors { throw RuleFailure(problem: .validation(errors: report.errors, warnings: report.warnings)) }
        for (field, messages) in report.warnings { for message in messages { warn(field, message) } }
    }

    func warn(_ field: String, _ message: String) {
        var list = warnings[field] ?? []
        if !list.contains(message) { list.append(message) }
        warnings[field] = list
    }

    func clean(_ text: String?) -> String? { HorseRules.clean(text) }

    // MARK: Odczyt (rekordy poza koszem, z uwzględnieniem zapisów tej operacji)

    func row(_ type: RecordType, _ id: String) throws -> SourceRow? {
        if let row = staged[Key(type: type, id: id)] { return row.isDeleted ? nil : row }
        guard let row = try base.get(type, id: id), !row.isDeleted else { return nil }
        return row
    }

    func find<R: LocalRecord>(_ type: RecordType, _ id: String, as _: R.Type = R.self) throws -> R? {
        try row(type, id)?.record as? R
    }

    func records(_ type: RecordType, horseId: String? = nil) throws -> [any LocalRecord] {
        try merged(base.query(type, horseId: horseId, from: nil, to: nil, includeDeleted: false), type: type, horseId: horseId, byOwner: nil).map(.record)
    }

    func ownerRecords(_ type: RecordType, _ ownerId: String) throws -> [any LocalRecord] {
        try merged(base.byOwner(type, ownerId: ownerId, includeDeleted: false), type: type, horseId: nil, byOwner: ownerId).map(.record)
    }

    func all<R: LocalRecord>(_ type: RecordType, as _: R.Type = R.self, horseId: String? = nil) throws -> [R] {
        try records(type, horseId: horseId).compactMap { $0 as? R }
    }

    func byOwner<R: LocalRecord>(_ type: RecordType, _ ownerId: String, as _: R.Type = R.self) throws -> [R] {
        try ownerRecords(type, ownerId).compactMap { $0 as? R }
    }

    private func merged(_ rows: [SourceRow], type: RecordType, horseId: String?, byOwner owner: String?) -> [SourceRow] {
        var result = rows.filter { staged[Key(type: type, id: $0.record.id)] == nil }
        for (key, row) in staged where key.type == type && !row.isDeleted {
            if let horseId, row.record.primaryHorseId != horseId, !row.record.horseIds.contains(horseId) { continue }
            if let owner, row.record.parentId != owner { continue }
            result.append(row)
        }
        return result.sorted { lhs, rhs in
            switch (lhs.dateKey, rhs.dateKey) {
            case let (left?, right?) where left != right: return left < right
            case (nil, .some): return true
            case (.some, nil): return false
            default: return lhs.record.id < rhs.record.id
            }
        }
    }

    func horse(_ id: String) throws -> LocalHorse? { try find(.horse, id) }
    func contact(_ id: String) throws -> LocalContact? { try find(.contact, id) }
    func dictionary(_ id: String) throws -> LocalDictionaryItem? { try find(.dictionary, id) }
    func competition(_ id: String) throws -> LocalCompetition? { try find(.competition, id) }

    // MARK: Zapis

    /// Dzień porządkujący rekord; start bez własnego dnia dziedziczy dzień rozpoczęcia zawodów.
    func dateKey(of record: any LocalRecord) throws -> LocalDate? {
        if let start = record as? LocalCompetitionStart, start.startDate == nil { return try competition(start.competitionId)?.dateFrom }
        return record.dateKey
    }

    /// Nowy rekord: wersja 1, znaczniki czasu z zegara.
    @discardableResult
    func insert<R: LocalRecord>(_ record: R, primary: Bool) throws -> R {
        let stamped = record.withAudit(version: 1, updatedAt: now).withCreated(at: now)
        try stage(stamped, primary: primary)
        effects.append(RecordEffect(type: stamped.recordType, id: stamped.id, kind: .created, primary: primary))
        return stamped
    }

    /// Zmiana rekordu: tryb samodzielny podnosi wersję.
    @discardableResult
    func replace<R: LocalRecord>(old: R, with record: R, primary: Bool) throws -> R {
        let updated = record.withAudit(version: old.version + 1, updatedAt: now)
        try stage(updated, primary: primary)
        effects.append(RecordEffect(type: updated.recordType, id: updated.id, kind: .updated, primary: primary))
        return updated
    }

    /// Zmiana skutkiem reguły (termin zamknięty, przełożony…): nie jest rekordem głównym; bez zmiany treści nic nie zapisuje.
    @discardableResult
    func replaceDerived<R: LocalRecord>(old: R, with record: R) throws -> R {
        old == record ? old : try replace(old: old, with: record, primary: false)
    }

    /// Rekord w koszu (partia usunięcia).
    func trash(_ record: any LocalRecord, batchId: String, primary: Bool) throws {
        let updated = record.withAudit(version: record.version + 1, updatedAt: now)
        let key = Key(type: updated.recordType, id: updated.id)
        let dateKey = try dateKey(of: updated)
        staged[key] = SourceRow(record: updated, dateKey: dateKey, isDeleted: true, deletionBatchId: batchId)
        writes.append(PlannedWrite(record: updated, dateKey: dateKey, deletedAt: now, deletionBatchId: batchId, primary: primary))
        effects.append(RecordEffect(type: updated.recordType, id: updated.id, kind: .trashed, primary: primary))
    }

    /// Rekord przywrócony z kosza.
    func untrash(_ record: any LocalRecord, primary: Bool) throws {
        let updated = record.withAudit(version: record.version + 1, updatedAt: now)
        try stage(updated, primary: primary)
        effects.append(RecordEffect(type: updated.recordType, id: updated.id, kind: .restored, primary: primary))
    }

    private func stage(_ record: any LocalRecord, primary: Bool) throws {
        let dateKey = try dateKey(of: record)
        staged[Key(type: record.recordType, id: record.id)] = SourceRow(record: record, dateKey: dateKey)
        writes.append(PlannedWrite(record: record, dateKey: dateKey, primary: primary))
    }

    func finish(_ record: (any LocalRecord)?, batchId: String? = nil) -> RuleOutcome {
        .saved(RuleSaved(record: record, writes: writes, effects: effects, warnings: warnings, batchId: batchId))
    }

}
