import HorselyCore

/// Rodzaje formularzy wpisów (9 — SPECYFIKACJA 5.3); termin ma własny, krótszy formularz (`ReminderFormView`).
enum FormKind: String, CaseIterable, Identifiable, Sendable {
    case vet, farrier, physio, specialist, note, purchase, start, training, competition

    var id: String { rawValue }

    var accent: EntryAccent {
        switch self {
        case .vet: .vet
        case .farrier: .farrier
        case .physio: .physio
        case .specialist: .specialist
        case .note: .note
        case .purchase: .purchase
        case .start, .competition: .competition
        case .training: .training
        }
    }

    /// Klucz tekstu z `strings.xml` („Wizyta weterynaryjna”, „Start w zawodach”…).
    var titleKey: String {
        switch self {
        case .vet: "entry_kind_vet"
        case .farrier: "entry_kind_farrier"
        case .physio: "entry_kind_physio"
        case .specialist: "entry_kind_specialist"
        case .note: "entry_kind_note"
        case .purchase: "entry_kind_purchase"
        case .start: "entry_kind_competition_start"
        case .training: "entry_kind_training"
        case .competition: "entry_kind_competition"
        }
    }

    var recordType: RecordType {
        switch self {
        case .vet: .vetVisit
        case .farrier: .farrierVisit
        case .physio: .physioVisit
        case .specialist: .specialistVisit
        case .note: .note
        case .purchase: .purchase
        case .start: .competitionStart
        case .training: .training
        case .competition: .competition
        }
    }

    /// Wpis rodzaju `type` otwierany z osi czasu (trening i zawody mają własne listy).
    init?(timeline type: TimelineEntryType) {
        switch type {
        case .vetVisit: self = .vet
        case .farrierVisit: self = .farrier
        case .physioVisit: self = .physio
        case .specialistVisit: self = .specialist
        case .competitionStart: self = .start
        case .purchase: self = .purchase
        case .note: self = .note
        }
    }

    /// Rodzaj z adresu `horsely://entry/new?kind=` (tylko `note` i `farrier`).
    init?(linkName: String) {
        switch linkName {
        case "note": self = .note
        case "farrier": self = .farrier
        default: return nil
        }
    }

    /// Czy przed formularzem pytamy o konia (zakup wskazuje konie w samym formularzu, zawody nie dotyczą konia).
    var asksForHorse: Bool {
        switch self {
        case .purchase, .competition: false
        default: true
        }
    }

    /// Rodzaje w kolejności listy „Co chcesz dodać?”.
    static let creatable: [FormKind] = [.vet, .farrier, .physio, .specialist, .note, .purchase, .start, .training]
}

/// Pole formularza. Jedno pole = jeden wiersz (albo grupa wierszy) w widoku; ten sam opis służy szczegółom wpisu.
enum FormField: Hashable, Sendable {
    case horse, horses, date, dateTime, startDate
    case visitType, farrierService, specialistType, trainingType, category, unit, rank, discipline
    case vetContact, farrierContact, physioContact, specialistContact, supplier, organizer, rider, trainer
    case reason, diagnosis, recommendations, vaccineOrProduct, batchNumber, medications
    case hoofNotes, bodyAreas, techniques, observations, description
    case cost, foreignAmount, nextVisitDate, nextVisitPurpose
    case title, content, pinned
    case productName, quantity, unitPrice, amount, deliveryCost, total, assignment, notes
    case competitionChoice, competitionName, dateFrom, dateTo, city, venue
    case className, placement, participants, resultStatus, rating, entryFee, otherCosts, prizeMoney, penaltyPoints, scorePercent, timeSeconds
    case duration, intensity, trainingCost, obstacleHeight

