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
