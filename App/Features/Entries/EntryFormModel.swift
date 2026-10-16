import Foundation
import HorselyCore
import HorselyKit
import Observation

/// Stan formularza wpisu (nowy i edycja): pola, opcje list wyboru, błędy z reguł programu przy polach, podpowiedzi (kowal, kwota
/// zakupu, trening) i zapis przez `EntryRepository` w jednej transakcji.
@MainActor
@Observable
final class EntryFormModel {
    let kind: FormKind
    /// Edytowany rekord; `nil` — nowy wpis.
    let editing: (any LocalRecord)?

    var draft: EntryDraft
    var errors: [String: [String]] = [:]
    var warnings: [String: [String]] = [:]
    var failure: String?
    var isSaving = false
    var showMore = false

    private(set) var dictionaries: [LocalDictionaryItem] = []
    private(set) var contacts: [LocalContact] = []
    private(set) var competitions: [LocalCompetition] = []
    private(set) var isLoaded = false

    var amountSuggestion = AmountSuggestion()
    @ObservationIgnored private var editedTraining: Set<SuggestedField> = []
    @ObservationIgnored private var nextVisitEdited = false
    @ObservationIgnored private var baseline: EntryDraft

    var isEditing: Bool { editing != nil }
    var isDirty: Bool { draft != baseline }

    init(kind: FormKind, editing: (any LocalRecord)? = nil, horseId: String? = nil, today: LocalDate, now: LocalDateTime) {
        self.kind = kind
        self.editing = editing
        var draft = Self.draft(for: kind, editing: editing)
        if editing == nil {
            draft.horseId = horseId
            if kind != .competition { draft.date = today }
            if kind == .competition { draft.dateFrom = today }
            draft.hour = now.hour
            draft.minute = now.minute
            if kind == .start { draft.startDate = nil }
        }
        self.draft = draft
        self.baseline = draft
        self.nextVisitEdited = editing != nil
    }

    private static func draft(for kind: FormKind, editing record: (any LocalRecord)?) -> EntryDraft {
        switch record {
        case let record as LocalVetVisit: EntryDraft(vet: record)
        case let record as LocalFarrierVisit: EntryDraft(farrier: record)
        case let record as LocalPhysioVisit: EntryDraft(physio: record)
        case let record as LocalSpecialistVisit: EntryDraft(specialist: record)
        case let record as LocalNote: EntryDraft(note: record)
        case let record as LocalPurchase: EntryDraft(purchase: record)
        case let record as LocalTraining: EntryDraft(training: record)
        case let record as LocalCompetition: EntryDraft(competition: record)
        case let record as LocalCompetitionStart: EntryDraft(start: record)
        default: EntryDraft()
        }
    }

    /// Nowy zakup z danych poprzedniego („Powtórz zakup”): dzisiejsza data, reszta jak w oryginale.
    static func repeating(_ purchase: LocalPurchase, today: LocalDate, now: LocalDateTime) -> EntryFormModel {
        let model = EntryFormModel(kind: .purchase, today: today, now: now)
        var draft = EntryDraft(purchase: purchase)
        draft.date = today
        model.draft = draft
        model.baseline = EntryDraft()
        return model
    }

    // MARK: Opcje list wyboru

    func load(using environment: AppEnvironment) async {
        await environment.prepareStore()
        dictionaries = (try? await environment.entries.allDictionaryItems()) ?? []
        contacts = (try? await environment.entries.allContacts()) ?? []
        if kind == .start { competitions = (try? await environment.entries.competitions()) ?? [] }
        isLoaded = true
        if kind == .start, !isEditing, competitions.isEmpty {
            draft.newCompetition = true
            baseline.newCompetition = true
        }
        if !isEditing {
            await applyTrainingDefaults(using: environment)
            applyFarrierSuggestion(horses: environment.horseDirectory.horses)
        }
    }

    func items(_ type: DictionaryType) -> [LocalDictionaryItem] {
        dictionaries.filter { $0.dictionaryType == type }
    }

    func item(_ id: String?) -> LocalDictionaryItem? {
        id.flatMap { id in dictionaries.first { $0.id == id } }
    }

    func contact(_ id: String?) -> LocalContact? {
        id.flatMap { id in contacts.first { $0.id == id } }
    }

    private func systemKey(_ id: String?) -> String? { item(id)?.systemKey }

