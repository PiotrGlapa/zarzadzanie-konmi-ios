import Foundation

/// Teksty raportów i eksportów 1:1 z programu (`ReportTexts.kt`, `AppTexts.resx`) — nagłówki CSV, sumy, uwagi i opisy filtrów muszą
/// być identyczne z plikami programu (contracts/android/report-export.md).
public enum ReportTexts {
    public static let horse = "Koń"
    public static let month = "Miesiąc"
    public static let category = "Kategoria"
    public static let costs = "Koszty"
    public static let income = "Przychody"
    public static let total = "Razem"
    public static let balance = "Saldo"
    public static let general = "Ogólne (stajnia)"

    public static let costTitle = "Raport kosztów"
    public static let balanceTitle = "Bilans konia"
    public static let trainingSummaryTitle = "Podsumowanie treningów"
    public static let riderTrainingsTitle = "Treningi jeźdźca"
    public static let riderCompetitionsTitle = "Zawody jeźdźca"
    public static let allRiders = "Wszyscy jeźdźcy"

    public static let balanceStatus = "Status"
    public static let balancePurchase = "Zakup"
    public static let balancePrizes = "Nagrody"
    public static let balanceSale = "Sprzedaż"
    public static let balanceResult = "Wynik"
    public static let balanceEstimatedValue = "Wartość (ocena własna)"
    public static let balanceRemarks = "Uwagi"
    public static let balanceProfit = "zysk"
    public static let balanceLoss = "strata"
    public static let balanceNoPurchase = "brak ceny zakupu"
    public static let balanceNotSold = "wynik dotychczasowy — koń niesprzedany"
    public static let balanceNote = "Wynik = sprzedaż + nagrody − zakup − koszty (z całej historii konia). "
        + "Wartość konia to tylko ocena własna właściciela i nie wchodzi do wyniku."

    public static let trainingType = "Rodzaj treningu"
    public static let trainingCount = "Liczba treningów"
    public static let trainingCost = "Koszt"
    public static let trainingTotalTime = "Łączny czas"
    public static let trainingTotalMinutes = "Łączny czas (min)"
    public static let trainingDuration = "Czas (min)"
    public static let trainingTime = "Czas"
    public static let trainingIntensity = "Intensywność"
    public static let trainingRating = "Ocena"
    public static let trainingObstacleHeight = "Wysokość przeszkód (cm)"
    public static let trainingMin = "minimum"
    public static let trainingAverage = "średnia"
    public static let trainingMax = "maksimum"
    public static let trainingSummaryNote = "Statystyki liczone są tylko z treningów, w których dany parametr jest wpisany. "
        + "Intensywność: lekka = 1, średnia = 2, ciężka = 3. Wysokość przeszkód dotyczy tylko treningów „Skoki”."

    public static let rider = "Jeździec"
    public static let date = "Data"
    public static let trainer = "Trener"
    public static let competition = "Zawody"
    public static let discipline = "Dyscyplina"
    public static let className = "Klasa"
    public static let result = "Wynik"
    public static let entryFee = "Wpisowe"
    public static let otherCosts = "Pozostałe koszty"
    public static let prize = "Nagroda"
    public static let riderCosts = "Koszty"
    public static let riderPrizes = "Nagrody"
    public static let riderBalance = "Bilans"
    public static let riderTrainingsNote = "Treningi bez jeźdźca nie są uwzględnione. Koszt jest sumą kosztów wpisanych w treningach; "
        + "średnia ocena liczona jest tylko z ocenionych treningów."
    public static let riderCompetitionsNote = "Starty bez jeźdźca nie są uwzględnione. Koszty = wpisowe + pozostałe koszty; bilans = nagrody − koszty."

    public static func placement(_ place: Int) -> String { "\(place). miejsce" }
    public static func groupTrainings(_ name: String, _ count: Int) -> String { "\(name) (treningów: \(count))" }
    public static func totalTrainings(_ count: Int) -> String { "Razem (treningów: \(count))" }
    public static func groupCompetitions(_ name: String, _ competitions: Int, _ starts: Int) -> String { "\(name) (zawodów: \(competitions), startów: \(starts))" }
    public static func totalCompetitions(_ competitions: Int, _ starts: Int) -> String { "Razem (zawodów: \(competitions), startów: \(starts))" }

