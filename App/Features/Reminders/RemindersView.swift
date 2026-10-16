import HorselyCore
import HorselyKit
import SwiftUI

/// Karta „Terminy” (FR-M-TER-02): lista terminów z filtrami koń / rodzaj / status (domyślnie „Otwarty”) / zakres dat, wiersze
/// rozdzielone liniami, przeterminowane z ostrzegawczą etykietą; wiersz otwiera szczegóły z akcjami. „+” dodaje termin.
struct RemindersView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var filter = ReminderFilter()
    @State private var items: [ReminderItem] = []
    @State private var isLoaded = false
    @State private var showingFilters = false
    @State private var path: [String] = []

    /// `preloaded` — gotowa lista (testy migawkowe); zwykle widok czyta ją z magazynu.
    init(preloaded: [ReminderItem]? = nil) {
        self._items = State(initialValue: preloaded ?? [])
        self._isLoaded = State(initialValue: preloaded != nil)
    }

    private var today: LocalDate { environment.dates.today() }

    private var activeFilters: Int {
        [filter.horseId != nil, filter.kind != nil, filter.status != .open, filter.from != nil, filter.to != nil].filter { $0 }.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoaded, items.isEmpty {
                        empty
                    } else {
                        DividedList(items) { item in
                            NavigationLink(value: item.id) {
                                row(item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("reminder-row-\(item.title)")
                        }
                    }
                    Color.clear.frame(height: Spacing.addButtonClearance)
                }
                .padding(.horizontal, Spacing.screenEdge)
            }
            .background(HorselyColor.background)
            .toolbarBackground(HorselyColor.background, for: .tabBar)
            .navigationTitle("reminders_title")
            .connectionChrome()
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { id in ReminderDetailView(reminderId: id) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingFilters = true
                    } label: {
                        Text(activeFilters == 0 ? tr("sections_filters") : tr("sections_filters_active", activeFilters))
                    }
                    .accessibilityIdentifier("reminders-filters")
                }
            }
            .sheet(isPresented: $showingFilters) { filters }
            .overlay(alignment: .bottomTrailing) {
                AddEntryButton(request: EntryRequest(isReminder: true))
            }
            .task(id: LoadKey(filter: filter, revision: environment.dataRevision)) { await load() }
            .onChange(of: environment.router.pendingDestination) { _, destination in
                if case let .reminder(id) = destination {
                    path = [id]
                    environment.router.pendingDestination = nil
                }
            }
        }
    }

    private struct LoadKey: Hashable {
        let filter: ReminderFilter
        let revision: Int64
    }

    private func load() async {
        items = (try? await environment.reminders.reminders(filter)) ?? []
        isLoaded = true
    }

    private func row(_ item: ReminderItem) -> some View {
        ReminderContent(reminder: item, today: today)
            .foregroundStyle(item.isOverdue && item.status == .open ? HorselyColor.warning : HorselyColor.onBackground)
            .padding(.vertical, Spacing.cardPadding)
            .frame(minHeight: Spacing.minTouchTarget)
            .contentShape(Rectangle())
    }

    private var empty: some View {
        VStack(spacing: Spacing.between) {
            Text("reminders_empty_title").font(.headline)
            Text(activeFilters == 0 ? "reminders_empty_hint" : "reminders_empty_filtered_hint")
                .font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var filters: some View {
        NavigationStack {
            Form {
                HorsePicker(title: "reminders_filter_horse", horses: environment.horseDirectory.horses, selection: $filter.horseId, identifier: "filter-horse")
                Picker(selection: $filter.kind) {
                    Text("reminders_filter_all").tag(ReminderKind?.none)
                    ForEach(ReminderKind.allCases, id: \.self) { Text(LocalizedStringKey($0.labelKey)).tag(ReminderKind?.some($0)) }
                } label: {
                    Text("reminders_filter_kind")
                }
                Picker(selection: $filter.status) {
                    Text("reminders_filter_all").tag(ReminderStatus?.none)
                    ForEach(ReminderStatus.allCases, id: \.self) { Text(LocalizedStringKey($0.labelKey)).tag(ReminderStatus?.some($0)) }
                } label: {
                    Text("reminders_filter_status")
                }
                .accessibilityIdentifier("filter-status")
                DateField("reminders_filter_from", date: $filter.from, defaultSelection: today)
                DateField("reminders_filter_to", date: $filter.to, defaultSelection: today)
                Button(tr("reminders_filter_clear")) { filter = ReminderFilter() }
                    .disabled(activeFilters == 0)
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