    var isVaccination: Bool { systemKey(draft.visitTypeId) == DefaultDictionaries.vetVaccination }
    var isJumping: Bool { systemKey(draft.trainingTypeId) == DefaultDictionaries.trainingJumping }

    // MARK: Widoczność pól

    func isVisible(_ slot: FormSlot) -> Bool {
        switch slot.field {
        case .horse:
            // Kowal: jeden wiersz z przełącznikiem „Kilka koni” (wybór jednego albo wielu koni jest w nim).
            return kind != .purchase || draft.assignment == .singleHorse
        case .horses:
            return kind == .purchase && draft.assignment == .multipleHorses
        case .obstacleHeight:
            return isJumping
        case .vaccineOrProduct, .batchNumber:
            return showMore || isVaccination
        case .nextVisitDate where kind == .vet, .nextVisitPurpose where kind == .vet:
            return showMore || draft.nextVisitDate != nil
        default:
            return !slot.more || showMore
        }
    }

    var hasMoreFields: Bool {
        FormSpec.sections(for: kind).contains { section in section.slots.contains { $0.more && $0.field != .obstacleHeight } }
    }

    // MARK: Błędy

    func errors(for field: FormField) -> [String] {
        field.errorKeys.flatMap { errors[$0] ?? [] }
    }

    func warnings(for field: FormField) -> [String] {
        field.errorKeys.flatMap { warnings[$0] ?? [] }
    }

    var firstErrorField: FormField? {
        FormSpec.sections(for: kind).flatMap(\.slots).map(\.field).first { !errors(for: $0).isEmpty }
    }

    /// Błędy, których żadne pole formularza nie pokazuje (np. klucz spoza układu) — wyświetlane na dole.
    private func unmatchedErrors() -> [String] {
        let shown = Set(FormSpec.sections(for: kind).flatMap(\.slots).flatMap { $0.field.errorKeys })
        return errors.filter { entry in !shown.contains(entry.key) && !entry.key.hasPrefix("medications[") }.flatMap { $0.value }.sorted()
    }

    func medicationErrors(at index: Int) -> [String] {
        errors.filter { $0.key.hasPrefix("medications[\(index)].") }.flatMap { $0.value }
    }

    // MARK: Podpowiedzi

    /// Wpisy zmienione ręcznie nie są nadpisywane podpowiedzią (FR-M-TRN-03).
    func markTrainingEdited(_ field: SuggestedField) { editedTraining.insert(field) }

    func markNextVisitEdited() { nextVisitEdited = true }

    func horseChanged(using environment: AppEnvironment) async {
        await applyTrainingDefaults(using: environment)
        applyFarrierSuggestion(horses: environment.horseDirectory.horses)
    }

    private func applyTrainingDefaults(using environment: AppEnvironment) async {
        guard kind == .training, !isEditing, let horseId = draft.horseId else { return }
        guard let defaults = try? await environment.trainings.defaults(horseId: horseId) else { return }
        let current = TrainingDefaults(
            trainerContactId: draft.trainerId, riderContactId: draft.riderId, cost: nil, originalAmount: nil, originalCurrency: nil
        )
        let merged = TrainingSuggestions.apply(current: current, defaults: defaults, edited: editedTraining)
        draft.trainerId = merged.trainerContactId
        draft.riderId = merged.riderContactId
        if !editedTraining.contains(.cost) {
            draft.cost = MoneyInput.format(merged.cost)
            draft.originalAmount = MoneyInput.format(merged.originalAmount)
            draft.originalCurrency = merged.originalCurrency ?? ""
        }
        baseline.trainerId = draft.trainerId
        baseline.riderId = draft.riderId
        baseline.cost = draft.cost
        baseline.originalAmount = draft.originalAmount
        baseline.originalCurrency = draft.originalCurrency
    }

    /// Następna wizyta kowala: data wizyty plus interwał konia (bez połączenia z programem — jak w trybie samodzielnym).
    func applyFarrierSuggestion(horses: [LocalHorse]) {
        guard kind == .farrier, !nextVisitEdited, let date = draft.date else { return }
        let weeks = draft.manyHorses ? nil : horses.first { $0.id == draft.horseId }?.farrierIntervalWeeks
        let suggested = FarrierNextDate.suggest(visitDate: date, intervalWeeks: weeks)
        draft.nextVisitDate = suggested
        baseline.nextVisitDate = suggested
    }

