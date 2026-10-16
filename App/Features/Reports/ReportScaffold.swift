import HorselyCore
import HorselyKit
import SwiftUI

/// Lista raportów (T108): pięć raportów programu z opisami.
struct ReportsListView: View {
    enum Route: String, Hashable, CaseIterable {
        case costs, balance, trainingSummary, riderTrainings, riderCompetitions

        var titleKey: String {
            switch self {
            case .costs: "reports_cost"
            case .balance: "reports_balance"
            case .trainingSummary: "reports_training_summary"
            case .riderTrainings: "reports_rider_trainings"
            case .riderCompetitions: "reports_rider_competitions"
            }
        }

        var hintKey: String { titleKey + "_hint" }
    }

    var body: some View {
        ScrollView {
            DividedList(Route.allCases.map(Item.init)) { item in
                NavigationLink(value: item.route) {
                    HStack(spacing: Spacing.between + 4) {
                        AccentIcon(icon: SectionAccent.reports.icon, color: SectionAccent.reports.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(item.route.titleKey)).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                            Text(LocalizedStringKey(item.route.hintKey)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(HorselyColor.onSurfaceVariant).accessibilityHidden(true)
                    }
                    .padding(.horizontal, Spacing.screenEdge)
                    .padding(.vertical, Spacing.between)
                    .frame(minHeight: Spacing.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("report-\(item.route.rawValue)")
            }
        }
        .background(HorselyColor.background)
        .navigationTitle(tr("nav_reports"))
        .navigationBarTitleDisplayMode(.inline)
        .connectionChrome()
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .costs: CostReportView()
            case .balance: HorseBalanceReportView()
            case .trainingSummary: TrainingSummaryReportView()
            case .riderTrainings: RiderTrainingsReportView()
            case .riderCompetitions: RiderCompetitionsReportView()
            }
        }
    }

    private struct Item: Identifiable {
        let route: Route
        var id: String { route.rawValue }
    }
}

/// Stan ładowania raportu.
enum ReportLoad<Report: Sendable> {
    case loading
    case loaded(Report, fromMemory: Bool, fetchedAt: Date)
    case failed(String)

    var report: Report? {
        if case let .loaded(report, _, _) = self { return report }
        return nil
    }

    var fromMemory: Bool {
        if case let .loaded(_, fromMemory, _) = self { return fromMemory }
        return false
    }

    var fetchedAt: Date? {
        if case let .loaded(_, _, fetchedAt) = self { return fetchedAt }
        return nil
    }

    var failure: String? {
        if case let .failed(text) = self { return text }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Wynik repozytorium; błąd (brak odpowiedzi programu i brak danych w pamięci) — komunikat „wymaga połączenia”.
    @MainActor
    static func run(_ work: () async throws -> ReportResult<Report>) async -> ReportLoad<Report> {
        do {
            let result = try await work()
            return .loaded(result.report, fromMemory: result.fromMemory, fetchedAt: result.fetchedAt)
        } catch {
            return .failed(tr("reports_needs_connection_hint"))
        }
    }
}

/// Wspólny ekran raportu: opis filtrów, wykresy, karty wierszy (pierwsza kolumna jako tytuł, pozostałe jako etykieta—wartość
/// z „Więcej szczegółów”), sumy, uwagi, eksport CSV i PDF.
struct ReportScaffold<Charts: View, Filters: View>: View {
    let titleKey: String
    let table: TabularReport?
    let isEmpty: Bool
    let fromMemory: Bool
    let fetchedAt: Date?
    let filterLines: [String]
    let failure: String?
    let loading: Bool
    let pdfCharts: [ChartImage]
    let fileName: String
    /// Wiersz rozwinięty od początku (zrzuty ekranu).
    var expandedRow: Int?
    @ViewBuilder let charts: () -> Charts
    @ViewBuilder let filters: () -> Filters

