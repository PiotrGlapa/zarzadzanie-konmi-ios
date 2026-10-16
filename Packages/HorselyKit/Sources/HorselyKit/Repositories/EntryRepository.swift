import Foundation
import HorselyCore

/// Reguły Core czytają rekordy przez `RecordSource`; tu źródłem jest otwarta transakcja magazynu.
struct AccessRecordSource: RecordSource {
    let access: RecordAccess

    static func row(_ stored: StoredRecord) throws -> SourceRow {
        SourceRow(record: try stored.record(), dateKey: stored.dateKey, isDeleted: stored.isDeleted, deletionBatchId: stored.deletionBatchId)
    }

    func query(_ type: RecordType, horseId: String?, from: LocalDate?, to: LocalDate?, includeDeleted: Bool) throws -> [SourceRow] {
        try access.query(type, horseId: horseId, from: from, to: to, includeDeleted: includeDeleted).map(Self.row)
    }

    func get(_ type: RecordType, id: String) throws -> SourceRow? {
        try access.get(type, id: id).map(Self.row)
    }

    func byOwner(_ type: RecordType, ownerId: String, includeDeleted: Bool) throws -> [SourceRow] {
        try access.byOwner(type, ownerId: ownerId, includeDeleted: includeDeleted).map(Self.row)
    }

    func byBatch(_ batchId: String) throws -> [SourceRow] {
        try access.byBatch(batchId).map(Self.row)
    }
}

/// Jeden krok cofnięcia: wiersz sprzed zapisu (`nil` — rekord powstał w tym zapisie i przy cofnięciu znika).
public struct UndoStep: Sendable {
    let type: RecordType
    let id: String
    let previous: StoredRecord?
}

/// Cofnięcie całego zapisu (FR-SAM-06): przywraca wiersze sprzed operacji — nowy rekord znika, edytowany wraca do poprzedniej wersji,
/// przeniesiony do kosza wraca z kosza razem z zależnymi.
public struct EntryUndo: Sendable {
    let steps: [UndoStep]
}

/// Zapisany wpis: rekord główny (`nil` przy usunięciu), skutki reguł (np. zamknięty termin), ostrzeżenia i cofnięcie.
public struct EntrySaved: Sendable {
    public let record: (any LocalRecord)?
    public let effects: [RecordEffect]
    public let warnings: [String: [String]]
    public let batchId: String?
    public let undo: EntryUndo
}

public enum EntryResult: Sendable {
    case saved(EntrySaved)
    case rejected(RuleProblem)

    public var saved: EntrySaved? {
        if case let .saved(saved) = self { return saved }
        return nil
    }

    public var problem: RuleProblem? {
        if case let .rejected(problem) = self { return problem }
        return nil
    }
}

/// Wpisy w magazynie lokalnym (tryb samodzielny — telefon jest źródłem prawdy): zapis z regułami programu w jednej transakcji
/// (rekord + skutki + licznik zmian), widoki Pulpitu i osi czasu, słowniki i kontakty do list wyboru. Zapis w trybie online
/// (rekord `Pending` + operacja w kolejce) dochodzi w zadaniu T085.
public final class EntryRepository: Sendable {
    let store: RecordStore
    let dates: any DateProvider

    public init(store: RecordStore, dates: any DateProvider = SystemDateProvider()) {
        self.store = store
        self.dates = dates
    }

    // MARK: Zapis

    /// Wykonuje operację silnika reguł i, gdy ją przyjął, zapisuje wszystkie zmiany w jednej transakcji.
    public func perform(_ operation: @escaping @Sendable (RuleEngine) -> RuleOutcome) async throws -> EntryResult {
        let dates = self.dates
        return try await store.write { access in
            let engine = RuleEngine(source: AccessRecordSource(access: access), dates: dates)
            switch operation(engine) {
            case let .rejected(problem):
                return .rejected(problem)
            case let .saved(saved):
                var steps: [UndoStep] = []
                var rows: [StoredRecord] = []
                for write in saved.writes {
                    steps.append(UndoStep(type: write.record.recordType, id: write.record.id, previous: try access.get(write.record.recordType, id: write.record.id)))
                    rows.append(try StoredRecord.of(
                        write.record, syncState: .local, dateKey: write.dateKey, deletedAt: write.deletedAt, deletionBatchId: write.deletionBatchId
                    ))
                }
                try access.upsert(rows)
                return .saved(EntrySaved(record: saved.record, effects: saved.effects, warnings: saved.warnings, batchId: saved.batchId, undo: EntryUndo(steps: steps)))
            }
        }
    }

    /// Cofnięcie ostatniego zapisu („Cofnij” w komunikacie „Zapisano”).
    public func undo(_ undo: EntryUndo) async throws {
        try await store.write { access in
            for step in undo.steps.reversed() {
                if let previous = step.previous {
                    try access.upsert([previous])
                } else {
                    try access.deleteHard(step.type, id: step.id)
                }
            }
        }
    }

