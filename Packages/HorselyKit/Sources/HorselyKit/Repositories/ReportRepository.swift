import Foundation
import HorselyCore

/// Wynik raportu z informacją o źródle: `fromMemory` — wyliczony w telefonie z danych w pamięci (tryb online bez połączenia;
/// ekran pokazuje „z pamięci”), `fetchedAt` — chwila odpowiedzi programu albo wyliczenia.
public struct ReportResult<Report: Sendable>: Sendable {
    public let report: Report
    public let fromMemory: Bool
    public let fetchedAt: Date
}

/// Raporty (T107, FR-M-RAP-01…07, FR-SAM-03): w trybie online — `GET /reports/*` programu z pamięcią ostatnich 20 odpowiedzi;
/// bez połączenia i w trybie samodzielnym — wyliczenie lokalne (`LocalReports`, ten sam wynik co program na tych samych danych).
public final class ReportRepository: Sendable {
    private let store: RecordStore
    private let client: ApiClient?
    private let mode: @Sendable () -> WorkMode
    private let dates: any DateProvider
    private let cache = ReportCache(limit: 20)

    public init(store: RecordStore, client: ApiClient?, mode: @escaping @Sendable () -> WorkMode, dates: any DateProvider = SystemDateProvider()) {
        self.store = store
        self.client = client
        self.mode = mode
        self.dates = dates
    }

    public func costs(_ filter: CostFilter) async throws -> ReportResult<CostReport> {
        var query: [(String, String?)] = [("from", filter.from?.description), ("to", filter.to?.description)]
        if filter.generalOnly {
            query.append(("horseIds", "general"))
        } else if !filter.horseIds.isEmpty {
            query.append(("horseIds", filter.horseIds.sorted().joined(separator: ",")))
        }
        if !filter.categories.isEmpty { query.append(("categories", filter.categories.sorted().joined(separator: ","))) }
        query.append(("groupBy", filter.groupBy.rawValue.lowercased()))
        return try await load("costs", query, as: CostReport.self) { try LocalReports(source: $0).costReport(filter) }
    }

    public func horseBalance(statuses: [HorseStatus], horseIds: [String]) async throws -> ReportResult<HorseBalanceReport> {
        let ordered = HorseStatus.allCases.filter(statuses.contains).map(\.rawValue)
        let query: [(String, String?)] = [
            ("status", ordered.isEmpty ? nil : ordered.joined(separator: ",")), ("horseIds", horseIds.isEmpty ? nil : horseIds.sorted().joined(separator: ",")),
        ]
        return try await load("horse-balance", query, as: HorseBalanceReport.self) { try LocalReports(source: $0).horseBalance(statuses: statuses, horseIds: horseIds) }
    }

    public func trainingSummary(horseId: String, range: TrainingRange, anchor: LocalDate) async throws -> ReportResult<TrainingSummaryReport> {
        let query: [(String, String?)] = [("horseId", horseId), ("range", range.rawValue.lowercased()), ("date", range == .all ? nil : anchor.description)]
        return try await load("training-summary", query, as: TrainingSummaryReport.self) {
            try LocalReports(source: $0).trainingSummary(horseId: horseId, range: range, anchor: anchor)
        }
    }

    public func riderTrainings(riderId: String?, from: LocalDate?, to: LocalDate?, horseId: String?) async throws -> ReportResult<RiderTrainingsReport> {
        let query: [(String, String?)] = [("riderId", riderId), ("horseId", horseId), ("from", from?.description), ("to", to?.description)]
        return try await load("rider-trainings", query, as: RiderTrainingsReport.self) {
            try LocalReports(source: $0).riderTrainings(riderId: riderId, from: from, to: to, horseId: horseId)
        }
    }

    public func riderCompetitions(riderId: String?, from: LocalDate?, to: LocalDate?, horseId: String?) async throws -> ReportResult<RiderCompetitionsReport> {
        let query: [(String, String?)] = [("riderId", riderId), ("horseId", horseId), ("from", from?.description), ("to", to?.description)]
        return try await load("rider-competitions", query, as: RiderCompetitionsReport.self) {
            try LocalReports(source: $0).riderCompetitions(riderId: riderId, from: from, to: to, horseId: horseId)
        }
    }

    // MARK: Wspólne

    private func load<T: Decodable & Sendable>(
        _ name: String, _ query: [(String, String?)], as type: T.Type, local: @escaping @Sendable (RecordSource) throws -> T
    ) async throws -> ReportResult<T> {
        let path = "reports/\(name)" + Self.queryString(query)
        if mode() == .online, let client {
            switch await client.get(path) {
            case let .success(response):
                if let report = response.decode(T.self) {
                    let result = ReportResult(report: report, fromMemory: false, fetchedAt: Date())
                    await cache.put(path, result)
                    return result
                }
            case .failure(.notFound):
                throw ReportTargetNotFound(what: name, id: path)
            case .failure:
                // Ostatnia odpowiedź programu dla tego filtra albo — gdy jej nie ma — wyliczenie z pamięci telefonu.
                if let cached: ReportResult<T> = await cache.get(path) { return ReportResult(report: cached.report, fromMemory: true, fetchedAt: cached.fetchedAt) }
            }
        }
        let report = try await store.read { access in try local(AccessRecordSource(access: access)) }
        return ReportResult(report: report, fromMemory: mode() == .online, fetchedAt: Date())
    }

    static func queryString(_ items: [(String, String?)]) -> String {
        let pairs = items.compactMap { key, value in value.map { "\(key)=\(MatchSpec.encode($0))" } }
        return pairs.isEmpty ? "" : "?" + pairs.joined(separator: "&")
    }
}

/// Pamięć ostatnich odpowiedzi raportów (najdawniej użyte wypadają pierwsze).
actor ReportCache {
    private let limit: Int
    private var order: [String] = []
    private var items: [String: any Sendable] = [:]

    init(limit: Int) {
        self.limit = limit
    }

    func put(_ key: String, _ value: any Sendable) {
        order.removeAll { $0 == key }
        order.append(key)
        items[key] = value
        while order.count > limit { items.removeValue(forKey: order.removeFirst()) }
    }

    func get<T: Sendable>(_ key: String) -> T? {
        guard let value = items[key] as? T else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return value
    }
}
