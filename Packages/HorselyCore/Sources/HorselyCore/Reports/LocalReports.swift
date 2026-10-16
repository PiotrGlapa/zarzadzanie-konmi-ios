import Foundation

/// Brak rekordu, o który pyta raport (jeździec, koń) — `404` w programie.
public struct ReportTargetNotFound: Error, Equatable, Sendable {
    public let what: String
    public let id: String
}

/// Okres podsumowania treningów (`TrainingPeriods`).
public enum TrainingRange: String, CaseIterable, Sendable, Hashable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case all = "All"

    /// Pierwszy i ostatni dzień okresu zawierającego `anchor`; oba `nil` dla całej historii.
    public func period(_ anchor: LocalDate) -> (from: LocalDate?, to: LocalDate?) {
        switch self {
        case .week: (anchor.weekStart, anchor.weekEnd)
        case .month: (anchor.firstOfMonth, anchor.firstOfMonth.adding(months: 1).adding(days: -1))
        case .year: (LocalDate(year: anchor.year, month: 1, day: 1), LocalDate(year: anchor.year, month: 12, day: 31))
        case .all: (nil, nil)
        }
    }

    /// Dzień, na który trening liczy się w wykresie: dzień (tydzień, miesiąc), poniedziałek tygodnia (rok), pierwszy dzień miesiąca
    /// (cała historia).
    func bucket(_ date: LocalDate) -> LocalDate {
        switch self {
        case .week, .month: date
        case .year: date.weekStart
        case .all: date.firstOfMonth
        }
    }
}

/// Grupowanie raportu kosztów.
public enum CostGroupBy: String, CaseIterable, Sendable, Hashable {
    case horse = "Horse"
    case month = "Month"
    case category = "Category"
}

/// Filtr raportu kosztów; `generalOnly` — tylko zakupy ogólne (stajnia).
public struct CostFilter: Hashable, Sendable {
    public var from: LocalDate?
    public var to: LocalDate?
    public var horseIds: [String]
    public var generalOnly: Bool
    public var categories: [String]
    public var groupBy: CostGroupBy

    public init(from: LocalDate? = nil, to: LocalDate? = nil, horseIds: [String] = [], generalOnly: Bool = false, categories: [String] = [], groupBy: CostGroupBy = .month) {
        self.from = from
        self.to = to
        self.horseIds = horseIds
        self.generalOnly = generalOnly
        self.categories = categories
        self.groupBy = groupBy
    }
}

/// Raporty z danych lokalnych (`LocalReports.kt`, port `Reports/…Query.cs` programu): ten sam wynik co odpowiedź programu na tych
/// samych danych (pliki wzorcowe `parity/*/reports`).
public struct LocalReports {
    let source: RecordSource

    public init(source: RecordSource) {
        self.source = source
    }

    // MARK: Koszty

