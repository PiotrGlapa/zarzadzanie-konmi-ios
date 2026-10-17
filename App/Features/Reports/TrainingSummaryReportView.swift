import HorselyCore
import HorselyKit
import SwiftUI

/// Podsumowanie treningów konia (FR-M-RAP-03): zakres tydzień / miesiąc / rok / wszystko (domyślnie miesiąc z dniem dzisiejszym),
/// przejście do poprzedniego i następnego okresu, wykres postępu wybranego parametru, wiersze typów treningu i „Razem”.
struct TrainingSummaryReportView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var horseId: String?
    @State private var range: TrainingRange = .month
    @State private var anchor: LocalDate?
    @State private var parameter: TrainingParameter = .duration
    @State private var load: ReportLoad<TrainingSummaryReport> = .loading
    @State private var pdfCharts: [ChartImage] = []

    var body: some View {
        let today = environment.dates.today()
        let horses = ReportOptions.horses(environment)
        if environment.horseDirectory.isLoaded && horses.isEmpty {
            ScrollView {
                InfoCard(tone: .neutral) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("reports_no_horses_title").font(.headline)
                        Text("reports_no_horses_hint").font(.subheadline)
                    }
                }
                .padding(Spacing.screenEdge)
            }
            .background(HorselyColor.background)
            .navigationTitle("reports_training_summary")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            content(today: today, horses: horses)
        }
    }

    private func content(today: LocalDate, horses: [(id: String, name: String)]) -> some View {
        let selectedHorse = horseId ?? horses.first?.id
        let day = anchor ?? today
        let report = load.report
        let parameters = report.map(ReportCharts.availableParameters) ?? []
        let shown = parameters.contains(parameter) ? parameter : parameters.first
        // Sumy „Razem” stoją teraz nad wykresem (jak w Androidzie), więc przejście między okresami zostaje nad nimi, przy filtrach.
        let navigator: AnyView? = range == .all ? nil : AnyView(
            HStack {
                Button { anchor = Self.shift(day, range, by: -1) } label: {
                    Image(systemName: "chevron.left").frame(minWidth: Spacing.minTouchTarget, minHeight: Spacing.minTouchTarget)
                }
                .accessibilityLabel(tr("reports_previous_period"))
                .accessibilityIdentifier("report-previous-period")
                Text(ReportFormat.period(range.period(day).from, range.period(day).to) ?? "")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                Button { anchor = Self.shift(day, range, by: 1) } label: {
                    Image(systemName: "chevron.right").frame(minWidth: Spacing.minTouchTarget, minHeight: Spacing.minTouchTarget)
                }
                .accessibilityLabel(tr("reports_next_period"))
                .accessibilityIdentifier("report-next-period")
            }
        )
        return ReportScaffold(
            titleKey: "reports_training_summary", table: report.map(ReportTables.trainingSummary), isEmpty: report?.isEmpty ?? true,
            fromMemory: load.fromMemory, fetchedAt: load.fetchedAt, filterLines: filterLines(report), failure: load.failure, loading: load.isLoading,
            pdfCharts: pdfCharts,
            fileName: ReportFormat.fileName(ReportTexts.trainingSummaryTitle + (report.map { " — \($0.horseName)" } ?? ""), today: today,
                                            fromMemory: load.fromMemory, fetchedAt: load.fetchedAt),
            accessory: navigator
        ) {
            if let report, let shown, let chart = ReportCharts.progress(report, shown) {
                InfoCard(tone: .neutral) {
                    VStack(alignment: .leading, spacing: Spacing.between) {
                        if parameters.count > 1 {
                            Picker(selection: Binding(get: { shown }, set: { parameter = $0 })) {
                                ForEach(parameters, id: \.self) { Text($0.label).tag($0) }
                            } label: {
                                EmptyView()
                            }
                            .pickerStyle(.segmented)
                        }
                        LineChartView(chart: chart)
                    }
                }
            }
        } filters: {
            Picker(selection: Binding(get: { selectedHorse ?? "" }, set: { horseId = $0 })) {
                ForEach(horses, id: \.id) { Text($0.name).tag($0.id) }
            } label: {
                Text("reports_horse_single")
            }
            Picker(selection: $range) {
                Text("reports_range_week").tag(TrainingRange.week)
                Text("reports_range_month").tag(TrainingRange.month)
                Text("reports_range_year").tag(TrainingRange.year)
                Text("reports_range_all").tag(TrainingRange.all)
            } label: {
                Text("reports_range")
            }
            .pickerStyle(.segmented)
        }
        .task(id: LoadKey(horseId: selectedHorse, range: range, anchor: day, revision: environment.dataRevision)) {
            guard let selectedHorse else { return }
            load = await ReportLoad.run { try await environment.reports.trainingSummary(horseId: selectedHorse, range: range, anchor: day) }
            var images: [ChartImage] = []
            if let report = load.report {
                for item in ReportCharts.availableParameters(report) {
                    if let chart = ReportCharts.progress(report, item),
                       let image = ChartRendering.image(LineChartView(chart: chart), title: ChartDescriptions.progressTitle(item), description: ChartDescriptions.lines(chart)) {
                        images.append(image)
                    }
                }
            }
            pdfCharts = images
        }
    }

    private struct LoadKey: Hashable {
        let horseId: String?
        let range: TrainingRange
        let anchor: LocalDate
        let revision: Int64
    }

    static func shift(_ day: LocalDate, _ range: TrainingRange, by step: Int) -> LocalDate {
        switch range {
        case .week: day.adding(days: 7 * step)
        case .month: day.adding(months: step)
        case .year: day.adding(months: 12 * step)
        case .all: day
        }
    }

    private func filterLines(_ report: TrainingSummaryReport?) -> [String] {
        guard let report else { return [] }
        var lines = [ReportTexts.filterHorses(report.horseName)]
        if let period = ReportFormat.period(report.from, report.to) { lines.append(period) }
        return lines
    }
}
