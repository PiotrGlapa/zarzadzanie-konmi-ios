import HorselyCore
import HorselyKit
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

    // MARK: Push z serwera (spec 003, T051, T057)

    /// Ustawienia → Powiadomienia we wszystkich stanach push; dane podane z zewnątrz, bez sieci.
    func testNotificationSettingsInEveryPushState() {
        let device = PushDevice(platform: "Ios", tokenPrefix: "dGhpcyBp", registeredAt: Date(timeIntervalSince1970: 1_793_787_300))
        let rules = [
            ClientPushRule(id: "r1", type: "Reminder", reminderKind: "Farrier", offsetDays: 1, sendTime: "08:00", description: "Kowal: dzień przed o 08:00"),
            ClientPushRule(id: "r2", type: "DailySummary", sendTime: "07:30", description: "Podsumowanie dnia o 07:30"),
        ]
        let cases: [(String, PushPreview)] = [
            ("registered_rules", PushPreview(state: .registered, device: device, rules: rules)),
            ("registered_empty", PushPreview(state: .registered, device: device, rules: [])),
            ("pending", PushPreview(state: .pending)),
            ("fallback_noPush", PushPreview(state: .fallback(.serverHasNoPush))),
            ("fallback_apns", PushPreview(state: .fallback(.apnsUnavailable))),
            ("noPermission", PushPreview(state: .noPermission(asked: true))),
            ("notDetermined", PushPreview(state: .noPermission(asked: false))),
        ]
        for (name, preview) in cases {
            for variant in SnapshotVariant.allCases {
                let env = makeEnvironment(mode: .online, variant: variant)
                assertScreen(NavigationStack { NotificationSettingsView(preview: preview) }.environment(env), name: "NotificationSettings_\(name)", variant: variant)
            }
        }
    }

    func testDashboardWithTheNotificationsOffCard() async {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .online, variant: variant)
            env.settings.notificationsOffCardDismissed = false
            await env.horseDirectory.refresh()
            assertScreen(DashboardView().environment(env), name: "Dashboard_notificationsOffCard", variant: variant)
        }
    }

    func testServerBackupInfo() {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .online, variant: variant)
            assertScreen(NavigationStack { ServerBackupInfoView() }.environment(env), name: "ServerBackupInfo", variant: variant)
        }
    }

    func testModeChoiceScreen() {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .unset, variant: variant)
            assertScreen(RootView().environment(env), name: "welcome", variant: variant)
        }
    }
}
