import Foundation

// Treść zapisu wpisów w kształcie żądań API programu (te same pola i nazwy co w kontrakcie `openapi`). Wszystkie pola są opcjonalne,
// bo walidacja pól wymaganych („Pole jest wymagane.”) jest częścią reguł; formularze wypełniają to, co wpisał użytkownik.
// Decodable — pliki wzorcowe scenariuszy programu to zwykłe żądania JSON.

public struct VetMedicationInput: Codable, Equatable, Sendable {
    public var name: String?
    public var dosage: String?
    public var startDate: LocalDate?
    public var endDate: LocalDate?
    public var administration: MedicationMode?
    public var notes: String?

    public init(name: String? = nil, dosage: String? = nil, startDate: LocalDate? = nil, endDate: LocalDate? = nil, administration: MedicationMode? = nil, notes: String? = nil) {
        self.name = name
        self.dosage = dosage
        self.startDate = startDate
        self.endDate = endDate
        self.administration = administration
        self.notes = notes
    }
}

public struct VetVisitInput: Codable, Equatable, Sendable {
    public var horseId: String?
    public var visitDateTime: LocalDateTime?
    public var contactId: String?
    public var visitTypeId: String?
    public var reason: String?
    public var diagnosis: String?
    public var recommendations: String?
    public var vaccineOrProduct: String?
    public var batchNumber: String?
    public var cost: Money?
    public var nextVisitDate: LocalDate?
    public var nextVisitPurpose: String?
    public var originalAmount: Money?
    public var originalCurrency: String?
    public var medications: [VetMedicationInput]?

    public init() {}
}

public struct FarrierVisitInput: Codable, Equatable, Sendable {
    public var horseId: String?
    public var visitDate: LocalDate?
    public var contactId: String?
    public var serviceId: String?
    public var hoofNotes: String?
    public var cost: Money?
    public var nextVisitDate: LocalDate?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init() {}
}

public struct PhysioVisitInput: Codable, Equatable, Sendable {
    public var horseId: String?
    public var visitDate: LocalDate?
    public var contactId: String?
    public var reason: String?
    public var bodyAreaIds: [String]?
    public var techniqueIds: [String]?
    public var observations: String?
    public var recommendations: String?
    public var cost: Money?
    public var nextVisitDate: LocalDate?
    public var nextVisitPurpose: String?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init() {}
}

public struct SpecialistVisitInput: Codable, Equatable, Sendable {
    public var horseId: String?
    public var visitDate: LocalDate?
    public var specialistTypeId: String?
    public var contactId: String?
    public var reason: String?
    public var description: String?
    public var recommendations: String?
    public var cost: Money?
    public var nextVisitDate: LocalDate?
    public var nextVisitPurpose: String?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init() {}
}

public struct NoteInput: Codable, Equatable, Sendable {
    public var horseId: String?
    public var noteDate: LocalDate?
    public var title: String?
    public var content: String?
    public var isPinned: Bool?

    public init() {}
}

public struct PurchaseInput: Codable, Equatable, Sendable {
    public var purchaseDate: LocalDate?
    public var productName: String?
    public var categoryId: String?
    public var supplierContactId: String?
    public var quantity: Money?
    public var unitId: String?
    public var unitPrice: Money?
    public var totalAmount: Money?
    public var deliveryCost: Money?
    public var assignment: PurchaseAssignment?
    public var horseIds: [String]?
    public var notes: String?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init() {}

    /// Dane istniejącego zakupu (edycja, „Powtórz zakup”).
    public init(purchase: LocalPurchase) {
        purchaseDate = purchase.purchaseDate
        productName = purchase.productName
        categoryId = purchase.categoryId
        supplierContactId = purchase.supplierContactId
        quantity = purchase.quantity
        unitId = purchase.unitId
        unitPrice = purchase.unitPrice
        totalAmount = purchase.totalAmount
        deliveryCost = purchase.deliveryCost
        assignment = purchase.assignment
        horseIds = purchase.horseIds
        notes = purchase.notes
        originalAmount = purchase.originalAmount
        originalCurrency = purchase.originalCurrency
    }
}

public struct TrainingCoachingInput: Codable, Equatable, Sendable {
    public var trainerContactId: String?
    public var cost: Money?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init(trainerContactId: String? = nil, cost: Money? = nil, originalAmount: Money? = nil, originalCurrency: String? = nil) {
        self.trainerContactId = trainerContactId
        self.cost = cost
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
    }
}

public struct TrainingInput: Codable, Equatable, Sendable {
    public var horseId: String?
    public var trainingDate: LocalDate?
    public var trainingTypeId: String?
    public var durationMinutes: Int?
    public var intensity: Intensity?
    public var obstacleHeightCm: Int?
    public var riderContactId: String?
    public var rating: Int?
    public var description: String?
    /// Trener i koszt; `nil` zostawia zapisane wartości (klient bez tej możliwości), obiekt zastępuje wszystkie cztery pola.
    public var coaching: TrainingCoachingInput?

    public init() {}
}

public struct ReminderInput: Codable, Equatable, Sendable {
    public var horseId: String?
    public var kind: ReminderKind?
    public var dueDate: LocalDate?
    public var title: String?
    public var specialistTypeId: String?
    public var notes: String?

    public init() {}
}

public struct CompetitionInput: Codable, Equatable, Sendable {
    public var name: String?
    public var dateFrom: LocalDate?
    public var dateTo: LocalDate?
    public var city: String?
    public var venue: String?
    public var organizerContactId: String?
    public var rankId: String?
    public var disciplineId: String?
    public var notes: String?

    public init() {}
}

public struct CompetitionStartInput: Codable, Equatable, Sendable {
    public var horseId: String?
    public var startDate: LocalDate?
    public var disciplineId: String?
    public var className: String?
    public var riderContactId: String?
    public var placement: Int?
    public var participantsCount: Int?
    public var resultStatus: ResultStatus?
    public var penaltyPoints: Money?
    public var scorePercent: Money?
    public var timeSeconds: Money?
    public var description: String?
    public var subjectiveRating: Int?
    public var entryFee: Money?
    public var otherCosts: Money?
    public var prizeMoney: Money?
    public var originalAmount: Money?
    public var originalCurrency: String?

    public init() {}
}