    public func costReport(_ filter: CostFilter) throws -> CostReport {
        let result = try CostCalculator.entries(source: source, from: filter.from, to: filter.to)
        var selected = result.entries
        if filter.generalOnly {
            selected = selected.filter { $0.horseId == nil }
        } else if !filter.horseIds.isEmpty {
            selected = selected.filter { $0.horseId.map(filter.horseIds.contains) ?? false }
        }
        if !filter.categories.isEmpty {
            selected = selected.filter { entry in filter.categories.contains { $0.caseInsensitiveCompare(entry.category) == .orderedSame } }
        }
        func horseName(_ id: String?) -> String { id.map { result.horseNames[$0] ?? "" } ?? CostCalculator.general }
        func sum(_ list: [CostEntry]) -> (Money, Money) {
            (list.reduce(Money.zero) { $0 + $1.cost }, list.reduce(Money.zero) { $0 + $1.income })
        }
        func categories(_ list: [CostEntry]) -> [(name: String, entries: [CostEntry])] {
            let groups = Dictionary(grouping: list) { "\($0.categoryOrder)\u{1}\($0.category)" }
            return groups.values.map { (name: $0[0].category, order: $0[0].categoryOrder, entries: $0) }
                .sorted { $0.order != $1.order ? $0.order < $1.order : PolishNames.isOrdered($0.name, before: $1.name) }
                .map { (name: $0.name, entries: $0.entries) }
        }
        var rows: [CostReportRow] = []
        switch filter.groupBy {
        case .horse:
            let byHorse = Dictionary(grouping: selected) { $0.horseId ?? "" }
            let keys = byHorse.keys.sorted { a, b in
                if a.isEmpty != b.isEmpty { return b.isEmpty }
                return PolishNames.isOrdered(horseName(a.isEmpty ? nil : a), before: horseName(b.isEmpty ? nil : b))
            }
            for key in keys {
                let horse: String? = key.isEmpty ? nil : key
                for category in categories(byHorse[key] ?? []) {
                    let (costs, income) = sum(category.entries)
                    rows.append(CostReportRow(group: horseName(horse), horseId: horse, category: category.name, month: nil, costs: costs, income: income))
                }
            }
        case .month:
            let byMonth = Dictionary(grouping: selected, by: \.month)
            for month in byMonth.keys.sorted() {
                for category in categories(byMonth[month] ?? []) {
                    let (costs, income) = sum(category.entries)
                    rows.append(CostReportRow(group: month, horseId: nil, category: category.name, month: month, costs: costs, income: income))
                }
            }
        case .category:
            for category in categories(selected) {
                let (costs, income) = sum(category.entries)
                rows.append(CostReportRow(group: category.name, horseId: nil, category: category.name, month: nil, costs: costs, income: income))
            }
        }
        let (totalCosts, totalIncome) = sum(selected)
        return CostReport(
            from: filter.from, to: filter.to, groupBy: filter.groupBy.rawValue, rows: rows,
            generalPurchasesTotal: selected.filter { $0.horseId == nil }.reduce(Money.zero) { $0 + $1.cost },
            totalCosts: totalCosts, totalIncome: totalIncome, balance: totalIncome - totalCosts
        )
    }

    // MARK: Bilans konia

    public func horseBalance(statuses: [HorseStatus] = [], horseIds: [String] = []) throws -> HorseBalanceReport {
        let horses = try source.records(.horse, as: LocalHorse.self)
            .filter { (statuses.isEmpty || statuses.contains($0.status)) && (horseIds.isEmpty || horseIds.contains($0.id)) }
            .sorted { PolishNames.compare($0.name, $1.name) != .orderedSame ? PolishNames.isOrdered($0.name, before: $1.name) : $0.id < $1.id }
        let byHorse = Dictionary(grouping: try CostCalculator.entries(source: source, from: nil, to: nil).entries.filter { $0.horseId != nil }) { $0.horseId! }
        let rows = horses.map { horse -> HorseBalanceRow in
            let entries = byHorse[horse.id] ?? []
            let costs = entries.reduce(Money.zero) { $0 + $1.cost }
            let prizes = entries.reduce(Money.zero) { $0 + $1.income }
            let sale = HorseRules.effectiveSalePrice(horse)
            let result = (sale ?? .zero) + prizes - (horse.purchasePrice ?? .zero) - costs
            let grouped = Dictionary(grouping: entries.filter { $0.cost.value != 0 }) { "\($0.date.year)\u{1}\($0.categoryOrder)\u{1}\($0.category)" }
            let breakdown = grouped.values
                .map { (year: $0[0].date.year, order: $0[0].categoryOrder, category: $0[0].category, costs: $0.reduce(Money.zero) { $0 + $1.cost }) }
                .sorted {
                    if $0.year != $1.year { return $0.year < $1.year }
                    if $0.order != $1.order { return $0.order < $1.order }
                    return PolishNames.isOrdered($0.category, before: $1.category)
                }
                .map { HorseBalanceBreakdown(year: $0.year, category: $0.category, costs: $0.costs) }
            return HorseBalanceRow(
                horseId: horse.id, horseName: horse.name, status: horse.status, purchasePrice: horse.purchasePrice, costs: costs, prizes: prizes,
                salePrice: sale, estimatedValue: horse.estimatedValue, result: result, isFinal: sale != nil, purchaseMissing: horse.purchasePrice == nil,
                breakdown: breakdown
            )
        }
        let totals = HorseBalanceTotals(
            purchasePrice: rows.reduce(Money.zero) { $0 + ($1.purchasePrice ?? .zero) },
            costs: rows.reduce(Money.zero) { $0 + $1.costs },
            prizes: rows.reduce(Money.zero) { $0 + $1.prizes },
            salePrice: rows.reduce(Money.zero) { $0 + ($1.salePrice ?? .zero) },
            result: rows.reduce(Money.zero) { $0 + $1.result }
        )
        return HorseBalanceReport(rows: rows, totals: totals)
    }