    public static let allHorses = "Wszystkie konie i zakupy ogólne"
    public static let generalOnly = "Tylko zakupy ogólne (stajnia)"
    public static let allCategories = "wszystkie"
    public static func filterPeriod(_ from: String, _ to: String) -> String { "Okres: \(from) – \(to)" }
    public static func filterHorses(_ horses: String) -> String { "Konie: \(horses)" }
    public static func filterStatuses(_ statuses: String) -> String { "Statusy: \(statuses)" }
    public static func filterCategories(_ categories: String) -> String { "Kategorie: \(categories)" }
    public static func filterGroupBy(_ groupBy: String) -> String { "Grupowanie: \(groupBy)" }

    public static func status(_ status: HorseStatus) -> String {
        switch status {
        case .active: "Aktywny"
        case .sold: "Sprzedany"
        case .deceased: "Padł"
        case .leased: "Wydzierżawiony"
        case .injured: "Kontuzjowany"
        }
    }

    public static func intensity(_ intensity: Intensity?) -> String {
        switch intensity {
        case .light: "Lekka"
        case .medium: "Średnia"
        case .hard: "Ciężka"
        case nil: ""
        }
    }

    /// Intensywność w statystykach to liczba 1–3.
    public static func intensity(level: Int) -> String {
        intensity(Intensity.allCases.indices.contains(level - 1) ? Intensity.allCases[level - 1] : nil)
    }

    public static func resultStatus(_ status: ResultStatus?) -> String? {
        switch status {
        case .completed: "Ukończony"
        case .eliminated: "Wyeliminowany"
        case .retired: "Wycofany"
        case .didNotStart: "Nie wystartował"
        case nil: nil
        }
    }
}

/// Jak wartości kolumny są zapisywane w eksportach (`ReportCellKind`).
public enum ReportCellKind: Sendable, Equatable {
    case text
    /// Kwota: `1 234,56 zł` na ekranie i w PDF, `1234,56` w CSV.
    case money
    /// Liczba z jednym miejscem po przecinku (średnie).
    case decimal1
    case integer
    /// Minuty: `2 h 5 min` na ekranie i w PDF, liczba minut w CSV.
    case minutes
}

/// Komórka tabeli raportu.
public enum ReportValue: Sendable, Equatable {
    case text(String)
    case integer(Int)
    case number(Money)

    static func of(_ text: String?) -> ReportValue? { text.map(ReportValue.text) }
    static func of(_ value: Int?) -> ReportValue? { value.map(ReportValue.integer) }
    static func of(_ value: Money?) -> ReportValue? { value.map(ReportValue.number) }
}

public struct ReportColumn: Sendable, Equatable {
    public let header: String
    public let kind: ReportCellKind
    /// Nagłówek w CSV, gdy różni się od `header` (np. `Czas (min)`).
    public let csvHeader: String?

    public init(_ header: String, _ kind: ReportCellKind = .text, csvHeader: String? = nil) {
        self.header = header
        self.kind = kind
        self.csvHeader = csvHeader
    }

    public var isNumeric: Bool { kind != .text }
}

/// Raport jako zwykła tabela (research R17): to samo dla ekranu, CSV i PDF.
public struct TabularReport: Sendable, Equatable {
    public let title: String
    public let columns: [ReportColumn]
    public let rows: [[ReportValue?]]
    public let totalRows: [[ReportValue?]]
    public let notes: [String]

    public init(title: String, columns: [ReportColumn], rows: [[ReportValue?]], totalRows: [[ReportValue?]] = [], notes: [String] = []) {
        self.title = title
        self.columns = columns
        self.rows = rows
        self.totalRows = totalRows
        self.notes = notes
    }

    /// Tekst komórki na ekranie i w PDF (brak wartości — „—”).
    public static func display(_ column: ReportColumn, _ value: ReportValue?) -> String {
        switch value {
        case nil: Formats.dash
        case let .text(text): text
        case let .integer(number): column.kind == .minutes ? Formats.duration(minutes: number) : String(number)
        case let .number(amount):
            switch column.kind {
            case .money: Formats.money(amount)
            case .decimal1: Formats.decimal1(amount)
            default: NSDecimalNumber(decimal: amount.value).stringValue.replacingOccurrences(of: ".", with: ",")
            }
        }
    }
}