    /// Domyślne słowniki przy pierwszym uruchomieniu w trybie samodzielnym (nic nie robi, gdy słowniki już są).
    public func seedDictionariesIfNeeded() async throws {
        _ = try await perform { $0.seedDictionaries() }
    }

    public func delete(_ type: RecordType, id: String) async throws -> EntryResult {
        try await perform { $0.delete(type, id: id) }
    }

    // MARK: Odczyt

    func read<T: Sendable>(_ block: @escaping @Sendable (AccessRecordSource, LocalDate) throws -> T) async throws -> T {
        let today = dates.today()
        return try await store.read { access in try block(AccessRecordSource(access: access), today) }
    }

    public func dashboard() async throws -> Dashboard {
        try await read { source, today in try LocalViews(source: source).dashboard(today: today) }
    }

    public func timeline(_ filter: TimelineFilter) async throws -> Page<TimelineItem> {
        try await read { source, _ in try LocalViews(source: source).timeline(filter) }
    }

    /// Rekord poza koszem.
    public func record(_ type: RecordType, id: String) async throws -> (any LocalRecord)? {
        try await read { source, _ in try source.get(type, id: id).flatMap { $0.isDeleted ? nil : $0.record } }
    }

    /// Wartości słownika; domyślnie tylko aktywne (nowe wpisy), w kolejności `sortOrder`. Zapisany wpis może wskazywać pozycję
    /// nieaktywną — wtedy formularz dokłada ją osobno.
    public func dictionary(_ type: DictionaryType, includeInactive: Bool = false) async throws -> [LocalDictionaryItem] {
        try await read { source, _ in
            try source.records(.dictionary, as: LocalDictionaryItem.self)
                .filter { $0.dictionaryType == type && (includeInactive || $0.isActive) }
                .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
        }
    }

    /// Kontakty niezarchiwizowane (opcjonalnie danego typu), po nazwie.
    public func contacts(type: ContactType? = nil) async throws -> [LocalContact] {
        try await read { source, _ in
            try source.records(.contact, as: LocalContact.self)
                .filter { !$0.isArchived && (type == nil || $0.types.contains(type!)) }
                .sorted { PolishNames.compare($0.name, $1.name) == .orderedAscending }
        }
    }

    /// Wszystkie pozycje słowników (także nieaktywne — istniejące wpisy mogą na nie wskazywać).
    public func allDictionaryItems() async throws -> [LocalDictionaryItem] {
        try await read { source, _ in
            try source.records(.dictionary, as: LocalDictionaryItem.self).sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
        }
    }

    /// Wszystkie kontakty poza koszem (także zarchiwizowane — istniejące wpisy mogą na nie wskazywać), po nazwie.
    public func allContacts() async throws -> [LocalContact] {
        try await read { source, _ in
            try source.records(.contact, as: LocalContact.self).sorted { PolishNames.compare($0.name, $1.name) == .orderedAscending }
        }
    }

    /// Zawody poza koszem, najnowsze na początku.
    public func competitions() async throws -> [LocalCompetition] {
        try await read { source, _ in
            try source.records(.competition, as: LocalCompetition.self).sorted { ($0.dateFrom, $0.id) > ($1.dateFrom, $1.id) }
        }
    }

    /// „Dodaj kontakt” z formularza wpisu: nowy kontakt o jednym typie. Nazwa wymagana, do 200 znaków (reguły kontaktów
    /// z fazy US8 zastąpią ten skrót pełnym formularzem).
    public func addContact(name: String, type: ContactType) async throws -> LocalContact? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return nil }
        let now = dates.now()
        let contact = LocalContact(id: UUID().uuidString.lowercased(), createdAt: now, updatedAt: now, version: 1, name: trimmed, types: [type])
        try await store.upsert([try StoredRecord.of(contact, syncState: .local)])
        return contact
    }

    /// Konie ostatnio używane we wpisach (najnowsze na początku) — wybór konia w „+”.
    public func recentHorseIds(limit: Int = 8) async throws -> [String] {
        try await read { source, _ in
            let page = try LocalViews(source: source).timeline(TimelineFilter(page: 1, pageSize: 60))
            var seen: [String] = []
            for item in page.items {
                if let id = item.horseId, !seen.contains(id) { seen.append(id) }
                if seen.count == limit { break }
            }
            return seen
        }
    }

    /// Rekordy rodzaju (poza koszem), opcjonalnie dla konia — zakładki karty konia i listy.
    public func records<R: LocalRecord>(_ type: RecordType, as _: R.Type = R.self, horseId: String? = nil) async throws -> [R] {
        try await read { source, _ in try source.records(type, as: R.self, horseId: horseId) }
    }
}