    /// Kwota zakupu z ilości × ceny, dopóki użytkownik nie zmienił jej ręcznie.
    func updateAmountSuggestion() {
        guard kind == .purchase else { return }
        draft.amount = amountSuggestion.apply(current: draft.amount, quantity: draft.quantity, unitPrice: draft.unitPrice)
    }

    func amountEditedManually() { amountSuggestion.onManualEdit() }

    /// „Razem” = kwota + dostawa.
    var purchaseTotal: String {
        guard case let .valid(amount) = MoneyInput.parse(draft.amount) else { return Formats.dash }
        let delivery: Money
        switch MoneyInput.parse(draft.deliveryCost) {
        case let .valid(value): delivery = value
        case .empty: delivery = .zero
        case .invalid: return Formats.dash
        }
        return Formats.money(PurchaseAmount.total(amount: amount, delivery: delivery))
    }

    // MARK: Kontakty

    func addContact(name: String, type: ContactType, using environment: AppEnvironment) async -> String? {
        guard let contact = try? await environment.entries.addContact(name: name, type: type) else { return nil }
        contacts = (try? await environment.entries.allContacts()) ?? contacts + [contact]
        return contact.id
    }

    // MARK: Zapis

    /// `true`, gdy trzeba zapytać o kontuzję („Koń jest kontuzjowany. Zapisać trening?”).
    func needsInjuryConfirmation(horses: [LocalHorse]) -> Bool {
        guard kind == .training, let id = draft.horseId else { return false }
        return horses.first { $0.id == id }?.status == .injured
    }

    /// Zapisuje wpis. Zwraca zapis (z możliwością cofnięcia) albo `nil`, gdy reguły odrzuciły treść — wtedy `errors` / `failure`
    /// opisują powód, a dane w formularzu zostają.
    func save(using environment: AppEnvironment) async -> EntrySaved? {
        guard !isSaving else { return nil }
        isSaving = true
        errors = [:]
        warnings = [:]
        failure = nil
        defer { isSaving = false }
        do {
            return try await perform(using: environment)
        } catch {
            failure = error.localizedDescription
            return nil
        }
    }

    private func perform(using environment: AppEnvironment) async throws -> EntrySaved? {
        let entries = environment.entries
        let editing = self.editing
        let id = editing?.id
        let version = editing?.version ?? 0

        func run(_ built: [String: [String]], _ operation: @escaping @Sendable (RuleEngine) -> RuleOutcome) async throws -> EntrySaved? {
            if !built.isEmpty {
                apply(.validation(errors: built, warnings: [:]))
                return nil
            }
            let result = try await entries.perform(operation)
            switch result {
            case let .saved(saved):
                warnings = saved.warnings
                return saved
            case let .rejected(problem):
                apply(problem)
                return nil
            }
        }

        switch kind {
        case .vet:
            let built = draft.vetInput()
            let input = built.input
            return try await run(built.parseErrors) { id == nil ? $0.createVetVisit(input) : $0.updateVetVisit(id: id!, input, expectedVersion: version) }
        case .farrier:
            if draft.manyHorses, id == nil { return try await saveFarrierForMany(using: environment) }
            let built = draft.farrierInput()
            let input = built.input
            return try await run(built.parseErrors) { id == nil ? $0.createFarrierVisit(input) : $0.updateFarrierVisit(id: id!, input, expectedVersion: version) }
        case .physio:
            let built = draft.physioInput()
            let input = built.input
            return try await run(built.parseErrors) { id == nil ? $0.createPhysioVisit(input) : $0.updatePhysioVisit(id: id!, input, expectedVersion: version) }
        case .specialist:
            let built = draft.specialistInput()
            let input = built.input
            return try await run(built.parseErrors) { id == nil ? $0.createSpecialistVisit(input) : $0.updateSpecialistVisit(id: id!, input, expectedVersion: version) }
        case .note:
            let built = draft.noteInput()
            let input = built.input
            return try await run(built.parseErrors) { id == nil ? $0.createNote(input) : $0.updateNote(id: id!, input, expectedVersion: version) }
        case .purchase:
            let built = draft.purchaseInput()
            let input = built.input
            return try await run(built.parseErrors) { id == nil ? $0.createPurchase(input) : $0.updatePurchase(id: id!, input, expectedVersion: version) }
        case .training:
            let built = draft.trainingInput(isJumping: isJumping)
            let input = built.input
            return try await run(built.parseErrors) { id == nil ? $0.createTraining(input) : $0.updateTraining(id: id!, input, expectedVersion: version) }
        case .competition:
            let built = draft.competitionInput()
            let input = built.input
            return try await run(built.parseErrors) { id == nil ? $0.createCompetition(input) : $0.updateCompetition(id: id!, input, expectedVersion: version) }
        case .start:
            return try await saveStart(using: environment)
        }
    }

