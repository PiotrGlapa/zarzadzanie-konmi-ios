import Foundation

/// Pola podpowiadane w nowym treningu (FR-M-TRN-03); koszt i jego kwota w walucie obcej to jedna grupa.
public enum SuggestedField: Sendable, Hashable {
    case trainer, rider, cost
}

/// Wartości podpowiadane w formularzu treningu.
public struct TrainingDefaults: Equatable, Sendable {
    public var trainerContactId: String?
    public var riderContactId: String?
    public var cost: Money?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init(trainerContactId: String? = nil, riderContactId: String? = nil, cost: Money? = nil, originalAmount: Money? = nil, originalCurrency: String? = nil) {
        self.trainerContactId = trainerContactId
        self.riderContactId = riderContactId
        self.cost = cost
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
    }
}

/// Podpowiedzi nowego treningu z ostatniego treningu tego konia (treningi z kosza program pomija): trener, jeździec i koszt z kwotą
/// w walucie obcej. Kontakt zarchiwizowany, nieistniejący albo bez typu „Trener” / „Jeździec” nie jest podpowiadany. Reguła nie dotyczy edycji.
public enum TrainingSuggestions {
    public static func defaults(from latest: LocalTraining?, contacts: [LocalContact]) -> TrainingDefaults {
        guard let latest else { return TrainingDefaults() }
        let byId = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func valid(_ id: String?, _ type: ContactType) -> String? {
            guard let id, let contact = byId[id], !contact.isArchived, contact.types.contains(type) else { return nil }
            return id
        }
        return TrainingDefaults(
            trainerContactId: valid(latest.trainerContactId, .trainer), riderContactId: valid(latest.riderContactId, .rider), cost: latest.cost,
            originalAmount: latest.originalAmount, originalCurrency: latest.originalCurrency
        )
    }

    /// Najnowszy trening z listy (po dacie, przy równej — później utworzony).
    public static func latest(_ trainings: [LocalTraining]) -> LocalTraining? {
        trainings.max { ($0.trainingDate, $0.createdAt) < ($1.trainingDate, $1.createdAt) }
    }

    /// Nakłada `defaults` na `current` tylko w polach, których użytkownik nie zmienił ręcznie (`edited`); zmiana konia daje nowe
    /// podpowiedzi, ale ręcznie wpisanych wartości nie rusza.
    public static func apply(current: TrainingDefaults, defaults: TrainingDefaults, edited: Set<SuggestedField>) -> TrainingDefaults {
        TrainingDefaults(
            trainerContactId: edited.contains(.trainer) ? current.trainerContactId : defaults.trainerContactId,
            riderContactId: edited.contains(.rider) ? current.riderContactId : defaults.riderContactId,
            cost: edited.contains(.cost) ? current.cost : defaults.cost,
            originalAmount: edited.contains(.cost) ? current.originalAmount : defaults.originalAmount,
            originalCurrency: edited.contains(.cost) ? current.originalCurrency : defaults.originalCurrency
        )
    }
}