/// CSV dla polskiego Excela, bajt w bajt jak program (`CsvReportWriter.kt`): UTF‑8 z BOM, `;`, przecinek dziesiętny, `\r\n` także
/// po ostatnim wierszu, cytowanie pól z `;`, `"` i końcami wierszy.
public enum CsvReportWriter {
    static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Nagłówek → wiersze → pusty wiersz → sumy (jeśli są) → pusty wiersz → uwagi (jeśli są).
    public static func write(_ report: TabularReport) -> Data {
        var lines: [[String]] = [report.columns.map { $0.csvHeader ?? $0.header }]
        func convert(_ rows: [[ReportValue?]]) -> [[String]] {
            rows.map { row in row.enumerated().map { index, value in format(report.columns[index], value) } }
        }
        lines += convert(report.rows)
        if !report.totalRows.isEmpty {
            lines.append([])
            lines += convert(report.totalRows)
        }
        if !report.notes.isEmpty {
            lines.append([])
            lines += report.notes.map { [$0] }
        }
        let text = lines.map { $0.map(escape).joined(separator: ";") + "\r\n" }.joined()
        return Data(bom) + Data(text.utf8)
    }

    static func format(_ column: ReportColumn, _ value: ReportValue?) -> String {
        switch value {
        case nil: ""
        case let .text(text): text
        case let .integer(number): String(number)
        case let .number(amount): column.kind == .decimal1 ? Formats.decimal1(amount) : Formats.fixed(amount.value, places: 2, grouping: false)
        }
    }

    static func escape(_ value: String) -> String {
        value.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\r" || $0 == "\n" || $0 == "\r\n" })
            ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
    }
}

// MARK: - Tabele pięciu raportów

public enum ReportTables {
    /// „Koszty”: kolumny wg grupowania, potem Koszty i Przychody; pod tabelą „Razem”, „Ogólne (stajnia)” i „Saldo”.
    public static func costs(_ report: CostReport) -> TabularReport {
        let labels: [String]
        switch report.groupBy?.lowercased() {
        case "horse": labels = [ReportTexts.horse, ReportTexts.category]
        case "month": labels = [ReportTexts.month, ReportTexts.category]
        default: labels = [ReportTexts.category]
        }
        let columns = labels.map { ReportColumn($0) } + [ReportColumn(ReportTexts.costs, .money), ReportColumn(ReportTexts.income, .money)]
        let rows: [[ReportValue?]] = report.rows.map { row -> [ReportValue?] in
            labels.count == 1 ? [.text(row.group), .number(row.costs), .number(row.income)]
                : [.text(row.group), .of(row.category), .number(row.costs), .number(row.income)]
        }
        let blanks = [ReportValue?](repeating: nil, count: labels.count - 1)
        func line(_ label: String, _ costs: Money?, _ income: Money?) -> [ReportValue?] {
            var cells: [ReportValue?] = [.text(label)]
            cells += blanks
            cells.append(costs.map(ReportValue.number))
            cells.append(income.map(ReportValue.number))
            return cells
        }
        let totals = [
            line(ReportTexts.total, report.totalCosts, report.totalIncome),
            line(ReportTexts.general, report.generalPurchasesTotal, nil),
            line(ReportTexts.balance, nil, report.balance),
        ]
        return TabularReport(title: ReportTexts.costTitle, columns: columns, rows: rows, totalRows: totals)
    }

    public static func horseBalance(_ report: HorseBalanceReport) -> TabularReport {
        let columns = [
            ReportColumn(ReportTexts.horse), ReportColumn(ReportTexts.balanceStatus), ReportColumn(ReportTexts.balancePurchase, .money),
            ReportColumn(ReportTexts.costs, .money), ReportColumn(ReportTexts.balancePrizes, .money), ReportColumn(ReportTexts.balanceSale, .money),
            ReportColumn(ReportTexts.balanceResult, .money), ReportColumn(ReportTexts.balanceEstimatedValue, .money), ReportColumn(ReportTexts.balanceRemarks),
        ]
        let rows: [[ReportValue?]] = report.rows.map { row -> [ReportValue?] in
            [.text(row.horseName), .of(row.status.map(ReportTexts.status)), .of(row.purchasePrice), .number(row.costs), .number(row.prizes),
             .of(row.salePrice), .number(row.result), .of(row.estimatedValue), .text(remarks(row))]
        }
        let totals = report.totals
        let total: [ReportValue?] = [.text(ReportTexts.total), nil, .number(totals.purchasePrice), .number(totals.costs), .number(totals.prizes),
                                     .number(totals.salePrice), .number(totals.result), nil, .text(resultText(totals.result))]
        return TabularReport(title: ReportTexts.balanceTitle, columns: columns, rows: rows, totalRows: [total], notes: [ReportTexts.balanceNote])
    }

