import Foundation

// Dane wykresów (research R16, `ReportCharts.kt`): ekran i PDF rysują je z tych samych struktur.

public enum MarkerShape: CaseIterable, Sendable {
    case circle, square, diamond, cross
}

/// Wygląd typu treningu na wykresie postępów: kolor z palety Okabe‑Ito, kształt znacznika, linia przerywana, znacznik pusty, gruba
/// linia — serie da się odróżnić także bez koloru.
public struct SeriesStyle: Equatable, Sendable {
    public static let colors = 8
    public let colorIndex: Int
    public let marker: MarkerShape
    public let dashed: Bool
    public let hollowMarker: Bool
    public let thickLine: Bool

    public static func of(_ paletteIndex: Int) -> SeriesStyle {
        let index = max(0, paletteIndex)
        return SeriesStyle(
            colorIndex: index % colors, marker: MarkerShape.allCases[index % MarkerShape.allCases.count], dashed: index / 4 % 2 == 1,
            hollowMarker: index / 8 % 2 == 1, thickLine: index / 16 % 2 == 1
        )
    }
}

/// Osiem kolorów odróżnialnych także przy zaburzeniach widzenia barw (Okabe‑Ito), 0xRRGGBB.
public enum ChartPalette {
    public static let rgb: [UInt32] = [0x0072B2, 0xD55E00, 0x009E73, 0xCC79A7, 0xE69F00, 0x56B4E9, 0x785EF0, 0x787878]

    public static func color(_ index: Int) -> UInt32 { rgb[((index % rgb.count) + rgb.count) % rgb.count] }
}

public struct BarSeries: Equatable, Sendable {
    public let name: String
    public let values: [Money]
}

/// Koszty miesięczne skumulowane po kategoriach; `months` — `yyyy-MM` rosnąco.
public struct StackedBarChart: Equatable, Sendable {
    public let months: [String]
    public let series: [BarSeries]

    public var maxTotal: Money {
        months.indices.map { index in series.reduce(Money.zero) { $0 + $1.values[index] } }.max() ?? .zero
    }
}

public struct PieSlice: Equatable, Sendable {
    public let label: String
    public let value: Money
}

/// Udział kategorii w kosztach; tylko dodatnie wartości, od największej.
public struct PieChart: Equatable, Sendable {
    public let slices: [PieSlice]
    public var total: Money { slices.reduce(Money.zero) { $0 + $1.value } }
}

public struct LinePoint: Equatable, Sendable {
    public let date: LocalDate
    public let value: Money
}

public struct LineSeries: Equatable, Sendable {
    public let name: String
    public let paletteIndex: Int
    public let points: [LinePoint]
    public var style: SeriesStyle { .of(paletteIndex) }
}

public enum TrainingParameter: String, CaseIterable, Sendable {
    case duration = "Duration"
    case rating = "Rating"
    case obstacleHeight = "ObstacleHeight"

    public var label: String {
        switch self {
        case .duration: ReportTexts.trainingDuration
        case .rating: ReportTexts.trainingRating
        case .obstacleHeight: ReportTexts.trainingObstacleHeight
        }
    }
}

/// Postęp parametru: po jednej linii na typ treningu.
public struct LineChart: Equatable, Sendable {
    public let parameter: TrainingParameter
    public let series: [LineSeries]
}

/// Miara wykresu grup „Treningi jeźdźca”: liczba treningów albo łączny czas w minutach.
public enum GroupMetric: CaseIterable, Sendable {
    case count, minutes

    public var label: String {
        switch self {
        case .count: ChartDescriptions.metricCount
        case .minutes: ChartDescriptions.metricTime
        }
    }
}

public struct GroupBar: Equatable, Sendable {
    public let label: String
    public let value: Int
}

/// Słupki grup raportu „Treningi jeźdźca” (konie jednego jeźdźca albo jeźdźcy): wartości z `RiderTrainingsReport.groups` bez
/// przeliczania. Przy więcej niż 12 grupach — 11 największych (w kolejności raportu) i „Pozostałe” z sumą reszty.
public struct GroupBarChart: Equatable, Sendable {
    public static let maxBars = 12
    public let metric: GroupMetric
    public let bars: [GroupBar]
}

