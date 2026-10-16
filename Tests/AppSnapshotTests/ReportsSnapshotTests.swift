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

    func testHorseBalanceWithExpandedRow() async throws {
        for variant in SnapshotVariant.allCases {
            let env = try await environment(variant)
            await assertSettledScreen(NavigationStack { HorseBalanceReportView(expandFirstRow: true) }.environment(env), name: "report-balance", variant: variant)
        }
    }
}