    // MARK: Podsumowanie treningów

    public func trainingSummary(horseId: String, range: TrainingRange, anchor: LocalDate) throws -> TrainingSummaryReport {
        guard let horse = try source.find(.horse, id: horseId, as: LocalHorse.self) else { throw ReportTargetNotFound(what: "Horse", id: horseId) }
        let period = range.period(anchor)
        let list = try source.records(.training, as: LocalTraining.self, horseId: horseId, from: period.from, to: period.to)
            .stableSorted { ($0.trainingDate, $0.createdAt) < ($1.trainingDate, $1.createdAt) }
        let types = try source.query(.dictionary, horseId: nil, from: nil, to: nil, includeDeleted: true)
            .compactMap { $0.record as? LocalDictionaryItem }
            .filter { $0.dictionaryType == .trainingType }
            .sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
        let first = range == .all ? list.first?.trainingDate : period.from
        let last = range == .all ? list.last?.trainingDate : period.to
        var rows: [TrainingSummaryRow] = []
        var series: [TrainingSeries] = []
        for (index, type) in types.enumerated() {
            let ofType = list.filter { $0.trainingTypeId == type.id }
            if ofType.isEmpty { continue }
            let jumping = type.systemKey == DefaultDictionaries.trainingJumping
            rows.append(Self.row(typeId: type.id, name: type.value, palette: index, ofType, includeHeight: jumping))
            Self.addSeries(&series, "Duration", type.id, ofType, range) { $0.durationMinutes }
            Self.addSeries(&series, "Rating", type.id, ofType, range) { $0.rating }
            if jumping { Self.addSeries(&series, "ObstacleHeight", type.id, ofType, range) { $0.obstacleHeightCm } }
        }
        return TrainingSummaryReport(
            horseId: horse.id, horseName: horse.name, range: range.rawValue, from: first, to: last, rows: rows,
            total: Self.row(typeId: nil, name: CostCalculator.total, palette: -1, list, includeHeight: false), series: series
        )
    }

    static func row(typeId: String?, name: String, palette: Int, _ list: [LocalTraining], includeHeight: Bool) -> TrainingSummaryRow {
        TrainingSummaryRow(
            typeId: typeId, typeName: name, paletteIndex: palette, count: list.count, totalMinutes: list.reduce(0) { $0 + ($1.durationMinutes ?? 0) },
            duration: stat(list.map(\.durationMinutes)),
            intensity: stat(list.map { training in training.intensity.map { (Intensity.allCases.firstIndex(of: $0) ?? 0) + 1 } }),
            rating: stat(list.map(\.rating)),
            obstacleHeight: includeHeight ? stat(list.map(\.obstacleHeightCm)) : nil,
            totalCost: list.reduce(Money.zero) { $0 + ($1.cost ?? .zero) }
        )
    }

    /// Minimum, średnia (jedno miejsce po przecinku, od zera w górę) i maksimum wpisanych wartości; `nil`, gdy żadnej nie wpisano.
    static func stat(_ values: [Int?]) -> TrainingStat? {
        let entered = values.compactMap { $0 }
        guard let minimum = entered.min(), let maximum = entered.max() else { return nil }
        return TrainingStat(min: Money(minimum), average: average(entered, places: 1), max: Money(maximum))
    }

    static func average(_ values: [Int], places: Int) -> Money {
        Money(Decimal(values.reduce(0, +)) / Decimal(values.count)).rounded(places: places)
    }

    static func addSeries(_ series: inout [TrainingSeries], _ parameter: String, _ typeId: String, _ list: [LocalTraining], _ range: TrainingRange, _ value: (LocalTraining) -> Int?) {
        let grouped = Dictionary(grouping: list.filter { value($0) != nil }) { range.bucket($0.trainingDate) }
        let points = grouped.keys.sorted().map { day in
            TrainingSeriesPoint(date: day, value: average(grouped[day]!.map { value($0)! }, places: 2))
        }
        if !points.isEmpty { series.append(TrainingSeries(parameter: parameter, typeId: typeId, points: points)) }
    }

