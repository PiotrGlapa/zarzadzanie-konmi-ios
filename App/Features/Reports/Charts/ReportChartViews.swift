import Charts
import HorselyCore
import SwiftUI
import UIKit

extension ChartPalette {
    static func swiftUIColor(_ index: Int) -> Color {
        let rgb = color(index)
        return Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

extension Money {
    var double: Double { NSDecimalNumber(decimal: value).doubleValue }
}

/// Koszty miesięczne skumulowane po kategoriach (słupki), z legendą; opis wartości dla VoiceOver.
struct StackedBarChartView: View {
    let chart: StackedBarChart

    private struct Point: Identifiable {
        let id: String
        let month: String
        let category: String
        let value: Double
    }

    var body: some View {
        let points = chart.series.flatMap { series in
            zip(chart.months, series.values).map { Point(id: "\(series.name)-\($0.0)", month: $0.0, category: series.name, value: $0.1.double) }
        }
        VStack(alignment: .leading, spacing: Spacing.between) {
            Text(ChartDescriptions.monthlyTitle).font(.subheadline.weight(.semibold))
            Chart(points) { point in
                BarMark(x: .value("Miesiąc", point.month), y: .value("Koszty", point.value))
                    .foregroundStyle(by: .value("Kategoria", point.category))
            }
            .chartForegroundStyleScale(domain: chart.series.map(\.name), range: chart.series.indices.map(ChartPalette.swiftUIColor))
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 220)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChartDescriptions.bars(chart))
        .accessibilityIdentifier("chart-monthly")
    }
}

/// Udział kategorii w kosztach (koło) z legendą i procentami.
struct PieChartView: View {
    let chart: PieChart

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            Text(ChartDescriptions.shareTitle).font(.subheadline.weight(.semibold))
            Chart(Array(chart.slices.enumerated()), id: \.offset) { index, slice in
                SectorMark(angle: .value("Koszty", slice.value.double), innerRadius: .ratio(0.5), angularInset: 1)
                    .foregroundStyle(ChartPalette.swiftUIColor(index))
            }
            .frame(height: 200)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(chart.slices.enumerated()), id: \.offset) { index, slice in
                    HStack(spacing: 6) {
                        Circle().fill(ChartPalette.swiftUIColor(index)).frame(width: 10, height: 10)
                        Text("\(slice.label) — \(ChartDescriptions.percent(slice.value, chart.total)) (\(Formats.money(slice.value)))").font(.caption)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChartDescriptions.pie(chart))
        .accessibilityIdentifier("chart-share")
    }
}

/// Postęp parametru treningu: linia na typ treningu, kolor i kształt znacznika z `paletteIndex` (rozróżnialne bez koloru).
struct LineChartView: View {
    let chart: LineChart

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let series: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            Text(ChartDescriptions.progressTitle(chart.parameter)).font(.subheadline.weight(.semibold))
            Chart {
                ForEach(chart.series, id: \.name) { series in
                    let style = series.style
                    ForEach(series.points, id: \.date) { point in
                        LineMark(x: .value("Data", Self.date(point.date)), y: .value(chart.parameter.label, point.value.double))
                            .foregroundStyle(by: .value("Rodzaj", series.name))
                            .lineStyle(StrokeStyle(lineWidth: style.thickLine ? 3 : 2, dash: style.dashed ? [6, 4] : []))
                            .symbol(Self.symbol(style.marker))
                    }
                }
            }
            .chartForegroundStyleScale(domain: chart.series.map(\.name), range: chart.series.map { ChartPalette.swiftUIColor($0.style.colorIndex) })
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 220)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChartDescriptions.lines(chart))
        .accessibilityIdentifier("chart-progress")
    }

    static func date(_ day: LocalDate) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: day.year, month: day.month, day: day.day)) ?? Date()
    }

    static func symbol(_ shape: MarkerShape) -> BasicChartSymbolShape {
        switch shape {
        case .circle: .circle
        case .square: .square
        case .diamond: .diamond
        case .cross: .cross
        }
    }
}

/// Obraz wykresu do PDF (renderowany przez `ImageRenderer` z tych samych widoków co ekran).
struct ChartImage: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let image: UIImage
}

@MainActor
enum ChartRendering {
    static func image(_ view: some View, title: String, description: String) -> ChartImage? {
        let renderer = ImageRenderer(content: view.frame(width: 480).padding(8).background(Color.white).environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        return ChartImage(title: title, description: description, image: image)
    }
}
