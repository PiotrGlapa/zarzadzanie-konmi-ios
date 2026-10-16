import Foundation

/// Metadane wiersza magazynu bez treści — uzgadnianie pełnego pobrania bez dekodowania 50 000 rekordów.
public struct RecordMeta: Sendable, Equatable {
    public let version: Int
    public let syncState: SyncState
    public let baseVersion: Int?
    public let deleted: Bool

    public init(version: Int, syncState: SyncState, baseVersion: Int?, deleted: Bool) {
        self.version = version
        self.syncState = syncState
        self.baseVersion = baseVersion
        self.deleted = deleted
    }
}

/// Rekord, którego dotyczy wynik uzgadniania.
public struct RecordRef: Hashable, Sendable {
    public let type: RecordType
    public let id: String

    public init(type: RecordType, id: String) {
        self.type = type
        self.id = id
    }
}

/// Podsumowanie pobrania.
public struct MergeResult: Equatable, Sendable {
    public var inserted = 0
    public var replaced = 0
    public var unchanged = 0
    /// Lokalna zmiana czeka na wysłanie — rekord zostaje (rozstrzygnie wysyłka).
    public var keptPending = 0
    /// `Synced` nieobecne w eksporcie (albo z `trashed`/`purged`) — usunięte lokalnie razem z plikami.
    public var removed: [RecordRef] = []
    /// Zmiana czekająca na wysłanie, a rekordu nie ma już w programie — konflikt „zmiana–usunięcie”.
    public var editDeleteConflicts: [RecordRef] = []

    public init() {}

    public static func + (lhs: MergeResult, rhs: MergeResult) -> MergeResult {
        var result = lhs
        result.inserted += rhs.inserted
        result.replaced += rhs.replaced
        result.unchanged += rhs.unchanged
        result.keptPending += rhs.keptPending
        result.removed += rhs.removed
        result.editDeleteConflicts += rhs.editDeleteConflicts
        return result
    }
}

/// Uzgadnianie rekordów z programu z magazynem (contracts/android/mode-and-sync.md §2, `SyncMerger.kt`):
///
/// | Lokalnie | Wynik |
/// |---|---|
/// | brak | wstaw jako `Synced` |
/// | `Synced` (inna wersja) | zastąp |
/// | `Pending`/`Conflict` z operacją w kolejce | bez zmian — moja zmiana czeka |
/// | `Pending`/`Conflict` bez operacji (osierocony) | zastąp rekordem z programu |
/// | `Synced` nieobecny w eksporcie | usuń lokalnie |
/// | `Pending` z wersją bazową nieobecny w eksporcie | konflikt `EditDelete` |
/// | `Pending` nowy (bez wersji bazowej) | bez zmian |
/// | `Projected` | usunięte przed uzgadnianiem |
///
/// Funkcje są czyste: magazyn (`HorselyKit`) czyta świeże metadane w transakcji zapisu i wykonuje decyzje.
public enum SyncMerger {
    public enum Incoming: Equatable, Sendable {
        case insert
        case replace
        case unchanged
        case keepPending
    }

    public enum Absent: Equatable, Sendable {
        case remove
        case editDeleteConflict
        case keep
    }

    /// Rekord z programu (`version`) wobec wiersza lokalnego.
    /// - Parameter hasOperation: czy rekord ma niewysłaną operację kolejki; `nil` — nie wiadomo (każdy `Pending` ma operację).
    public static func incoming(version: Int, local: RecordMeta?, hasOperation: Bool?) -> Incoming {
        guard let local else { return .insert }
        if local.syncState.isUnsent && (hasOperation ?? true) { return .keepPending }
        if version > 0 && local.version == version && local.syncState == .synced && !local.deleted { return .unchanged }
        return .replace
    }

    /// Rekord, którego program już nie ma (nieobecny w pełnym eksporcie albo w `trashed[]`/`purged[]`).
    public static func absent(local: RecordMeta, hasOperation: Bool?) -> Absent {
        let operation = hasOperation ?? true
        if local.syncState == .synced || local.syncState == .local { return .remove }
        if local.syncState.isUnsent && !operation { return .remove }
        if local.syncState.isUnsent && local.baseVersion != nil { return .editDeleteConflict }
        return .keep
    }
}