public enum ReportCharts {
    /// Wykres grup w wybranej mierze; `nil`, gdy raport nie ma grup.
    public static func riderGroups(_ report: RiderTrainingsReport, metric: GroupMetric) -> GroupBarChart? {
        let bars = report.groups.map { GroupBar(label: $0.name, value: metric == .count ? $0.count : $0.totalMinutes) }
        guard !bars.isEmpty else { return nil }
        guard bars.count > GroupBarChart.maxBars else { return GroupBarChart(metric: metric, bars: bars) }
        let keep = GroupBarChart.maxBars - 1
        let largest = Set(bars.indices.sorted { bars[$0].value != bars[$1].value ? bars[$0].value > bars[$1].value : $0 < $1 }.prefix(keep))
        let shown = bars.indices.filter(largest.contains).map { bars[$0] }
        let rest = bars.indices.filter { !largest.contains($0) }.reduce(0) { $0 + bars[$1].value }
        return GroupBarChart(metric: metric, bars: shown + [GroupBar(label: ChartDescriptions.others, value: rest)])
    }

    /// Słupki miesięczne po kategoriach z wierszy `groupBy=Month`; `nil` dla innego grupowania albo bez kosztów.
    public static func monthlyCosts(_ report: CostReport) -> StackedBarChart? {
        guard report.groupBy?.lowercased() == "month" else { return nil }
        let rows = report.rows.filter { $0.costs.value > 0 && $0.category != nil }
        guard !rows.isEmpty else { return nil }
        let months = Array(Set(rows.map { $0.month ?? $0.group })).sorted()
        var order: [String] = []
        var grouped: [String: [CostReportRow]] = [:]
        for row in rows {
            if grouped[row.category!] == nil { order.append(row.category!) }
            grouped[row.category!, default: []].append(row)
        }
        var categories: [CategoryGroup] = []
        for (offset, name) in order.enumerated() {
            let items = grouped[name] ?? []
            var total = Money.zero
            for item in items { total = total + item.costs }
            categories.append(CategoryGroup(offset: offset, name: name, rows: items, total: total))
        }
        categories.sort { $0.total != $1.total ? $0.total > $1.total : $0.offset < $1.offset }
        var series: [BarSeries] = []
        for category in categories {
            var values: [Money] = []
            for month in months {
                var sum = Money.zero
                for row in category.rows where (row.month ?? row.group) == month { sum = sum + row.costs }
                values.append(sum)
            }
            series.append(BarSeries(name: category.name, values: values))
        }
        return StackedBarChart(months: months, series: series)
    }

    /// Udział kategorii w kosztach okresu (dowolne grupowanie); `nil`, gdy nie ma kosztów.
    public static func categoryShare(_ report: CostReport) -> PieChart? {
        let byCategory = report.groupBy?.lowercased() == "category"
        var sums: [String: Money] = [:]
        var order: [String] = []
        for row in report.rows where row.costs.value > 0 {
            guard let key = byCategory ? row.group : row.category else { continue }
            if sums[key] == nil { order.append(key) }
            sums[key, default: .zero] = sums[key, default: .zero] + row.costs
        }
        let slices = order.map { PieSlice(label: $0, value: sums[$0]!) }.enumerated()
            .sorted { $0.element.value != $1.element.value ? $0.element.value > $1.element.value : $0.offset < $1.offset }.map(\.element)
        return slices.isEmpty ? nil : PieChart(slices: slices)
    }

    /// Linie postępu `parameter` po typach treningu; `nil`, gdy nie ma punktów.
    public static func progress(_ report: TrainingSummaryReport, _ parameter: TrainingParameter) -> LineChart? {
        let rows = Dictionary(report.rows.compactMap { row in row.typeId.map { ($0, row) } }, uniquingKeysWith: { first, _ in first })
        let series = report.series
            .filter { $0.parameter.caseInsensitiveCompare(parameter.rawValue) == .orderedSame && !$0.points.isEmpty }
            .compactMap { item -> LineSeries? in
                guard let row = rows[item.typeId] else { return nil }
                return LineSeries(name: row.typeName, paletteIndex: row.paletteIndex, points: item.points.sorted { $0.date < $1.date }.map { LinePoint(date: $0.date, value: $0.value) })
            }
        return series.isEmpty ? nil : LineChart(parameter: parameter, series: series)
    }

