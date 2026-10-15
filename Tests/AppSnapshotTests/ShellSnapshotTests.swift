import HorselyCore
import HorselyKit
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Horsely

/// Testy migawkowe powłoki (T037): pasek kart i „Więcej” w obu trybach, jasny / ciemny / tekst 200 % (XXXL). Wzorce leżą w
/// `__Snapshots__` obok testów; pierwszy przebieg CI je zapisuje (test świeci na czerwono), po przejrzeniu artefaktu
/// wzorce zatwierdza się commitem (contracts/test-fixtures.md §3). Rozmiar ekranu: iPhone 15 Pro (393 × 852 pt).
@MainActor
final class ShellSnapshotTests: XCTestCase {
    private enum Variant: String, CaseIterable {
        case light, dark, xxxl

        var traits: UITraitCollection {
            switch self {
            case .light: UITraitCollection(userInterfaceStyle: .light)
            case .dark: UITraitCollection(userInterfaceStyle: .dark)
            case .xxxl: UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge),
            ])
            }
        }

        var theme: ThemeSetting { self == .dark ? .dark : .light }
    }

    private let size = CGSize(width: 393, height: 852)

    private func environment(mode: WorkMode, variant: Variant, queue: Int = 0, conflicts: Int = 0) -> AppEnvironment {
        let suite = "horsely.snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.workMode = mode
        settings.theme = variant.theme
        return AppEnvironment.testing(settings: settings, queueCount: queue, conflictCount: conflicts)
    }

    private func check(_ view: some View, name: String, variant: Variant, file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
        let controller = UIHostingController(rootView: view)
        assertSnapshot(
            of: controller,
            as: .image(drawHierarchyInKeyWindow: true, precision: 0.98, perceptualPrecision: 0.98, size: size, traits: variant.traits),
            named: "\(name)-\(variant.rawValue)",
            file: file,
            testName: testName,
            line: line
        )
    }

    func testTabBarWithTheDashboardTab() {
        for variant in Variant.allCases {
            let env = environment(mode: .standalone, variant: variant)
            check(RootView().environment(env), name: "shell-dashboard", variant: variant)
        }
    }

    func testMoreInTheStandaloneMode() {
        for variant in Variant.allCases {
            let env = environment(mode: .standalone, variant: variant)
            env.router.selectedTab = .more
            check(RootView().environment(env), name: "more-standalone", variant: variant)
        }
    }

    func testMoreInTheOnlineModeWithQueueAndConflicts() {
        for variant in Variant.allCases {
            let env = environment(mode: .online, variant: variant, queue: 3, conflicts: 2)
            env.router.selectedTab = .more
            check(RootView().environment(env), name: "more-online", variant: variant)
        }
    }
}
