import SwiftUI
import XCTest
@testable import Horsely

/// Testy migawkowe powłoki (T037): pasek kart i „Więcej” w obu trybach, jasny / ciemny / tekst 200 % (XXXL). Wzorce leżą w
/// `__Snapshots__` obok testów; pierwszy przebieg CI je zapisuje (test świeci na czerwono), po przejrzeniu artefaktu
/// wzorce zatwierdza się commitem (contracts/test-fixtures.md §3).
@MainActor
final class ShellSnapshotTests: XCTestCase {
    func testTabBarWithTheDashboardTab() async {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            await env.horseDirectory.refresh()
            assertScreen(RootView().environment(env), name: "shell-dashboard", variant: variant)
        }
    }

    func testMoreInTheStandaloneMode() {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            env.router.selectedTab = .more
            assertScreen(RootView().environment(env), name: "more-standalone", variant: variant)
        }
    }

    func testMoreInTheOnlineModeWithQueueAndConflicts() {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .online, variant: variant, queue: 3, conflicts: 2)
            env.router.selectedTab = .more
            assertScreen(RootView().environment(env), name: "more-online", variant: variant)
        }
    }

    func testModeChoiceScreen() {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .unset, variant: variant)
            assertScreen(RootView().environment(env), name: "welcome", variant: variant)
        }
    }
}
