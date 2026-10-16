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

/// Treningi jeźdźca (FR-M-RAP-04): treningi jednego jeźdźca albo wszystkich w okresie, sumy po jeźdźcach albo koniach.
struct RiderTrainingsReportView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var filter = RiderReportFilter()
    @State private var names = SectionNames()
    @State private var load: ReportLoad<RiderTrainingsReport> = .loading

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
            failure: load.failure, loading: load.isLoading, pdfCharts: [],
            fileName: ReportFormat.fileName(table?.title ?? ReportTexts.riderTrainingsTitle, today: today, fromMemory: load.fromMemory, fetchedAt: load.fetchedAt)
        ) {
            EmptyView()
        } filters: {
            RiderReportFilterFields(filter: $filter, riders: RiderReportSupport.riders(names), horses: horses, today: today)
        }
        .task { await names.load(using: environment) }
        .task(id: LoadKey(riderId: filter.riderId, horseId: filter.horseId, from: range.from, to: range.to, revision: environment.dataRevision)) {
            let current = filter
            load = await ReportLoad.run {
                try await environment.reports.riderTrainings(riderId: current.riderId, from: range.from, to: range.to, horseId: current.horseId)
            }
        }
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
