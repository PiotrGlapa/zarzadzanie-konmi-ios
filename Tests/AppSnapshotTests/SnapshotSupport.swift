import HorselyCore
import HorselyKit
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Horsely

/// Wspólne wsparcie testów migawkowych (contracts/test-fixtures.md §2–3): trzy warianty (jasny, ciemny, tekst 200 %), rozmiar ekranu
/// iPhone 15 Pro (393 × 852 pt), środowisko z bazą w pamięci i stałą datą 2026-10-05.
@MainActor
enum SnapshotVariant: String, CaseIterable {
    case light, dark, xxxl

    var traits: UITraitCollection {
        switch self {
        case .light: UITraitCollection(userInterfaceStyle: .light)
        case .dark: UITraitCollection(userInterfaceStyle: .dark)
        case .xxxl: UITraitCollection { traits in
            traits.userInterfaceStyle = .light
            traits.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        }
        }
    }

    var theme: ThemeSetting { self == .dark ? .dark : .light }
}

@MainActor
extension XCTestCase {
    static var snapshotSize: CGSize { CGSize(width: 393, height: 852) }

    func makeEnvironment(mode: WorkMode, variant: SnapshotVariant, queue: Int = 0, conflicts: Int = 0) -> AppEnvironment {
        let suite = "horsely.snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.workMode = mode
        settings.theme = variant.theme
        return AppEnvironment.testing(settings: settings, queueCount: queue, conflictCount: conflicts)
    }

    func assertScreen(
        _ view: some View, name: String, variant: SnapshotVariant, file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        let controller = UIHostingController(rootView: view.tint(HorselyColor.primary))
        assertSnapshot(
            of: controller,
            as: .image(drawHierarchyInKeyWindow: true, precision: 0.98, perceptualPrecision: 0.98, size: Self.snapshotSize, traits: variant.traits),
            named: "\(name)-\(variant.rawValue)",
            file: file,
            testName: testName,
            line: line
        )
    }
}

/// Konie do zrzutów: aktywny z imieniem stajennym, kontuzjowany, źrebię bez paszportu od 14 miesięcy (ostrzeżenie na kaflu), sprzedany.
enum SnapshotHorses {
    struct Spec {
        var name: String
        var passport: String?
        var stableName: String?
        var foal = false
        var birth: LocalDate?
        var status: HorseStatus = .active
        var statusDate: LocalDate?
    }

    static let all: [Spec] = [
        Spec(name: "Grom", passport: "PL-0001", stableName: "Gromek", birth: LocalDate(year: 2018, month: 4, day: 12)),
        Spec(name: "Iskra", passport: "PL-0002", birth: LocalDate(year: 2020, month: 6, day: 1)),
        Spec(name: "Pegaz", passport: "PL-0003", status: .injured, statusDate: LocalDate(year: 2026, month: 9, day: 25)),
        Spec(name: "Źrebak Łatek", foal: true, birth: LocalDate(year: 2025, month: 8, day: 10)),
        Spec(name: "Burza", passport: "PL-0004", status: .sold, statusDate: LocalDate(year: 2026, month: 3, day: 3)),
    ]

    @discardableResult
    static func seed(_ environment: AppEnvironment) async throws -> [LocalHorse] {
        var saved: [LocalHorse] = []
        for spec in all {
            var draft = HorseDraft()
            draft.name = spec.name
            draft.passportNumber = spec.passport ?? ""
            draft.stableName = spec.stableName ?? ""
            draft.isFoal = spec.foal
            draft.birthDate = spec.birth
            draft.status = spec.status
            draft.statusDate = spec.statusDate
            if case let .saved(horse, _) = try await environment.horses.save(draft) { saved.append(horse) }
        }
        await environment.horseDirectory.refresh()
        return saved
    }
}
