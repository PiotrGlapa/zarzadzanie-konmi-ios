import Foundation
import HorselyCore

/// Filtr listy treningów konia (FR-M-TRN-02): rodzaj i zakres dat.
public struct TrainingFilter: Sendable, Hashable {
    public var trainingTypeId: String?
    public var from: LocalDate?
    public var to: LocalDate?

    public init(trainingTypeId: String? = nil, from: LocalDate? = nil, to: LocalDate? = nil) {
        self.trainingTypeId = trainingTypeId
        self.from = from
        self.to = to
    }
}

/// Lista treningów z podsumowaniem „Treningów: N · Razem: kwota” (suma kosztów trenera w filtrze).
public struct TrainingList: Sendable, Equatable {
    public let trainings: [LocalTraining]
    public let totalCost: Money
}

/// Treningi w magazynie lokalnym: lista, podpowiedzi nowego treningu (trener, jeździec i koszt z ostatniego treningu konia), zapis.
public final class TrainingRepository: Sendable {
    private let entries: EntryRepository

    public init(entries: EntryRepository) {
        self.entries = entries
    }

    /// Najnowsze treningi na początku.
    public func trainings(horseId: String, filter: TrainingFilter = TrainingFilter()) async throws -> TrainingList {
        try await entries.read { source, _ in
            let list = try source.records(.training, as: LocalTraining.self, horseId: horseId, from: filter.from, to: filter.to)
                .filter { filter.trainingTypeId == nil || $0.trainingTypeId == filter.trainingTypeId }
                .sorted { ($0.trainingDate, $0.createdAt, $0.id) > ($1.trainingDate, $1.createdAt, $1.id) }
            return TrainingList(trainings: list, totalCost: list.reduce(Money.zero) { $0 + ($1.cost ?? .zero) })
        }
    }

    /// Podpowiedzi do nowego treningu konia; kontakty zarchiwizowane i bez wymaganego typu są pomijane.
    public func defaults(horseId: String) async throws -> TrainingDefaults {
        try await entries.read { source, _ in
            let latest = TrainingSuggestions.latest(try source.records(.training, as: LocalTraining.self, horseId: horseId))
            return TrainingSuggestions.defaults(from: latest, contacts: try source.records(.contact, as: LocalContact.self))
        }
    }

    public func create(_ input: TrainingInput) async throws -> EntryResult {
        try await entries.perform { $0.createTraining(input) }
    }

    public func update(id: String, _ input: TrainingInput, expectedVersion: Int) async throws -> EntryResult {
        try await entries.perform { $0.updateTraining(id: id, input, expectedVersion: expectedVersion) }
    }

    public func delete(id: String) async throws -> EntryResult {
        try await entries.delete(.training, id: id)
    }
}
