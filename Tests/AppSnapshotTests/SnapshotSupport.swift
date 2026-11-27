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
        // Zrzuty ekranów nie pokazują przypomnienia o kopii zapasowej (ma osobne warunki, test `BackupPolicyTests`).
        settings.backupReminderSnoozedUntil = "2100-01-01T00:00:00Z"
        // Karta „Powiadomienia o terminach są wyłączone” ma własną migawkę (`Dashboard_notificationsOffCard`).
        settings.notificationsOffCardDismissed = true
        return AppEnvironment.testing(settings: settings, queueCount: queue, conflictCount: conflicts)
    }

    func assertScreen(
        _ view: some View, name: String, variant: SnapshotVariant, file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        let controller = UIHostingController(rootView: view.tint(HorselyColor.primary))
        SnapshotDiag.log("before \(name)-\(variant.rawValue)", controller: nil, file: file)
        assertSnapshot(
            of: controller,
            as: .image(drawHierarchyInKeyWindow: true, precision: 0.98, perceptualPrecision: 0.98, size: Self.snapshotSize, traits: variant.traits),
            named: "\(name)-\(variant.rawValue)",
            file: file,
            testName: testName,
            line: line
        )
        SnapshotDiag.log("after \(name)-\(variant.rawValue)", controller: controller, file: file)
    }
}

@MainActor
extension XCTestCase {
    /// Jak `assertScreen`, ale najpierw pokazuje widok w oknie przez sekundę, żeby zadania ładujące dane (`.task`) zdążyły się wykonać.
    func assertSettledScreen(
        _ view: some View, name: String, variant: SnapshotVariant, file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) async {
        let controller = UIHostingController(rootView: view.tint(HorselyColor.primary))
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.snapshotSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try? await Task.sleep(for: .seconds(1))
        SnapshotDiag.log("settled \(name)-\(variant.rawValue)", controller: controller, file: file)
        window.rootViewController = nil
        window.isHidden = true
        SnapshotDiag.log("before \(name)-\(variant.rawValue)", controller: nil, file: file)
        assertSnapshot(
            of: controller,
            as: .image(drawHierarchyInKeyWindow: true, precision: 0.98, perceptualPrecision: 0.98, size: Self.snapshotSize, traits: variant.traits),
            named: "\(name)-\(variant.rawValue)",
            file: file,
            testName: testName,
            line: line
        )
        SnapshotDiag.log("after \(name)-\(variant.rawValue)", controller: controller, file: file)
    }
}

/// TYMCZASOWA DIAGNOSTYKA (przeciek stanu między migawkami, Task 17 I1): okna, obszar bezpieczny, przewijanie i pasek nawigacji
/// zapisywane do `__Snapshots__/diag.txt` (artefakt CI).
@MainActor
enum SnapshotDiag {
    static func log(_ label: String, controller: UIViewController?, file: StaticString) {
        var lines = ["== \(label) t=\(Int(ProcessInfo.processInfo.systemUptime)) idle=\(UIApplication.shared.isIdleTimerDisabled) battery=\(UIDevice.current.isBatteryMonitoringEnabled) scenes=\(UIApplication.shared.connectedScenes.count)"]
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            lines.append("  scene state=\(scene.activationState.rawValue) statusBar=\(scene.statusBarManager?.statusBarFrame ?? .zero) hidden=\(scene.statusBarManager?.isStatusBarHidden ?? false)")
            for window in scene.windows {
                lines.append("  win \(type(of: window)) \(Unmanaged.passUnretained(window).toOpaque()) key=\(window.isKeyWindow) hidden=\(window.isHidden) frame=\(window.frame) safe=\(window.safeAreaInsets) root=\(window.rootViewController.map { "\(type(of: $0))" } ?? "nil") level=\(window.windowLevel.rawValue)")
            }
        }
        if let controller {
            lines.append("  vc safe=\(controller.view.safeAreaInsets) frame=\(controller.view.frame) window=\(controller.view.window != nil)")
            func visitControllers(_ vc: UIViewController, _ depth: Int) {
                if let nav = vc as? UINavigationController {
                    lines.append("  nav bar=\(nav.navigationBar.frame) large=\(nav.navigationBar.prefersLargeTitles) safe=\(nav.view.safeAreaInsets) add=\(nav.additionalSafeAreaInsets) top=\(nav.topViewController.map { "\(type(of: $0))" } ?? "nil")")
                    if let top = nav.topViewController {
                        lines.append("    topvc safe=\(top.view.safeAreaInsets) mode=\(top.navigationItem.largeTitleDisplayMode.rawValue)")
                    }
                }
                if depth < 8 { vc.children.forEach { visitControllers($0, depth + 1) } }
            }
            visitControllers(controller, 0)
            func visit(_ view: UIView, _ depth: Int) {
                if let scroll = view as? UIScrollView, scroll.bounds.height > 300 {
                    lines.append("  scroll \(type(of: scroll)) offset=\(scroll.contentOffset.y) adjusted=\(scroll.adjustedContentInset) inset=\(scroll.contentInset) frame=\(scroll.frame) size=\(scroll.contentSize) behavior=\(scroll.contentInsetAdjustmentBehavior.rawValue)")
                }
                let name = "\(type(of: view))"
                if name.contains("LargeTitle") || view is UINavigationBar {
                    lines.append("  \(name) frame=\(view.frame) inWindow=\(view.convert(view.bounds, to: nil))")
                }
                if depth < 40 { view.subviews.forEach { visit($0, depth + 1) } }
            }
            visit(controller.view, 0)
        }
        let url = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().appendingPathComponent("__Snapshots__/diag.txt")
        let text = lines.joined(separator: "\n") + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
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
