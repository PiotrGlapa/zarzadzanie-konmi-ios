import HorselyCore
import HorselyKit
import SwiftUI

/// Pulpit (FR-M-PUL): karta „Dodaj pierwszego konia” (tryb samodzielny, brak koni), szybkie dodawanie (8 chipów), obszary terminów
/// „Przeterminowane” (ostrzegawczy) · „Nadchodzące (najbliższe N dni)” (zielony) · „Później w tym miesiącu” (neutralny) albo „Brak
/// terminów do wykonania”, Koszty (ten i poprzedni miesiąc), Ostatnie wpisy oraz kafle koni po 2 w rzędzie (miniatura 40 pt, imię stajenne,
/// najbliższy termin, „bez paszportu od X mies.”, ikona kontuzji). Dół listy z zapasem 96 pt na przycisk „+”.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showingForm = false
    @State private var banner: String?
    @State private var dashboard: Dashboard?

    /// `preloaded` — gotowy Pulpit (testy migawkowe); zwykle widok czyta go z magazynu.
    init(preloaded: Dashboard? = nil) {
        self._dashboard = State(initialValue: preloaded)
    }

    private var directory: HorseDirectory { environment.horseDirectory }
    private var today: LocalDate { environment.dates.today() }

    /// Konie w stajni (aktywne i kontuzjowane), po imieniu.
    private var stableHorses: [LocalHorse] {
        HorseSearch.apply(directory.horses, query: "", filter: .inStable)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OnlineDashboardCards()
                    BackupReminderCard()
                    if directory.isLoaded, directory.horses.isEmpty, environment.workMode == .standalone {
                        addFirstHorseCard.padding(.top, Spacing.between)
                    }
                    if environment.workMode != .unset, !directory.horses.isEmpty { quickAdd }
                    if let dashboard, !directory.horses.isEmpty {
                        reminderAreas(dashboard)
                        costs(dashboard)
                        recent(dashboard)
                    }
                    if !stableHorses.isEmpty {
                        SectionHeader("dashboard_horses")
                        tiles
                    }
                    Color.clear.frame(height: Spacing.addButtonClearance)
                }
                .padding(.horizontal, Spacing.screenEdge)
            }
            .background(HorselyColor.background)
            .toolbarBackground(HorselyColor.background, for: .tabBar)
            .navigationTitle("nav_dashboard")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { id in HorseCardView(horseId: id) }
            .navigationDestination(for: EntryRoute.self) { route in EntryDetailView(route: route) }
            .navigationDestination(for: ReminderRoute.self) { route in ReminderDetailView(reminderId: route.id) }
            .sheet(isPresented: $showingForm) {
                HorseFormView(horse: nil) { banner = tr("horse_form_saved") }
            }
            .overlay(alignment: .bottom) {
                if let banner {
                    SaveBanner(message: banner, undo: nil) { self.banner = nil }.padding(.bottom, Spacing.between)
                }
            }
            .overlay(alignment: .bottomTrailing) { AddEntryButton() }
            .animation(.default, value: banner)
            .task(id: environment.dataRevision) { await load() }
            .refreshable { if environment.workMode == .online { await environment.refresh(force: true) } }
            .connectionChrome()
        }
    }

    private func load() async {
        dashboard = try? await environment.entries.dashboard()
    }

    private var addFirstHorseCard: some View {
        InfoCard(tone: .primary) {
            VStack(alignment: .leading, spacing: Spacing.between) {
                Text("dashboard_add_first_horse_title").font(.headline).accessibilityAddTraits(.isHeader)
                Text("dashboard_add_first_horse_hint").font(.subheadline)
                Button {
                    showingForm = true
                } label: {
                    Text("dashboard_add_first_horse_action").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.primaryFilled)
                .tint(HorselyColor.primary)
                .accessibilityIdentifier("dashboard-add-first-horse")
            }
        }
    }

    // MARK: Szybkie dodawanie

    private struct Chip: Identifiable {
        let id: String
        let titleKey: String
        let icon: String
        let color: Color
        let request: EntryRequest
    }

    private var chips: [Chip] {
        [
            Chip(id: "vet", titleKey: "quick_add_vet", icon: EntryAccent.vet.icon, color: EntryAccent.vet.color, request: EntryRequest(kind: .vet)),
            Chip(id: "farrier", titleKey: "quick_add_farrier", icon: EntryAccent.farrier.icon, color: EntryAccent.farrier.color, request: EntryRequest(kind: .farrier)),
            Chip(id: "farrier-many", titleKey: "quick_add_farrier_many", icon: EntryAccent.farrier.icon, color: EntryAccent.farrier.color, request: EntryRequest(kind: .farrier, manyHorses: true)),
            Chip(id: "reminder", titleKey: "quick_add_reminder", icon: SectionAccent.reminders.icon, color: SectionAccent.reminders.color, request: EntryRequest(isReminder: true)),
            Chip(id: "purchase", titleKey: "quick_add_purchase", icon: EntryAccent.purchase.icon, color: EntryAccent.purchase.color, request: EntryRequest(kind: .purchase)),
            Chip(id: "start", titleKey: "quick_add_competition", icon: EntryAccent.competition.icon, color: EntryAccent.competition.color, request: EntryRequest(kind: .start)),
            Chip(id: "training", titleKey: "quick_add_training", icon: EntryAccent.training.icon, color: EntryAccent.training.color, request: EntryRequest(kind: .training)),
            Chip(id: "note", titleKey: "quick_add_note", icon: EntryAccent.note.icon, color: EntryAccent.note.color, request: EntryRequest(kind: .note)),
        ]
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("quick_add_title")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.between) {
                    ForEach(chips) { chip in
                        Button {
                            environment.router.entryRequest = chip.request.renewed()
                        } label: {
                            HStack(spacing: 6) {
                                HIcon(name: chip.icon, size: 18).foregroundStyle(chip.color)
                                Text(LocalizedStringKey(chip.titleKey)).font(.subheadline).foregroundStyle(HorselyColor.onSecondaryContainer)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: Spacing.minTouchTarget - 4)
                            .background(HorselyColor.secondaryContainer, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quick-add-\(chip.id)")
                    }
                }
            }
        }
    }

    // MARK: Terminy

    @ViewBuilder
    private func reminderAreas(_ dashboard: Dashboard) -> some View {
        if dashboard.overdue.isEmpty, dashboard.upcoming.isEmpty, dashboard.laterThisMonth.isEmpty {
            InfoCard {
                Text("dashboard_nothing_due").font(.subheadline)
            }
            .padding(.top, Spacing.beforeSection)
            .accessibilityIdentifier("dashboard-nothing-due")
        } else {
            if !dashboard.overdue.isEmpty { area(LocalizedStringKey("dashboard_overdue"), dashboard.overdue, tone: .warning, id: "dashboard-overdue") }
            if !dashboard.upcoming.isEmpty {
                area(LocalizedStringKey(trPlural("dashboard_upcoming", dashboard.horizonDays)), dashboard.upcoming, tone: .primary, id: "dashboard-upcoming")
            }
            if !dashboard.laterThisMonth.isEmpty { area(LocalizedStringKey("dashboard_later"), dashboard.laterThisMonth, tone: .neutral, id: "dashboard-later") }
        }
    }

    private func area(_ title: LocalizedStringKey, _ items: [ReminderItem], tone: InfoTone, id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title)
            InfoCard(tone: tone) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { DividerLine(inset: 0).padding(.vertical, 6) }
                        NavigationLink(value: ReminderRoute(id: item.id)) {
                            ReminderContent(reminder: item, today: today)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(tr("reminders_open"))
                    }
                }
            }
        }
        .accessibilityIdentifier(id)
    }

    // MARK: Koszty

    private func costs(_ dashboard: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("dashboard_costs")
            HStack(alignment: .top, spacing: Spacing.between + 4) {
                costCard("dashboard_costs_this_month", dashboard.costsThisMonth, id: "dashboard-costs-this")
                costCard("dashboard_costs_previous_month", dashboard.costsPreviousMonth, id: "dashboard-costs-previous")
            }
        }
    }

    private func costCard(_ title: LocalizedStringKey, _ amount: Money, id: String) -> some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote)
                Text(Formats.money(amount)).font(.title3.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: Ostatnie wpisy

    @ViewBuilder
    private func recent(_ dashboard: Dashboard) -> some View {
        if !dashboard.recentEntries.isEmpty {
            SectionHeader("dashboard_recent")
            DividedList(dashboard.recentEntries) { item in
                NavigationLink(value: EntryRoute(recordType: item.entryType.recordType, id: item.id)) {
                    TimelineRow(item: item, showsHorse: true)
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("dashboard-recent")
        }
    }

    // MARK: Konie

    private var tiles: some View {
        let rows = stride(from: 0, to: stableHorses.count, by: 2).map { Array(stableHorses[$0..<min($0 + 2, stableHorses.count)]) }
        return Grid(horizontalSpacing: Spacing.between + 4, verticalSpacing: Spacing.between + 4) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { horse in tile(horse) }
                    if row.count == 1 { Color.clear }
                }
            }
        }
    }

    private func tile(_ horse: LocalHorse) -> some View {
        let months = HorseRules.monthsWithoutPassport(of: horse, on: today)
        let warns = HorseDescription.isForgottenPassport(horse, today: today)
        let next = dashboard?.horses.first { $0.horseId == horse.id }
        return NavigationLink(value: horse.id) {
            HStack(alignment: .top, spacing: Spacing.between) {
                VStack(alignment: .leading, spacing: 4) {
                    HorseAvatar(photo: directory.thumbnail(for: horse), diameter: 40)
                    Text(horse.name).font(.body.weight(.semibold)).foregroundStyle(warns ? HorselyColor.onWarningContainer : HorselyColor.onBackground)
                    if let stable = HorseDescription.stableName(horse) {
                        Text(stable).font(.footnote).foregroundStyle(warns ? HorselyColor.onWarningContainer : HorselyColor.onSurfaceVariant)
                    }
                    if let next, let date = next.nextReminderDate, let title = next.nextReminderTitle {
                        Text(tr("dashboard_horse_next", title, Formats.date(date)))
                            .font(.footnote.weight(next.isNextReminderOverdue ? .bold : .regular))
                            .foregroundStyle(next.isNextReminderOverdue ? HorselyColor.warning : (warns ? HorselyColor.onWarningContainer : HorselyColor.onSurfaceVariant))
                    }
                    if let months, horse.isFoal {
                        Text(trPlural("foal_months_without_passport", months))
                            .font(.footnote)
                            .foregroundStyle(warns ? HorselyColor.onWarningContainer : HorselyColor.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                if horse.status == .injured {
                    HIcon(name: "healing", size: 24).foregroundStyle(HorselyColor.warning)
                }
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(warns ? HorselyColor.warningContainer : HorselyColor.surfaceVariant, in: RoundedRectangle(cornerRadius: Spacing.cardRadius))
            .overlay {
                if warns { RoundedRectangle(cornerRadius: Spacing.cardRadius).strokeBorder(HorselyColor.warning, lineWidth: Spacing.cardBorder) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(HorseDescription.accessibilityName(horse))
        .accessibilityHint(tr("dashboard_open_horse", horse.name))
        .accessibilityIdentifier("horse-tile-\(horse.name)")
    }
}

/// Termin wskazany z listy (Pulpit, zakładka konia).
struct ReminderRoute: Hashable {
    let id: String
}
