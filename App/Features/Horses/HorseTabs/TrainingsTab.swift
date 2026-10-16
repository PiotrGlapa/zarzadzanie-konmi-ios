import HorselyCore
import HorselyKit
import SwiftUI

/// Treningi konia (FR-M-TRN-04): filtry (rodzaj, zakres dat), „Treningów: N · Razem: kwota”, wiersze z paskiem koloru treningu
/// (rodzaj, czas „X h Y min”, intensywność, wysokość przeszkód, ocena, trener), „Dodaj trening”.
struct TrainingsTab: View {
    @Environment(AppEnvironment.self) private var environment
    let horseId: String
    @State private var filter = TrainingFilter()
    @State private var list: TrainingList?
    @State private var names = DictionaryNames()
    @State private var showingFilters = false

    private var today: LocalDate { environment.dates.today() }
    private var activeFilters: Int { [filter.trainingTypeId != nil, filter.from != nil, filter.to != nil].filter { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            HStack {
                if let list {
                    Text(tr("trainings_summary", list.trainings.count, Formats.money(list.totalCost)))
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("trainings-summary")
                }
                Spacer()
                Button {
                    showingFilters = true
                } label: {
                    Text(activeFilters == 0 ? tr("sections_filters") : tr("sections_filters_active", activeFilters))
                        .frame(minHeight: Spacing.minTouchTarget)
                }
                .accessibilityIdentifier("trainings-filters")
            }
            TabAddButton(title: "trainings_section_add", request: EntryRequest(kind: .training, horseId: horseId), identifier: "trainings-add")
            if let list {
                if list.trainings.isEmpty {
                    TabEmptyText(key: "trainings_section_empty_title", hint: "trainings_section_empty_hint")
                } else {
                    DividedList(list.trainings) { training in
                        NavigationLink(value: EntryRoute(recordType: .training, id: training.id)) { row(training) }
                            .buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
        .task(id: LoadKey(filter: filter, revision: environment.dataRevision)) {
            await names.load(using: environment)
            list = try? await environment.trainings.trainings(horseId: horseId, filter: filter)
        }
        .sheet(isPresented: $showingFilters) { filters }
    }

    private struct LoadKey: Hashable {
        let filter: TrainingFilter
        let revision: Int64
    }

    private func row(_ training: LocalTraining) -> some View {
        var parts: [String] = []
        if training.durationMinutes != nil { parts.append(Formats.duration(minutes: training.durationMinutes)) }
        if let intensity = training.intensity { parts.append(tr(intensity.labelKey)) }
        if let height = training.obstacleHeightCm { parts.append(tr("trainings_height", height)) }
        return AccentRow(color: EntryAccent.training.color) {
            HStack(alignment: .top, spacing: Spacing.between) {
                HIcon(name: EntryAccent.training.icon, size: 24).foregroundStyle(EntryAccent.training.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(names.name(training.trainingTypeId) ?? Formats.dash).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                    if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                    if training.rating != nil { StarRatingDisplay(rating: training.rating).font(.footnote) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formats.date(training.trainingDate)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    if let cost = training.cost { Text(Formats.money(cost)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                }
            }
            .padding(.vertical, Spacing.between)
        }
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var filters: some View {
        NavigationStack {
            Form {
                Picker(selection: $filter.trainingTypeId) {
                    Text("reminders_filter_all").tag(String?.none)
                    ForEach(names.names.sorted { $0.value < $1.value }, id: \.key) { entry in
                        Text(entry.value).tag(String?.some(entry.key))
                    }
                } label: {
                    Text("dictionary_training_type")
                }
                DateField("sections_period_from", date: $filter.from, defaultSelection: today)
                DateField("sections_period_to", date: $filter.to, defaultSelection: today)
                Button(tr("sections_clear_filters")) { filter = TrainingFilter() }.disabled(activeFilters == 0)
            }
            .navigationTitle("sections_filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(tr("sections_filters_done")) { showingFilters = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
