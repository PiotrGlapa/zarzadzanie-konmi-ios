import HorselyCore
import SwiftUI
import XCTest
@testable import Horsely

/// Testy migawkowe koni (T052): lista, karta i kafle na Pulpicie; jasny / ciemny / tekst 200 %; konie z pięciu przypadków
/// (aktywny z imieniem stajennym, kontuzjowany, źrebię bez paszportu od 14 mies., sprzedany), dziś 2026-10-05.
@MainActor
final class HorsesSnapshotTests: XCTestCase {
    func testHorsesList() async throws {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            try await SnapshotHorses.seed(env)
            env.router.selectedTab = .horses
            assertScreen(RootView().environment(env), name: "horses-list", variant: variant)
        }
    }

    func testDashboardTiles() async throws {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            try await SnapshotHorses.seed(env)
            assertScreen(RootView().environment(env), name: "dashboard-tiles", variant: variant)
        }
    }

    func testHorseCardOfAnInjuredHorse() async throws {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            let horses = try await SnapshotHorses.seed(env)
            let injured = try XCTUnwrap(horses.first { $0.status == .injured })
            assertScreen(NavigationStack { HorseCardView(horseId: injured.id) }.environment(env), name: "horse-card", variant: variant)
        }
    }

    func testHorseCardWithAStableName() async throws {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            let horses = try await SnapshotHorses.seed(env)
            let grom = try XCTUnwrap(horses.first { $0.name == "Grom" })
            assertScreen(NavigationStack { HorseCardView(horseId: grom.id) }.environment(env), name: "horse-card-stable-name", variant: variant)
        }
    }

    func testHorseFormForANewHorse() {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            assertScreen(HorseFormView(horse: nil) {}.environment(env), name: "horse-form-new", variant: variant)
        }
    }

    func testHorseFormForAnEditedHorse() async throws {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            let horses = try await SnapshotHorses.seed(env)
            let injured = try XCTUnwrap(horses.first { $0.status == .injured })
            assertScreen(HorseFormView(horse: injured) {}.environment(env), name: "horse-form-edit", variant: variant)
        }
    }
}
