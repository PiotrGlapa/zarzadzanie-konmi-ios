import HorselyCore
import HorselyKit
import SwiftUI

/// Dział Zawody (T101, US11/4): zawody (nazwa, data od–do, miejscowość, dyscyplina, liczba startów, najlepsze miejsce), filtry
/// (okres, dyscyplina, koń), „+” — formularz zawodów.
struct CompetitionsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var list: [CompetitionListItem]?
    @State private var names = SectionNames()
    @State private var showingFilters = false

    struct Route: Hashable {
        let id: String
    }

    var body: some View {
        @Bindable var filters = environment.sectionFilters
        let today = environment.dates.today()
        ScrollView {
            if let list {
                if list.isEmpty {
                    SectionEmpty(title: "competitions_empty_title", hint: "competitions_empty_hint")
                } else {
                    DividedList(list) { item in
                        NavigationLink(value: Route(id: item.id)) { row(item) }.buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            }
            Color.clear.frame(height: Spacing.addButtonClearance)
        }
        .safeAreaInset(edge: .bottom) {
            if let list { SectionFooter(text: tr("competitions_summary", list.count), identifier: "competitions-summary") }
        }
        .background(HorselyColor.background)
        .navigationTitle(tr("nav_competitions"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FiltersButton(active: filters.competitions.activeCount(today: today)) { showingFilters = true }
            }
        }
        .connectionChrome()
        .navigationDestination(for: Route.self) { CompetitionDetailView(competitionId: $0.id) }
        .navigationDestination(for: EntryRoute.self) { EntryDetailView(route: $0) }
        .overlay(alignment: .bottomTrailing) { AddEntryButton(request: EntryRequest(kind: .competition)) }
        .task(id: LoadKey(query: filters.competitions, revision: environment.dataRevision)) {
            await names.load(using: environment)
            list = try? await environment.entries.competitions(filters.competitions)
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                Form {
                    PeriodFields(period: $filters.competitions.period, today: today)
                    OptionalPicker(title: "competitions_filter_discipline", selection: $filters.competitions.disciplineId,
                                   options: names.items(.competitionDiscipline).map { (id: $0.id, name: $0.value) })
                    OptionalPicker(title: "competitions_filter_horse", selection: $filters.competitions.horseId,
                                   options: environment.horseDirectory.horses.map { (id: $0.id, name: $0.name) })
                    Button(tr("sections_clear_filters")) { filters.competitions = CompetitionQuery(period: .default(today: today)) }
                        .disabled(filters.competitions.activeCount(today: today) == 0)
                        .accessibilityIdentifier("section-clear-filters")
                }
                .navigationTitle("sections_filters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("sections_filters_done")) { showingFilters = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private struct LoadKey: Hashable {
        let query: CompetitionQuery
        let revision: Int64
    }

    static func dates(_ competition: LocalCompetition) -> String {
        guard let to = competition.dateTo, to != competition.dateFrom else { return Formats.date(competition.dateFrom) }
        return "\(Formats.date(competition.dateFrom)) – \(Formats.date(to))"
    }

    private func row(_ item: CompetitionListItem) -> some View {
        let competition = item.competition
        var details = [Self.dates(competition)]
        if let city = competition.city { details.append(city) }
        if let discipline = names.dictionaryName(competition.disciplineId) { details.append(discipline) }
        var results = [trPlural("competitions_starts_count", item.startsCount)]
        if let best = item.bestPlacement { results.append(tr("competitions_best_place", best)) }
        return AccentRow(color: EntryAccent.competition.color) {
            HStack(alignment: .top, spacing: Spacing.between) {
                HIcon(name: EntryAccent.competition.icon, size: 24).foregroundStyle(EntryAccent.competition.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(competition.name).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                    Text(details.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    Text(results.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    RecordMarkerLabel(type: .competition, id: competition.id)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.between)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("competition-row")
    }
}

/// Szczegóły zawodów: dane zawodów i starty (jeździec, klasa, miejsce, ocena gwiazdkami, koszty, nagroda), „Dodaj start”,
/// „Edytuj”, „Usuń” z potwierdzeniem (odmowa programu pokazana bez zmian).
struct CompetitionDetailView: View {
    let competitionId: String
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var detail: CompetitionDetail?
    @State private var loaded = false
    @State private var names = SectionNames()
    @State private var editing: EntryFormModel?
    @State private var confirmingDelete = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.beforeSection) {
                if let detail {
                    content(detail)
                } else if loaded {
                    Text("competitions_not_found").frame(maxWidth: .infinity).padding(.vertical, 32)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }
            .padding(Spacing.screenEdge)
        }
        .background(HorselyColor.background)
        .navigationTitle(detail?.competition.name ?? tr("nav_competitions"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let competition = detail?.competition {
                ToolbarItem(placement: .primaryAction) {
                    Button(tr("competitions_edit")) {
                        editing = EntryFormModel(kind: .competition, editing: competition, today: environment.dates.today(), now: environment.dates.now())
                    }
                    .accessibilityIdentifier("competition-edit")
                }
            }
        }
        .task(id: environment.dataRevision) {
            await names.load(using: environment)
            detail = try? await environment.entries.competitionDetail(id: competitionId)
            loaded = true
        }
        .sheet(item: $editing) { model in
            EntryFormView(model: model) { saved, _ in
                Task {
                    let text = await environment.messageAfterSave(saved, edited: true)
                    environment.router.banner = BannerMessage(text: text) { Task { try? await environment.entries.undo(saved.undo) } }
                }
            }
            .environment(environment)
        }
        .confirmationDialog(tr("competitions_delete_title"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(tr("competitions_delete"), role: .destructive) { delete() }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text(tr("competitions_delete_message", detail?.competition.name ?? ""))
        }
    }

    @ViewBuilder private func content(_ detail: CompetitionDetail) -> some View {
        let competition = detail.competition
        if let message { InfoCard(tone: .warning) { Text(message).font(.subheadline) } }
        VStack(alignment: .leading, spacing: Spacing.between) {
            field("competitions_detail_dates", CompetitionsView.dates(competition))
            field("competitions_detail_city", competition.city)
            field("competitions_detail_venue", competition.venue)
            field("competitions_detail_rank", names.dictionaryName(competition.rankId))
            field("competitions_detail_discipline", names.dictionaryName(competition.disciplineId))
            field("competitions_detail_organizer", names.contactName(competition.organizerContactId))
            field("competitions_detail_notes", competition.notes)
        }
        SectionHeader("competitions_starts_title")
        if detail.starts.isEmpty {
            Text("competitions_starts_empty").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
        } else {
            DividedList(detail.starts) { start in
                NavigationLink(value: EntryRoute(recordType: .competitionStart, id: start.id)) { startRow(start) }.buttonStyle(.plain)
            }
            .padding(.horizontal, -Spacing.screenEdge)
        }
        Button {
            var request = EntryRequest(kind: .start)
            request.horseId = nil
            environment.router.entryRequest = request
        } label: {
            Text("competitions_add_start").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
        }
        .buttonStyle(.bordered)
        .tint(HorselyColor.primary)
        .accessibilityIdentifier("competition-add-start")
        Button(role: .destructive) { confirmingDelete = true } label: {
            Text("competitions_delete").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("competition-delete")
    }

    @ViewBuilder private func field(_ key: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(key).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                Text(value).font(.body)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func startRow(_ start: LocalCompetitionStart) -> some View {
        var lines: [String] = []
        if let rider = names.contactName(start.riderContactId) { lines.append(rider) }
        if let className = start.className { lines.append(className) }
        if let place = start.placement { lines.append(tr("competitions_start_result", place)) }
        var money: [String] = []
        let costs = (start.entryFee ?? .zero) + (start.otherCosts ?? .zero)
        if costs != .zero { money.append(tr("competitions_start_costs", Formats.money(costs))) }
        if let prize = start.prizeMoney { money.append(tr("competitions_start_prize", Formats.money(prize))) }
        return VStack(alignment: .leading, spacing: 2) {
            Text(environment.horseDirectory.horses.first { $0.id == start.horseId }?.name ?? Formats.dash).font(.body.weight(.semibold))
            if !lines.isEmpty { Text(lines.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
            if start.subjectiveRating != nil { StarRatingDisplay(rating: start.subjectiveRating).font(.footnote) }
            if !money.isEmpty { Text(money.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
            RecordMarkerLabel(type: .competitionStart, id: start.id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.between)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func delete() {
        Task {
            switch try? await environment.entries.delete(.competition, id: competitionId) {
            case let .saved(saved)?:
                environment.router.banner = BannerMessage(text: tr("competitions_deleted")) { Task { try? await environment.entries.undo(saved.undo) } }
                dismiss()
            case let .rejected(problem)?:
                message = problem.message
            case nil:
                message = tr("pairing_error_other")
            }
        }
    }
}