    /// Klucze pól w odpowiedzi reguł (`errors`), których błędy pokazuje to pole.
    var errorKeys: [String] {
        switch self {
        case .horse: ["horseId"]
        case .horses: ["horseIds"]
        case .date: ["visitDate", "noteDate", "purchaseDate", "trainingDate"]
        case .dateTime: ["visitDateTime"]
        case .startDate: ["startDate"]
        case .visitType: ["visitTypeId"]
        case .farrierService: ["serviceId"]
        case .specialistType: ["specialistTypeId"]
        case .trainingType: ["trainingTypeId"]
        case .category: ["categoryId"]
        case .unit: ["unitId"]
        case .rank: ["rankId"]
        case .discipline: ["disciplineId"]
        case .vetContact, .farrierContact, .physioContact, .specialistContact: ["contactId"]
        case .supplier: ["supplierContactId"]
        case .organizer: ["organizerContactId"]
        case .rider: ["riderContactId"]
        case .trainer: ["coaching.trainerContactId", "trainerContactId"]
        case .reason: ["reason"]
        case .diagnosis: ["diagnosis"]
        case .recommendations: ["recommendations"]
        case .vaccineOrProduct: ["vaccineOrProduct"]
        case .batchNumber: ["batchNumber"]
        case .medications: ["medications"]
        case .hoofNotes: ["hoofNotes"]
        case .bodyAreas: ["bodyAreaIds"]
        case .techniques: ["techniqueIds"]
        case .observations: ["observations"]
        case .description: ["description"]
        case .cost, .trainingCost: ["cost", "coaching.cost"]
        case .foreignAmount: ["originalAmount", "originalCurrency", "coaching.originalAmount", "coaching.originalCurrency"]
        case .nextVisitDate: ["nextVisitDate"]
        case .nextVisitPurpose: ["nextVisitPurpose"]
        case .title: ["title"]
        case .content: ["content"]
        case .pinned: []
        case .productName: ["productName"]
        case .quantity: ["quantity"]
        case .unitPrice: ["unitPrice"]
        case .amount: ["totalAmount"]
        case .deliveryCost: ["deliveryCost"]
        case .total: []
        case .assignment: ["assignment"]
        case .notes: ["notes"]
        case .competitionChoice: ["competitionId"]
        case .competitionName: ["name"]
        case .dateFrom: ["dateFrom"]
        case .dateTo: ["dateTo"]
        case .city: ["city"]
        case .venue: ["venue"]
        case .className: ["className"]
        case .placement: ["placement"]
        case .participants: ["participantsCount"]
        case .resultStatus: ["resultStatus"]
        case .rating: ["rating", "subjectiveRating"]
        case .entryFee: ["entryFee"]
        case .otherCosts: ["otherCosts"]
        case .prizeMoney: ["prizeMoney"]
        case .penaltyPoints: ["penaltyPoints"]
        case .scorePercent: ["scorePercent"]
        case .timeSeconds: ["timeSeconds"]
        case .duration: ["durationMinutes"]
        case .intensity: ["intensity"]
        case .obstacleHeight: ["obstacleHeightCm"]
        }
    }

    /// Klucz tekstu z `strings.xml` (etykieta w formularzu i w szczegółach).
    func labelKey(for kind: FormKind) -> String {
        switch self {
        case .horse: "field_label_horse"
        case .horses: "field_horses"
        case .date:
            switch kind {
            case .note: "field_note_date"
            case .purchase: "field_purchase_date"
            case .training: "field_training_date"
            default: "field_visit_date"
            }
        case .dateTime: "field_visit_date"
        case .startDate: "field_start_date"
        case .visitType: "dictionary_vet_visit_type"
        case .farrierService: "dictionary_farrier_service"
        case .specialistType: "dictionary_specialist_type"
        case .trainingType: "dictionary_training_type"
        case .category: "dictionary_purchase_category"
        case .unit: "dictionary_unit"
        case .rank: "dictionary_competition_rank"
        case .discipline: "dictionary_competition_discipline"
        case .vetContact: "field_vet"
        case .farrierContact: "field_farrier"
        case .physioContact: "field_physio"
        case .specialistContact: "field_specialist"
        case .supplier: "field_supplier"
        case .organizer: "field_organizer"
        case .rider: "field_rider"
        case .trainer: "field_trainer"
        case .reason: "field_reason"
        case .diagnosis: "field_diagnosis"
        case .recommendations: "field_recommendations"
        case .vaccineOrProduct: "field_vaccine_or_product"
        case .batchNumber: "field_batch_number"
        case .medications: "field_medications"
        case .hoofNotes: "field_hoof_notes"
        case .bodyAreas: "dictionary_physio_body_area"
        case .techniques: "dictionary_physio_technique"
        case .observations: "field_observations"
        case .description: "field_description"
        case .cost: "field_cost"
        case .foreignAmount: "field_original_amount"
        case .nextVisitDate: "field_next_visit_date"
        case .nextVisitPurpose: "field_next_visit_purpose"
        case .title: "field_title"
        case .content: "field_content"
        case .pinned: "field_pinned"
        case .productName: "field_product"
        case .quantity: "field_quantity"
        case .unitPrice: "field_unit_price"
        case .amount: "field_amount"
        case .deliveryCost: "field_delivery_cost"
        case .total: "entry_total"
        case .assignment: "field_purchase_for"
        case .notes: "field_notes"
        case .competitionChoice: "field_competition"
        case .competitionName: "field_competition_name"
        case .dateFrom: "field_competition_date_from"
        case .dateTo: "field_competition_date_to"
        case .city: "field_city"
        case .venue: "field_venue"
        case .className: "field_class_name"
        case .placement: "field_placement"
        case .participants: "field_participants"
        case .resultStatus: "field_result_status"
        case .rating: "field_rating"
        case .entryFee: "field_entry_fee"
        case .otherCosts: "field_other_costs"
        case .prizeMoney: "field_prize_money"
        case .penaltyPoints: "field_penalty_points"
        case .scorePercent: "field_score_percent"
        case .timeSeconds: "field_time_seconds"
        case .duration: "field_duration"
        case .intensity: "field_intensity"
        case .trainingCost: "field_training_cost"
        case .obstacleHeight: "field_obstacle_height"
        }
    }
}