    @State private var showingFilters = false
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.beforeSection) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filterLines, id: \.self) { Text($0).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                    if fromMemory {
                        Text("sections_from_memory").font(.footnote).foregroundStyle(HorselyColor.warning)
                    }
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                } else if let failure {
                    InfoCard(tone: .warning) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("reports_needs_connection_title").font(.headline)
                            Text(failure).font(.subheadline)
                        }
                    }
                } else if let table {
                    if isEmpty {
                        InfoCard(tone: .neutral) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("reports_no_data_title").font(.headline)
                                Text("reports_no_data_hint").font(.subheadline)
                            }
                        }
                    }
                    charts()
                    ForEach(Array(table.rows.enumerated()), id: .offset) { index, row in
                        ReportRowCard(columns: table.columns, cells: row, expanded: index == expandedRow)
                    }
                    if !table.totalRows.isEmpty {
                        InfoCard(tone: .primary) {
                            VStack(alignment: .leading, spacing: Spacing.between) {
                                ForEach(Array(table.totalRows.enumerated()), id: \.offset) { _, row in
                                    ReportTotalLine(columns: table.columns, cells: row)
                                }
                            }
                        }
                        .accessibilityIdentifier("report-totals")
                    }
                    ForEach(table.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                }
            }
            .padding(Spacing.screenEdge)
        }
        .background(HorselyColor.background)
        .navigationTitle(LocalizedStringKey(titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(tr("reports_filters")) { showingFilters = true }.accessibilityIdentifier("report-filters")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ReportExportMenu(table: table, isEmpty: isEmpty, fileName: fileName, filterLines: filterLines, fromMemory: fromMemory, fetchedAt: fetchedAt,
                                 charts: pdfCharts)
            }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                Form { filters() }
                    .navigationTitle(tr("reports_filters"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("reports_filters_done")) { showingFilters = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// Karta wiersza raportu (FR-027/028): tytuł z pierwszej kolumny; pierwsze trzy wartości zawsze, reszta po „Więcej szczegółów”.
/// Wiersz etykieta—wartość mieści się w jednej linii albo — przy dużym tekście / wąskim ekranie — przechodzi pod etykietę.
struct ReportRowCard: View {
    let columns: [ReportColumn]
    let cells: [ReportValue?]
    @State private var expanded: Bool

    static let collapsedCount = 3

    init(columns: [ReportColumn], cells: [ReportValue?], expanded: Bool = false) {
        self.columns = columns
        self.cells = cells
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        let values = Array(zip(columns, cells).enumerated().dropFirst())
        let visible = expanded ? values : Array(values.prefix(Self.collapsedCount))
        InfoCard(tone: .neutral) {
            VStack(alignment: .leading, spacing: 6) {
                Text(TabularReport.display(columns[0], cells.first ?? nil)).font(.body.weight(.semibold))
                ForEach(visible, id: \.offset) { _, pair in
                    LabelValueRow(label: pair.0.header, value: TabularReport.display(pair.0, pair.1), numeric: pair.0.isNumeric)
                }
                if values.count > Self.collapsedCount {
                    Button(expanded ? tr("reports_collapse") : tr("reports_expand")) { withAnimation { expanded.toggle() } }
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: Spacing.minTouchTarget)
                        .accessibilityIdentifier("report-expand")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Wiersz sumy: etykieta z pierwszej kolumny, potem wartości niepuste z nagłówkami kolumn.
struct ReportTotalLine: View {
    let columns: [ReportColumn]
    let cells: [ReportValue?]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TabularReport.display(columns[0], cells.first ?? nil)).font(.subheadline.weight(.semibold))
            ForEach(Array(zip(columns, cells).enumerated().dropFirst()).filter { $0.element.1 != nil }, id: \.offset) { _, pair in
                LabelValueRow(label: pair.0.header, value: TabularReport.display(pair.0, pair.1), numeric: pair.0.isNumeric)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Etykieta i wartość w jednej linii, a gdy się nie mieszczą — wartość pod etykietą (`ViewThatFits`).
struct LabelValueRow: View {
    let label: String
    let value: String
    let numeric: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.between) {
                Text(label).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                Spacer(minLength: Spacing.between)
                Text(value).font(.footnote.weight(.semibold)).monospacedDigit().multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                Text(value).font(.footnote.weight(.semibold)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Wybór okresu raportu: szybkie okresy i „Własny” z datami.
struct ReportPeriodPicker: View {
    @Binding var period: ReportPeriod
    @Binding var from: LocalDate?
    @Binding var to: LocalDate?
    let today: LocalDate

    var body: some View {
        Picker(selection: $period) {
            ForEach(ReportPeriod.allCases, id: \.self) { item in Text(LocalizedStringKey(Self.key(item))).tag(item) }
        } label: {
            Text("reports_period")
        }
        .onChange(of: period) { _, value in
            if let range = value.range(today: today) {
                from = range.from
                to = range.to
            }
        }
        if period == .custom {
            DateField("reports_date_from", date: $from, defaultSelection: today)
            DateField("reports_date_to", date: $to, defaultSelection: today)
        }
    }

    static func key(_ period: ReportPeriod) -> String {
        switch period {
        case .currentMonth: "reports_period_current_month"
        case .previousMonth: "reports_period_previous_month"
        case .currentYear: "reports_period_current_year"
        case .previousYear: "reports_period_previous_year"
        case .last12Months: "reports_period_last_12"
        case .custom: "reports_period_custom"
        }
    }
}

/// Wybór wielu pozycji przełącznikami (konie, kategorie, statusy).
struct MultiToggleList: View {
    let options: [(id: String, name: String)]
    @Binding var selection: [String]

    var body: some View {
        ForEach(options, id: \.id) { option in
            Toggle(option.name, isOn: Binding(
                get: { selection.contains(option.id) },
                set: { on in
                    if on { if !selection.contains(option.id) { selection.append(option.id) } } else { selection.removeAll { $0 == option.id } }
                }
            ))
        }
    }
}

enum ReportFormat {
    static func period(_ from: LocalDate?, _ to: LocalDate?) -> String? {
        guard from != nil || to != nil else { return nil }
        return ReportTexts.filterPeriod(from.map { Formats.date($0) } ?? "…", to.map { Formats.date($0) } ?? "…")
    }

    /// Nazwa pliku jak w programie: `<Tytuł> <yyyy-MM-dd>`, z pamięci — dopisek ` (dane z <yyyy-MM-dd>)`.
    static func fileName(_ title: String, today: LocalDate, fromMemory: Bool, fetchedAt: Date?) -> String {
        var name = "\(title) \(today)"
        if fromMemory, let fetchedAt {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: fetchedAt)
            name += String(format: " (dane z %04d-%02d-%02d)", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        return name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")
    }
}
