import HorselyKit
import SwiftUI
import UIKit

/// Szybkie akcje ikony aplikacji (T134, FR-023, FR-M-UI-06): „Notatka”, „Kowal”, „Terminy” z `UIApplicationShortcutItems`.
/// Akcja z zimnego startu przychodzi w opcjach sceny, z pracującej aplikacji — do delegata sceny; obie trafiają do `QuickActions`,
/// a `RootView` kieruje je przez router (tryb nieustawiony — najpierw wybór trybu, potem cel).
@MainActor
@Observable
final class QuickActions {
    static let shared = QuickActions()

    /// Typ akcji czekającej na obsłużenie.
    var pending: String?
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Telefon, który już dostawał powiadomienia z serwera (`push.active`), konfiguruje Firebase synchronicznie przy starcie —
    /// zanim system dostarczy token APNs (spec 003, research R6). Bez tego znacznika nic z Firebase się nie uruchamia.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let isTestRun = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-UITest") }
        if !isTestRun, SettingsStore().pushActive {
            MainActor.assumeIsolated { FirebasePushTokenSource.shared.configureNow() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { FirebasePushTokenSource.shared.setAPNSToken(deviceToken) }
        Task { await PushBridge.shared.registrar?.didRegisterAPNs() }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { await PushBridge.shared.registrar?.didFailAPNs() }
    }

    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        if let type = options.shortcutItem?.type {
            MainActor.assumeIsolated { QuickActions.shared.pending = type }
        }
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let type = shortcutItem.type
        MainActor.assumeIsolated { QuickActions.shared.pending = type }
        completionHandler(true)
    }
}
