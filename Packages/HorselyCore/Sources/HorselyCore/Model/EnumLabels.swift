import Foundation

/// Polskie nazwy wartości wyliczeniowych programu. `labelKey` to klucz ze `strings.xml` Androida (aplikacja pobiera tekst z
/// `Localizable.xcstrings`), `label` — ten sam tekst dla logiki bez dostępu do pakietu aplikacji (raporty, CSV, powiadomienia).
/// Test `EnumLabelsTests` pilnuje zgodności `label` z `App/Resources/android/strings.xml`.
public protocol EnumLabel {
    var labelKey: String { get }
    var label: String { get }
}

extension HorseStatus: EnumLabel {
    public var labelKey: String { "horse_status_\(rawValue.lowercased())" }

    public var label: String {
        switch self {
        case .active: "Aktywny"
        case .injured: "Kontuzjowany"
        case .sold: "Sprzedany"
        case .deceased: "Padł"
        case .leased: "Wydzierżawiony"
        }
    }
}

extension Sex: EnumLabel {
    public var labelKey: String { "horse_sex_\(rawValue.lowercased())" }

    public var label: String {
        switch self {
        case .mare: "Klacz"
        case .stallion: "Ogier"
        case .gelding: "Wałach"
        }
    }
}

extension ContactType: EnumLabel {
    public var labelKey: String { "contact_type_\(rawValue.lowercased())" }

    public var label: String {
        switch self {
        case .vet: "Weterynarz"
        case .farrier: "Kowal"
        case .physio: "Fizjoterapeuta"
        case .specialist: "Specjalista"
        case .shop: "Sklep"
        case .organizer: "Organizator zawodów"
        case .other: "Inny"
        case .trainer: "Trener"
        case .rider: "Jeździec"
        }
    }
}

extension ReminderKind: EnumLabel {
    public var labelKey: String { "reminder_kind_\(rawValue.lowercased())" }

    public var label: String {
        switch self {
        case .vet: "Wizyta weterynaryjna"
        case .vaccination: "Szczepienie"
        case .deworming: "Odrobaczanie"
        case .farrier: "Kowal"
        case .physio: "Fizjoterapia"
        case .specialist: "Specjalista"
        case .competition: "Zawody"
        case .other: "Inne"
        }
    }
}

extension ReminderStatus: EnumLabel {
    public var labelKey: String { "reminder_status_\(rawValue.lowercased())" }

    public var label: String {
        switch self {
        case .open: "Otwarty"
        case .completed: "Zrealizowany"
        case .dismissed: "Odrzucony"
        }
    }
}

extension PurchaseAssignment: EnumLabel {
    public var labelKey: String {
        switch self {
        case .singleHorse: "purchase_assignment_single"
        case .multipleHorses: "purchase_assignment_multiple"
        case .general: "purchase_assignment_general"
        }
    }

    public var label: String {
        switch self {
        case .singleHorse: "Jeden koń"
        case .multipleHorses: "Kilka koni"
        case .general: "Ogólny (cała stajnia)"
        }
    }
}

extension ResultStatus: EnumLabel {
    public var labelKey: String {
        switch self {
        case .completed: "result_status_completed"
        case .eliminated: "result_status_eliminated"
        case .retired: "result_status_retired"
        case .didNotStart: "result_status_did_not_start"
        }
    }

    public var label: String {
        switch self {
        case .completed: "Ukończony"
        case .eliminated: "Eliminacja"
        case .retired: "Wycofany"
        case .didNotStart: "Nie wystartował"
        }
    }
}

extension MedicationMode: EnumLabel {
    public var labelKey: String {
        switch self {
        case .administeredAtVisit: "medication_administered"
        case .prescribed: "medication_prescribed"
        }
    }

    public var label: String {
        switch self {
        case .administeredAtVisit: "Podane na wizycie"
        case .prescribed: "Przepisane"
        }
    }
}

extension Intensity: EnumLabel {
    public var labelKey: String { "intensity_\(rawValue.lowercased())" }

    public var label: String {
        switch self {
        case .light: "Lekka"
        case .medium: "Średnia"
        case .hard: "Ciężka"
        }
    }
}
