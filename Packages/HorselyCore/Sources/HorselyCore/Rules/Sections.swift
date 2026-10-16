import Foundation

/// Okres filtra działów Treningi, Zakupy i Zawody (`ListPeriod.kt`, US11/5): domyślnie cały bieżący rok — 1 stycznia do 31 grudnia
/// (koniec nie jest „dziś”: zawody zaplanowane na później w tym roku też się mieszczą). `nil` — bez ograniczenia.
public struct ListPeriod: Hashable, Sendable {
    public var from: LocalDate?
    public var to: LocalDate?

    public init(from: LocalDate?, to: LocalDate?) {
        self.from = from
        self.to = to
    }

    public static func `default`(today: LocalDate) -> ListPeriod {
        ListPeriod(from: LocalDate(year: today.year, month: 1, day: 1), to: LocalDate(year: today.year, month: 12, day: 31))
    }
}

/// Przypisanie w filtrze zakupów: wszystkie, konkretny koń albo „Ogólne (stajnia)”.
public enum PurchaseScope: Hashable, Sendable {
    case all
    case horse(String)
    case general
}

/// Filtr działu Treningi (`TrainingService.ListAsync`).
public struct TrainingQuery: Hashable, Sendable {
    public var period: ListPeriod
    public var horseId: String?
    public var typeId: String?
    public var trainerId: String?
    public var riderId: String?

    public init(period: ListPeriod, horseId: String? = nil, typeId: String? = nil, trainerId: String? = nil, riderId: String? = nil) {
        self.period = period
        self.horseId = horseId
        self.typeId = typeId
        self.trainerId = trainerId
        self.riderId = riderId
    }

    /// Liczba włączonych filtrów poza okresem domyślnym („Filtry (N)”).
    public func activeCount(today: LocalDate) -> Int {
        [period != .default(today: today), horseId != nil, typeId != nil, trainerId != nil, riderId != nil].filter { $0 }.count
    }
}

/// Filtr działu Zakupy (`PurchaseService.ListAsync`).
public struct PurchaseQuery: Hashable, Sendable {
    public var period: ListPeriod
    public var scope: PurchaseScope
    public var categoryId: String?
    public var supplierId: String?

    public init(period: ListPeriod, scope: PurchaseScope = .all, categoryId: String? = nil, supplierId: String? = nil) {
        self.period = period
        self.scope = scope
        self.categoryId = categoryId
        self.supplierId = supplierId
    }

    public func activeCount(today: LocalDate) -> Int {
        [period != .default(today: today), scope != .all, categoryId != nil, supplierId != nil].filter { $0 }.count
    }
}

/// Filtr działu Zawody (`CompetitionService.ListAsync`): okres obejmuje zawody nachodzące na niego.
public struct CompetitionQuery: Hashable, Sendable {
    public var period: ListPeriod
    public var horseId: String?
    public var disciplineId: String?

    public init(period: ListPeriod, horseId: String? = nil, disciplineId: String? = nil) {
        self.period = period
        self.horseId = horseId
        self.disciplineId = disciplineId
    }

    public func activeCount(today: LocalDate) -> Int {
        [period != .default(today: today), horseId != nil, disciplineId != nil].filter { $0 }.count
    }
}

/// Lista działu z liczbą i sumą całego filtra (stopka „Treningów: N · Razem: kwota”).
public struct SectionList<Item: Sendable>: Sendable {
    public let items: [Item]
    public let total: Money

    public var count: Int { items.count }
}

/// Zawody na liście z liczbą startów i najlepszym miejscem.
public struct CompetitionListItem: Hashable, Sendable, Identifiable {
    public let competition: LocalCompetition
    public let startsCount: Int
    public let bestPlacement: Int?

    public var id: String { competition.id }
}

/// Listy i sumy działów z danych w telefonie (`LocalSections.kt`): te same filtry, kolejność i sumy co program.
public struct LocalSections {
    let source: RecordSource

    public init(source: RecordSource) {
        self.source = source
    }

    /// Treningi od najnowszych (data, potem chwila zapisu); suma — koszty treningów.
    public func trainings(_ query: TrainingQuery) throws -> SectionList<LocalTraining> {
        let items = try source.records(.training, as: LocalTraining.self, horseId: query.horseId, from: query.period.from, to: query.period.to)
            .filter {
                (query.typeId == nil || $0.trainingTypeId == query.typeId) && (query.riderId == nil || $0.riderContactId == query.riderId)
                    && (query.trainerId == nil || $0.trainerContactId == query.trainerId)
            }
            .sorted { ($0.trainingDate, $0.createdAt) > ($1.trainingDate, $1.createdAt) }
        return SectionList(items: items, total: items.reduce(Money.zero) { $0 + ($1.cost ?? .zero) })
    }

    /// Zakupy od najnowszych; suma „Razem” — kwota z dostawą (`totalCost` programu).
    public func purchases(_ query: PurchaseQuery) throws -> SectionList<LocalPurchase> {
        var items = try source.records(.purchase, as: LocalPurchase.self, from: query.period.from, to: query.period.to)
        switch query.scope {
        case .all: break
        case .general: items = items.filter { $0.assignment == .general }
        case let .horse(id): items = items.filter { $0.horseIds.contains(id) }
        }
        if let category = query.categoryId { items = items.filter { $0.categoryId == category } }
        if let supplier = query.supplierId { items = items.filter { $0.supplierContactId == supplier } }
        items.sort { ($0.purchaseDate, $0.createdAt) > ($1.purchaseDate, $1.createdAt) }
        return SectionList(items: items, total: items.reduce(Money.zero) { $0 + $1.totalAmount + $1.deliveryCost })
    }

    /// Zawody od najnowszych (potem nazwa), z liczbą startów i najlepszym miejscem.
    public func competitions(_ query: CompetitionQuery) throws -> [CompetitionListItem] {
        let starts = Dictionary(grouping: try source.records(.competitionStart, as: LocalCompetitionStart.self), by: \.competitionId)
        var all = try source.records(.competition, as: LocalCompetition.self)
        if let horse = query.horseId { all = all.filter { (starts[$0.id] ?? []).contains { $0.horseId == horse } } }
        if let discipline = query.disciplineId {
            all = all.filter { $0.disciplineId == discipline || (starts[$0.id] ?? []).contains { $0.disciplineId == discipline } }
        }
        if let from = query.period.from { all = all.filter { ($0.dateTo ?? $0.dateFrom) >= from } }
        if let to = query.period.to { all = all.filter { $0.dateFrom <= to } }
        all.sort { $0.dateFrom != $1.dateFrom ? $0.dateFrom > $1.dateFrom : $0.name < $1.name }
        return all.map { competition in
            let own = starts[competition.id] ?? []
            return CompetitionListItem(competition: competition, startsCount: own.count, bestPlacement: own.compactMap(\.placement).min())
        }
    }
}

/// „Powtórz zakup” (`PurchaseRepeat.kt`): dane wejściowe zakupu z dzisiejszą datą — konie, przypisanie, kwoty, dostawa, dostawca
/// i uwagi; bez identyfikatora, wersji i załączników.
public enum PurchaseRepeat {
    public static func from(_ purchase: LocalPurchase, today: LocalDate) -> PurchaseInput {
        var input = PurchaseInput(purchase: purchase)
        input.purchaseDate = today
        return input
    }
}