/// Pole w sekcji; `more` — ukryte pod przełącznikiem „Więcej szczegółów”.
struct FormSlot: Hashable, Sendable {
    let field: FormField
    let more: Bool
}

struct FormSection: Sendable {
    let titleKey: String
    let slots: [FormSlot]
}

/// Układ formularzy (SPECYFIKACJA 5.3): Podstawowe · Szczegóły · Koszty · Następna wizyta · Uwagi. Pola widoczne od razu są w tabeli
/// 5.3, pozostałe są w swojej sekcji pod przełącznikiem „Więcej szczegółów”.
enum FormSpec {
    private static func visible(_ fields: FormField...) -> [FormSlot] { fields.map { FormSlot(field: $0, more: false) } }
    private static func more(_ fields: FormField...) -> [FormSlot] { fields.map { FormSlot(field: $0, more: true) } }

    private static func section(_ key: String, _ slots: [FormSlot]...) -> FormSection {
        FormSection(titleKey: key, slots: slots.flatMap { $0 })
    }

    static func sections(for kind: FormKind) -> [FormSection] {
        switch kind {
        case .vet:
            [
                section("form_section_basic", visible(.horse, .dateTime, .visitType, .vetContact)),
                section("form_section_details", visible(.reason, .diagnosis, .medications), more(.vaccineOrProduct, .batchNumber, .recommendations)),
                section("form_section_costs", visible(.cost), more(.foreignAmount)),
                section("form_section_next_visit", more(.nextVisitDate, .nextVisitPurpose)),
            ]
        case .farrier:
            [
                section("form_section_basic", visible(.horse, .horses, .date, .farrierContact, .farrierService)),
                section("form_section_details", more(.hoofNotes)),
                section("form_section_costs", visible(.cost), more(.foreignAmount)),
                section("form_section_next_visit", visible(.nextVisitDate)),
            ]
        case .physio:
            [
                section("form_section_basic", visible(.horse, .date, .physioContact)),
                section("form_section_details", visible(.bodyAreas, .techniques), more(.reason, .observations, .recommendations)),
                section("form_section_costs", visible(.cost), more(.foreignAmount)),
                section("form_section_next_visit", visible(.nextVisitDate), more(.nextVisitPurpose)),
            ]
        case .specialist:
            [
                section("form_section_basic", visible(.horse, .date, .specialistType, .specialistContact)),
                section("form_section_details", visible(.description), more(.reason, .recommendations)),
                section("form_section_costs", visible(.cost), more(.foreignAmount)),
                section("form_section_next_visit", visible(.nextVisitDate), more(.nextVisitPurpose)),
            ]
        case .note:
            [
                section("form_section_basic", visible(.horse, .date, .title)),
                section("form_section_notes", visible(.content, .pinned)),
            ]
        case .purchase:
            [
                section("form_section_basic", visible(.date, .productName, .category, .assignment, .horse, .horses)),
                section("form_section_details", visible(.quantity, .unitPrice, .supplier), more(.unit)),
                section("form_section_costs", visible(.amount, .deliveryCost, .total), more(.foreignAmount)),
                section("form_section_notes", more(.notes)),
            ]
        case .start:
            [
                section("form_section_basic", visible(.competitionChoice, .horse, .className, .rider)),
                section("form_section_details", visible(.placement, .participants, .resultStatus, .rating), more(.startDate, .discipline, .penaltyPoints, .scorePercent, .timeSeconds)),
                section("form_section_costs", visible(.entryFee, .prizeMoney), more(.otherCosts, .foreignAmount)),
                section("form_section_notes", more(.description)),
            ]
        case .training:
            [
                section("form_section_basic", visible(.horse, .date, .trainingType)),
                section("form_section_details", visible(.duration, .intensity, .rating, .trainer, .rider, .obstacleHeight)),
                section("form_section_costs", visible(.trainingCost), more(.foreignAmount)),
                section("form_section_notes", visible(.description)),
            ]
        case .competition:
            [
                section("form_section_basic", visible(.competitionName, .dateFrom)),
                section("form_section_details", visible(.city), more(.dateTo, .venue, .organizer, .rank, .discipline)),
                section("form_section_notes", more(.notes)),
            ]
        }
    }

    /// Pola, których wartość wskazuje wymagany wiersz („*”).
    static func isRequired(_ field: FormField, kind: FormKind) -> Bool {
        switch (kind, field) {
        case (.vet, .horse), (.vet, .dateTime), (.vet, .visitType): true
        case (.farrier, .horse), (.farrier, .date), (.farrier, .farrierService): true
        case (.physio, .horse), (.physio, .date): true
        case (.specialist, .horse), (.specialist, .date), (.specialist, .specialistType): true
        case (.note, .horse), (.note, .date), (.note, .title): true
        case (.purchase, .date), (.purchase, .productName), (.purchase, .category), (.purchase, .assignment): true
        case (.start, .competitionChoice), (.start, .horse): true
        case (.training, .horse), (.training, .date), (.training, .trainingType): true
        case (.competition, .competitionName), (.competition, .dateFrom): true
        default: false
        }
    }
}
