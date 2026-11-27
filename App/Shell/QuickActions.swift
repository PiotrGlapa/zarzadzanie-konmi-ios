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
        // Nagrywanie jazdy (Task 15, A13): system zamknął aplikację w trakcie jazdy → uruchamia ją ponownie W TLE (klucz `location`) i wtedy
        // wznawiamy (sesja aktywności w tle powstaje synchronicznie, przed końcem uruchamiania). Otwarcie przez użytkownika (stan `.inactive`)
        // z jazdą w bazie oznacza przesunięcie — jazda „przerwana”, przy starcie „Zapisz / Odrzuć”.
        if let ride = RideBridge.shared.controller {
            let launch: RideLaunchKind
            if launchOptions?[.location] != nil {
                launch = .backgroundLocation
            } else if application.applicationState == .background {
                launch = .background
            } else {
                launch = .foreground
            }
            ride.prepareRelaunch(launch: launch)
        }
        return true
    }

    /// Zamknięcie aplikacji przesunięciem w trakcie jazdy (aplikacja działa w tle dzięki lokalizacji, więc system to zgłasza): ostatni
    /// zapis i stan „przerwane” — przy następnym starcie „Zapisz / Odrzuć” zamiast wznowienia ([ZAK] 6). Najwyżej 2 s (system daje kilka).
    func applicationWillTerminate(_ application: UIApplication) {
        guard let ride = RideBridge.shared.controller, ride.isRunning else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await ride.interrupt()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
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