    /// „zysk” albo „strata”, potem to, czego wynik nie obejmuje: brak ceny zakupu, koń niesprzedany (FR-027/028).
    public static func remarks(_ row: HorseBalanceRow) -> String {
        var parts: [String] = []
        let result = resultText(row.result)
        if !result.isEmpty { parts.append(result) }
        if row.purchaseMissing { parts.append(ReportTexts.balanceNoPurchase) }
        if !row.isFinal { parts.append(ReportTexts.balanceNotSold) }
        return parts.joined(separator: "; ")
    }

    public static func resultText(_ result: Money) -> String {
        result.value > 0 ? ReportTexts.balanceProfit : (result.value < 0 ? ReportTexts.balanceLoss : "")
    }

    public static func trainingSummary(_ report: TrainingSummaryReport) -> TabularReport {
        var columns = [
            ReportColumn(ReportTexts.trainingType), ReportColumn(ReportTexts.trainingCount, .integer),
            ReportColumn(ReportTexts.trainingTotalTime, .minutes, csvHeader: ReportTexts.trainingTotalMinutes), ReportColumn(ReportTexts.trainingCost, .money),
        ]
        for parameter in [ReportTexts.trainingDuration, ReportTexts.trainingIntensity, ReportTexts.trainingRating, ReportTexts.trainingObstacleHeight] {
            let bounds: ReportCellKind = parameter == ReportTexts.trainingIntensity ? .text : .integer
            columns.append(ReportColumn("\(parameter) — \(ReportTexts.trainingMin)", bounds))
            columns.append(ReportColumn("\(parameter) — \(ReportTexts.trainingAverage)", .decimal1))
            columns.append(ReportColumn("\(parameter) — \(ReportTexts.trainingMax)", bounds))
        }
        func whole(_ stat: TrainingStat?) -> [ReportValue?] {
            guard let stat else { return [nil, nil, nil] }
            return [.integer(NSDecimalNumber(decimal: stat.min.value).intValue), .number(stat.average), .integer(NSDecimalNumber(decimal: stat.max.value).intValue)]
        }
        func intensity(_ stat: TrainingStat?) -> [ReportValue?] {
            guard let stat else { return [nil, nil, nil] }
            return [.text(ReportTexts.intensity(level: NSDecimalNumber(decimal: stat.min.value).intValue)), .number(stat.average),
                    .text(ReportTexts.intensity(level: NSDecimalNumber(decimal: stat.max.value).intValue))]
        }
        func row(_ row: TrainingSummaryRow) -> [ReportValue?] {
            [.text(row.typeName), .integer(row.count), .integer(row.totalMinutes), .number(row.totalCost)]
                + whole(row.duration) + intensity(row.intensity) + whole(row.rating) + whole(row.obstacleHeight)
        }
        return TabularReport(
            title: ReportTexts.trainingSummaryTitle, columns: columns, rows: report.rows.map(row), totalRows: report.total.map { [row($0)] } ?? [],
            notes: [ReportTexts.trainingSummaryNote]
        )
    }

