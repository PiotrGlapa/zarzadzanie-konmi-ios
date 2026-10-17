import HorselyCore
import HorselyKit
import SwiftUI

/// Filtr raportów jeźdźca: jeździec (albo wszyscy), koń, okres (domyślnie bez ograniczeń).
struct RiderReportFilter: Hashable {
    var riderId: String?
    var horseId: String?
    var period: ReportPeriod = .custom
    var from: LocalDate?
    var to: LocalDate?

    func range(today: LocalDate) -> (from: LocalDate?, to: LocalDate?) {
        if let range = period.range(today: today) { return (range.from, range.to) }
        return (from, to)
    }
}

/// Pola arkusza filtrów raportów jeźdźca.
struct RiderReportFilterFields: View {
    @Binding var filter: RiderReportFilter
    let riders: [(id: String, name: String)]
    let horses: [(id: String, name: String)]
    let today: LocalDate

    var body: some View {
        Picker(selection: $filter.riderId) {
            Text(ReportTexts.allRiders).tag(String?.none)
            ForEach(riders, id: \.id) { Text($0.name).tag(String?.some($0.id)) }
        } label: {
            Text("reports_rider")
        }
        OptionalPicker(title: "reports_horse_single", selection: $filter.horseId, options: horses)
        ReportPeriodPicker(period: $filter.period, from: $filter.from, to: $filter.to, today: today)
    }
}

enum RiderReportSupport {
    @MainActor
    static func riders(_ names: SectionNames) -> [(id: String, name: String)] {
        names.contacts(.rider).filter { !$0.isArchived }
            .sorted { PolishNames.compare($0.name, $1.name) == .orderedAscending }
            .map { (id: $0.id, name: $0.name) }
    }

    static func filterLines(riderName: String?, horseName: String?, from: LocalDate?, to: LocalDate?) -> [String] {
        var lines = ["\(ReportTexts.rider): \(riderName ?? ReportTexts.allRiders)"]
        if let horseName { lines.append(ReportTexts.filterHorses(horseName)) }
        if let period = ReportFormat.period(from, to) { lines.append(period) }
        return lines
    }
}

/// Treningi jeźdźca (FR-M-RAP-04; 2.0.2 FR-012…FR-017): na górze podsumowanie (kafelki), wykres słupkowy grup z przełącznikiem
/// miary, karty grup, a treningi zwinięte pod „Pokaż treningi (N)”. CSV i PDF mają te same wartości co w 2.0.1; PDF dodatkowo
/// zawiera oba warianty wykresu.
struct RiderTrainingsReportView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var filter: RiderReportFilter
    @State private var names = SectionNames()
    @State private var load: ReportLoad<RiderTrainingsReport> = .loading
    @State private var pdfCharts: [ChartImage] = []

    /// `riderId` — jeździec wybrany od początku (zrzuty ekranu); domyślnie wszyscy jeźdźcy.
    init(riderId: String? = nil) {
        _filter = State(initialValue: RiderReportFilter(riderId: riderId))
    }

    var body: some View {
        let today = environment.dates.today()
        let range = filter.range(today: today)
        let horses = ReportOptions.horses(environment)
        let table = load.report.map(ReportTables.riderTrainings)
        ReportScaffold(
            titleKey: "reports_rider_trainings", table: table, isEmpty: load.report?.rows.isEmpty ?? true, fromMemory: load.fromMemory,
            fetchedAt: load.fetchedAt,
            filterLines: RiderReportSupport.filterLines(riderName: names.contactName(filter.riderId), horseName: horses.first { $0.id == filter.horseId }?.name,
                                                        from: range.from, to: range.to),
            failure: load.failure, loading: load.isLoading, pdfCharts: pdfCharts,
            fileName: ReportFormat.fileName(table?.title ?? ReportTexts.riderTrainingsTitle, today: today, fromMemory: load.fromMemory, fetchedAt: load.fetchedAt),
            showsTotals: false, collapsibleRows: true
        ) {
            if let report = load.report { RiderTrainingsSummaryView(report: report) }
        } filters: {
            RiderReportFilterFields(filter: $filter, riders: RiderReportSupport.riders(names), horses: horses, today: today)
        }
        .task { await names.load(using: environment) }
        .task(id: LoadKey(riderId: filter.riderId, horseId: filter.horseId, from: range.from, to: range.to, revision: environment.dataRevision)) {
            let current = filter
            load = await ReportLoad.run {
                try await environment.reports.riderTrainings(riderId: current.riderId, from: range.from, to: range.to, horseId: current.horseId)
            }
            pdfCharts = load.report.map(Self.chartImages) ?? []
        }
    }

    /// Oba warianty wykresu grup do PDF (liczba, czas) z opisem tekstowym.
    private static func chartImages(_ report: RiderTrainingsReport) -> [ChartImage] {
        GroupMetric.allCases.compactMap { metric in
            guard let chart = ReportCharts.riderGroups(report, metric: metric) else { return nil }
            return ChartRendering.image(GroupBarChartView(chart: chart), title: "\(tr("reports_chart_rider_groups_title")) — \(metric.label)",
                                        description: ChartDescriptions.groupBars(chart))
        }
    }
}

