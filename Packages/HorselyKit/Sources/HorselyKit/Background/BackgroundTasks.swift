import Foundation
import HorselyCore
#if os(iOS)
import BackgroundTasks
#endif

/// Praca w tle (research R12, T093): `pl.glapa.horsely.refresh` — odświeżenie danych co 60 min (15 min, gdy program ma stempel
/// danych), `pl.glapa.horsely.sync` — wysyłka kolejki. iOS uruchamia je „w miarę możliwości”, więc przy każdej aktywacji aplikacja
/// nadrabia zaległości (`catchUpIfNeeded`). Reguła „tylko przez Wi‑Fi”: w sieci z limitem w tle nie są używane adresy nielokalne
/// do odświeżania (wpisy bez załączników wysyłane zawsze).
public enum BackgroundWork {
    public static let refreshIdentifier = "pl.glapa.horsely.refresh"
    public static let syncIdentifier = "pl.glapa.horsely.sync"
    public static let refreshInterval: TimeInterval = 60 * 60
    public static let stampRefreshInterval: TimeInterval = 15 * 60

    public static func refreshInterval(for capabilities: ProgramCapabilities) -> TimeInterval {
        capabilities.dataStamp ? stampRefreshInterval : refreshInterval
    }

    /// Czy odświeżenie w tle może teraz użyć sieci: bez ograniczenia albo w sieci bez limitu, albo gdy jest adres lokalny.
    public static func mayRefresh(network: NetworkConditions, wifiOnly: Bool, hasLocalAddress: Bool) -> Bool {
        guard network.isAvailable else { return false }
        return !wifiOnly || !network.isExpensive || hasLocalAddress
    }

    /// Nadrabianie przy aktywacji: odświeżenie, gdy od ostatniego minął odstęp pracy w tle (albo 15 min na pierwszym planie).
    public static func isRefreshDue(lastSyncAt: Date?, now: Date, interval: TimeInterval = stampRefreshInterval) -> Bool {
        guard let lastSyncAt else { return true }
        return now.timeIntervalSince(lastSyncAt) >= interval
    }
}

#if os(iOS)
/// Rejestracja zadań w `BGTaskScheduler` — wołana raz przy starcie aplikacji, przed końcem `didFinishLaunching`.
public final class BackgroundTasks: @unchecked Sendable {
    public typealias Work = @Sendable (_ background: Bool) async -> Bool

    private let refresh: Work
    private let sync: Work
    private let interval: @Sendable () async -> TimeInterval

    /// - Parameters:
    ///   - refresh: wysyłka kolejki + odświeżenie danych; `true` — udane
    ///   - sync: sama wysyłka kolejki
    ///   - interval: odstęp następnego odświeżenia (zależny od możliwości programu)
    public init(refresh: @escaping Work, sync: @escaping Work, interval: @escaping @Sendable () async -> TimeInterval) {
        self.refresh = refresh
        self.sync = sync
        self.interval = interval
    }

    public func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundWork.refreshIdentifier, using: nil) { [self] task in
            handle(task, work: refresh, reschedule: true)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundWork.syncIdentifier, using: nil) { [self] task in
            handle(task, work: sync, reschedule: false)
        }
    }

    private func handle(_ task: BGTask, work: @escaping Work, reschedule: Bool) {
        let holder = TaskHolder(task)
        let job = Task {
            let ok = await work(true)
            if reschedule { await self.scheduleRefresh() }
            holder.complete(ok)
        }
        holder.onExpiration { job.cancel() }
    }

    /// `BGTask` nie jest `Sendable`; dostęp tylko przez ten pojemnik.
    private final class TaskHolder: @unchecked Sendable {
        private let task: BGTask

        init(_ task: BGTask) {
            self.task = task
        }

        func complete(_ success: Bool) {
            task.setTaskCompleted(success: success)
        }

        func onExpiration(_ handler: @escaping @Sendable () -> Void) {
            task.expirationHandler = handler
        }
    }

    public func scheduleRefresh() async {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundWork.refreshIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(await interval())
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Wysyłka kolejki w tle, gdy zostały niewysłane operacje (sieć wymagana).
    public func scheduleSync(after delay: TimeInterval = 60) {
        let request = BGProcessingTaskRequest(identifier: BackgroundWork.syncIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date().addingTimeInterval(delay)
        try? BGTaskScheduler.shared.submit(request)
    }
}
#endif