    /// Parametry, dla których są punkty — do wyboru na ekranie.
    public static func availableParameters(_ report: TrainingSummaryReport) -> [TrainingParameter] {
        TrainingParameter.allCases.filter { parameter in
            report.series.contains { $0.parameter.caseInsensitiveCompare(parameter.rawValue) == .orderedSame && !$0.points.isEmpty }
        }
    }
}

/// Tytuły i opisy wykresów dla VoiceOver i legendy w PDF — wartości w tekście, nie tylko w kolorze (`ChartDescriptions.kt`).
public enum ChartDescriptions {
    public static let monthlyTitle = "Koszty miesięczne według kategorii"
    public static let shareTitle = "Udział kategorii w kosztach"
    public static let riderGroupsTitle = "Treningi według grup"
    public static let metricCount = "Liczba treningów"
    public static let metricTime = "Łączny czas"
    public static let others = "Pozostałe"

    /// Wartość słupka grup: liczba albo czas „X h Y min” (FR-M-RAP-04).
    public static func groupValue(_ value: Int, metric: GroupMetric) -> String {
        metric == .count ? String(value) : Formats.duration(minutes: value)
    }

    public static func groupBars(_ chart: GroupBarChart) -> String {
        "\(riderGroupsTitle), \(chart.metric.label): "
            + chart.bars.map { "\($0.label) — \(groupValue($0.value, metric: chart.metric))" }.joined(separator: "; ")
    }

    public static func progressTitle(_ parameter: TrainingParameter) -> String { "Postęp: \(parameter.label)" }

    public static func bars(_ chart: StackedBarChart) -> String {
        "\(monthlyTitle), \(chart.months.count) mies.: " + chart.series.map { "\($0.name) — \(Formats.money($0.values.reduce(Money.zero, +)))" }.joined(separator: "; ")
    }

    public static func pie(_ chart: PieChart) -> String {
        "\(shareTitle): " + chart.slices.map { "\($0.label) — \(percent($0.value, chart.total)) (\(Formats.money($0.value)))" }.joined(separator: "; ")
    }

    public static func lines(_ chart: LineChart) -> String {
        "\(progressTitle(chart.parameter)): " + chart.series.map { series in
            "\(series.name) — \(series.points.count) pomiarów, od \(plain(series.points.first!.value)) do \(plain(series.points.last!.value))"
        }.joined(separator: "; ")
    }

    /// Udział jako całkowity procent (`32%`).
    public static func percent(_ part: Money, _ total: Money) -> String {
        guard total.value != 0 else { return "0%" }
        return Formats.fixed((part.value * 100 / total.value), places: 0, grouping: false) + "%"
    }

    /// Wartość bez zbędnych zer: `45`, `4,5`.
    public static func plain(_ value: Money) -> String {
        NSDecimalNumber(decimal: value.value).stringValue.replacingOccurrences(of: ".", with: ",")
    }
}

/// Szybkie okresy filtrów raportów (`ReportPeriods`).
public enum ReportPeriod: String, CaseIterable, Sendable {
    case currentMonth, previousMonth, currentYear, previousYear, last12Months, custom

    public func range(today: LocalDate) -> (from: LocalDate, to: LocalDate)? {
        let month = today.firstOfMonth
        switch self {
        case .currentMonth: return (month, month.adding(months: 1).adding(days: -1))
        case .previousMonth: return (month.adding(months: -1), month.adding(days: -1))
        case .currentYear: return (LocalDate(year: today.year, month: 1, day: 1)!, LocalDate(year: today.year, month: 12, day: 31)!)
        case .previousYear: return (LocalDate(year: today.year - 1, month: 1, day: 1)!, LocalDate(year: today.year - 1, month: 12, day: 31)!)
        case .last12Months: return (month.adding(months: -11), month.adding(months: 1).adding(days: -1))
        case .custom: return nil
        }
    }
}

/// Kategoria wykresu słupkowego z sumą i kolejnością pierwszego wystąpienia.
struct CategoryGroup {
    let offset: Int
    let name: String
    let rows: [CostReportRow]
    let total: Money
}
