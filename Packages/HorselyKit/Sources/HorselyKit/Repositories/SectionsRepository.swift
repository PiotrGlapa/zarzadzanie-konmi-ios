import Foundation
import HorselyCore

/// Szczegóły zawodów ze startami.
public struct CompetitionDetail: Sendable, Equatable {
    public let competition: LocalCompetition
    public let starts: [LocalCompetitionStart]
}

/// Historia kontaktu na karcie (FR-M-KTK-02): zakupy u dostawcy z sumą, treningi jako trener i jeździec, starty jako jeździec.
public struct ContactHistory: Sendable, Equatable {
    public let purchases: [LocalPurchase]
    public let purchasesTotal: Money
    public let asTrainer: [LocalTraining]
    public let asRider: [LocalTraining]
    public let starts: [LocalCompetitionStart]
}

/// Działy Treningi, Zakupy i Zawody oraz kontakty (US4): listy z filtrami i sumami z danych w telefonie (w trybie online — pełna
/// kopia danych programu, FR-SYN2-08), zapis kontaktu i zawodów tą samą drogą co wpisy (`EntryRepository.perform`: tryb samodzielny
/// — rekord `Local`, online — rekord `Pending` + operacja w kolejce).
public extension EntryRepository {
    func trainings(_ query: TrainingQuery) async throws -> SectionList<LocalTraining> {
        try await read { source, _ in try LocalSections(source: source).trainings(query) }
    }

    func purchases(_ query: PurchaseQuery) async throws -> SectionList<LocalPurchase> {
        try await read { source, _ in try LocalSections(source: source).purchases(query) }
    }

    func competitions(_ query: CompetitionQuery) async throws -> [CompetitionListItem] {
        try await read { source, _ in try LocalSections(source: source).competitions(query) }
    }

    func competitionDetail(id: String) async throws -> CompetitionDetail? {
        try await read { source, _ in
            guard let competition = try source.find(.competition, id: id, as: LocalCompetition.self) else { return nil }
            let starts = try source.byOwner(.competitionStart, ownerId: id).compactMap { $0.record as? LocalCompetitionStart }
                .sorted { ($0.startDate ?? competition.dateFrom, $0.id) < ($1.startDate ?? competition.dateFrom, $1.id) }
            return CompetitionDetail(competition: competition, starts: starts)
        }
    }

    /// Kontakty z wyszukiwaniem i filtrem typu (bez zarchiwizowanych).
    func contacts(query: String, type: ContactType?) async throws -> [LocalContact] {
        try await read { source, _ in ContactRules.search(try source.records(.contact, as: LocalContact.self), query: query, type: type) }
    }

    func contact(id: String) async throws -> LocalContact? {
        try await read { source, _ in try source.find(.contact, id: id, as: LocalContact.self) }
    }

    func contactHistory(id: String) async throws -> ContactHistory {
        try await read { source, _ in
            let purchases = try source.records(.purchase, as: LocalPurchase.self).filter { $0.supplierContactId == id }
                .sorted { ($0.purchaseDate, $0.id) > ($1.purchaseDate, $1.id) }
            let trainings = try source.records(.training, as: LocalTraining.self).sorted { ($0.trainingDate, $0.id) > ($1.trainingDate, $1.id) }
            let starts = try source.records(.competitionStart, as: LocalCompetitionStart.self).filter { $0.riderContactId == id }
            return ContactHistory(
                purchases: purchases, purchasesTotal: purchases.reduce(Money.zero) { $0 + $1.totalAmount + $1.deliveryCost },
                asTrainer: trainings.filter { $0.trainerContactId == id }, asRider: trainings.filter { $0.riderContactId == id }, starts: starts
            )
        }
    }

    func saveContact(_ input: ContactInput, id: String? = nil, expectedVersion: Int? = nil) async throws -> EntryResult {
        try await perform { engine in
            if let id { return engine.updateContact(id: id, input, expectedVersion: expectedVersion) }
            return engine.createContact(input)
        }
    }

    func setContactArchived(id: String, _ archived: Bool) async throws -> EntryResult {
        try await perform { $0.setContactArchived(id: id, archived) }
    }
}