/// Podsumowanie „Treningów jeźdźca” w miejscu sum i wykresów: kafelki z `report.total` (liczba, łączny czas, średnia ocena,
/// koszt), przełącznik „Liczba treningów / Łączny czas” z wykresem grup i karty grup (konie albo jeźdźcy).
struct RiderTrainingsSummaryView: View {
    let report: RiderTrainingsReport
    @State private var metric: GroupMetric = .count
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let ratingColumn = ReportColumn(ReportTexts.trainingRating, .decimal1)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.beforeSection) {
            tiles
            if let chart = ReportCharts.riderGroups(report, metric: metric) {
                InfoCard(tone: .neutral) {
                    VStack(alignment: .leading, spacing: Spacing.between) {
                        Picker(selection: $metric) {
                            ForEach(GroupMetric.allCases, id: \.self) { Text($0.label).tag($0) }
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("report-chart-metric")
                        GroupBarChartView(chart: chart)
                    }
                }
            }
            ForEach(Array(report.groups.enumerated()), id: \.offset) { index, group in
                groupCard(group)
                    .accessibilityIdentifier("report-group-\(index)")
            }
        }
    }

    private var tiles: some View {
        let total = report.total
        return InfoCard(tone: .primary) {
            // Przy dużym tekście (dostępność) jedna kolumna — etykiety i kwoty nie łamią się w środku słowa.
            let columns = typeSize.isAccessibilitySize
                ? [GridItem(.flexible(), alignment: .topLeading)]
                : [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.between) {
                tile(tr("reports_chart_metric_count"), String(total.count))
                tile(tr("reports_chart_metric_time"), Formats.duration(minutes: total.totalMinutes))
                tile(ReportTexts.trainingRating, TabularReport.display(Self.ratingColumn, total.averageRating.map(ReportValue.number)))
                tile(ReportTexts.trainingCost, Formats.money(total.totalCost))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("report-totals")
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.7)
        }
    }

    private func groupCard(_ group: RiderTrainingsGroup) -> some View {
        InfoCard(tone: .neutral) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ReportTexts.groupTrainings(group.name, group.count)).font(.body.weight(.semibold))
                LabelValueRow(label: ReportTexts.trainingTime, value: Formats.duration(minutes: group.totalMinutes), numeric: true)
                LabelValueRow(label: ReportTexts.trainingRating, value: TabularReport.display(Self.ratingColumn, group.averageRating.map(ReportValue.number)), numeric: true)
                LabelValueRow(label: ReportTexts.trainingCost, value: Formats.money(group.totalCost), numeric: true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Zawody jeźdźca (FR-M-RAP-05): zawody i starty jednego jeźdźca albo wszystkich, koszty, nagrody i bilans.
struct RiderCompetitionsReportView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var filter = RiderReportFilter()
    @State private var names = SectionNames()
    @State private var load: ReportLoad<RiderCompetitionsReport> = .loading

    var body: some View {
        let today = environment.dates.today()
        let range = filter.range(today: today)
        let horses = ReportOptions.horses(environment)
        let table = load.report.map(ReportTables.riderCompetitions)
        ReportScaffold(
            titleKey: "reports_rider_competitions", table: table, isEmpty: load.report?.competitions.isEmpty ?? true, fromMemory: load.fromMemory,
            fetchedAt: load.fetchedAt,
            filterLines: RiderReportSupport.filterLines(riderName: names.contactName(filter.riderId), horseName: horses.first { $0.id == filter.horseId }?.name,
                                                        from: range.from, to: range.to),
            failure: load.failure, loading: load.isLoading, pdfCharts: [],
            fileName: ReportFormat.fileName(table?.title ?? ReportTexts.riderCompetitionsTitle, today: today, fromMemory: load.fromMemory,
                                            fetchedAt: load.fetchedAt)
        ) {
            EmptyView()
        } filters: {
            RiderReportFilterFields(filter: $filter, riders: RiderReportSupport.riders(names), horses: horses, today: today)
        }
        .task { await names.load(using: environment) }
        .task(id: LoadKey(riderId: filter.riderId, horseId: filter.horseId, from: range.from, to: range.to, revision: environment.dataRevision)) {
            let current = filter
            load = await ReportLoad.run {
                try await environment.reports.riderCompetitions(riderId: current.riderId, from: range.from, to: range.to, horseId: current.horseId)
            }
        }
    }
}

private struct LoadKey: Hashable {
    let riderId: String?
    let horseId: String?
    let from: LocalDate?
    let to: LocalDate?
    let revision: Int64
}
