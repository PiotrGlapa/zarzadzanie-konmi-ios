import Foundation
import HorselyCore

/// Koszt jednej kategorii w roku (karta konia: „Koszty 2026”).
public struct CategoryCost: Sendable, Equatable, Identifiable {
    public let category: String
    public let amount: Money
    public var id: String { category }
}

/// Bilans konia (karta konia, skrót): zakup, koszty, nagrody, sprzedaż i wynik (sprzedaż + nagrody − zakup − koszty).
public struct HorseBalance: Sendable, Equatable {
    public let purchase: Money?
    public let costs: Money
    public let prizes: Money
    public let sale: Money?

    public var result: Money { (sale ?? .zero) + prizes - (purchase ?? .zero) - costs }
}

/// Dane nagłówka karty konia: najbliższe terminy, koszty bieżącego roku wg kategorii i bilans.
public struct HorseOverview: Sendable, Equatable {
    public let nextReminders: [ReminderItem]
    public let year: Int
    public let yearCosts: [CategoryCost]
    public let yearTotal: Money
    public let balance: HorseBalance
}

/// Start konia razem z nazwą zawodów (zakładka „Zawody”).
public struct HorseStart: Sendable, Equatable, Identifiable {
    public let start: LocalCompetitionStart
    public let competitionName: String
    public let date: LocalDate?
    public var id: String { start.id }
}

/// Statystyki startów konia.
public struct StartStatistics: Sendable, Equatable {
    public let starts: Int
    public let wins: Int
    public let podiums: Int
    public let averageRating: Double?
    public let prizes: Money
    public let costs: Money
}

extension EntryRepository {
    /// Ile najbliższych terminów pokazuje karta konia.
    public static let overviewReminders = 3

    public func overview(horseId: String) async throws -> HorseOverview {
        try await read { source, today in
            let reminders = try source.records(.reminder, as: LocalReminder.self, horseId: horseId)
                .filter { $0.status == .open }
                .sorted { ($0.dueDate, $0.id) < ($1.dueDate, $1.id) }
                .prefix(Self.overviewReminders)
            let items = try LocalViews(source: source).reminderItems(Array(reminders), today: today)

            let yearStart = LocalDate(year: today.year, month: 1, day: 1)!
            let yearEnd = LocalDate(year: today.year, month: 12, day: 31)!
            let yearEntries = try CostCalculator.entries(source: source, from: yearStart, to: yearEnd, horseId: horseId).entries
            var byCategory: [String: (order: Int, amount: Money)] = [:]
            for entry in yearEntries where entry.cost.value != 0 {
                let current = byCategory[entry.category] ?? (entry.categoryOrder, .zero)
                byCategory[entry.category] = (current.order, current.amount + entry.cost)
            }
            let categories = byCategory.sorted { ($0.value.order, $0.key) < ($1.value.order, $1.key) }.map { CategoryCost(category: $0.key, amount: $0.value.amount) }

            let all = try CostCalculator.entries(source: source, from: nil, to: nil, horseId: horseId).entries
            let horse = try source.find(.horse, id: horseId, as: LocalHorse.self)
            let balance = HorseBalance(
                purchase: horse?.purchasePrice, costs: all.reduce(Money.zero) { $0 + $1.cost }, prizes: all.reduce(Money.zero) { $0 + $1.income },
                sale: horse.flatMap { HorseRules.effectiveSalePrice($0) }
            )
            return HorseOverview(
                nextReminders: items, year: today.year, yearCosts: categories, yearTotal: categories.reduce(Money.zero) { $0 + $1.amount }, balance: balance
            )
        }
    }

    /// Szczepienia konia (wizyty weterynaryjne rodzaju „Szczepienie”), najnowsze na początku.
    public func vaccinations(horseId: String) async throws -> [LocalVetVisit] {
        try await read { source, _ in
            let types = try source.records(.dictionary, as: LocalDictionaryItem.self)
                .filter { $0.dictionaryType == .vetVisitType && $0.systemKey == DefaultDictionaries.vetVaccination }
            let ids = Set(types.map(\.id))
            return try source.records(.vetVisit, as: LocalVetVisit.self, horseId: horseId)
                .filter { ids.contains($0.visitTypeId) }
                .sorted { ($0.visitDateTime, $0.id) > ($1.visitDateTime, $1.id) }
        }
    }

    /// Starty konia, najnowsze na początku.
    public func starts(horseId: String) async throws -> [HorseStart] {
        try await read { source, _ in
            let names = Dictionary(
                try source.records(.competition, as: LocalCompetition.self).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
            )
            return try source.query(.competitionStart, horseId: horseId).compactMap { row -> HorseStart? in
                guard let start = row.record as? LocalCompetitionStart else { return nil }
                return HorseStart(start: start, competitionName: names[start.competitionId] ?? "", date: row.dateKey)
            }
            .sorted { ($0.date ?? LocalDate(dayNumber: 0), $0.id) > ($1.date ?? LocalDate(dayNumber: 0), $1.id) }
        }
    }

    public static func statistics(_ starts: [HorseStart]) -> StartStatistics {
        let list = starts.map(\.start)
        let placements = list.filter { $0.resultStatus == .completed || $0.resultStatus == nil }.compactMap(\.placement)
        let ratings = list.compactMap(\.subjectiveRating)
        return StartStatistics(
            starts: list.count, wins: placements.filter { $0 == 1 }.count, podiums: placements.filter { (1...3).contains($0) }.count,
            averageRating: ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count),
            prizes: list.reduce(Money.zero) { $0 + ($1.prizeMoney ?? .zero) },
            costs: list.reduce(Money.zero) { $0 + ($1.entryFee ?? .zero) + ($1.otherCosts ?? .zero) }
        )
    }

    /// Zakupy konia (także wspólne z innymi końmi), najnowsze na początku.
    public func purchases(horseId: String) async throws -> [LocalPurchase] {
        try await read { source, _ in
            try source.records(.purchase, as: LocalPurchase.self, horseId: horseId).sorted { ($0.purchaseDate, $0.id) > ($1.purchaseDate, $1.id) }
        }
    }
}
