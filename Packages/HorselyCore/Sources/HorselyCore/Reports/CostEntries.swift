import Foundation

/// Wiersz kosztów lub przychodu po podziale zakupów (`CostEntry`).
public struct CostEntry: Equatable, Sendable {
    public let date: LocalDate
    public let horseId: String?
    public let category: String
    public let categoryOrder: Int
    public let cost: Money
    public let income: Money

    public init(date: LocalDate, horseId: String?, category: String, categoryOrder: Int, cost: Money, income: Money) {
        self.date = date
        self.horseId = horseId
        self.category = category
        self.categoryOrder = categoryOrder
        self.cost = cost
        self.income = income
    }

    /// `yyyy-MM`.
    public var month: String { String(format: "%04d-%02d", date.year, date.month) }
}

public struct CostEntries: Sendable {
    public let entries: [CostEntry]
    public let horseNames: [String: String]
}

public enum CostCalculator {
    /// Kategoria zakupów ma własną kolejność po stałych kategoriach (FR-RAP-02).
    public static let purchaseCategoryOrder = 100
    public static let general = "Ogólne (stajnia)"
    public static let total = "Razem"

    /// Stałe kategorie raportu kosztów w kolejności wyświetlania.
    public static let fixedCategories = ["Weterynarz", "Kowal", "Fizjoterapeuta", "Specjaliści", "Zawody", "Treningi"]

    /// Koszty i przychody okresu ze wszystkich źródeł; zakupy dzielone między konie; rekordy z kosza pominięte (`CostEntriesQuery`).
    public static func entries(source: RecordSource, from: LocalDate?, to: LocalDate?, horseId: String? = nil) throws -> CostEntries {
        var entries: [CostEntry] = []
        func add(_ date: LocalDate, _ horse: String, _ category: Int, _ amount: Money?) {
            entries.append(CostEntry(date: date, horseId: horse, category: fixedCategories[category], categoryOrder: category, cost: amount ?? .zero, income: .zero))
        }
        for visit in try source.records(.vetVisit, as: LocalVetVisit.self, horseId: horseId, from: from, to: to) {
            if let cost = visit.cost { add(visit.visitDateTime.date, visit.horseId, 0, cost) }
        }
        for visit in try source.records(.farrierVisit, as: LocalFarrierVisit.self, horseId: horseId, from: from, to: to) {
            if let cost = visit.cost { add(visit.visitDate, visit.horseId, 1, cost) }
        }
        for visit in try source.records(.physioVisit, as: LocalPhysioVisit.self, horseId: horseId, from: from, to: to) {
            if let cost = visit.cost { add(visit.visitDate, visit.horseId, 2, cost) }
        }
        for visit in try source.records(.specialistVisit, as: LocalSpecialistVisit.self, horseId: horseId, from: from, to: to) {
            if let cost = visit.cost { add(visit.visitDate, visit.horseId, 3, cost) }
        }
        for row in try source.query(.competitionStart, horseId: horseId, from: from, to: to) {
            guard let start = row.record as? LocalCompetitionStart, let date = row.dateKey else { continue }
            if start.entryFee == nil, start.otherCosts == nil, start.prizeMoney == nil { continue }
            entries.append(CostEntry(
                date: date, horseId: start.horseId, category: fixedCategories[4], categoryOrder: 4,
                cost: (start.entryFee ?? .zero) + (start.otherCosts ?? .zero), income: start.prizeMoney ?? .zero
            ))
        }
        for training in try source.records(.training, as: LocalTraining.self, horseId: horseId, from: from, to: to) {
            if let cost = training.cost { add(training.trainingDate, training.horseId, 5, cost) }
        }

        let purchases = try source.records(.purchase, as: LocalPurchase.self, horseId: horseId, from: from, to: to)
        let horseNames = try names(source, .horse)
        let dictionary = try names(source, .dictionary)
        for purchase in purchases {
            let horses = purchase.horseIds.map { HorseName(id: $0, name: horseNames[$0] ?? "") }
            let category = dictionary[purchase.categoryId] ?? ""
            for share in PurchaseSplit.allocate(purchase.totalAmount + purchase.deliveryCost, assignment: purchase.assignment, horses: horses)
            where horseId == nil || share.horseId == horseId {
                entries.append(CostEntry(date: purchase.purchaseDate, horseId: share.horseId, category: category, categoryOrder: purchaseCategoryOrder, cost: share.amount, income: .zero))
            }
        }
        let usedHorses = Set(entries.compactMap(\.horseId))
        return CostEntries(
            entries: entries.filter { $0.cost.value != 0 || $0.income.value != 0 },
            horseNames: horseNames.filter { usedHorses.contains($0.key) }
        )
    }

    /// Nazwy rekordów (wraz z tymi w koszu — raporty pokazują nazwy usuniętych koni) po `id`.
    static func names(_ source: RecordSource, _ type: RecordType) throws -> [String: String] {
        var result: [String: String] = [:]
        for row in try source.query(type, horseId: nil, from: nil, to: nil, includeDeleted: true) {
            switch row.record {
            case let horse as LocalHorse: result[horse.id] = horse.name
            case let contact as LocalContact: result[contact.id] = contact.name
            case let item as LocalDictionaryItem: result[item.id] = item.value
            default: break
            }
        }
        return result
    }
}
