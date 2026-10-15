import Foundation

// Wartości wyliczeniowe programu 2.0.0 (schemat eksportu 1.5): nazwy znakowe są częścią kontraktu JSON — nie zmieniać.

public enum HorseStatus: String, Codable, Sendable, CaseIterable {
    case active = "Active"
    case injured = "Injured"
    case sold = "Sold"
    case deceased = "Deceased"
    case leased = "Leased"
}

public enum Sex: String, Codable, Sendable, CaseIterable {
    case mare = "Mare"
    case stallion = "Stallion"
    case gelding = "Gelding"
}

public enum ReminderKind: String, Codable, Sendable, CaseIterable {
    case vet = "Vet"
    case vaccination = "Vaccination"
    case deworming = "Deworming"
    case farrier = "Farrier"
    case physio = "Physio"
    case specialist = "Specialist"
    case competition = "Competition"
    case other = "Other"
}

public enum ReminderStatus: String, Codable, Sendable, CaseIterable {
    case open = "Open"
    case completed = "Completed"
    case dismissed = "Dismissed"
}

public enum ContactType: String, Codable, Sendable, CaseIterable {
    case vet = "Vet"
    case farrier = "Farrier"
    case physio = "Physio"
    case specialist = "Specialist"
    case shop = "Shop"
    case organizer = "Organizer"
    case other = "Other"
    case trainer = "Trainer"
    case rider = "Rider"
}

public enum Intensity: String, Codable, Sendable, CaseIterable {
    case light = "Light"
    case medium = "Medium"
    case hard = "Hard"
}

public enum ResultStatus: String, Codable, Sendable, CaseIterable {
    case completed = "Completed"
    case eliminated = "Eliminated"
    case retired = "Retired"
    case didNotStart = "DidNotStart"
}

public enum PurchaseAssignment: String, Codable, Sendable, CaseIterable {
    case singleHorse = "SingleHorse"
    case multipleHorses = "MultipleHorses"
    case general = "General"
}

/// Sposób podania leku (`administration` w lekach wizyty weterynaryjnej).
public enum MedicationMode: String, Codable, Sendable, CaseIterable {
    case administeredAtVisit = "AdministeredAtVisit"
    case prescribed = "Prescribed"
}

public enum DictionaryType: String, Codable, Sendable, CaseIterable {
    case vetVisitType = "VetVisitType"
    case farrierService = "FarrierService"
    case physioBodyArea = "PhysioBodyArea"
    case physioTechnique = "PhysioTechnique"
    case specialistType = "SpecialistType"
    case competitionRank = "CompetitionRank"
    case competitionDiscipline = "CompetitionDiscipline"
    case purchaseCategory = "PurchaseCategory"
    case unit = "Unit"
    case trainingType = "TrainingType"
}

public enum AttachmentOwnerType: String, Codable, Sendable, CaseIterable {
    case horse = "Horse"
    case vetVisit = "VetVisit"
    case farrierVisit = "FarrierVisit"
    case physioVisit = "PhysioVisit"
    case specialistVisit = "SpecialistVisit"
    case competition = "Competition"
    case competitionStart = "CompetitionStart"
    case purchase = "Purchase"
    case note = "Note"
    case contact = "Contact"
}

/// Rodzaje rekordów magazynu lokalnego (data-model.md §1) — 1:1 z `$defs` schematu eksportu. Starty zawodów są osobnymi
/// rekordami (w pliku eksportu zagnieżdżone w zawodach).
public enum RecordType: String, Codable, Sendable, CaseIterable {
    case dictionary = "Dictionary"
    case contact = "Contact"
    case horse = "Horse"
    case vetVisit = "VetVisit"
    case farrierVisit = "FarrierVisit"
    case physioVisit = "PhysioVisit"
    case specialistVisit = "SpecialistVisit"
    case competition = "Competition"
    case competitionStart = "CompetitionStart"
    case purchase = "Purchase"
    case note = "Note"
    case training = "Training"
    case reminder = "Reminder"
    case attachment = "Attachment"

    /// Nazwa kolekcji w `data` pliku eksportu; `nil` dla startów (zagnieżdżone w zawodach).
    public var exportCollection: String? {
        switch self {
        case .dictionary: "dictionaries"
        case .contact: "contacts"
        case .horse: "horses"
        case .vetVisit: "vetVisits"
        case .farrierVisit: "farrierVisits"
        case .physioVisit: "physioVisits"
        case .specialistVisit: "specialistVisits"
        case .competition: "competitions"
        case .competitionStart: nil
        case .purchase: "purchases"
        case .note: "notes"
        case .training: "trainings"
        case .reminder: "reminders"
        case .attachment: "attachments"
        }
    }

    /// Rodzaj z nazwy typu w `trashed[]` i `purged[]` schematu 1.5 (`DictionaryItem` to słownik); `nil` — typ nieznany telefonowi.
    public static func fromRemovalType(_ name: String) -> RecordType? {
        name == "DictionaryItem" ? .dictionary : RecordType(rawValue: name)
    }
}

/// Stan rekordu w magazynie lokalnym (data-model.md §3).
/// Tryb online: `synced` → `pending` → `synced`, konflikt → `conflict`; `projected` = przewidywany skutek reguły dla niewysłanej
/// zmiany (usuwany przy pełnym pobraniu). Tryb samodzielny: jedyny stan `local`.
public enum SyncState: String, Codable, Sendable, CaseIterable {
    case synced = "Synced"
    case pending = "Pending"
    case conflict = "Conflict"
    case projected = "Projected"
    case local = "Local"

    /// Rekord ma lokalną zmianę, której program jeszcze nie zna — pełne pobranie go nie nadpisuje.
    public var isUnsent: Bool { self == .pending || self == .conflict }
}

/// Tryb pracy aplikacji (FR-TRB-01); wartość `unset` do wyboru na ekranie powitalnym.
public enum WorkMode: String, Codable, Sendable, CaseIterable {
    case unset
    case online
    case standalone
}