/// Klucze `local_meta` stanu współpracy z programem 2.0.0 — kasowane razem przy rozłączeniu, ponownym parowaniu i przejściu
/// w tryb samodzielny.
public enum SyncMetaKey {
    /// Możliwości programu z ostatniego `GET /system/info` (nazwy rozdzielone przecinkami).
    public static let capabilities = "program.capabilities"
    /// Wersja programu z ostatniego `GET /system/info`.
    public static let programVersion = "program.version"
    /// Stempel danych odczytany przed ostatnim **udanym** pobraniem.
    public static let dataStamp = "sync.dataStamp"
    /// `scope.nextUpdatedSince` z ostatniego udanego pobrania (napis programu, bez zmian).
    public static let nextUpdatedSince = "sync.nextUpdatedSince"
    /// Chwila ostatniego udanego **pełnego** pobrania (ISO 8601, zegar telefonu).
    public static let lastFullAt = "sync.lastFullAt"
    /// Chwila ostatniego udanego pobrania (pełnego albo zmian) — podtytuł „Dane z …”.
    public static let lastSyncAt = "sync.lastSyncAt"
    /// `true` — następne pobranie ma być pełne.
    public static let forceFull = "sync.forceFull"
    /// Program bez wersji rekordów — tryb zgodności 1.x (FR-SYN2-09).
    public static let unversioned = "sync.unversioned"

    public static let all = [capabilities, programVersion, dataStamp, nextUpdatedSince, lastFullAt, lastSyncAt, forceFull, unversioned]
}

/// Co zrobi odświeżenie (contracts/android/program-2.0-integration.md §3).
public enum RefreshKind: Equatable, Sendable {
    /// Stempel danych bez zmian, kolejka pusta — koniec bez `/export`.
    case upToDate
    /// `GET /export?scope=full&updatedSince=<since>`.
    case incremental(since: String)
    /// `GET /export?scope=full`.
    case full
}

/// Zapamiętany stan pobierania (`local_meta`).
public struct SyncMetaState: Equatable, Sendable {
    public var dataStamp: String?
    public var nextUpdatedSince: String?
    public var lastFullAt: Date?
    public var forceFull: Bool

    public init(dataStamp: String? = nil, nextUpdatedSince: String? = nil, lastFullAt: Date? = nil, forceFull: Bool = false) {
        self.dataStamp = dataStamp
        self.nextUpdatedSince = nextUpdatedSince
        self.lastFullAt = lastFullAt
        self.forceFull = forceFull
    }
}

/// Wybór planu odświeżenia (`ProgramSync.plan`): stempel, pobieranie zmian, pełne raz na dobę w tle.
public enum RefreshPlan {
    /// Pełne pobranie w tle co najmniej raz na dobę (clarification 2026-10-15).
    public static let fullInterval: TimeInterval = 24 * 60 * 60
    /// Punkt pełnego eksportu bez `nextUpdatedSince`: chwila odczytu programu cofnięta o minutę (zegar programu).
    public static let nextPointMargin: TimeInterval = 60

    public static func plan(capabilities: ProgramCapabilities, stamp: String?, state: SyncMetaState, background: Bool, queueEmpty: Bool, now: Date) -> RefreshKind {
        let dailyDue = background && (state.lastFullAt.map { now.timeIntervalSince($0) >= fullInterval } ?? true)
        let knownStamp = capabilities.dataStamp ? stamp : nil
        if let knownStamp, knownStamp == state.dataStamp, !state.forceFull, !dailyDue, queueEmpty { return .upToDate }
        if capabilities.updatedSince, let since = state.nextUpdatedSince, !state.forceFull, !dailyDue { return .incremental(since: since) }
        return .full
    }

    /// Punkt następnego pobrania zmian: `scope.nextUpdatedSince` od programu; pełny eksport go nie niesie — wtedy `exportedAt`
    /// cofnięte o minutę.
    public static func nextPoint(header: ExportHeader) -> String? {
        if let next = header.scope.nextUpdatedSince { return next }
        guard let exportedAt = header.exportedAt, let moment = parseInstant(exportedAt) else { return nil }
        return formatInstant(moment.addingTimeInterval(-nextPointMargin))
    }

    /// Czy odpowiedź na żądanie zmian jest w istocie pełna (`fullRequired`).
    public static func isIncremental(requested: Bool, header: ExportHeader) -> Bool {
        requested && header.scope.fullRequired != true
    }

    public static func parseInstant(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    public static func formatInstant(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
