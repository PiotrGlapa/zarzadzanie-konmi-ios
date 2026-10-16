import HorselyCore
import HorselyKit
import SwiftUI

/// Raport kosztów (FR-M-RAP-01): okres (domyślnie bieżący rok), konie (wszystkie / wybrane / tylko ogólne), kategorie, grupowanie;
/// wykres miesięczny po kategoriach i udział kategorii; wiersze, sumy, eksport CSV/PDF.
struct CostReportView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var period: ReportPeriod = .currentYear
    @State private var from: LocalDate?
    @State private var to: LocalDate?
    @State private var horseScope: HorseScope = .all
    @State private var horseIds: [String] = []
    @State private var categories: [String] = []
    @State private var groupBy: CostGroupBy = .month
    @State private var load: ReportLoad<CostReport> = .loading
    @State private var knownCategories: [String] = []
    @State private var pdfCharts: [ChartImage] = []

    enum HorseScope: String, CaseIterable {
        case all, selected, general

        var key: LocalizedStringKey {
            switch self {
            case .all: "reports_horses_all"
            case .selected: "reports_horses_selected"
            case .general: "reports_horses_general"
            }
        }
    }

    var body: some View {
        let today = environment.dates.today()
        let current = makeFilter(today: today)
        let table = load.report.map(ReportTables.costs)
        ReportScaffold(
            titleKey: "reports_cost", table: table, isEmpty: load.report?.rows.isEmpty ?? true, fromMemory: load.fromMemory, fetchedAt: load.fetchedAt,
            filterLines: filterLines(current), failure: load.failure, loading: load.isLoading, pdfCharts: pdfCharts,
            fileName: ReportFormat.fileName(ReportTexts.costTitle, today: today, fromMemory: load.fromMemory, fetchedAt: load.fetchedAt)
        ) {
            if let report = load.report {
                if let bars = ReportCharts.monthlyCosts(report) {
                    InfoCard(tone: .neutral) { StackedBarChartView(chart: bars) }
                }
                if let pie = ReportCharts.categoryShare(report) {
                    InfoCard(tone: .neutral) { PieChartView(chart: pie) }
                }
            }
        } filters: {
            ReportPeriodPicker(period: $period, from: $from, to: $to, today: today)
            Section {
                Picker(selection: $horseScope) {
                    ForEach(HorseScope.allCases, id: \.self) { Text($0.key).tag($0) }
                } label: {
                    Text("reports_horses")
                }
                if horseScope == .selected {
                    MultiToggleList(options: ReportOptions.horses(environment), selection: $horseIds)
                }
            }
            if !knownCategories.isEmpty {
                Section {
                    MultiToggleList(options: knownCategories.map { (id: $0, name: $0) }, selection: $categories)
                } header: {
                    Text("reports_categories")
                } footer: {
                    if categories.isEmpty { Text("reports_categories_all") }
                }
            }
            Picker(selection: $groupBy) {
                ForEach(CostGroupBy.allCases, id: \.self) { Text(Self.label($0)).tag($0) }
            } label: {
                Text("reports_group_by")
            }
            .pickerStyle(.segmented)
        }
        .task(id: LoadKey(filter: current, revision: environment.dataRevision)) {
            load = await ReportLoad.run { try await environment.reports.costs(current) }
            guard let report = load.report else { return }
            for row in report.rows {
                if let category = row.category, !knownCategories.contains(category) { knownCategories.append(category) }
            }
            var images: [ChartImage] = []
            if let bars = ReportCharts.monthlyCosts(report),
               let image = ChartRendering.image(StackedBarChartView(chart: bars), title: ChartDescriptions.monthlyTitle, description: ChartDescriptions.bars(bars)) {
                images.append(image)
            }
            if let pie = ReportCharts.categoryShare(report),
               let image = ChartRendering.image(PieChartView(chart: pie), title: ChartDescriptions.shareTitle, description: ChartDescriptions.pie(pie)) {
                images.append(image)
            }
            pdfCharts = images
        }
    }

    private struct LoadKey: Hashable {
        let filter: CostFilter
        let revision: Int64
    }

    private func makeFilter(today: LocalDate) -> CostFilter {
        let range = period.range(today: today)
        return CostFilter(
            from: range?.from ?? from, to: range?.to ?? to, horseIds: horseScope == .selected ? horseIds : [], generalOnly: horseScope == .general,
            categories: categories, groupBy: groupBy
        )
    }

    private func filterLines(_ filter: CostFilter) -> [String] {
        var lines: [String] = []
        if let period = ReportFormat.period(filter.from, filter.to) { lines.append(period) }
        if filter.generalOnly {
            lines.append(ReportTexts.filterHorses(ReportTexts.general))
        } else if !filter.horseIds.isEmpty {
            lines.append(ReportTexts.filterHorses(ReportOptions.horses(environment).filter { filter.horseIds.contains($0.id) }.map(\.name).joined(separator: ", ")))
        }
        if !filter.categories.isEmpty { lines.append(ReportTexts.filterCategories(filter.categories.joined(separator: ", "))) }
        lines.append(ReportTexts.filterGroupBy(Self.label(filter.groupBy)))
        return lines
    }

    static func label(_ groupBy: CostGroupBy) -> String {
        switch groupBy {
        case .horse: ReportTexts.horse
        case .month: ReportTexts.month
        case .category: ReportTexts.category
        }
    }
}

/// Opcje filtrów raportów.
@MainActor
enum ReportOptions {
    /// Wszystkie konie (także sprzedane) w kolejności alfabetycznej.
    static func horses(_ environment: AppEnvironment) -> [(id: String, name: String)] {
        environment.horseDirectory.horses
            .sorted { PolishNames.compare($0.name, $1.name) == .orderedAscending }
            .map { (id: $0.id, name: $0.name) }
    }
}
