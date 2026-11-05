import Foundation
import HorselyCore

/// Co wywołało uzgodnienie stanu push (research R7).
public enum PushTrigger: Sendable, Equatable {
    /// Start aplikacji w trybie z serwerem.
    case launch
    /// Po sparowaniu telefonu z serwerem.
    case paired
    /// Wejście na pierwszy plan (odczyt zgody systemu, nadrabianie rejestracji).
    case foreground
    /// Zadanie w tle (`BGAppRefreshTask`): jedna próba, bez ponowień w aplikacji.
    case background
    /// Zmiana zgody na powiadomienia (pytanie z Pulpitu albo z ustawień systemu).
    case permissionChanged
    /// Biblioteka zgłosiła nowy token.
    case tokenChanged
    /// Inne (np. ekran „Powiadomienia”).
    case manual
    /// System zarejestrował telefon w APNs i dostarczył token — rejestracja, która czekała na niego, rusza od razu.
    case apnsRegistered
    /// `system/info` zmieniło możliwości serwera (`push` pojawiło się albo zniknęło).
    case capabilities(CapabilitiesChange)
}

/// Rejestracja telefonu na serwerze i stan push (spec 003, data-model.md §1–§2, research R4–R9).
///
/// - Rejestruje token FCM na serwerze (`PUT push/device`) tylko w trybie z serwerem, gdy serwer ogłasza `push` i jest zgoda
///   na powiadomienia (FR-014a). Najwyżej raz na dobę, chyba że zmienił się token albo rejestracji brakuje (FR-003).
/// - Ponawia nieudane próby w aplikacji: 30 s → 15 min (FR-004); po 24 h bez powodzenia albo po `400` — `registrationFailed`
///   (powiadomienia lokalne wracają), ale ponowienia trwają dalej (FR-005).
/// - Stan `PushState` liczy `PushPolicy.decide` z trwałych danych i bieżącej zgody; każdą zmianę zgłasza przez `onState`, a
///   wołający przelicza powiadomienia lokalne (tylko `registered` je wyłącza — FR-006, FR-007).
/// - Wyrejestrowanie (`unregister`) wołane jest **przed** usunięciem klucza API (research R9); jego wynik nigdy nie blokuje
///   odparowania ani zmiany trybu.
///
/// Dziennik zawiera tylko 8-znakowy prefiks tokenu i opisy słowami (FR-028).
public actor PushRegistrar {
    /// Planuje pracę po opóźnieniu; zwraca funkcję anulującą. W testach — ręcznie wyzwalana kolejka.
    public typealias RetryTimer = @Sendable (TimeInterval, @escaping @Sendable () async -> Void) -> @Sendable () -> Void

    /// Odstępy między ponowieniami (research R7); ostatni powtarza się aż do skutku.
    public static let retryDelays: [TimeInterval] = [30, 60, 120, 240, 480, 900, 900]
    /// Po tylu sekundach nieudanych prób rejestracja uznawana jest za nieudaną na stałe (FR-005).
    public static let failureThreshold: TimeInterval = 24 * 3600
    /// Odświeżenie rejestracji najwyżej raz na dobę (FR-003).
    public static let refreshInterval: TimeInterval = 24 * 3600
    /// Limit wyrejestrowania — brak odpowiedzi nie wstrzymuje odparowania (SC-005).
    public static let unregisterTimeout: TimeInterval = 5

    /// Zegar produkcyjny: `Task.sleep`, anulowalny.
    public static let liveTimer: RetryTimer = { delay, work in
        let task = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await work()
        }
        return { task.cancel() }
    }

    private let api: PushApi
    private let tokens: any PushTokenSource
    private let settings: SettingsStore
    private let capabilities: @Sendable () async -> ProgramCapabilities
    private let authorization: @Sendable () async -> PushAuthorization
    private let now: @Sendable () -> Date
    private let schedule: RetryTimer
    private let wait: @Sendable (TimeInterval) async -> Void
    private let log: @Sendable (String) -> Void
    private let onState: @Sendable (PushState) -> Void

    private var attempting = false
    /// Token APNs dotarł w trakcie próby rejestracji — nieudana próba jest od razu powtórzona raz.
    private var apnsArrivedDuringAttempt = false
    private var cancelRetry: (@Sendable () -> Void)?
    private var published: PushState?
    private var observing: Task<Void, Never>?

    public init(
        api: PushApi, tokens: any PushTokenSource, settings: SettingsStore,
        capabilities: @escaping @Sendable () async -> ProgramCapabilities,
        authorization: @escaping @Sendable () async -> PushAuthorization,
        now: @escaping @Sendable () -> Date = { Date() },
        schedule: @escaping RetryTimer = PushRegistrar.liveTimer,
        wait: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        log: @escaping @Sendable (String) -> Void = { _ in },
        onState: @escaping @Sendable (PushState) -> Void = { _ in }
    ) {
        self.api = api
        self.tokens = tokens
        self.settings = settings
        self.capabilities = capabilities
        self.authorization = authorization
        self.now = now
        self.schedule = schedule
        self.wait = wait
        self.log = log
        self.onState = onState
    }

    // MARK: Stan

    /// Bieżący stan push (z trwałych danych, możliwości serwera i zgody systemu); zgłasza zmianę przez `onState`.
    @discardableResult
    public func state() async -> PushState {
        let state = PushPolicy.decide(PushInput(
            workMode: settings.workMode, serverHasPush: await capabilities().push, authorization: await authorization(),
            registration: settings.pushRegistration
        ))
        if state != published {
            published = state
            onState(state)
        }
        return state
    }

    // MARK: Uzgadnianie

    /// Uzgadnia rejestrację ze stanem: rejestruje, ponawia, wyrejestrowuje po cofnięciu zgody, nic nie robi w trybie samodzielnym
    /// i przy serwerze bez `push`.
    public func reconcile(_ trigger: PushTrigger) async {
        if case let .capabilities(change) = trigger, change.pushVanished {
            var registration = settings.pushRegistration
            if registration.registered {
                // Serwer przestał ogłaszać `push`: lokalne powiadomienia wracają, bez `DELETE` (FR-011).
                registration.registered = false
                registration.failingSince = nil
                settings.pushRegistration = registration
            }
        }
        let current = await state()
        switch current {
        case .standalone, .fallback(.serverHasNoPush):
            stopRetrying()
        case .noPermission:
            stopRetrying()
            // Cofnięta zgoda: telefon przestaje być adresatem (R9). Bez wcześniejszego użycia push — zero wywołań (FR-027).
            if settings.pushActive || settings.pushRegistration.registered { await unregister() }
        case .fallback(.apnsUnavailable):
            stopRetrying()
            // System mógł zmienić zdanie (np. po przywróceniu sieci) — kolejna próba przy każdym wejściu na pierwszy plan.
            if trigger != .background, trigger != .apnsRegistered { await tokens.registerForRemoteNotifications() }
        case .pending, .registered, .fallback(.registrationFailed):
            await register(trigger)
        }
    }

    /// Przejście aplikacji w tło: oczekujące ponowienia są anulowane (iOS i tak wstrzyma aplikację); nadrobi je następne
    /// wejście na pierwszy plan albo zadanie w tle.
    public func suspend() {
        stopRetrying()
    }

    /// System zarejestrował telefon w APNs. Po wcześniejszej odmowie — stan wraca do `pending` i rejestracja rusza dalej.
    public func didRegisterAPNs() async {
        var registration = settings.pushRegistration
        if registration.apnsRefused {
            registration.apnsRefused = false
            settings.pushRegistration = registration
        }
        await reconcile(.apnsRegistered)
    }

    /// System odmówił rejestracji w APNs (np. brak uprawnienia w profilu, brak sieci): tryb awaryjny z powodem (FR-009).
    public func didFailAPNs() async {
        var registration = settings.pushRegistration
        if !registration.apnsRefused {
            registration.apnsRefused = true
            settings.pushRegistration = registration
        }
        log(PushDiagnostics.apnsRefused)
        stopRetrying()
        await state()
    }

    /// Nasłuchuje nowych tokenów z biblioteki (jedna pętla na proces).
    public func startObservingTokenChanges() {
        guard observing == nil else { return }
        let changes = tokens.tokenChanges
        observing = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await self?.reconcile(.tokenChanged)
            }
        }
    }

    // MARK: Rejestracja

    private func register(_ trigger: PushTrigger) async {
        guard !attempting else {
            if trigger == .apnsRegistered { apnsArrivedDuringAttempt = true }
            return
        }
        let registration = settings.pushRegistration
        let fresh = registration.registered && (registration.registeredAt.map { now().timeIntervalSince($0) < Self.refreshInterval } ?? false)
        // Rejestracja aktualna (< 24 h) i ten sam token — bez żądania (FR-003). Token APNs mógł się jednak zmienić, a system
        // dostarcza go dopiero po rejestracji w APNs, więc przy starcie i wejściu na pierwszy plan ta rejestracja jest ponawiana.
        if fresh, trigger != .tokenChanged {
            if settings.pushActive, trigger == .launch || trigger == .foreground { await tokens.registerForRemoteNotifications() }
            return
        }
        attempting = true
        apnsArrivedDuringAttempt = false
        defer { attempting = false }
        stopRetrying()
        await prepareSystem(trigger)
        var result = await attempt()
        if result == .retry, apnsArrivedDuringAttempt {
            apnsArrivedDuringAttempt = false
            result = await attempt()
        }
        if result == .retry, trigger != .background { scheduleRetry(index: 0) }
    }

    /// Konfiguracja biblioteki i rejestracja w APNs — dopiero przy pierwszej próbie w trybie z serwerem, z `push` i zgodą.
    private func prepareSystem(_ trigger: PushTrigger) async {
        await tokens.configureIfNeeded()
        if !settings.pushActive {
            settings.pushActive = true
            await tokens.setAutoInit(true)
        }
        if trigger != .background, trigger != .apnsRegistered { await tokens.registerForRemoteNotifications() }
    }

    private enum Attempt { case done, retry, stop }

    private func attempt() async -> Attempt {
        let token: String
        do {
            token = try await tokens.token()
        } catch {
            log(PushDiagnostics.noToken)
            await markFailure()
            return .retry
        }
        guard let registration = DeviceRegistration(token: token) else {
            log(PushDiagnostics.noToken)
            await markFailure()
            return .retry
        }
        switch await api.registerDevice(token: registration) {
        case .ok:
            var stored = settings.pushRegistration
            stored.registered = true
            stored.tokenPrefix = registration.prefix
            stored.registeredAt = now()
            stored.failingSince = nil
            stored.permanentFailure = false
            settings.pushRegistration = stored
            log(PushDiagnostics.registered(prefix: registration.prefix))
            await state()
            return .done
        case let .invalid(fields):
            // `400`: serwer odrzucił token — tryb awaryjny, ale ponowienia trwają (FR-005).
            var stored = settings.pushRegistration
            stored.registered = false
            if stored.failingSince == nil { stored.failingSince = now() }
            stored.permanentFailure = true
            settings.pushRegistration = stored
            log(PushDiagnostics.registrationRejected(fields: fields))
            await state()
            return .retry
        case let .transient(reason):
            log(PushDiagnostics.registrationFailed(reason))
            await markFailure()
            return .retry
        case .notRegistered:
            log(PushDiagnostics.registrationFailed("serwer nie zna urządzenia (404)"))
            await markFailure()
            return .retry
        case .access:
            // `401`/`403`/`429`: obsłużone przez `ApiClient` (wstrzymanie adresu, ekran połączenia) — bez komunikatu push.
            log(PushDiagnostics.registrationFailed("dostęp do serwera wstrzymany"))
            return .stop
        }
    }

    /// Pierwszy błąd serii ustawia `failingSince`; po 24 h rejestracja uznawana jest za nieudaną (FR-004, FR-005).
    private func markFailure() async {
        var stored = settings.pushRegistration
        if stored.failingSince == nil { stored.failingSince = now() }
        if let since = stored.failingSince, now().timeIntervalSince(since) >= Self.failureThreshold { stored.permanentFailure = true }
        settings.pushRegistration = stored
        await state()
    }

    private func scheduleRetry(index: Int) {
        let delay = Self.retryDelays[min(index, Self.retryDelays.count - 1)]
        stopRetrying()
        cancelRetry = schedule(delay) { [weak self] in await self?.retry(index: index + 1) }
    }

    private func retry(index: Int) async {
        cancelRetry = nil
        guard !attempting else { return }
        let current = await state()
        guard current.registrationAllowed else { return }
        attempting = true
        defer { attempting = false }
        if await attempt() == .retry { scheduleRetry(index: index) }
    }

    private func stopRetrying() {
        cancelRetry?()
        cancelRetry = nil
    }

    // MARK: Ekran „Powiadomienia”

    /// Dane z `GET push/device` (daty rejestracji i doręczeń). `404` — właściciel usunął telefon z listy urządzeń: rejestracja
    /// jest unieważniona, ekran pokaże jednorazowy komunikat, a telefon rejestruje się ponownie od razu (FR-025).
    public func deviceInfo() async -> PushDevice? {
        switch await api.device() {
        case let .ok(device):
            return device
        case .notRegistered:
            var registration = settings.pushRegistration
            guard registration.registered else { return nil }
            registration.registered = false
            registration.deviceRemovedNotice = true
            settings.pushRegistration = registration
            log(PushDiagnostics.registrationFailed("serwer nie zna urządzenia (404)"))
            await state()
            await register(.manual)
            return nil
        default:
            return nil
        }
    }

    /// Reguły z `GET push/rules` w kolejności serwera; `nil` — nie udało się pobrać (stan push bez zmian, FR-026a).
    public func rules() async -> [ClientPushRule]? {
        guard case let .ok(rules) = await api.rules() else { return nil }
        return rules
    }

    /// „Rozumiem” w oknie o usuniętym telefonie.
    public func acknowledgeDeviceRemoved() {
        var registration = settings.pushRegistration
        guard registration.deviceRemovedNotice else { return }
        registration.deviceRemovedNotice = false
        settings.pushRegistration = registration
    }

    // MARK: Wyrejestrowanie

    /// `DELETE push/device` (limit 5 s), potem token, samoczynne pobieranie, APNs i stan lokalny. Wołać **przed** usunięciem klucza
    /// API. Każdy wynik `DELETE` (204, 401, brak sieci, 5xx, brak odpowiedzi) jest ignorowany poza wpisem w dzienniku.
    /// Gdy push nigdy nie był używany na tym telefonie — tylko czyszczenie, zero wywołań źródła tokenu (FR-027).
    public func unregister() async {
        stopRetrying()
        let used = settings.pushActive || settings.pushRegistration.registered || settings.pushRegistration.tokenPrefix != nil
        guard used else {
            settings.clearPushConnectionState()
            await state()
            return
        }
        let api = self.api
        let result = await withTimeout(Self.unregisterTimeout) { await api.unregisterDevice() }
        switch result {
        case .some(.ok): log(PushDiagnostics.unregistered("ok"))
        case let .some(.transient(reason)): log(PushDiagnostics.unregistered(reason))
        case .some(.access): log(PushDiagnostics.unregistered("dostęp do serwera wstrzymany"))
        case .some(.notRegistered): log(PushDiagnostics.unregistered("serwer nie zna urządzenia"))
        case .some(.invalid): log(PushDiagnostics.unregistered("serwer odrzucił żądanie"))
        case .none: log(PushDiagnostics.unregistered("brak odpowiedzi w \(Int(Self.unregisterTimeout)) s"))
        }
        await tokens.deleteToken()
        await tokens.setAutoInit(false)
        await tokens.unregisterForRemoteNotifications()
        settings.clearPushConnectionState()
        await state()
    }

    /// Wynik operacji albo `nil`, gdy upłynął limit. Zapomniana operacja dobiega końca w tle.
    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async -> T) async -> T? {
        let wait = self.wait
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = ResumeOnce(continuation)
            Task { gate.resume(await operation()) }
            Task {
                await wait(seconds)
                gate.resume(nil)
            }
        }
    }
}

/// Wznawia kontynuację dokładnie raz (wyścig wyniku z limitem czasu).
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T?) {
        let pending = lock.withLock { () -> CheckedContinuation<T?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
