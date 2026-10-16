import Foundation

/// Formularze, do których prowadzi „Zarejestruj wizytę” z terminu.
public enum EntryForm: Sendable, Equatable {
    case vetVisit, farrierVisit, physioVisit, specialistVisit, competitionStart, note
}

/// Wartości wstępne formularza otwieranego z terminu.
public struct FormPrefill: Equatable, Sendable {
    public let form: EntryForm
    public let horseId: String
    public let date: LocalDate
    public let reminderId: String
    /// Tylko dla `specialistVisit`.
    public let specialistTypeId: String?
}

/// Mapowanie rodzaju terminu na formularz (FR-M-TER-03).
public enum ReminderFormMapping {
    public static func form(for kind: ReminderKind) -> EntryForm {
        switch kind {
        case .vet, .vaccination, .deworming: .vetVisit
        case .farrier: .farrierVisit
        case .physio: .physioVisit
        case .specialist: .specialistVisit
        case .competition: .competitionStart
        case .other: .note
        }
    }

    /// Koń z terminu i dzisiejsza data; typ specjalisty tylko dla wizyty specjalisty.
    public static func prefill(for reminder: ReminderItem, today: LocalDate) -> FormPrefill {
        let form = form(for: reminder.kind)
        return FormPrefill(form: form, horseId: reminder.horseId, date: today, reminderId: reminder.id, specialistTypeId: form == .specialistVisit ? reminder.specialistTypeId : nil)
    }
}
