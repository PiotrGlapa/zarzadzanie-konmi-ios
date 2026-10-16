import HorselyCore
import HorselyKit
import SwiftUI
import UserNotifications

/// Punkt wejścia aplikacji. Środowisko (magazyn, ustawienia, zegar, router) tworzone raz przy starcie; zadania w tle rejestrowane
/// przed końcem uruchamiania (wymóg `BGTaskScheduler`).
@main
struct HorselyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment
    private let background: BackgroundTasks
    private let notificationDelegate: NotificationDelegate

    init() {
        let environment = AppEnvironment.live()
        #if DEBUG
        // Testy UI: szybka akcja ikony podana jako argument (`-UITestShortcut <typ>`).
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-UITestShortcut"), arguments.indices.contains(index + 1) {
            QuickActions.shared.pending = arguments[index + 1]
        }
        #endif
        _environment = State(initialValue: environment)
        let settings = environment.settings
        let store = environment.store
        let sync = environment.sync
        let outbox = environment.outbox
        let network = environment.network
        background = BackgroundTasks(
            refresh: { _ in
                await environment.processSharedInbox()
                // Okno planu powiadomień (14 dni) przesuwa się z każdym przebiegiem w tle.
                await environment.rescheduleNotificationsNow()
                guard settings.workMode == .online else { return true }
                _ = await outbox.processAll()
                let hasLocal = ((try? await store.read { try $0.addresses() }) ?? []).contains(where: \.isLocal)
                guard BackgroundWork.mayRefresh(network: network.conditions, wifiOnly: settings.wifiOnly, hasLocalAddress: hasLocal) else { return true }
                return await sync.refresh(background: true).succeeded
            },
            sync: { _ in
                await environment.processSharedInbox()
                guard settings.workMode == .online else { return true }
                return await outbox.processAll().stopped == nil
            },
            backup: { _ in
                await AutoBackupRunner.runIfDue(environment)
                return true
            },
            interval: { BackgroundWork.refreshInterval(for: await sync.capabilities()) }
        )
        background.register()
        notificationDelegate = NotificationDelegate { url in environment.router.handle(url: url, mode: environment.workMode) }
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task {
                    // Kopia automatyczna: nadrabianie przy otwarciu i następne zadanie w tle (tryb samodzielny).
                    if environment.workMode == .standalone {
                        await AutoBackupRunner.runIfDue(environment)
                        background.scheduleBackup()
                    }
                }
                .task {
                    guard environment.workMode == .online else { return }
                    await background.scheduleRefresh()
                }
        }
        // Sesja wysyłki plików w tle: system budzi aplikację, gdy wysyłka skończy się poza nią — zdarzenia odbiera `BackgroundUploader`.
        .backgroundTask(.urlSession(BackgroundUploader.identifier)) {}
    }
}
