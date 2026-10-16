import HorselyCore
import HorselyKit
import SwiftUI

/// Nazwy do wierszy działów: pozycje słowników, kontakty i konie.
@MainActor
@Observable
final class SectionNames {
    private(set) var dictionary: [LocalDictionaryItem] = []
    private(set) var contacts: [LocalContact] = []
    private var dictionaryNames: [String: String] = [:]
    private var contactNames: [String: String] = [:]

    func load(using environment: AppEnvironment) async {
        dictionary = (try? await environment.entries.allDictionaryItems()) ?? []
        contacts = (try? await environment.entries.allContacts()) ?? []
        dictionaryNames = Dictionary(dictionary.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        contactNames = Dictionary(contacts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    func dictionaryName(_ id: String?) -> String? { id.flatMap { dictionaryNames[$0] } }
    func contactName(_ id: String?) -> String? { id.flatMap { contactNames[$0] } }

    func items(_ type: DictionaryType) -> [LocalDictionaryItem] { dictionary.filter { $0.dictionaryType == type } }
    func contacts(_ type: ContactType) -> [LocalContact] { contacts.filter { $0.types.contains(type) } }
}

/// Stopka działu („Treningów: N · Razem: kwota”) i informacja „z pamięci” w trybie online bez połączenia (US11/6).
struct SectionFooter: View {
    let text: String
    let identifier: String
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(HorselyColor.onBackground).accessibilityIdentifier(identifier)
            if environment.workMode == .online, environment.connection.problem != nil {
                Text("sections_from_memory").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.between)
        .background(HorselyColor.background)
    }
}

/// Przycisk „Filtry” / „Filtry (N)” w pasku tytułu działu.
struct FiltersButton: View {
    let active: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(active > 0 ? tr("sections_filters_active", active) : tr("sections_filters"))
        }
        .accessibilityIdentifier("section-filters")
    }
}

/// Wybór okresu w arkuszu filtrów (od–do).
struct PeriodFields: View {
    @Binding var period: ListPeriod
    let today: LocalDate

    var body: some View {
        DateField("sections_period_from", date: $period.from, defaultSelection: today)
        DateField("sections_period_to", date: $period.to, defaultSelection: today)
    }
}

/// Wybór jednej wartości z listy z pozycją „Wszystkie”.
struct OptionalPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: String?
    let options: [(id: String, name: String)]

    var body: some View {
        Picker(selection: $selection) {
            Text("reminders_filter_all").tag(String?.none)
            ForEach(options, id: \.id) { option in Text(option.name).tag(String?.some(option.id)) }
        } label: {
            Text(title)
        }
    }
}

/// Pusty dział w danym okresie.
struct SectionEmpty: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey

    var body: some View {
        VStack(spacing: Spacing.between) {
            Text(title).font(.headline)
            Text(hint).font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, Spacing.screenEdge)
    }
}

/// Filtry działów zapamiętane do zamknięcia aplikacji (US11/5).
@MainActor
@Observable
final class SectionFilters {
    var trainings: TrainingQuery
    var purchases: PurchaseQuery
    var competitions: CompetitionQuery

    init(today: LocalDate) {
        trainings = TrainingQuery(period: .default(today: today))
        purchases = PurchaseQuery(period: .default(today: today))
        competitions = CompetitionQuery(period: .default(today: today))
    }
}
