import Foundation
import Testing
@testable import HorselyCore

/// Pięć raportów (T104, FR-M-RAP-05, FR-SAM-03): wyliczenie z danych w telefonie równe odpowiedziom programu 2.0.0 na tych samych
/// danych (`parity/*/reports`, zegar 2026-09-28), a CSV bajt w bajt równy plikom programu; pliki `golden/` (program 1.6.1) — CSV
/// z odpowiedzi API bajt w bajt.
struct ReportsParityTests {
    private static let sets = ["maly", "brzegowy", "duzy"]

    private struct Case: Decodable {
        let report: String
        let `case`: String
        let query: String
        let json: String
        let csv: String
    }

    private func decode<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        try JSONDecoder().decode(type, from: Fixtures.data(path))
    }

    private func parameters(_ query: String) -> (name: String, values: [String: String]) {
        let route = query.replacingOccurrences(of: "/api/v1/reports/", with: "")
        let parts = route.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var values: [String: String] = [:]
        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") {
                let item = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if item.count == 2 { values[String(item[0])] = String(item[1]).removingPercentEncoding ?? String(item[1]) }
            }
        }
        return (String(parts[0]), values)
    }

    private func list(_ text: String?) -> [String] {
        (text ?? "").split(separator: ",").map(String.init)
    }

    @Test(arguments: sets)
    func theFiveReportsEqualTheProgramAndTheirCsvIsByteForByteTheSame(set: String) throws {
        let source = InMemoryRecordSource(document: try ExportDocument.parse(Fixtures.data("parity/\(set)/export.json")))
        let reports = LocalReports(source: source)
        let anchorDay = LocalDate(year: 2026, month: 9, day: 28)!
        let cases = try decode([Case].self, "parity/\(set)/reports/index.json")
        #expect(cases.count >= 20, "\(set): przypadków \(cases.count)")
        for item in cases {
            let label = "\(set) \(item.report)@\(item.case)"
            let (name, p) = parameters(item.query)
            let date = { (key: String) in p[key].flatMap(LocalDate.init) }
            let jsonPath = "parity/\(set)/reports/\(item.json)"
            let csv: Data
            switch name {
            case "costs":
                let horses = list(p["horseIds"])
                let groupBy = CostGroupBy.allCases.first { $0.rawValue.lowercased() == (p["groupBy"] ?? "month").lowercased() } ?? .month
                let report = try reports.costReport(CostFilter(
                    from: date("from"), to: date("to"), horseIds: horses.filter { $0 != "general" }, generalOnly: horses.contains("general"),
                    categories: list(p["categories"]), groupBy: groupBy
                ))
                let expected = try decode(CostReport.self, jsonPath)
                #expect(report == expected, "\(label) JSON")
                csv = CsvReportWriter.write(ReportTables.costs(report))
            case "horse-balance":
                let report = try reports.horseBalance(statuses: list(p["status"]).compactMap(HorseStatus.init(rawValue:)), horseIds: list(p["horseIds"]))
                let expected = try decode(HorseBalanceReport.self, jsonPath)
                #expect(report == expected, "\(label) JSON")
                csv = CsvReportWriter.write(ReportTables.horseBalance(report))
            case "training-summary":
                let range = TrainingRange.allCases.first { $0.rawValue.lowercased() == (p["range"] ?? "").lowercased() } ?? .all
                let report = try reports.trainingSummary(horseId: try #require(p["horseId"]), range: range, anchor: date("date") ?? anchorDay)
                let expected = try decode(TrainingSummaryReport.self, jsonPath)
                #expect(report == expected, "\(label) JSON")
                csv = CsvReportWriter.write(ReportTables.trainingSummary(report))
            case "rider-trainings":
                let report = try reports.riderTrainings(riderId: p["riderId"], from: date("from"), to: date("to"), horseId: p["horseId"])
                let expected = try decode(RiderTrainingsReport.self, jsonPath)
                #expect(report == expected, "\(label) JSON")
                csv = CsvReportWriter.write(ReportTables.riderTrainings(report))
            case "rider-competitions":
                let report = try reports.riderCompetitions(riderId: p["riderId"], from: date("from"), to: date("to"), horseId: p["horseId"])
                let expected = try decode(RiderCompetitionsReport.self, jsonPath)
                #expect(report == expected, "\(label) JSON")
                csv = CsvReportWriter.write(ReportTables.riderCompetitions(report))
            default:
                Issue.record("Nieznany raport \(name) w \(set)")
                continue
            }
            let expected = try Fixtures.data("parity/\(set)/reports/\(item.csv)")
            #expect(String(decoding: csv, as: UTF8.self) == String(decoding: expected, as: UTF8.self), "\(label) CSV")
            #expect(csv == expected, "\(label) CSV — bajty")
        }
    }

    @Test func theProgram161GoldenCsvIsReproducedFromTheApiAnswers() throws {
        let lines = try Fixtures.string("golden/cases.csv").components(separatedBy: .newlines).dropFirst().filter { !$0.isEmpty }
        #expect(lines.count == 16)
        for line in lines {
            let parts = line.split(separator: ";").map(String.init)
            let (report, name) = (parts[0], parts[1])
            let json = "golden/\(report)/\(name).json"
            let csv: Data
            switch report {
            case "costs": csv = CsvReportWriter.write(ReportTables.costs(try decode(CostReport.self, json)))
            case "horse-balance": csv = CsvReportWriter.write(ReportTables.horseBalance(try decode(HorseBalanceReport.self, json)))
            case "training-summary": csv = CsvReportWriter.write(ReportTables.trainingSummary(try decode(TrainingSummaryReport.self, json)))
            case "rider-trainings": csv = CsvReportWriter.write(ReportTables.riderTrainings(try decode(RiderTrainingsReport.self, json)))
            default: csv = CsvReportWriter.write(ReportTables.riderCompetitions(try decode(RiderCompetitionsReport.self, json)))
            }
            let expected = try Fixtures.data("golden/\(report)/\(name).csv")
            #expect(String(decoding: csv, as: UTF8.self) == String(decoding: expected, as: UTF8.self), "\(report)/\(name)")
            #expect(csv == expected, "\(report)/\(name) — bajty")
        }
    }

    @Test func balanceRemarksDescribeLossMissingPurchaseAndUnsoldHorse() {
        let row = HorseBalanceRow(
            horseId: "h", horseName: "Grom", status: .active, purchasePrice: nil, costs: Money(100), prizes: .zero, salePrice: nil, estimatedValue: nil,
            result: Money(-100), isFinal: false, purchaseMissing: true, breakdown: []
        )
        #expect(ReportTables.remarks(row) == "strata; brak ceny zakupu; wynik dotychczasowy — koń niesprzedany")
    }

    @Test func quickPeriodsAreCountedFromToday() {
        let today = LocalDate(year: 2026, month: 10, day: 5)!
        func days(_ period: ReportPeriod) -> String? { period.range(today: today).map { "\($0.from)/\($0.to)" } }
        #expect(days(.currentMonth) == "2026-10-01/2026-10-31")
        #expect(days(.previousMonth) == "2026-09-01/2026-09-30")
        #expect(days(.currentYear) == "2026-01-01/2026-12-31")
        #expect(days(.previousYear) == "2025-01-01/2025-12-31")
        #expect(days(.last12Months) == "2025-11-01/2026-10-31")
        #expect(days(.custom) == nil)
        #expect(ReportPeriod.previousMonth.range(today: LocalDate(year: 2026, month: 1, day: 15)!).map { "\($0.from)" } == "2025-12-01")
        #expect(TrainingRange.week.period(LocalDate(year: 2026, month: 9, day: 23)!).from == LocalDate(year: 2026, month: 9, day: 21))
    }

    @Test func chartsComeFromTheReportRows() throws {
        let source = InMemoryRecordSource(document: try ExportDocument.parse(Fixtures.data("parity/maly/export.json")))
        let report = try LocalReports(source: source).costReport(CostFilter(from: LocalDate(year: 2026, month: 1, day: 1), to: LocalDate(year: 2026, month: 12, day: 31)))
        let bars = try #require(ReportCharts.monthlyCosts(report))
        #expect(bars.months == bars.months.sorted())
        #expect(bars.series.map { $0.values.count } == Array(repeating: bars.months.count, count: bars.series.count))
        let pie = try #require(ReportCharts.categoryShare(report))
        #expect(pie.total == report.totalCosts)
        #expect(ChartDescriptions.pie(pie).hasPrefix("Udział kategorii w kosztach: "))
        #expect(SeriesStyle.of(5) == SeriesStyle(colorIndex: 5, marker: .square, dashed: true, hollowMarker: false, thickLine: false))
    }
}
