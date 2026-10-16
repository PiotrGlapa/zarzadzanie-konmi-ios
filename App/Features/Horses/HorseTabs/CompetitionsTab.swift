import HorselyCore
import HorselyKit
import SwiftUI

/// Zawody konia: statystyki startów (Starty · Zwycięstwa · Podia · Średnia ocena · Nagrody · Koszty) i lista startów z miejscem,
/// wpisowym i nagrodą; „Dodaj start”.
struct CompetitionsTab: View {
    @Environment(AppEnvironment.self) private var environment
    let horseId: String
    @State private var starts: [HorseStart]?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            TabAddButton(title: "competitions_add_start", request: EntryRequest(kind: .start, horseId: horseId), identifier: "starts-add")
            if let starts {
                if starts.isEmpty {
                    TabEmptyText(key: "horse_starts_empty")
                } else {
                    statistics(EntryRepository.statistics(starts))
                    DividedList(starts) { item in
                        NavigationLink(value: EntryRoute(recordType: .competitionStart, id: item.id)) { row(item) }
                            .buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
        .task(id: environment.dataRevision) {
            starts = try? await environment.entries.starts(horseId: horseId)
        }
    }

    private func statistics(_ stats: StartStatistics) -> some View {
        let rating = stats.averageRating.map { String(format: "%.1f", locale: Locale(identifier: "pl_PL"), $0) } ?? Formats.dash
        let cells: [(LocalizedStringKey, String)] = [
            ("horse_stats_starts", String(stats.starts)), ("horse_stats_wins", String(stats.wins)), ("horse_stats_podiums", String(stats.podiums)),
            ("horse_stats_rating", rating), ("horse_stats_prizes", Formats.money(stats.prizes)), ("horse_stats_costs", Formats.money(stats.costs)),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.between), GridItem(.flexible(), spacing: Spacing.between)], spacing: Spacing.between) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                InfoCard {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cell.0).font(.footnote)
                        Text(cell.1).font(.title3.weight(.semibold))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func row(_ item: HorseStart) -> some View {
        let start = item.start
        var details: [String] = []
        if let place = start.placement { details.append(tr("competitions_start_result", place)) }
        if let name = HorseRules.clean(start.className) { details.append(name) }
        if let status = start.resultStatus, status != .completed { details.append(tr(status.labelKey)) }
        var money: [String] = []
        let costs = (start.entryFee ?? .zero) + (start.otherCosts ?? .zero)
        if costs.value > 0 { money.append(tr("competitions_start_costs", Formats.money(costs))) }
        if let prize = start.prizeMoney, prize.value > 0 { money.append(tr("competitions_start_prize", Formats.money(prize))) }
        return AccentRow(color: EntryAccent.competition.color) {
            HStack(alignment: .top, spacing: Spacing.between) {
                HIcon(name: EntryAccent.competition.icon, size: 24).foregroundStyle(EntryAccent.competition.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.competitionName).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                    if !details.isEmpty { Text(details.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                    if !money.isEmpty { Text(money.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let date = item.date { Text(Formats.date(date)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
            }
            .padding(.vertical, Spacing.between)
        }
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