    public static func riderTrainings(_ report: RiderTrainingsReport) -> TabularReport {
        let allRiders = report.riderContactId == nil
        var columns: [ReportColumn] = allRiders ? [ReportColumn(ReportTexts.rider)] : []
        columns += [
            ReportColumn(ReportTexts.date), ReportColumn(ReportTexts.horse), ReportColumn(ReportTexts.trainingType),
            ReportColumn(ReportTexts.trainingTime, .minutes, csvHeader: ReportTexts.trainingDuration), ReportColumn(ReportTexts.trainingIntensity),
            ReportColumn(ReportTexts.trainingRating, .decimal1), ReportColumn(ReportTexts.trainer), ReportColumn(ReportTexts.trainingCost, .money),
        ]
        let rows: [[ReportValue?]] = report.rows.map { row -> [ReportValue?] in
            let head: [ReportValue?] = allRiders ? [.text(row.riderName)] : []
            return head + [.text(Formats.date(row.date)), .text(row.horseName), .text(row.typeName), .of(row.durationMinutes),
                   .of(row.intensity.map { ReportTexts.intensity($0) }), .of(row.rating), .of(row.trainerName), .of(row.cost)]
        }
        func sum(_ label: String, _ minutes: Int, _ average: Money?, _ cost: Money) -> [ReportValue?] {
            [.text(label)] + [ReportValue?](repeating: nil, count: columns.count - 6) + [.integer(minutes), nil, .of(average), nil, .number(cost)]
        }
        let totals = report.groups.map { sum(ReportTexts.groupTrainings($0.name, $0.count), $0.totalMinutes, $0.averageRating, $0.totalCost) }
            + [sum(ReportTexts.totalTrainings(report.total.count), report.total.totalMinutes, report.total.averageRating, report.total.totalCost)]
        let title = "\(ReportTexts.riderTrainingsTitle): \(report.riderName ?? ReportTexts.allRiders)"
        return TabularReport(title: title, columns: columns, rows: rows, totalRows: totals, notes: [ReportTexts.riderTrainingsNote])
    }

    public static func riderCompetitions(_ report: RiderCompetitionsReport) -> TabularReport {
        let allRiders = report.riderContactId == nil
        var columns: [ReportColumn] = allRiders ? [ReportColumn(ReportTexts.rider)] : []
        columns += [
            ReportColumn(ReportTexts.competition), ReportColumn(ReportTexts.date), ReportColumn(ReportTexts.horse), ReportColumn(ReportTexts.discipline),
            ReportColumn(ReportTexts.className), ReportColumn(ReportTexts.result), ReportColumn(ReportTexts.entryFee, .money),
            ReportColumn(ReportTexts.otherCosts, .money), ReportColumn(ReportTexts.prize, .money),
        ]
        let rows: [[ReportValue?]] = report.competitions.flatMap { competition in
            competition.starts.map { start -> [ReportValue?] in
                let head: [ReportValue?] = allRiders ? [.text(start.riderName)] : []
                return head + [.text(competition.name), .text(Formats.date(start.date ?? competition.dateFrom)), .text(start.horseName), .of(start.disciplineName),
                       .of(start.className), .of(resultText(start)), .of(start.entryFee), .of(start.otherCosts), .of(start.prizeMoney)]
            }
        }
        func sum(_ label: String, _ of: [RiderCompetitionStartRow]) -> [ReportValue?] {
            var fees = Money.zero
            var other = Money.zero
            var prizes = Money.zero
            for start in of {
                fees = fees + (start.entryFee ?? .zero)
                other = other + (start.otherCosts ?? .zero)
                prizes = prizes + (start.prizeMoney ?? .zero)
            }
            var cells: [ReportValue?] = [.text(label)]
            cells += [ReportValue?](repeating: nil, count: columns.count - 4)
            cells.append(.number(fees))
            cells.append(.number(other))
            cells.append(.number(prizes))
            return cells
        }
        func labelled(_ label: String, _ value: Money) -> [ReportValue?] {
            var cells: [ReportValue?] = [.text(label)]
            cells += [ReportValue?](repeating: nil, count: columns.count - 2)
            cells.append(.number(value))
            return cells
        }
        let all = report.competitions.flatMap(\.starts)
        let totals = report.groups.map { group in
            sum(ReportTexts.groupCompetitions(group.riderName, group.competitions, group.starts), all.filter { $0.riderContactId == group.riderContactId })
        } + [
            sum(ReportTexts.totalCompetitions(report.total.competitions, report.total.starts), all),
            labelled(ReportTexts.riderCosts, report.total.totalCosts),
            labelled(ReportTexts.riderPrizes, report.total.totalPrizes),
            labelled(ReportTexts.riderBalance, report.total.balance),
        ]
        let title = "\(ReportTexts.riderCompetitionsTitle): \(report.riderName ?? ReportTexts.allRiders)"
        return TabularReport(title: title, columns: columns, rows: rows, totalRows: totals, notes: [ReportTexts.riderCompetitionsNote])
    }

    /// „2. miejsce” albo status startu bez miejsca; `nil`, gdy nie ma jeszcze wyniku.
    public static func resultText(_ start: RiderCompetitionStartRow) -> String? {
        start.placement.map(ReportTexts.placement) ?? ReportTexts.resultStatus(start.resultStatus)
    }
}
