import HorselyCore
import HorselyKit
import SwiftUI
import XCTest
@testable import Horsely

/// Testy migawkowe raportów (T111) na danych `SnapshotEntries` (dziś 2026-10-05, tryb samodzielny — wyliczenie lokalne):
/// Koszty z wykresami (bieżący rok, grupowanie po miesiącach) i Bilans konia z rozwiniętym pierwszym wierszem.
@MainActor
final class ReportsSnapshotTests: XCTestCase {
    private func environment(_ variant: SnapshotVariant) async throws -> AppEnvironment {
        let env = makeEnvironment(mode: .standalone, variant: variant)
        _ = try await SnapshotEntries.seed(env)
        return env
    }

    func testReportsList() async throws {
        for variant in SnapshotVariant.allCases {
            let env = try await environment(variant)
            await assertSettledScreen(NavigationStack { ReportsListView() }.environment(env), name: "reports-list", variant: variant)
        }
    }

    func testCostReportWithCharts() async throws {
        for variant in SnapshotVariant.allCases {
            let env = try await environment(variant)
            await assertSettledScreen(NavigationStack { CostReportView() }.environment(env), name: "report-costs", variant: variant)
        }
    }

    /// Treningi jeźdźców do raportu „Treningi jeźdźca”: Anna (Grom, Iskra) i Ewa (Grom) w kilku rodzajach treningu.
    private func riderEnvironment(_ variant: SnapshotVariant) async throws -> (env: AppEnvironment, annaId: String) {
        let env = makeEnvironment(mode: .standalone, variant: variant)
        let horses = try await SnapshotEntries.seed(env)
        let dictionary = try await env.entries.allDictionaryItems()
        func horse(_ name: String) throws -> String {
            guard let id = horses.first(where: { $0.name == name })?.id else { throw SnapshotEntries.SeedError() }
            return id
        }
        func type(_ name: String) throws -> String {
            guard let id = dictionary.first(where: { $0.dictionaryType == .trainingType && $0.value == name })?.id else { throw SnapshotEntries.SeedError() }
            return id
        }
        func rider(_ name: String) async throws -> String {
            guard let id = try await env.entries.saveContact(ContactInput(name: name, types: [.rider])).saved?.record?.id else { throw SnapshotEntries.SeedError() }
            return id
        }
        let anna = try await rider("Anna Nowak")
        let ewa = try await rider("Ewa Wiśniewska")
        let sessions: [(horse: String, rider: String, date: String, type: String, minutes: Int, rating: Int, cost: Int)] = [
            ("Grom", anna, "2026-09-01", "Skoki", 75, 5, 150), ("Grom", anna, "2026-09-08", "Ujeżdżenie", 60, 4, 100),
            ("Iskra", anna, "2026-09-10", "Ujeżdżenie", 45, 3, 90), ("Iskra", anna, "2026-09-17", "Skoki", 50, 4, 110),
            ("Iskra", anna, "2026-09-20", "Ujeżdżenie", 30, 4, 0), ("Grom", ewa, "2026-09-22", "Ujeżdżenie", 90, 3, 130),
            ("Grom", ewa, "2026-09-29", "Skoki", 40, 4, 80),
        ]
        for session in sessions {
            var training = TrainingInput()
            training.horseId = try horse(session.horse)
            training.riderContactId = session.rider
            training.trainingDate = LocalDate(session.date)
            training.trainingTypeId = try type(session.type)
            training.durationMinutes = session.minutes
            training.intensity = .medium
            training.rating = session.rating
            training.coaching = TrainingCoachingInput(cost: Money(session.cost))
            let input = training
            _ = try await env.entries.perform { $0.createTraining(input) }
        }
        return (env, anna)
    }

    /// Jeden jeździec, kilka koni: kafelki, wykres grup (konie), karty grup i zwinięta lista — sumy i wykres bez przewijania.
    func testRiderTrainingsSummaryAndChart() async throws {
        for variant in SnapshotVariant.allCases {
            let (env, anna) = try await riderEnvironment(variant)
            await assertSettledScreen(NavigationStack { RiderTrainingsReportView(riderId: anna) }.environment(env), name: "report-rider-trainings", variant: variant)
        }
    }

    /// Wszyscy jeźdźcy: wykres grup po jeźdźcach.
    func testRiderTrainingsAllRiders() async throws {
        for variant in SnapshotVariant.allCases {
            let (env, _) = try await riderEnvironment(variant)
            await assertSettledScreen(NavigationStack { RiderTrainingsReportView() }.environment(env), name: "report-rider-trainings-all", variant: variant)
        }
    }

    func testHorseBalanceWithExpandedRow() async throws {
        for variant in SnapshotVariant.allCases {
            let env = try await environment(variant)
            await assertSettledScreen(NavigationStack { HorseBalanceReportView(expandFirstRow: true) }.environment(env), name: "report-balance", variant: variant)
        }
    }
}
