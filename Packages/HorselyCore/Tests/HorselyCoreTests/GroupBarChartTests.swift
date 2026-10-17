import Foundation
import Testing
@testable import HorselyCore

/// Wykres grup w „Treningach jeźdźca” (poprawka 2.0.2, FR-013…FR-015): wartości z grup raportu bez przeliczania, „Pozostałe”
/// przy więcej niż 12 grupach, opis dla czytnika ekranu z każdą etykietą i wartością.
struct GroupBarChartTests {
    private func group(_ name: String, count: Int, minutes: Int) -> RiderTrainingsGroup {
        RiderTrainingsGroup(key: name, name: name, count: count, totalMinutes: minutes, averageRating: nil, totalCost: .zero)
    }

    private func report(_ groups: [RiderTrainingsGroup], groupedBy: String = "Horse") -> RiderTrainingsReport {
        RiderTrainingsReport(
            from: nil, to: nil, riderContactId: "r1", riderName: "Anna", rows: [],
            total: RiderTrainingsTotals(count: groups.reduce(0) { $0 + $1.count }, totalMinutes: groups.reduce(0) { $0 + $1.totalMinutes }, averageRating: nil, totalCost: .zero),
            groups: groups, groupedBy: groupedBy
        )
    }

    @Test func eachMetricEqualsTheReportGroupsInTheReportOrder() throws {
        let source = report([group("Grom", count: 3, minutes: 180), group("Iskra", count: 1, minutes: 0), group("Ala", count: 2, minutes: 75)])
        let count = try #require(ReportCharts.riderGroups(source, metric: .count))
        #expect(count.metric == .count)
        #expect(count.bars.map(\.label) == ["Grom", "Iskra", "Ala"])
        #expect(count.bars.map(\.value) == [3, 1, 2])
        let minutes = try #require(ReportCharts.riderGroups(source, metric: .minutes))
        #expect(minutes.bars.map(\.label) == ["Grom", "Iskra", "Ala"])
        #expect(minutes.bars.map(\.value) == [180, 0, 75])
    }

    @Test func aReportWithoutGroupsHasNoChart() {
        #expect(ReportCharts.riderGroups(report([]), metric: .count) == nil)
        #expect(ReportCharts.riderGroups(report([]), metric: .minutes) == nil)
    }

    @Test func exactlyTwelveGroupsAreAllShown() throws {
        let groups = (1...12).map { group("K\($0)", count: $0, minutes: $0 * 10) }
        let chart = try #require(ReportCharts.riderGroups(report(groups), metric: .count))
        #expect(chart.bars.count == 12)
        #expect(!chart.bars.contains { $0.label == "Pozostałe" })
    }

    @Test func thirteenGroupsShowTheElevenLargestAndTheRestAsOthers() throws {
        let groups = (1...13).map { group("K\($0)", count: $0, minutes: (14 - $0) * 10) }
        let count = try #require(ReportCharts.riderGroups(report(groups), metric: .count))
        #expect(count.bars.count == 12)
        // Największe liczby: K13…K3 (w kolejności raportu), reszta: K1 + K2 = 1 + 2.
        #expect(count.bars.dropLast().map(\.label) == (3...13).map { "K\($0)" })
        #expect(count.bars.last == GroupBar(label: "Pozostałe", value: 3))
        let minutes = try #require(ReportCharts.riderGroups(report(groups), metric: .minutes))
        // Największy czas: K1…K11, reszta: K12 + K13 = 20 + 10.
        #expect(minutes.bars.dropLast().map(\.label) == (1...11).map { "K\($0)" })
        #expect(minutes.bars.last == GroupBar(label: "Pozostałe", value: 30))
        // Suma słupków nie zmienia się przez zebranie reszty.
        #expect(count.bars.reduce(0) { $0 + $1.value } == groups.reduce(0) { $0 + $1.count })
        #expect(minutes.bars.reduce(0) { $0 + $1.value } == groups.reduce(0) { $0 + $1.totalMinutes })
    }

    @Test func theDescriptionNamesEveryLabelAndValueWithTheTimeFormat() throws {
        let source = report([group("Grom", count: 3, minutes: 180), group("Ala", count: 2, minutes: 75)])
        let count = ChartDescriptions.groupBars(try #require(ReportCharts.riderGroups(source, metric: .count)))
        #expect(count == "Treningi według grup, Liczba treningów: Grom — 3; Ala — 2")
        let time = ChartDescriptions.groupBars(try #require(ReportCharts.riderGroups(source, metric: .minutes)))
        #expect(time == "Treningi według grup, Łączny czas: Grom — 3 h 0 min; Ala — 1 h 15 min")
    }

    @Test func goldenGroupsFromTheProgramBecomeBarsUnchanged() throws {
        let golden = try JSONDecoder().decode(RiderTrainingsReport.self, from: Fixtures.data("golden/rider-trainings/all-riders.json"))
        let count = try #require(ReportCharts.riderGroups(golden, metric: .count))
        #expect(count.bars == golden.groups.map { GroupBar(label: $0.name, value: $0.count) })
        let minutes = try #require(ReportCharts.riderGroups(golden, metric: .minutes))
        #expect(minutes.bars == golden.groups.map { GroupBar(label: $0.name, value: $0.totalMinutes) })
    }
}