    // MARK: Treningi jeźdźca

    public func riderTrainings(riderId: String?, from: LocalDate?, to: LocalDate?, horseId: String?) throws -> RiderTrainingsReport {
        let riderName = try riderId.map { id in
            guard let contact = try source.find(.contact, id: id, as: LocalContact.self) else { throw ReportTargetNotFound(what: "Contact", id: id) }
            return contact.name
        }
        if let horseId, try source.find(.horse, id: horseId, as: LocalHorse.self) == nil { throw ReportTargetNotFound(what: "Horse", id: horseId) }
        let trainings = try source.records(.training, as: LocalTraining.self, horseId: horseId, from: from, to: to)
            .filter { $0.riderContactId != nil && (riderId == nil || $0.riderContactId == riderId) }
        let horses = try CostCalculator.names(source, .horse)
        let dictionary = try CostCalculator.names(source, .dictionary)
        let contacts = try CostCalculator.names(source, .contact)
        let rows = trainings.map { t in
            RiderTrainingsRow(
                trainingId: t.id, date: t.trainingDate, horseId: t.horseId, horseName: horses[t.horseId] ?? "", typeName: dictionary[t.trainingTypeId] ?? "",
                durationMinutes: t.durationMinutes, intensity: t.intensity, rating: t.rating, trainerName: t.trainerContactId.flatMap { contacts[$0] }, cost: t.cost,
                riderContactId: t.riderContactId, riderName: contacts[t.riderContactId!] ?? ""
            )
        }.stableSorted { a, b in
            if riderId == nil, PolishNames.compare(a.riderName, b.riderName) != .orderedSame { return PolishNames.isOrdered(a.riderName, before: b.riderName) }
            if a.date != b.date { return a.date < b.date }
            return PolishNames.isOrdered(a.horseName, before: b.horseName)
        }
        let grouped = Dictionary(grouping: rows) { riderId == nil ? $0.riderContactId! : $0.horseId }
        let groups = grouped.map { key, items in (key: key, name: riderId == nil ? items[0].riderName : items[0].horseName, items: items) }
            .sorted { PolishNames.isOrdered($0.name, before: $1.name) }
            .map { group in
                RiderTrainingsGroup(
                    key: group.key, name: group.name, count: group.items.count, totalMinutes: group.items.reduce(0) { $0 + ($1.durationMinutes ?? 0) },
                    averageRating: Self.averageRating(group.items), totalCost: group.items.reduce(Money.zero) { $0 + ($1.cost ?? .zero) }
                )
            }
        let total = RiderTrainingsTotals(
            count: rows.count, totalMinutes: rows.reduce(0) { $0 + ($1.durationMinutes ?? 0) }, averageRating: Self.averageRating(rows),
            totalCost: rows.reduce(Money.zero) { $0 + ($1.cost ?? .zero) }
        )
        return RiderTrainingsReport(from: from, to: to, riderContactId: riderId, riderName: riderName, rows: rows, total: total, groups: groups, groupedBy: riderId == nil ? "Rider" : "Horse")
    }

    static func averageRating(_ rows: [RiderTrainingsRow]) -> Money? {
        let rated = rows.compactMap(\.rating)
        return rated.isEmpty ? nil : average(rated, places: 1)
    }

    // MARK: Zawody jeźdźca

