import Foundation

// Odpowiedzi raportów programu (`GET /reports/*`) — te same nazwy pól co JSON programu, więc ten sam model służy do odczytu
// odpowiedzi w trybie online i do wyniku wyliczenia lokalnego (tryb samodzielny i offline; pliki wzorcowe `parity/*/reports`).

// MARK: Koszty

public struct CostReportRow: Codable, Hashable, Sendable {
    /// Grupa: imię konia / miesiąc `yyyy-MM` / kategoria — zależnie od `groupBy`.
    public let group: String
    public let horseId: String?
    public let category: String?
    public let month: String?
    public let costs: Money
    public let income: Money

    public init(group: String, horseId: String?, category: String?, month: String?, costs: Money, income: Money) {
        self.group = group
        self.horseId = horseId
        self.category = category
        self.month = month
        self.costs = costs
        self.income = income
    }
}

public struct CostReport: Codable, Hashable, Sendable {
    public let from: LocalDate?
    public let to: LocalDate?
    /// `Horse`, `Month`, `Category`.
    public let groupBy: String?
    public let rows: [CostReportRow]
    public let generalPurchasesTotal: Money
    public let totalCosts: Money
    public let totalIncome: Money
    public let balance: Money
}

// MARK: Bilans konia

public struct HorseBalanceBreakdown: Codable, Hashable, Sendable {
    public let year: Int
    public let category: String
    public let costs: Money
}

public struct HorseBalanceRow: Codable, Hashable, Sendable, Identifiable {
    public let horseId: String
    public let horseName: String
    public let status: HorseStatus?
    public let purchasePrice: Money?
    public let costs: Money
    public let prizes: Money
    public let salePrice: Money?
    public let estimatedValue: Money?
    public let result: Money
    /// Koń sprzedany (albo padł) — wynik ostateczny.
    public let isFinal: Bool
    public let purchaseMissing: Bool
    public let breakdown: [HorseBalanceBreakdown]

    public var id: String { horseId }
}

public struct HorseBalanceTotals: Codable, Hashable, Sendable {
    public let purchasePrice: Money
    public let costs: Money
    public let prizes: Money
    public let salePrice: Money
    public let result: Money
}

public struct HorseBalanceReport: Codable, Hashable, Sendable {
    public let rows: [HorseBalanceRow]
    public let totals: HorseBalanceTotals
}

// MARK: Podsumowanie treningów

public struct TrainingStat: Codable, Hashable, Sendable {
    public let min: Money
    public let average: Money
    public let max: Money
}

public struct TrainingSummaryRow: Codable, Hashable, Sendable, Identifiable {
    public let typeId: String?
    public let typeName: String
    /// Indeks typu w palecie wykresów (kolor i znacznik); `-1` dla wiersza „Razem”.
    public let paletteIndex: Int
    public let count: Int
    public let totalMinutes: Int
    public let duration: TrainingStat?
    public let intensity: TrainingStat?
    public let rating: TrainingStat?
    public let obstacleHeight: TrainingStat?
    public let totalCost: Money

    public var id: String { typeId ?? "total" }
}

public struct TrainingSeriesPoint: Codable, Hashable, Sendable {
    public let date: LocalDate
    public let value: Money
}

public struct TrainingSeries: Codable, Hashable, Sendable {
    /// `Duration`, `Rating`, `ObstacleHeight`.
    public let parameter: String
    public let typeId: String
    public let points: [TrainingSeriesPoint]
}

public struct TrainingSummaryReport: Codable, Hashable, Sendable {
    public let horseId: String
    public let horseName: String
    /// `Week`, `Month`, `Year`, `All`.
    public let range: String
    public let from: LocalDate?
    public let to: LocalDate?
    public let rows: [TrainingSummaryRow]
    public let total: TrainingSummaryRow?
    public let series: [TrainingSeries]

    public var isEmpty: Bool { rows.isEmpty }

    private enum CodingKeys: String, CodingKey { case horseId, horseName, range, from, to, rows, total, series }
}

// MARK: Treningi jeźdźca

public struct RiderTrainingsRow: Codable, Hashable, Sendable, Identifiable {
    public let trainingId: String
    public let date: LocalDate
    public let horseId: String
    public let horseName: String
    public let typeName: String
    public let durationMinutes: Int?
    public let intensity: Intensity?
    public let rating: Int?
    public let trainerName: String?
    public let cost: Money?
    public let riderContactId: String?
    public let riderName: String

    public var id: String { trainingId }
}

public struct RiderTrainingsTotals: Codable, Hashable, Sendable {
    public let count: Int
    public let totalMinutes: Int
    public let averageRating: Money?
    public let totalCost: Money
}

public struct RiderTrainingsGroup: Codable, Hashable, Sendable {
    public let key: String
    public let name: String
    public let count: Int
    public let totalMinutes: Int
    public let averageRating: Money?
    public let totalCost: Money
}

public struct RiderTrainingsReport: Codable, Hashable, Sendable {
    public let from: LocalDate?
    public let to: LocalDate?
    public let riderContactId: String?
    public let riderName: String?
    public let rows: [RiderTrainingsRow]
    public let total: RiderTrainingsTotals
    public let groups: [RiderTrainingsGroup]
    /// `Rider` (wszyscy jeźdźcy) albo `Horse` (jeden jeździec).
    public let groupedBy: String
}

// MARK: Zawody jeźdźca

public struct RiderCompetitionStartRow: Codable, Hashable, Sendable, Identifiable {
    public let startId: String
    public let date: LocalDate?
    public let horseId: String
    public let horseName: String
    public let disciplineName: String?
    public let className: String?
    public let resultStatus: ResultStatus?
    public let placement: Int?
    public let participantsCount: Int?
    public let entryFee: Money?
    public let otherCosts: Money?
    public let prizeMoney: Money?
    public let riderContactId: String?
    public let riderName: String

    public var id: String { startId }
}

public struct RiderCompetitionRow: Codable, Hashable, Sendable, Identifiable {
    public let competitionId: String
    public let name: String
    public let dateFrom: LocalDate
    public let dateTo: LocalDate?
    public let city: String?
    public let starts: [RiderCompetitionStartRow]

    public var id: String { competitionId }
}

public struct RiderCompetitionsTotals: Codable, Hashable, Sendable {
    public let competitions: Int
    public let starts: Int
    public let totalCosts: Money
    public let totalPrizes: Money
    public let balance: Money
}

public struct RiderCompetitionsGroup: Codable, Hashable, Sendable {
    public let riderContactId: String
    public let riderName: String
    public let competitions: Int
    public let starts: Int
    public let totalCosts: Money
    public let totalPrizes: Money
    public let balance: Money
}

public struct RiderCompetitionsReport: Codable, Hashable, Sendable {
    public let from: LocalDate?
    public let to: LocalDate?
    public let riderContactId: String?
    public let riderName: String?
    public let competitions: [RiderCompetitionRow]
    public let total: RiderCompetitionsTotals
    public let groups: [RiderCompetitionsGroup]
}
