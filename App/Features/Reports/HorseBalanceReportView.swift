import HorselyCore
import HorselyKit
import SwiftUI

/// Bilans konia (FR-M-RAP-02): zakup, koszty, nagrody, sprzedaż, wynik i uwagi każdego konia z całej historii; filtry statusu i koni.
struct HorseBalanceReportView: View {
    /// Pierwszy wiersz rozwinięty od początku (zrzuty ekranu).
    var expandFirstRow = false

    @Environment(AppEnvironment.self) private var environment
    @State private var statuses: [String] = []
    @State private var horseIds: [String] = []
    @State private var load: ReportLoad<HorseBalanceReport> = .loading

    var body: some View {
        let today = environment.dates.today()
        let selectedStatuses = HorseStatus.allCases.filter { statuses.contains($0.rawValue) }
        ReportScaffold(
            titleKey: "reports_balance", table: load.report.map(ReportTables.horseBalance), isEmpty: load.report?.rows.isEmpty ?? true,
            fromMemory: load.fromMemory, fetchedAt: load.fetchedAt, filterLines: filterLines(selectedStatuses), failure: load.failure,
            loading: load.isLoading, pdfCharts: [],
            fileName: ReportFormat.fileName(ReportTexts.balanceTitle, today: today, fromMemory: load.fromMemory, fetchedAt: load.fetchedAt),
            expandedRow: expandFirstRow ? 0 : nil
        ) {
            EmptyView()
        } filters: {
            Section {
                MultiToggleList(options: HorseStatus.allCases.map { (id: $0.rawValue, name: ReportTexts.status($0)) }, selection: $statuses)
            } header: {
                Text("reports_status")
            } footer: {
                if statuses.isEmpty { Text("reports_status_all") }
            }
            Section {
                MultiToggleList(options: ReportOptions.horses(environment), selection: $horseIds)
            } header: {
                Text("reports_horses")
            } footer: {
                if horseIds.isEmpty { Text("reports_horses_all") }
            }
        }
        .task(id: LoadKey(statuses: selectedStatuses, horseIds: horseIds, revision: environment.dataRevision)) {
            load = await ReportLoad.run { try await environment.reports.horseBalance(statuses: selectedStatuses, horseIds: horseIds) }
        }
    }

    private struct LoadKey: Hashable {
        let statuses: [HorseStatus]
        let horseIds: [String]
        let revision: Int64
    }

    private func filterLines(_ selected: [HorseStatus]) -> [String] {
        var lines: [String] = []
        if !selected.isEmpty { lines.append(ReportTexts.filterStatuses(selected.map(ReportTexts.status).joined(separator: ", "))) }
        if !horseIds.isEmpty {
            lines.append(ReportTexts.filterHorses(ReportOptions.horses(environment).filter { horseIds.contains($0.id) }.map(\.name).joined(separator: ", ")))
        }
        return lines
    }
}