    /// Kowal „Kilka koni”: osobny wpis dla każdego zaznaczonego konia; gdy któryś zostanie odrzucony, poprzednie zapisy są cofane.
    private func saveFarrierForMany(using environment: AppEnvironment) async throws -> EntrySaved? {
        let entries = environment.entries
        guard !draft.horseIds.isEmpty else {
            apply(.validation(errors: ["horseIds": [Messages.required]], warnings: [:]))
            return nil
        }
        var saved: [EntrySaved] = []
        for horse in draft.horseIds {
            let built = draft.farrierInput(horseId: horse)
            if !built.parseErrors.isEmpty {
                apply(.validation(errors: built.parseErrors, warnings: [:]))
                try await undo(saved, entries)
                return nil
            }
            let input = built.input
            switch try await entries.perform({ $0.createFarrierVisit(input) }) {
            case let .saved(result): saved.append(result)
            case let .rejected(problem):
                apply(problem)
                try await undo(saved, entries)
                return nil
            }
        }
        guard let first = saved.first else { return nil }
        return EntrySaved(record: first.record, effects: saved.flatMap(\.effects), warnings: first.warnings, batchId: nil, undo: .combine(saved.map(\.undo)))
    }

    private func undo(_ saved: [EntrySaved], _ entries: EntryRepository) async throws {
        for item in saved.reversed() { try await entries.undo(item.undo) }
    }

    /// Start w zawodach: istniejące zawody albo nowe tworzone razem ze startem (cofnięcie usuwa oba).
    private func saveStart(using environment: AppEnvironment) async throws -> EntrySaved? {
        let entries = environment.entries
        let built = draft.startInput()
        if !built.parseErrors.isEmpty {
            apply(.validation(errors: built.parseErrors, warnings: [:]))
            return nil
        }
        let input = built.input
        if let editing = editing as? LocalCompetitionStart {
            let id = editing.id
            let version = editing.version
            switch try await entries.perform({ $0.updateCompetitionStart(id: id, input, expectedVersion: version) }) {
            case let .saved(saved): warnings = saved.warnings; return saved
            case let .rejected(problem): apply(problem); return nil
            }
        }
        var created: EntrySaved?
        var competitionId = draft.competitionId
        if draft.newCompetition {
            let competition = draft.inlineCompetitionInput()
            let competitionInput = competition.input
            switch try await entries.perform({ $0.createCompetition(competitionInput) }) {
            case let .saved(saved):
                created = saved
                competitionId = saved.record?.id
            case let .rejected(problem):
                apply(problem)
                return nil
            }
        }
        guard let competitionId else {
            apply(.validation(errors: ["competitionId": [Messages.required]], warnings: [:]))
            return nil
        }
        switch try await entries.perform({ $0.createCompetitionStart(competitionId: competitionId, input) }) {
        case let .saved(saved):
            warnings = saved.warnings
            guard let created else { return saved }
            return EntrySaved(record: saved.record, effects: created.effects + saved.effects, warnings: saved.warnings, batchId: nil, undo: .combine([created.undo, saved.undo]))
        case let .rejected(problem):
            if let created { try await entries.undo(created.undo) }
            apply(problem)
            return nil
        }
    }

    /// Pokazuje odmowę reguł: błędy przy polach, a to, czego żadne pole nie pokazuje, w komunikacie na dole.
    private func apply(_ problem: RuleProblem) {
        switch problem {
        case let .validation(fieldErrors, fieldWarnings):
            errors = fieldErrors
            warnings = fieldWarnings
            let hidden = FormSpec.sections(for: kind).flatMap(\.slots).filter { slot in slot.more && !errors(for: slot.field).isEmpty }
            if !hidden.isEmpty { showMore = true }
            let unmatched = unmatchedErrors()
            failure = unmatched.isEmpty ? nil : ([tr("entry_error_general_title")] + unmatched).joined(separator: "\n")
        case .conflict:
            failure = problem.message
        case .notFound:
            failure = tr("entry_not_found")
        }
    }
}

extension EntryFormModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
