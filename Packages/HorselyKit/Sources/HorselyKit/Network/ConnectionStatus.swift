import Foundation
import HorselyCore
import Network
import Observation

/// Problem z połączeniem pokazywany w aplikacji (contracts/android/connection-behavior.md §2–§4).
public enum ConnectionProblem: Equatable, Sendable {
    /// Komputer nie odpowiada — pomarańczowa ikonka, „Odśwież”.
    case offline
    /// Telefon nie ma sieci — pomarańczowa ikonka, wznowienie samoczynne.
    case noNetwork
    /// Odmowa programu albo zmieniony certyfikat — czerwona ikonka, wymaga działania.
    case denied(BlockReason, until: Date?)

    /// Czerwona ikonka (`ErrorOutline`) — odmowy; pomarańczowa (`CloudOff`) — brak połączenia.
    public var isDenial: Bool {
        if case .denied = self { return true }
        return false
    }

    /// Rodzaj problemu do porównania „ten sam / inny” (samoczynne rozwinięcie tylko przy zmianie rodzaju).
    public var variant: String {
        switch self {
        case .offline: "offline"
        case .noNetwork: "noNetwork"
        case let .denied(reason, _): "denied-\(reason.rawValue)"
        }
    }

    /// Czy przycisk działania prowadzi do ponownego parowania („Połącz ponownie”), a nie do sprawdzenia połączenia.
    public var needsRepairing: Bool {
        if case let .denied(reason, _) = self { return reason == .keyRejected || reason == .certificateChanged }
        return false
    }
}

/// Jeden stan połączenia dla całej aplikacji (T082): aktualizowany **każdym** żądaniem (`ConnectionEvent`), sprawdzaniem co 30 s
/// na pierwszym planie w stanie „offline” i zmianą sieci (`NWPathMonitor`). Zmiana ekranu nie zmienia stanu.
@MainActor
@Observable
public final class ConnectionStatus {
    public static let foregroundCheckInterval: TimeInterval = 30

    public private(set) var problem: ConnectionProblem?
    /// Trwa sprawdzanie („Sprawdzam połączenie…”, przycisk nieaktywny).
    public private(set) var checking = false
    /// Chwila nieudanego „Odśwież” — „Komputer nadal nie odpowiada (sprawdzono HH:mm)”.
    public private(set) var failedCheckAt: Date?
    /// Data danych w pamięci (podtytuł „Dane z …”).
    public var dataFrom: Date?

    @ObservationIgnored private var checker: (@Sendable () async -> Bool)?
    @ObservationIgnored private var running: Task<Bool, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var foreground = false

    public init(problem: ConnectionProblem? = nil, dataFrom: Date? = nil) {
        self.problem = problem
        self.dataFrom = dataFrom
    }

    /// Sprawdzenie połączenia: `GET /system/info` po kolei na adresach; `true` — program odpowiedział.
    public func setChecker(_ checker: @escaping @Sendable () async -> Bool) {
        self.checker = checker
    }

    /// Zdarzenie z klienta programu.
    public func handle(_ event: ConnectionEvent) {
        switch event {
        case .answered:
            // Odmowy mają pierwszeństwo: odpowiedź z innego adresu nie kasuje wstrzymania klucza.
            if case .denied = problem { return }
            problem = nil
            failedCheckAt = nil
        case .unreachable:
            if case .denied = problem { return }
            problem = .offline
        case let .denied(reason, until):
            problem = .denied(reason, until: until)
        case .noNetwork:
            if case .denied = problem { return }
            problem = .noNetwork
        }
    }

    /// Zmiana sieci: utrata ostatniej sieci → „brak sieci”; odzyskanie → natychmiastowe sprawdzenie.
    public func networkChanged(available: Bool) {
        if !available {
            handle(.noNetwork)
        } else if problem == .noNetwork || problem == .offline {
            Task { await checkNow() }
        }
    }

    /// Ponowne parowanie / „Sprawdź połączenie” zwolniło wstrzymanie.
    public func clearDenial() {
        if case .denied = problem { problem = nil }
    }

    public func reset() {
        problem = nil
        checking = false
        failedCheckAt = nil
    }

    /// „Odśwież” i sprawdzanie samoczynne: jedno naraz — kolejne wywołania dołączają do trwającego (FR-POL2-08).
    @discardableResult
    public func checkNow(userInitiated: Bool = false) async -> Bool {
        if let running { return await running.value }
        guard let checker else { return false }
        if problem == .noNetwork {
            failedCheckAt = userInitiated ? Date() : failedCheckAt
            return false
        }
        checking = true
        let task = Task { await checker() }
        running = task
        let ok = await task.value
        running = nil
        checking = false
        if ok {
            if case .denied = problem {} else { problem = nil }
            failedCheckAt = nil
        } else {
            if problem == nil { problem = .offline }
            if userInitiated { failedCheckAt = Date() }
        }
        return ok
    }

    /// Aplikacja na pierwszym planie: sprawdzanie co 30 s w stanie „offline”, natychmiast przy powrocie.
    public func enterForeground() {
        foreground = true
        if problem == .offline { Task { await checkNow() } }
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(ConnectionStatus.foregroundCheckInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if self.foreground && self.problem == .offline { await self.checkNow() }
            }
        }
    }

    /// W tle — bez żądań.
    public func enterBackground() {
        foreground = false
        loop?.cancel()
        loop = nil
    }
}

/// Stan sieci telefonu z `NWPathMonitor` (zmiany sieci → stan połączenia, reguła „tylko przez Wi‑Fi”).
public final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var current = FixedNetwork.wifi
    private var listeners: [@Sendable (FixedNetwork) -> Void] = []

    public init() {}

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let label: String
            if path.status != .satisfied {
                label = "brak sieci"
            } else if path.usesInterfaceType(.wifi) {
                label = "Wi‑Fi"
            } else if path.usesInterfaceType(.cellular) {
                label = "komórkowa"
            } else if path.usesInterfaceType(.wiredEthernet) {
                label = "Ethernet"
            } else {
                label = "inna"
            }
            let snapshot = FixedNetwork(isAvailable: path.status == .satisfied, isExpensive: path.isExpensive, label: label)
            self.lock.lock()
            let changed = snapshot.isAvailable != self.current.isAvailable || snapshot.label != self.current.label
            self.current = snapshot
            let listeners = self.listeners
            self.lock.unlock()
            if changed { listeners.forEach { $0(snapshot) } }
        }
        monitor.start(queue: DispatchQueue(label: "pl.glapa.horsely.network"))
    }

    public var conditions: FixedNetwork {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func onChange(_ listener: @escaping @Sendable (FixedNetwork) -> Void) {
        lock.lock()
        listeners.append(listener)
        lock.unlock()
    }
}
