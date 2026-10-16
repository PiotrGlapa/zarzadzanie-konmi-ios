import Foundation

/// Stany operacji kolejki (data-model.md §4). `sent` jest przejściowy — operacja trafia do historii i znika z kolejki,
/// gdy nie zależy od niej żadna niewysłana.
public enum OutboxState: String, Codable, Sendable, CaseIterable {
    case pending = "Pending"
    case sending = "Sending"
    case unknown = "Unknown"
    case sent = "Sent"
    case needsFix = "NeedsFix"
    case alreadyHandled = "AlreadyHandled"
    case held = "Held"
    /// Wysyłka wykryła konflikt zmiany z programem: operacja czeka na decyzję, zależne czekają razem z nią.
    case conflict = "Conflict"

    /// Czeka na wysłanie albo wymaga uwagi — liczy się w liczniku „niewysłane”.
    public var isUnsent: Bool { self != .sent && self != .alreadyHandled }

    /// Edycja i usunięcie operacji (FR-M-SYN-12); `sending`, `unknown` i `conflict` blokują edycję. Łączenie — tylko te stany.
    public var isEditable: Bool { self == .pending || self == .needsFix || self == .held }

    public static let editable: Set<OutboxState> = [.pending, .needsFix, .held]
}

/// Rodzaje operacji (contracts/android/outbox-operations.md i mode-and-sync.md §3). `path` względem `/api/v1/`; `{…}` — wartość
/// z treści operacji. Zmiany i usunięcia obejmują wszystkie rodzaje rekordów — rodzaj niesie `OutboxOperation.recordType`.
public enum OperationKind: String, Codable, Sendable, CaseIterable {
    case createVetVisit = "CreateVetVisit"
    case createFarrierVisit = "CreateFarrierVisit"
    case createPhysioVisit = "CreatePhysioVisit"
    case createSpecialistVisit = "CreateSpecialistVisit"
    case createCompetition = "CreateCompetition"
    case createCompetitionStart = "CreateCompetitionStart"
    case createPurchase = "CreatePurchase"
    case createNote = "CreateNote"
    case createTraining = "CreateTraining"
    case createReminder = "CreateReminder"
    case createContact = "CreateContact"
    case createAttachment = "CreateAttachment"
    case completeReminder = "CompleteReminder"
    case dismissReminder = "DismissReminder"
    case createHorse = "CreateHorse"
    /// `PUT` rekordu dowolnego rodzaju z `If-Match: "<baseVersion>"`.
    case updateRecord = "UpdateRecord"
    /// „Przełóż” termin: `PUT /reminders/{id}`.
    case rescheduleReminder = "RescheduleReminder"
    /// `DELETE` rekordu dowolnego rodzaju (do kosza programu) po sprawdzeniu wersji.
    case deleteRecord = "DeleteRecord"

    public var path: String {
        switch self {
        case .createVetVisit: "vet-visits"
        case .createFarrierVisit: "farrier-visits"
        case .createPhysioVisit: "physio-visits"
        case .createSpecialistVisit: "specialist-visits"
        case .createCompetition: "competitions"
        case .createCompetitionStart: "competitions/{competitionId}/starts"
        case .createPurchase: "purchases"
        case .createNote: "notes"
        case .createTraining: "trainings"
        case .createReminder: "reminders"
        case .createContact: "contacts"
        case .createAttachment: "attachments"
        case .completeReminder: "reminders/{id}/complete"
        case .dismissReminder: "reminders/{id}/dismiss"
        case .createHorse: "horses"
        case .updateRecord, .deleteRecord: ""
        case .rescheduleReminder: "reminders/{id}"
        }
    }

    public var isCreate: Bool { rawValue.hasPrefix("Create") }
    public var isReminderAction: Bool { self == .completeReminder || self == .dismissReminder }
    public var isUpdate: Bool { self == .updateRecord || self == .rescheduleReminder }
    public var isDelete: Bool { self == .deleteRecord }
    /// Zmiana albo usunięcie rekordu z programu — wykrywa konflikty.
    public var isChange: Bool { isUpdate || isDelete }
    /// Operacje wysyłające plik — „tylko przez Wi‑Fi” w sieci z limitem (FR-M-UST-03).
    public var sendsFile: Bool { self == .createAttachment }

    /// Rodzaj tworzenia dla rodzaju rekordu (np. ponowne utworzenie po „Zachowaj moją” dla usuniętego rekordu).
    public static func create(for type: RecordType) -> OperationKind? {
        switch type {
        case .horse: .createHorse
        case .contact: .createContact
        case .vetVisit: .createVetVisit
        case .farrierVisit: .createFarrierVisit
        case .physioVisit: .createPhysioVisit
        case .specialistVisit: .createSpecialistVisit
        case .competition: .createCompetition
        case .competitionStart: .createCompetitionStart
        case .purchase: .createPurchase
        case .note: .createNote
        case .training: .createTraining
        case .reminder: .createReminder
        case .attachment: .createAttachment
        case .dictionary: nil
        }
    }

    /// Nazwa do listy kolejki (bez treści wpisu).
    public var label: String {
        switch self {
        case .createVetVisit: "Wizyta weterynaryjna"
        case .createFarrierVisit: "Wizyta kowala"
        case .createPhysioVisit: "Fizjoterapia"
        case .createSpecialistVisit: "Wizyta specjalisty"
        case .createCompetition: "Zawody"
        case .createCompetitionStart: "Start w zawodach"
        case .createPurchase: "Zakup"
        case .createNote: "Notatka"
        case .createTraining: "Trening"
        case .createReminder: "Termin"
        case .createContact: "Kontakt"
        case .createAttachment: "Załącznik"
        case .completeReminder: "Zrealizowany termin"
        case .dismissReminder: "Odrzucony termin"
        case .createHorse: "Koń"
        case .updateRecord: "Zmiana"
        case .rescheduleReminder: "Przełożony termin"
        case .deleteRecord: "Usunięcie"
        }
    }
}