    public func riderCompetitions(riderId: String?, from: LocalDate?, to: LocalDate?, horseId: String?) throws -> RiderCompetitionsReport {
        let riderName = try riderId.map { id in
            guard let contact = try source.find(.contact, id: id, as: LocalContact.self) else { throw ReportTargetNotFound(what: "Contact", id: id) }
            return contact.name
        }
        if let horseId, try source.find(.horse, id: horseId, as: LocalHorse.self) == nil { throw ReportTargetNotFound(what: "Horse", id: horseId) }
        let competitions = Dictionary(uniqueKeysWithValues: try source.records(.competition, as: LocalCompetition.self).map { ($0.id, $0) })
        let horses = try CostCalculator.names(source, .horse)
        let dictionary = try CostCalculator.names(source, .dictionary)
        let contacts = try CostCalculator.names(source, .contact)
        let starts = try source.records(.competitionStart, as: LocalCompetitionStart.self, horseId: horseId)
            .filter { $0.riderContactId != nil && (riderId == nil || $0.riderContactId == riderId) && competitions[$0.competitionId] != nil }
            .filter { start in
                let day = start.startDate ?? competitions[start.competitionId]!.dateFrom
                return (from.map { day >= $0 } ?? true) && (to.map { day <= $0 } ?? true)
            }
        let rows = starts.map { s -> (competition: LocalCompetition, row: RiderCompetitionStartRow) in
            let competition = competitions[s.competitionId]!
            return (competition, RiderCompetitionStartRow(
                startId: s.id, date: s.startDate ?? competition.dateFrom, horseId: s.horseId, horseName: horses[s.horseId] ?? "",
                disciplineName: (s.disciplineId ?? competition.disciplineId).flatMap { dictionary[$0] }, className: s.className, resultStatus: s.resultStatus,
                placement: s.placement, participantsCount: s.participantsCount, entryFee: s.entryFee, otherCosts: s.otherCosts, prizeMoney: s.prizeMoney,
                riderContactId: s.riderContactId, riderName: contacts[s.riderContactId!] ?? ""
            ))
        }
        var order: [String] = []
        var byCompetition: [String: [(competition: LocalCompetition, row: RiderCompetitionStartRow)]] = [:]
        for item in rows {
            if byCompetition[item.competition.id] == nil { order.append(item.competition.id) }
            byCompetition[item.competition.id, default: []].append(item)
        }
        let competitionRows = order.map { id -> RiderCompetitionRow in
            let group = byCompetition[id]!
            let competition = group[0].competition
            let sortedStarts = group.map(\.row).stableSorted { a, b in
                if riderId == nil, PolishNames.compare(a.riderName, b.riderName) != .orderedSame { return PolishNames.isOrdered(a.riderName, before: b.riderName) }
                if a.date != b.date { return (a.date ?? competition.dateFrom) < (b.date ?? competition.dateFrom) }
                if PolishNames.compare(a.horseName, b.horseName) != .orderedSame { return PolishNames.isOrdered(a.horseName, before: b.horseName) }
                return PolishNames.isOrdered(a.className ?? "", before: b.className ?? "")
            }
            return RiderCompetitionRow(competitionId: competition.id, name: competition.name, dateFrom: competition.dateFrom, dateTo: competition.dateTo, city: competition.city, starts: sortedStarts)
        }.stableSorted { a, b in
            let firstA = a.starts.compactMap(\.date).min() ?? a.dateFrom
            let firstB = b.starts.compactMap(\.date).min() ?? b.dateFrom
            if firstA != firstB { return firstA < firstB }
            return PolishNames.isOrdered(a.name, before: b.name)
        }
        func sums(_ items: [(competition: LocalCompetition, row: RiderCompetitionStartRow)]) -> RiderCompetitionsTotals {
            let costs = items.reduce(Money.zero) { $0 + ($1.row.entryFee ?? .zero) + ($1.row.otherCosts ?? .zero) }
            let prizes = items.reduce(Money.zero) { $0 + ($1.row.prizeMoney ?? .zero) }
            return RiderCompetitionsTotals(competitions: Set(items.map(\.competition.id)).count, starts: items.count, totalCosts: costs, totalPrizes: prizes, balance: prizes - costs)
        }
        var groups: [RiderCompetitionsGroup] = []
        if riderId == nil {
            groups = Dictionary(grouping: rows) { $0.row.riderContactId! }
                .map { id, items in (id: id, name: items[0].row.riderName, sums: sums(items)) }
                .sorted { PolishNames.isOrdered($0.name, before: $1.name) }
                .map { RiderCompetitionsGroup(
                    riderContactId: $0.id, riderName: $0.name, competitions: $0.sums.competitions, starts: $0.sums.starts, totalCosts: $0.sums.totalCosts,
                    totalPrizes: $0.sums.totalPrizes, balance: $0.sums.balance
                ) }
        }
        return RiderCompetitionsReport(from: from, to: to, riderContactId: riderId, riderName: riderName, competitions: competitionRows, total: sums(rows), groups: groups)
    }
}

extension Array {
    /// Sortowanie stabilne (jak `sortedWith` w Kotlinie): równe elementy zachowują kolejność wejściową.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if areInIncreasingOrder(a.element, b.element) { return true }
            if areInIncreasingOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}
