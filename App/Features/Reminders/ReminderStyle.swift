import HorselyCore
import SwiftUI

extension ReminderKind {
    /// Kolor rodzaju terminu (5.4): szczepienie i odrobaczanie jak weterynarz, „Inne” jak notatka.
    var accent: EntryAccent {
        switch self {
        case .vet, .vaccination, .deworming: .vet
        case .farrier: .farrier
        case .physio: .physio
        case .specialist: .specialist
        case .competition: .competition
        case .other: .note
        }
    }

    /// Ikona rodzaju terminu: jak wpis tego rodzaju, poza szczepieniem (`vaccines`), odrobaczaniem (`bug_report`) i „Inne” (`event`).
    var iconName: String {
        switch self {
        case .vaccination: "vaccines"
        case .deworming: "bug_report"
        case .other: "event"
        default: accent.icon
        }
    }

    var color: Color { accent.color }
}

extension ReminderItem {
    /// Liczba dni po terminie (0 — dziś lub w przyszłości).
    func daysOverdue(today: LocalDate) -> Int { max(0, today.dayNumber - dueDate.dayNumber) }
}

/// Termin jako treść obszaru (5.4): wiersz 1 — ikona rodzaju 20 pt, „rodzaj · koń”, data z prawej; wiersz 2 — tytuł; wiersz 3 — notatka;
/// wiersz 4 — pogrubiona etykieta „Przeterminowany” i „N dni temu”.
struct ReminderContent: View {
    let reminder: ReminderItem
    let today: LocalDate
    var showsHorse = true

    private var kindTitle: String {
        if reminder.kind == .specialist, let type = reminder.specialistTypeName { return type }
        return tr(reminder.kind.labelKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.between) {
                HIcon(name: reminder.kind.iconName, size: 20).foregroundStyle(reminder.kind.color)
                Text(showsHorse && !(reminder.horseName ?? "").isEmpty ? "\(kindTitle) · \(reminder.horseName ?? "")" : kindTitle)
                    .font(.footnote)
                Spacer(minLength: Spacing.between)
                Text(Formats.date(reminder.dueDate)).font(.footnote)
            }
            Text(reminder.title).font(.body.weight(.semibold))
            if let notes = HorseRules.clean(reminder.notes) {
                Text(notes).font(.footnote).lineLimit(2)
            }
            if reminder.status == .open, reminder.isOverdue {
                HStack(spacing: 4) {
                    Text("reminders_overdue_label").font(.footnote.weight(.bold))
                    Text(trPlural("reminders_days_ago", reminder.daysOverdue(today: today))).font(.footnote)
                }
            } else if reminder.status != .open {
                Text(LocalizedStringKey(reminder.status.labelKey)).font(.footnote.weight(.bold))
            }
            RecordMarkerLabel(type: .reminder, id: reminder.id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
