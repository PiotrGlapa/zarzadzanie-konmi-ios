import HorselyCore
import SwiftUI
import UIKit

/// PDF raportu (contracts/android/report-export.md): A4 pionowo, marginesy 36 pt; nagłówek z nazwą „Horsely”, tytułem, filtrami
/// i datą danych; wykresy; tabela z tymi samymi kolumnami co CSV (wartości jak na ekranie), łamanie stron z powtórzeniem nagłówka
/// kolumn; sumy i uwagi; stopka z wersją aplikacji i numerem strony.
enum PdfReportRenderer {
    static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    static let margin: CGFloat = 36

    static func render(_ table: TabularReport, filterLines: [String], dataLine: String, charts: [ChartImage], appVersion: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let width = page.width - 2 * margin
        let titleFont = UIFont.systemFont(ofSize: 16, weight: .bold)
        let textFont = UIFont.systemFont(ofSize: 9)
        let boldFont = UIFont.systemFont(ofSize: 8, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 8)
        let columnWidth = width / CGFloat(max(table.columns.count, 1))

        return renderer.pdfData { context in
            var pageNumber = 0
            var y: CGFloat = 0
            func footer() {
                let text = "Horsely — aplikacja na iOS \(appVersion) · strona \(pageNumber)"
                draw(text, font: textFont, in: CGRect(x: margin, y: page.height - margin + 8, width: width, height: 14), color: .gray)
            }
            func newPage() {
                if pageNumber > 0 { footer() }
                context.beginPage()
                pageNumber += 1
                y = margin
            }
            func ensure(_ height: CGFloat) {
                if y + height > page.height - margin - 16 { newPage() }
            }
            func header() {
                let height = rowHeight(table.columns.map(\.header), font: boldFont, width: columnWidth)
                ensure(height + 4)
                for (index, column) in table.columns.enumerated() {
                    draw(column.header, font: boldFont, in: CGRect(x: margin + CGFloat(index) * columnWidth, y: y, width: columnWidth - 4, height: height),
                         alignment: column.isNumeric ? .right : .left)
                }
                y += height + 2
                UIColor.gray.setStroke()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: width, height: 0.5)).stroke()
                y += 4
            }
            func row(_ cells: [ReportValue?], font: UIFont) {
                let texts = zip(table.columns, cells).map { TabularReport.display($0.0, $0.1) }
                let height = rowHeight(texts, font: font, width: columnWidth)
                if y + height > page.height - margin - 16 {
                    newPage()
                    header()
                }
                for (index, text) in texts.enumerated() {
                    draw(text, font: font, in: CGRect(x: margin + CGFloat(index) * columnWidth, y: y, width: columnWidth - 4, height: height),
                         alignment: table.columns[index].isNumeric ? .right : .left)
                }
                y += height + 3
            }

            newPage()
            draw("Horsely", font: textFont, in: CGRect(x: margin, y: y, width: width, height: 12), color: .gray)
            y += 14
            draw(table.title, font: titleFont, in: CGRect(x: margin, y: y, width: width, height: 22))
            y += 24
            for line in filterLines + [dataLine] {
                draw(line, font: textFont, in: CGRect(x: margin, y: y, width: width, height: 12))
                y += 13
            }
            y += 8
            for chart in charts {
                let size = CGSize(width: min(width, chart.image.size.width), height: min(width, chart.image.size.width) * chart.image.size.height / max(chart.image.size.width, 1))
                ensure(size.height + 30)
                draw(chart.title, font: boldFont, in: CGRect(x: margin, y: y, width: width, height: 12))
                y += 14
                chart.image.draw(in: CGRect(origin: CGPoint(x: margin, y: y), size: size))
                y += size.height + 4
                let descriptionHeight = textHeight(chart.description, font: cellFont, width: width)
                ensure(descriptionHeight)
                draw(chart.description, font: cellFont, in: CGRect(x: margin, y: y, width: width, height: descriptionHeight), color: .darkGray)
                y += descriptionHeight + 10
            }
            header()
            for cells in table.rows { row(cells, font: cellFont) }
            if !table.totalRows.isEmpty {
                y += 6
                for cells in table.totalRows { row(cells, font: boldFont) }
            }
            for note in table.notes {
                let height = textHeight(note, font: cellFont, width: width)
                ensure(height + 6)
                y += 6
                draw(note, font: cellFont, in: CGRect(x: margin, y: y, width: width, height: height), color: .darkGray)
                y += height
            }
            footer()
        }
    }

    private static func rowHeight(_ texts: [String], font: UIFont, width: CGFloat) -> CGFloat {
        texts.map { textHeight($0, font: font, width: width - 4) }.max() ?? font.lineHeight
    }

    private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin],
                                             attributes: [.font: font], context: nil).height)
    }

    private static func draw(_ text: String, font: UIFont, in rect: CGRect, alignment: NSTextAlignment = .left, color: UIColor = .black) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .paragraphStyle: style, .foregroundColor: color])
    }
}

/// Plik eksportu do udostępnienia albo zapisania; plik tymczasowy znika po zamknięciu arkusza.
struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Menu „Eksport CSV” / „Eksport PDF”: plik tymczasowy z nazwą jak w programie → „Udostępnij” albo „Zapisz w plikach”.
struct ReportExportMenu: View {
    let table: TabularReport?
    let isEmpty: Bool
    let fileName: String
    let filterLines: [String]
    let fromMemory: Bool
    let fetchedAt: Date?
    let charts: [ChartImage]

    @State private var file: ExportedFile?
    @State private var saving: ExportedFile?
    @State private var message: String?

    var body: some View {
        Menu {
            Button(tr("reports_export_csv")) { export(pdf: false) }.accessibilityIdentifier("report-export-csv")
            Button(tr("reports_export_pdf")) { export(pdf: true) }.accessibilityIdentifier("report-export-pdf")
        } label: {
            Image(systemName: "square.and.arrow.up").accessibilityLabel(tr("reports_share"))
        }
        .disabled(table == nil || isEmpty)
        .accessibilityIdentifier("report-export")
        .confirmationDialog(tr("reports_export_ready_title"), isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }), titleVisibility: .visible) {
            if let file {
                ShareLink(item: file.url) { Text("reports_share") }
                Button(tr("reports_save_to_files")) { saving = file }
            }
        } message: {
            if let file { Text(tr("reports_export_ready_text", file.url.lastPathComponent)) }
        }
        .fileMover(isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }), file: saving?.url) { result in
            message = (try? result.get()) != nil ? tr("reports_saved") : tr("reports_save_failed")
            saving = nil
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(tr("common_ok")) { message = nil }
        }
    }

    private func export(pdf: Bool) {
        guard let table else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-export", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName + (pdf ? ".pdf" : ".csv"))
        let data: Data
        if pdf {
            let stamp = fetchedAt.map { ConnectionTexts.stamp($0) ?? "" } ?? ""
            let dataLine = fromMemory ? "Dane z pamięci telefonu, pobrane \(stamp)" : "Dane z: \(stamp)"
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            data = PdfReportRenderer.render(table, filterLines: filterLines, dataLine: dataLine, charts: charts, appVersion: version)
        } else {
            data = CsvReportWriter.write(table)
        }
        do {
            try data.write(to: url, options: .atomic)
            file = ExportedFile(url: url)
        } catch {
            message = tr("reports_save_failed")
        }
    }
}
