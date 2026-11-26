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
        let attachments = environment.attachments
        background = BackgroundTasks(
            refresh: { _ in
                await environment.processSharedInbox()
                // Okno planu powiadomień (14 dni) przesuwa się z każdym przebiegiem w tle.
                await environment.rescheduleNotificationsNow()
                guard settings.workMode == .online else { return true }
                // Push z serwera: jedna próba nadrobienia rejestracji, bez ponowień (spec 003, research R7).
                await environment.pushRegistrar.reconcile(.background)
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
            video: { _ in
                // Przygotowanie filmów z kolejki (A10); przerwane przez koniec czasu zadania wznowi start aplikacji.
                guard settings.workMode == .online else { return true }
                if await attachments.resumePreparation() > 0 { _ = await outbox.processAll() }
                let waiting = await attachments.hasPreparingVideos()
                return !waiting
            },
            interval: { BackgroundWork.refreshInterval(for: await sync.capabilities()) }
        )
        background.register()
        let tasks = background
        environment.scheduleVideoPreparation = { tasks.scheduleVideoPreparation() }
        PushBridge.shared.registrar = environment.pushRegistrar
        // Nagrywanie jazdy (Task 15, A13): decyzję o wznowieniu niezakończonej jazdy podejmuje `AppDelegate.didFinishLaunching` (zna
        // przyczynę uruchomienia i stan aplikacji); `App.init` wykonuje się wcześniej, więc kontroler jest już wtedy dostępny.
        RideBridge.shared.controller = environment.ride
        // Przyciski Live Activity (Task 16): `LiveActivityIntent` wykonuje się w tym procesie i trafia do tego samego kontrolera.
        RideActivityActions.shared.register(environment.ride)
        notificationDelegate = NotificationDelegate(
            open: { url in environment.router.handle(url: url, mode: environment.workMode) },
            presentServerMessage: { message in environment.presentation(forServerMessage: message) },
            openServerMessage: { message in environment.open(serverMessage: message) }
        )
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