/// Koń, którego dotyczy operacja — rozpoznanie „tej samej stajni” po ponownym parowaniu (FR-M-POL-08).
public struct HorseRef: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let passportNumber: String?

    public init(id: String, name: String, passportNumber: String?) {
        self.id = id
        self.name = name
        self.passportNumber = passportNumber
    }

    public init(_ horse: LocalHorse) {
        self.init(id: horse.id, name: horse.name, passportNumber: horse.passportNumber)
    }

    /// Klucz zgodności: `id`, imię i numer paszportu (pusty = brak).
    var identity: String {
        let passport = passportNumber.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "\u{0}"
        return "\(id)\u{1}\(name)\u{1}\(passport)"
    }
}

/// Operacja kolejki (`queue_operation`). `payload` — treść żądania (z odwołaniami do rekordów tworzonych w kolejce), `summary`
/// — opis **bez treści wpisu** („Notatka · Grom · 05.10.2026”), `localRef` — identyfikator tworzonego rekordu, którym posługują się
/// operacje zależne (`id` rekordu nadane w telefonie). `resultId` — `id` rekordu utworzonego w programie.
///
/// - `recordType`/`recordId`: rekord w telefonie (dla tworzenia `recordId == localRef`)
/// - `baseVersion`: wersja z programu, od której zaczęła się zmiana — `If-Match` i wykrywanie konfliktów
/// - `countBefore`: licznik przed wysyłką (FR-M-SYN-06); `nil` — wysłano z `Idempotency-Key`
public struct OutboxOperation: Hashable, Sendable, Identifiable {
    public var id: String
    public var sequence: Int64
    public var kind: OperationKind
    public var localRef: String
    public var payload: JSONValue
    public var dependsOn: [String]
    public var horseRefs: [HorseRef]
    public var summary: String
    public var state: OutboxState
    public var countBefore: Int?
    public var attempts: Int
    public var nextAttemptAt: Date?
    public var problem: ApiProblem?
    public var resultId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var recordType: RecordType?
    public var recordId: String?
    public var baseVersion: Int?

    public init(
        id: String, sequence: Int64 = 0, kind: OperationKind, localRef: String, payload: JSONValue, dependsOn: [String] = [],
        horseRefs: [HorseRef] = [], summary: String, state: OutboxState = .pending, countBefore: Int? = nil, attempts: Int = 0,
        nextAttemptAt: Date? = nil, problem: ApiProblem? = nil, resultId: String? = nil, createdAt: Date, updatedAt: Date,
        recordType: RecordType? = nil, recordId: String? = nil, baseVersion: Int? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.kind = kind
        self.localRef = localRef
        self.payload = payload
        self.dependsOn = dependsOn
        self.horseRefs = horseRefs
        self.summary = summary
        self.state = state
        self.countBefore = countBefore
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
        self.problem = problem
        self.resultId = resultId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordType = recordType
        self.recordId = recordId
        self.baseVersion = baseVersion
    }

    /// Pole tekstowe treści (np. `id` terminu, `competitionId` startu).
    public func text(_ key: String) -> String? { payload[key]?.stringValue }

    /// Czy operacja dotyczy tego samego rekordu co `other`.
    public func sameRecord(as other: OutboxOperation) -> Bool {
        recordType != nil && recordId != nil && recordType == other.recordType && recordId == other.recordId
    }
}

/// Plik operacji `CreateAttachment` — kopia w kontenerze App Group (nigdy nie czyszczona przez LRU).
public struct OutboxFile: Hashable, Sendable {
    public static let maxSizeBytes: Int64 = 100 * 1024 * 1024

    public let operationId: String
    public let path: String
    public let fileName: String
    public let contentType: String
    public let sizeBytes: Int64
    public let sha256: String
    public let description: String?

    public init(operationId: String, path: String, fileName: String, contentType: String, sizeBytes: Int64, sha256: String, description: String? = nil) {
        self.operationId = operationId
        self.path = path
        self.fileName = fileName
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.description = description
    }
}

public enum HistoryOutcome: String, Codable, Sendable {
    case sent = "Sent"
    case alreadyHandled = "AlreadyHandled"
    case conflictResolved = "ConflictResolved"
    case deleted = "Deleted"
}

/// Wpis historii kolejki (30 dni, FR-M-SYN-13) — bez treści wpisu.
public struct QueueHistoryEntry: Hashable, Sendable {
    public let operationId: String
    public let kind: OperationKind
    public let summary: String
    public let outcome: HistoryOutcome
    public let at: Date

    public init(operationId: String, kind: OperationKind, summary: String, outcome: HistoryOutcome, at: Date) {
        self.operationId = operationId
        self.kind = kind
        self.summary = summary
        self.outcome = outcome
        self.at = at
    }
}

/// Odstęp ponowienia po `attempts`-tej nieudanej próbie: 15 s → 30 s → 1 min → … maks. 30 min, bez limitu prób (FR-M-SYN-05).
public enum RetryPolicy {
    public static func delay(afterAttempts attempts: Int) -> TimeInterval {
        let shift = min(max(attempts - 1, 0), 20)
        return TimeInterval(min(15 << shift, 30 * 60))
    }
}
