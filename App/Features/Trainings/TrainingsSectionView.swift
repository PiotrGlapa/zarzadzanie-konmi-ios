import HorselyCore
import HorselyKit
import SwiftUI

/// Dział Treningi (T099, US11/2): treningi wszystkich koni od najnowszych — data, koń, rodzaj, czas, wysokość przeszkód przy skokach,
/// trener, koszt, ocena gwiazdkami; filtry w arkuszu (okres, koń, rodzaj, trener, jeździec); stopka „Treningów: N · Razem: kwota”;
/// „+” otwiera formularz treningu z wyborem konia.
struct TrainingsSectionView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var list: SectionList<LocalTraining>?
    @State private var names = SectionNames()
    @State private var showingFilters = false

    var body: some View {
        @Bindable var filters = environment.sectionFilters
        let today = environment.dates.today()
        NavigationStack {
            ScrollView {
                if let list {
                    if list.items.isEmpty {
                        SectionEmpty(title: "trainings_section_empty_title", hint: "trainings_section_empty_hint")
                    } else {
                        DividedList(list.items) { training in
                            NavigationLink(value: EntryRoute(recordType: .training, id: training.id)) { row(training) }
                                .buttonStyle(.plain)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                }
                Color.clear.frame(height: Spacing.addButtonClearance)
            }
            .safeAreaInset(edge: .bottom) {
                if let list { SectionFooter(text: tr("trainings_summary", list.count, Formats.money(list.total)), identifier: "trainings-section-summary") }
            }
            .background(HorselyColor.background)
            .toolbarBackground(HorselyColor.background, for: .tabBar)
            .navigationTitle("nav_trainings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FiltersButton(active: filters.trainings.activeCount(today: today)) { showingFilters = true }
                }
            }
            .connectionChrome()
            .navigationDestination(for: EntryRoute.self) { EntryDetailView(route: $0) }
            .overlay(alignment: .bottomTrailing) { AddEntryButton(request: EntryRequest(kind: .training)) }
            .task(id: LoadKey(query: filters.trainings, revision: environment.dataRevision)) {
                await names.load(using: environment)
                list = try? await environment.entries.trainings(filters.trainings)
            }
            .sheet(isPresented: $showingFilters) {
                NavigationStack {
                    Form {
                        PeriodFields(period: $filters.trainings.period, today: today)
                        OptionalPicker(title: "trainings_section_horse", selection: $filters.trainings.horseId,
                                       options: environment.horseDirectory.horses.map { (id: $0.id, name: $0.name) })
                        OptionalPicker(title: "dictionary_training_type", selection: $filters.trainings.typeId,
                                       options: names.items(.trainingType).map { (id: $0.id, name: $0.value) })
                        OptionalPicker(title: "contact_type_trainer", selection: $filters.trainings.trainerId,
                                       options: names.contacts(.trainer).map { (id: $0.id, name: $0.name) })
                        OptionalPicker(title: "contact_type_rider", selection: $filters.trainings.riderId,
                                       options: names.contacts(.rider).map { (id: $0.id, name: $0.name) })
                        Button(tr("sections_clear_filters")) { filters.trainings = TrainingQuery(period: .default(today: today)) }
                            .disabled(filters.trainings.activeCount(today: today) == 0)
                            .accessibilityIdentifier("section-clear-filters")
                    }
                    .navigationTitle("sections_filters")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("sections_filters_done")) { showingFilters = false } } }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private struct LoadKey: Hashable {
        let query: TrainingQuery
        let revision: Int64
    }

    private func row(_ training: LocalTraining) -> some View {
        var parts: [String] = []
        if let horse = environment.horseDirectory.horses.first(where: { $0.id == training.horseId }) { parts.append(horse.name) }
        if training.durationMinutes != nil { parts.append(Formats.duration(minutes: training.durationMinutes)) }
        if let height = training.obstacleHeightCm { parts.append(tr("trainings_height", height)) }
        if let trainer = names.contactName(training.trainerContactId) { parts.append(trainer) }
        return AccentRow(color: EntryAccent.training.color) {
            HStack(alignment: .top, spacing: Spacing.between) {
                HIcon(name: EntryAccent.training.icon, size: 24).foregroundStyle(EntryAccent.training.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(names.dictionaryName(training.trainingTypeId) ?? Formats.dash).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                    if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                    if training.rating != nil { StarRatingDisplay(rating: training.rating).font(.footnote) }
                    RecordMarkerLabel(type: .training, id: training.id)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formats.date(training.trainingDate)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    if let cost = training.cost { Text(Formats.money(cost)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                }
            }
            .padding(.vertical, Spacing.between)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("training-row")
    }
}
