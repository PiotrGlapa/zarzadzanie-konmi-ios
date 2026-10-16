import HorselyCore
import SwiftUI

extension LocalDate {
    /// Data kalendarzowa jako `Date` w południe czasu lokalnego (do `DatePicker`; nigdy nie przechodzi przez strefę na zapis).
    var pickerDate: Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return Calendar.current.date(from: parts) ?? Date()
    }

    /// Dzień kalendarzowy wybrany w `DatePicker` (w strefie urządzenia — tej samej, w której użytkownik go widzi).
    init(pickerDate date: Date) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self = LocalDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1) ?? LocalDate(dayNumber: 0)
    }
}

/// Pole daty opcjonalnej: „Nie wybrano” z przyciskiem „Wybierz datę” albo wybrana data z możliwością wyczyszczenia.
/// `maximum` ogranicza wybór (np. dzisiaj dla dat, które nie mogą być z przyszłości).
struct DateField: View {
    let title: LocalizedStringKey
    @Binding var date: LocalDate?
    var maximum: LocalDate?
    var defaultSelection: LocalDate

    init(_ title: LocalizedStringKey, date: Binding<LocalDate?>, maximum: LocalDate? = nil, defaultSelection: LocalDate) {
        self.title = title
        self._date = date
        self.maximum = maximum
        self.defaultSelection = defaultSelection
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let current = date {
                DatePicker(
                    "",
                    selection: Binding(get: { current.pickerDate }, set: { date = LocalDate(pickerDate: $0) }),
                    in: ...(maximum?.pickerDate ?? .distantFuture),
                    displayedComponents: .date
                )
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "pl_PL"))
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                .frame(minWidth: Spacing.minTouchTarget, minHeight: Spacing.minTouchTarget)
                .accessibilityLabel(tr("date_clear"))
            } else {
                Button(tr("date_pick")) { date = defaultSelection }
                    .frame(minHeight: Spacing.minTouchTarget)
                    .accessibilityHint(tr("date_not_set"))
            }
        }
    }
}
