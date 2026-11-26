import Foundation
import HorselyCore
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

// Kontroler nagrywania jazdy (Task 15 = Android `RideRecordingController.kt` + logika `RideRecordingService.kt` z Androida 3.0.2, decyzja
// A13): łączy źródło lokalizacji i akcelerometru z maszyną `RideRecorder` i zapisem w `RideSessionStore`.

/// Dlaczego nie można zacząć nagrywania. Teksty dla użytkownika daje interfejs (Task 17) z katalogu: odmowa i przybliżona lokalizacja —
/// `ride_location_denied` („Bez dostępu do dokładnej lokalizacji nie da się nagrać jazdy.”) z przyciskiem „Otwórz ustawienia”.
public enum RideStartError: Error, Sendable, Equatable {
    /// Użytkownik nie odpowiedział jeszcze na pytanie o lokalizację — interfejs musi najpierw o nią poprosić.
    case locationNotDetermined
    /// Odmowa (albo ograniczenie) dostępu do lokalizacji.
    case locationDenied
    /// Zgoda tylko na przybliżoną lokalizację — trasa byłaby bezużyteczna.
    case reducedAccuracy
    /// Ten kontroler już nagrywa jazdę.
    case alreadyRecording
    /// Sesja powstała, ale nie dało się uruchomić odbioru GPS — sesja dostała stan `.interrupted` (do zapisania albo odrzucenia).
    case locationUnavailable
}

/// Jak uruchomiono aplikację — decyduje, czy niezakończona jazda wraca do nagrywania (A13 na iOS, [ZAK] 6, SPECYFIKACJA 9.3).
public enum RideLaunchKind: Sendable, Hashable {
    /// Użytkownik otworzył aplikację (stan `.inactive` w `didFinishLaunching`). Niezakończona jazda NIE jest wznawiana: system, który
    /// zamknął aplikację, wznawia ją w tle, więc uruchomienie na pierwszym planie z jazdą w bazie oznacza przesunięcie (albo nieudane
    /// wznowienie) → stan `.interrupted` i „Zapisz / Odrzuć”.
    case foreground
    /// System uruchomił aplikację w tle z powodu lokalizacji (`UIApplication.LaunchOptionsKey.location`) — wznowienie.
    case backgroundLocation
    /// Inne uruchomienie w tle (push, odświeżanie w tle): wznowienie tylko jazdy wstrzymanej albo ze świeżym ostatnim zapisem
    /// (≤ `RideRecordingController.relaunchFreshnessMillis`) — bezpiecznik na przesunięcie, po którym przyszło np. odświeżanie w tle.
    case background
}

/// Poziom baterii w trakcie nagrywania (w testach zaślepka). `start`/`stop` nie czekają (wywołanie z `applicationWillTerminate`, kiedy
/// wątek główny jest zajęty, nie może się zakleszczyć).
public protocol BatteryMonitor: Sendable {
    func start()
    func stop()
    /// Poziom w procentach albo `nil`, gdy nieznany.
    func percent() async -> Int?
}

#if canImport(UIKit) && os(iOS)
/// `UIDevice`: monitorowanie baterii włączone tylko w trakcie nagrywania ([ZAK] 6).
public struct DeviceBatteryMonitor: BatteryMonitor {
    public init() {}

    public func start() {
        Task { @MainActor in UIDevice.current.isBatteryMonitoringEnabled = true }
    }

    public func stop() {
        Task { @MainActor in UIDevice.current.isBatteryMonitoringEnabled = false }
    }

    public func percent() async -> Int? {
        await MainActor.run {
            let device = UIDevice.current
            guard device.isBatteryMonitoringEnabled, device.batteryState != .unknown else { return nil }
            return Self.percent(level: device.batteryLevel)
        }
    }

    /// `batteryLevel` 0…1 (−1 nieznany) → procent zaokrąglony do całości.
    static func percent(level: Float) -> Int? {
        guard level >= 0, level.isFinite else { return nil }
        return Int((Double(level) * 100).rounded())
    }
}
#endif

/// Kontroler nagrywania jazdy — serce nagrywania (Android: sterownik + usługa pierwszoplanowa).
///
/// **Jedna instancja i jeden aktor (kontrakt, Task 14 M6):** aplikacja ma JEDEN `RideSessionStore` i JEDEN `RideRecordingController`
/// (`AppEnvironment`). Maszyna `RideRecorder` (klasa nie-`Sendable`) żyje wyłącznie w tym aktorze i nigdy go nie opuszcza. Pasek NAG-01 nie
/// pyta kontrolera — obserwuje migawkę z tego samego sklepu (`observeActiveRide()`), którą aktualizuje każdy zapis; dwa sklepy albo dwa
/// kontrolery dałyby dwie maszyny i odwróconą kolejność migawek.
///
/// Zasady (jak w Androidzie):
/// - jeden zegar `clock` dla punktów (`onLocation`), okien ruchu (`onMotion`) i tików — czas odbioru, nie `CLLocation.timestamp`;
/// - maszyna powstaje z wiersza sesji (`LoadedSession.restoreRecorder()`), więc jej `startedAtMillis` to zawsze ten zapisany przez `start`;
/// - punkty wchodzą bez rytmu i intensywności; okna 5 s dodaje `onMotion`;
/// - tik co `tickInterval` (1 s); po `.flushDue` (co 5 s) zapis `drainUnsaved()` + migawka + pauzy. Gdy zapis się nie uda, oddane przez
///   maszynę punkty czekają w zaległych (`backlog`) i następny zapis wysyła TĘ SAMĄ partię razem z nowymi punktami (Task 14 M5) — dzięki
///   temu po zabiciu procesu w bazie jest wszystko sprzed ≥ 10 s (Review Focus 2). Zapisy idą po kolei (łańcuch zadań), więc zaległe
///   punkty nie mieszają się między równoległymi zapisami;
/// - po `.autoFinished` (8 h) — ostatni zapis, stan `.finished`, powiadomienie.
///
/// Zgoda na lokalizację: start tylko przy `.whenInUse` (dokładna, „Podczas używania”); cofnięcie zgody w trakcie (sprawdzane przy każdym
/// tiku) zapisuje bieżące punkty i oznacza sesję `.interrupted` z powiadomieniem „Nagrywanie przerwane — …”.
///
/// Dziennik diagnostyczny (`log`) dostaje wpisy stanu: start, pauza, wznowienie, ponowne uruchomienie, słaby GPS, bateria, przerwanie,
/// koniec — z czasem jazdy, liczbą punktów i ostatnią dokładnością. **Nigdy współrzędnych ani nazwy konia** (konstytucja 3.0.0, zasada II);
/// błędy tylko nazwą typu.
public actor RideRecordingController {
    /// Kategoria wpisów w dzienniku diagnostycznym (jak `LOG_CATEGORY` usługi Androida).
    public static let logCategory = "nagrywanie"

    /// Tik co sekundę (maszyna oczekuje tików nie rzadziej niż co 5 s).
    public static let defaultTickInterval: Duration = .seconds(1)

    private static let maxFailuresLogged = 5

    /// Uruchomienie w tle bez klucza lokalizacji wznawia nagrywanie tylko, gdy ostatni zapis jest nie starszy niż 10 min.
    public static let relaunchFreshnessMillis: Int64 = 10 * 60 * 1000

    /// Ile razy z rzędu ponawiamy odbiór GPS po nieoczekiwanym końcu strumienia, zanim przerwiemy jazdę.
    static let maxLocationRestarts = 3

    private struct Status: Sendable {
        var sessionId: String?
        var running = false
    }

    private let store: RideSessionStore
    private let locations: any LocationSource
    private let motion: any MotionSource
    private let battery: any BatteryMonitor
    private let notifier: any RideNotifier
    private let activity: any RideActivityPresenter
    private let clock: @Sendable () -> Int64
    private let log: @Sendable (String) -> Void
    private let tickInterval: Duration?
    private let status = Mutex(Status())

    /// Zadanie zaplanowane przez `prepareRelaunch` — akcje z Live Activity (proces uruchomiony w tle przez przycisk) czekają na nie, żeby
    /// „Pauza” nie trafiła w kontroler przed wznowieniem jazdy.
    private let pendingRelaunch = Mutex<Task<Void, Never>?>(nil)

    /// Ostatni stan wysłany do Live Activity (`nil` — aktywności nie ma); aktualizacja tylko przy zmianie widocznej treści.
    private var activityState: RideActivityState?

    /// Migawki stanu na żywo (Live Activity — Task 16): po każdym tiku, punkcie zmieniającym słaby GPS, pauzie, wznowieniu i zakończeniu;
    /// najnowsza wygrywa. Jeden odbiorca. Przy przerwaniu ostatnia migawka ma stan `.interrupted`.
    public nonisolated let snapshots: AsyncStream<RideSnapshot>
    private let snapshotContinuation: AsyncStream<RideSnapshot>.Continuation

    private var recorder: RideRecorder?
    private var sessionId: String?
    private var window = AccelWindowBuffer()
    private var ticker: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var motionTask: Task<Void, Never>?
    private var sensorsRunning = false
    private var finishing = false
    private var flushQueued = false
    private var flushChain: Task<Void, Never>?

    /// Punkty oddane przez `drainUnsaved()`, a jeszcze niepotwierdzone zapisem — wracają przy następnej próbie (zapis zastępuje wiersz po czasie).
    private var backlog: [TrackPoint] = []
    private var lastBattery: Int?
    private var lastAccuracyM: Double?
    private var failuresLogged = 0

    /// Wznawianie po ponownym uruchomieniu w toku — drugie równoczesne wywołanie nic nie robi.
    private var relaunching = false

    /// Numer bieżącego strumienia lokalizacji (koniec starego, anulowanego strumienia nie jest awarią) i liczba ponowień z rzędu.
    private var locationGeneration = 0
    private var locationRestarts = 0

    /// Ostatni punkt z flagą bezruchu (`CLLocationUpdate.stationary`): iOS wstrzymuje wtedy dostawy, więc tik podaje maszynie ten punkt
    /// z bieżącym czasem (prędkość 0) — postój konia nie jest „słabym GPS”, a dystans się nie zmienia (te same współrzędne).
    private var stationarySample: LocationSample?

    /// Liczniki odebranych próbek (testy czekają na nie zamiast na czas).
    private(set) var receivedLocations = 0
    private(set) var receivedMotionSamples = 0

    /// - Parameters:
    ///   - store: JEDYNY sklep sesji aplikacji (ten sam, który obserwuje pasek NAG-01)
    ///   - activity: Live Activity jazdy (Task 16) — start, aktualizacje i koniec prowadzi kontroler
    ///   - clock: „teraz” w ms epoki — ten sam zegar co `RideSessionStore` (testy podają sterowany)
    ///   - log: wpis w dzienniku diagnostycznym (kategoria `logCategory`) — tekst bez współrzędnych i nazwy konia
    ///   - tickInterval: odstęp tików; `nil` — bez samoczynnych tików (testy wołają `tick()` same)
    public init(
        store: RideSessionStore, locations: any LocationSource, motion: any MotionSource, battery: any BatteryMonitor, notifier: any RideNotifier,
        activity: any RideActivityPresenter = NoRideActivityPresenter(),
        clock: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded()) },
        log: @escaping @Sendable (String) -> Void = { _ in }, tickInterval: Duration? = RideRecordingController.defaultTickInterval
    ) {
        self.store = store
        self.locations = locations
        self.motion = motion
        self.battery = battery
        self.notifier = notifier
        self.activity = activity
        self.clock = clock
        self.log = log
        self.tickInterval = tickInterval
        let (stream, continuation) = AsyncStream<RideSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.snapshots = stream
        self.snapshotContinuation = continuation
    }

    /// Czy kontroler nagrywa jazdę w tym procesie (Android: `RideRecordingService.running`). Gdy `false`, niezakończona sesja w bazie czeka
    /// na „Zapisz / Odrzuć” (Task 17).
    public nonisolated var isRunning: Bool { status.withLock { $0.running } }

    /// Id nagrywanej sesji albo `nil`.
    public nonisolated var activeSessionId: String? { status.withLock { $0.sessionId } }

    // MARK: - Akcje

    /// Zaczyna nagrywanie nowej jazdy i zwraca id sesji. Najpierw zgoda: tylko dokładna lokalizacja „Podczas używania” — inaczej
    /// `RideStartError` i nic nie powstaje. Niezapisana poprzednia jazda — `RideSessionError.onlyOneActiveSession` ze sklepu.
    public func start(horse: HorseRef, params: EffectiveRideParameters) async throws -> String {
        guard recorder == nil else { throw RideStartError.alreadyRecording }
        switch locations.authorization {
        case .whenInUse: break
        case .notDetermined: throw RideStartError.locationNotDetermined
        case .denied:
            log("Start zablokowany: brak zgody na lokalizację")
            throw RideStartError.locationDenied
        case .reducedAccuracy:
            log("Start zablokowany: tylko przybliżona lokalizacja")
            throw RideStartError.reducedAccuracy
        }
        let id = try await store.start(horse: horse, params: params, startedAtMillis: clock())
        let started: Bool
        do {
            started = try await begin(sessionId: id, afterRestart: false)
        } catch {
            log("Start nagrywania nie powiódł się (\(Self.typeName(error)))")
            started = false
        }
        if !started {
            await markInterrupted(id)
            throw RideStartError.locationUnavailable
        }
        return id
    }

    /// Wstrzymuje jazdę: zatrzymuje odbiór GPS i akcelerometr, zapisuje stan (pauza przetrwa zabicie procesu). Sesja aktywności w tle
    /// zostaje (iOS): bez niej „Wznów” z ekranu blokady (Live Activity, Task 16) nie mógłby ponownie uruchomić lokalizacji w tle.
    public func pause() async {
        guard let machine = recorder, !finishing, machine.snapshot().state == .recording else { return }
        machine.pause(tMillis: clock())
        stopSensors(keepBackgroundActivity: true)
        log(entry("Pauza", machine))
        await flush()
        await publish()
    }

    /// Wznawia po pauzie: zeruje bufor okna akcelerometru (okno nie może obejmować przerwy) i włącza czujniki.
    public func resume() async {
        guard let machine = recorder, !finishing, machine.snapshot().state == .paused else { return }
        machine.resume(tMillis: clock())
        window.clear()
        if startSensors() {
            log(entry("Wznowienie", machine))
        } else {
            log(entry("Wznowienie: nie udało się uruchomić GPS (\(Self.describe(locations.authorization)))", machine))
        }
        await flush()
        await publish()
    }

    /// Kończy jazdę na prośbę użytkownika: zatrzymuje źródła, ostatni zapis punktów, stan `.finished`. Zwraca id sesji (ekran zakończenia)
    /// albo `nil`, gdy nic się nie nagrywało.
    @discardableResult
    public func finish() async -> String? {
        guard let machine = recorder, let id = sessionId, !finishing else { return nil }
        finishing = true
        stopSensors(keepBackgroundActivity: false)
        // Czas maszyny dochodzi do chwili zakończenia (otwarta pauza dostaje właściwy koniec); tik może też zgłosić 8 h.
        let events = machine.tick(tMillis: clock(), batteryPercent: nil)
        await closeRide(machine, id)
        if events.contains(.autoFinished) { await notifier.autoFinished() }
        log(entry("Koniec nagrywania", machine))
        await end(machine)
        return id
    }

    /// Najlepsza próba zapisania stanu, gdy aplikacja kończy się bez zakończenia jazdy (`applicationWillTerminate` — zamknięcie
    /// przesunięciem): ostatnie punkty i stan `.interrupted`, więc przy następnym starcie jest „Zapisz / Odrzuć” zamiast wznowienia.
    /// Zabicie procesu przez system nie zostawia czasu na nic — wtedy chroni zapis co 5 s. Bez powiadomienia (jak `interrupt()` Androida).
    public func interrupt() async {
        guard let machine = recorder, let id = sessionId, !finishing else { return }
        await abort(machine, id, reason: "Przerwanie nagrywania")
    }

    /// Tik zegara: zgoda na lokalizację, bateria, słaby GPS, 8 h i zapis; migawka dostaje świeży stan.
    public func tick() async {
        guard let machine = recorder, let id = sessionId, !finishing else { return }
        let authorization = locations.authorization
        if authorization != .whenInUse {
            await abort(machine, id, reason: "Cofnięto zgodę na lokalizację (\(Self.describe(authorization)))", notify: true)
            return
        }
        let level = await battery.percent()
        // Po oczekiwaniu na baterię jazda mogła się zakończyć (aktor jest współbieżny na `await`).
        guard recorder === machine, !finishing else { return }
        if let level { lastBattery = level }
        if let still = stationarySample, sensorsRunning {
            // Bezruch: iOS nie dostarcza punktów — podajemy ostatni z bieżącym czasem (zob. `stationarySample`).
            let point = LocationSample(lat: still.lat, lon: still.lon, altM: still.altM, speedMs: 0, hAccM: still.hAccM, stationary: true)
            await handle(machine.onLocation(point.trackPoint(tMillis: clock())), machine)
            guard recorder === machine, !finishing else { return }
        }
        await handle(machine.tick(tMillis: clock(), batteryPercent: level), machine)
        if !finishing { await publish() }
    }

    // MARK: - Ponowne uruchomienie (A13)

    /// Wołane synchronicznie w `application(_:didFinishLaunchingWithOptions:)`, ZANIM skończy się uruchamianie: gdy w bazie jest sesja
    /// `.recording`/`.paused`, decyduje według `launch`:
    /// - wznowienie (`backgroundLocation`; `background` z jazdą wstrzymaną albo świeżym zapisem) — od razu odtwarza sesję aktywności w tle
    ///   (iOS uruchamia aplikację ponownie w tle po zamknięciu jej przez system i oczekuje tego natychmiast) i planuje `resumeAfterRelaunch()`;
    /// - w przeciwnym razie (`foreground`, nieświeży zapis) — bez lokalizacji: jazda dostaje `.interrupted` (punkty są już w bazie) i przy
    ///   starcie jest „Zapisz / Odrzuć”.
    /// Zwraca zaplanowane zadanie albo `nil`, gdy w bazie nie ma jazdy do wznowienia.
    @discardableResult
    public nonisolated func prepareRelaunch(launch: RideLaunchKind) -> Task<Void, Never>? {
        guard let active = store.activeSessionNow(), active.state == .recording || active.state == .paused else { return nil }
        let ageMillis = clock() - active.lastFlushMillis
        let resume: Bool
        switch launch {
        case .backgroundLocation: resume = true
        case .background: resume = active.state == .paused || ageMillis <= Self.relaunchFreshnessMillis
        case .foreground: resume = false
        }
        let task: Task<Void, Never>
        if resume {
            if locations.authorization == .whenInUse { locations.beginBackgroundActivity() }
            task = Task { await self.resumeAfterRelaunch() }
        } else {
            task = Task { await self.interruptStaleSession(active.id, launch: launch, ageMillis: ageMillis) }
        }
        pendingRelaunch.withLock { $0 = task }
        return task
    }

    /// Jazda, której system nie wznowił (przesunięcie albo nieudane wznowienie): `.interrupted` bez powiadomienia (użytkownik jest w aplikacji,
    /// odzyskanie pokaże „Zapisz / Odrzuć”), bez włączania lokalizacji. Live Activity z poprzedniego procesu znika z ekranu blokady.
    private func interruptStaleSession(_ id: String, launch: RideLaunchKind, ageMillis: Int64) async {
        guard recorder == nil, !relaunching else { return }
        await endActivity()
        let how = launch == .foreground ? "na pierwszym planie" : "w tle"
        do {
            try await store.setState(sessionId: id, state: .interrupted)
            log("Uruchomienie \(how) z niezakończoną jazdą (ostatni zapis \(max(0, ageMillis) / 1000) s temu) — jazda przerwana, bez wznowienia")
        } catch {
            log("Uruchomienie \(how): nie ustawiono stanu przerwania (\(Self.typeName(error)))")
        }
    }

    /// Wznowienie po ponownym uruchomieniu aplikacji (odpowiednik `START_STICKY` z A13). Niezakończona sesja `.recording` wraca do pracy:
    /// najpierw dostaje `.interrupted`, odtwarza się wstrzymana od ostatniego zapisu i od razu wznawia — czas, w którym aplikacja nie działała,
    /// jest pauzą. Sesja `.paused` zostaje wstrzymana (wybór użytkownika). Sesja `.interrupted` (także nieznany stan z bazy) i `.finished`
    /// nie są wznawiane — czekają na „Zapisz / Odrzuć”. Bez zgody na dokładną lokalizację: stan `.interrupted` i powiadomienie
    /// „Nagrywanie przerwane — otwórz aplikację, aby zapisać jazdę” (punkty zapisane wcześniej zostają w bazie).
    public func resumeAfterRelaunch() async {
        // Strażnik przed pierwszym `await`: drugie równoczesne wywołanie nie może zatrzymać GPS ani oznaczyć jako przerwanej jazdy wznowionej
        // przez pierwsze.
        guard recorder == nil, !relaunching else { return }
        relaunching = true
        defer { relaunching = false }
        let pending: UnfinishedRide?
        do {
            pending = try await store.unfinished()
        } catch {
            log("Ponowne uruchomienie: odczyt niezakończonej jazdy nie powiódł się (\(Self.typeName(error)))")
            locations.stop()
            await endActivity()
            return
        }
        guard let pending, pending.state == .recording || pending.state == .paused else {
            locations.stop()
            await endActivity()
            return
        }
        let authorization = locations.authorization
        guard authorization == .whenInUse else {
            log("Ponowne uruchomienie: brak zgody na dokładną lokalizację (\(Self.describe(authorization))) — jazda przerwana")
            locations.stop()
            await markInterrupted(pending.sessionId)
            return
        }
        let started: Bool
        do {
            started = try await begin(sessionId: pending.sessionId, afterRestart: true)
        } catch {
            log("Ponowne uruchomienie: wznowienie nie powiodło się (\(Self.typeName(error)))")
            started = false
        }
        if !started {
            locations.stop()
            await markInterrupted(pending.sessionId)
        }
    }

    // MARK: - Wnętrze

    /// Zaczyna nagrywanie sesji z bazy (Android: `begin`). Dla `afterRestart`: sesja `.recording` dostaje najpierw `.interrupted` i wraca
    /// wstrzymana od ostatniego zapisu, po czym od razu ją wznawiamy; `.paused` zostaje wstrzymana. `false`, gdy sesja jest zakończona albo
    /// nie da się uruchomić GPS (nic wtedy nie zostaje włączone); błędy bazy lecą do wywołującego.
    private func begin(sessionId id: String, afterRestart: Bool) async throws -> Bool {
        var loaded = try await store.load(sessionId: id)
        if loaded.session.state == .finished { return false }
        if afterRestart && loaded.session.state == .recording {
            try await store.setState(sessionId: id, state: .interrupted)
            loaded = try await store.load(sessionId: id)
        }
        guard recorder == nil else { return false }
        let machine = loaded.restoreRecorder()
        if afterRestart && loaded.session.state == .interrupted { machine.resume(tMillis: clock()) }
        recorder = machine
        sessionId = id
        finishing = false
        backlog = []
        window.clear()
        lastAccuracyM = nil
        stationarySample = nil
        locationRestarts = 0
        if machine.snapshot().state == .recording && !startSensors() {
            recorder = nil
            sessionId = nil
            return false
        }
        battery.start()
        status.withLock { $0 = Status(sessionId: id, running: true) }
        let initial = RideActivityState(machine.snapshot())
        activityState = initial
        await activity.start(horseName: loaded.session.horse.name, state: initial)
        if afterRestart {
            log(entry("Ponowne uruchomienie: wznowiono jazdę w stanie \(machine.snapshot().state.rawValue)", machine))
            await flush()
        } else {
            log(entry("Start nagrywania", machine))
        }
        await publish()
        startTicker()
        return true
    }

    private func onLocation(_ sample: LocationSample) async {
        // Licznik po obsłużeniu (także po zapisie, gdy był należny) — testy czekają na niego.
        defer { receivedLocations += 1 }
        guard let machine = recorder, !finishing else { return }
        lastAccuracyM = sample.hAccM
        stationarySample = sample.stationary ? sample : nil
        locationRestarts = 0
        // Punkt dostaje czas odbioru z tego samego zegara co tiki; rytm i intensywność dopisują okna akcelerometru (`onMotion`).
        await handle(machine.onLocation(sample.trackPoint(tMillis: clock())), machine)
    }

    private func onSample(_ sample: AccelSample) {
        receivedMotionSamples += 1
        guard let machine = recorder, !finishing, let samples = window.add(sample) else { return }
        machine.onMotion(tMillis: clock(), CadenceAnalyzer.analyze(samples))
    }

    private func handle(_ events: [RideEvent], _ machine: RideRecorder) async {
        for event in events {
            guard recorder === machine else { return }
            switch event {
            case .flushDue:
                await scheduleFlush()
            case .weakGpsStarted:
                log(entry("Słaby GPS", machine))
                await publish()
                await notifier.weakGps(started: true)
            case .weakGpsEnded:
                log(entry("Koniec słabego GPS", machine))
                await publish()
                await notifier.weakGps(started: false)
            case .batteryLow:
                let percent = lastBattery ?? 15
                log(entry("Bateria \(percent)%", machine))
                await notifier.batteryLow(percent: percent)
            case .autoFinished:
                await autoFinish(machine)
            }
        }
    }

    /// Po `.autoFinished` maszyna jest już w stanie `.finished`; obowiązkowy ostatni zapis punktów i stanu.
    private func autoFinish(_ machine: RideRecorder) async {
        guard !finishing, let id = sessionId else { return }
        finishing = true
        stopSensors(keepBackgroundActivity: false)
        await closeRide(machine, id)
        await notifier.autoFinished()
        log(entry("Koniec nagrywania po 8 godzinach", machine))
        await end(machine)
    }

    /// Przerwanie bez zakończenia jazdy: zatrzymanie źródeł, zapis bieżących punktów, stan `.interrupted`; sesja czeka na „Zapisz / Odrzuć”.
    private func abort(_ machine: RideRecorder, _ id: String, reason: String, notify: Bool = false) async {
        finishing = true
        stopSensors(keepBackgroundActivity: false)
        ticker?.cancel()
        ticker = nil
        await flushChain?.value
        do {
            try await writeBatch(machine, id)
        } catch {
            log("\(reason): zapis nie powiódł się (\(Self.typeName(error)))")
        }
        do {
            try await store.setState(sessionId: id, state: .interrupted)
        } catch {
            log("\(reason): nie ustawiono stanu przerwania (\(Self.typeName(error)))")
        }
        log(entry(reason, machine))
        var last = machine.snapshot()
        last.state = .interrupted
        snapshotContinuation.yield(last)
        release()
        await endActivity()
        if notify { await notifier.interrupted() }
    }

    /// Zapis kolejnych punktów; `.flushDue` powtarza się do czasu `drainUnsaved()`, więc pilnujemy jednego zapisu w kolejce.
    private func scheduleFlush() async {
        if flushQueued { return }
        flushQueued = true
        await flush()
    }

    /// Zapis w łańcuchu: kolejny zaczyna się dopiero po poprzednim, więc zaległe punkty nie mieszają się między zapisami.
    private func flush() async {
        let previous = flushChain
        let task = Task {
            await previous?.value
            await self.performFlush()
        }
        flushChain = task
        await task.value
    }

    private func performFlush() async {
        flushQueued = false
        guard !finishing, let machine = recorder, let id = sessionId else { return }
        do {
            try await writeBatch(machine, id)
        } catch {
            logFailure("Zapis jazdy nie powiódł się (\(Self.typeName(error))) — ponowię przy następnym zapisie")
        }
    }

    /// Oddaje punkty maszyny i zapisuje je wraz ze stanem i pauzami; przy błędzie punkty zostają w `backlog` do następnej próby (ta sama partia).
    private func writeBatch(_ machine: RideRecorder, _ id: String) async throws {
        backlog += machine.drainUnsaved()
        let toWrite = backlog
        try await store.flush(sessionId: id, points: toWrite, snapshot: machine.snapshot(), pauses: machine.pauses())
        backlog.removeFirst(min(toWrite.count, backlog.count))
    }

    /// Ostatni zapis zakończonej jazdy i oznaczenie `.finished` (zapis ustawia też chwilę końca). Nieudany zapis jest ponawiany raz (ta sama
    /// partia z zaległymi punktami); gdy dalej się nie da — stan `.interrupted`, żeby przy starcie było „Zapisz / Odrzuć” z tym, co już jest
    /// w bazie, a nie wznowienie GPS dla jazdy zakończonej przez użytkownika.
    private func closeRide(_ machine: RideRecorder, _ id: String) async {
        await flushChain?.value
        var saved = false
        for attempt in 1...2 where !saved {
            do {
                try await writeBatch(machine, id)
                saved = true
            } catch {
                log("Zakończenie jazdy: zapis nie powiódł się (\(Self.typeName(error)), próba \(attempt) z 2)")
            }
        }
        if saved {
            do {
                try await store.setState(sessionId: id, state: .finished)
                return
            } catch {
                log("Zakończenie jazdy: nie ustawiono stanu zakończenia (\(Self.typeName(error)))")
            }
        }
        do {
            try await store.setState(sessionId: id, state: .interrupted)
            log("Zakończenie jazdy: jazda oznaczona jako przerwana — do odzyskania przy starcie aplikacji (niezapisane punkty: \(backlog.count))")
        } catch {
            log("Zakończenie jazdy: nie ustawiono stanu przerwania (\(Self.typeName(error)))")
        }
    }

    /// Nie udało się zacząć/wznowić albo brak zgody po ponownym uruchomieniu: jazda zostaje do odzyskania, użytkownik dostaje powiadomienie;
    /// Live Activity (także z poprzedniego procesu) znika.
    private func markInterrupted(_ id: String) async {
        await endActivity()
        do {
            let state = try await store.load(sessionId: id).session.state
            if state == .finished { return }
            try await store.setState(sessionId: id, state: .interrupted)
            log("Jazda oznaczona jako przerwana")
            await notifier.interrupted()
        } catch {
            log("Nie ustawiono stanu przerwania (\(Self.typeName(error)))")
        }
    }

    private func end(_ machine: RideRecorder) async {
        var last = machine.snapshot()
        last.state = .finished
        snapshotContinuation.yield(last)
        release()
        await endActivity()
    }

    /// Zdejmuje Live Activity jazdy.
    private func endActivity() async {
        activityState = nil
        await activity.end()
    }

    private func release() {
        ticker?.cancel()
        ticker = nil
        battery.stop()
        recorder = nil
        sessionId = nil
        backlog = []
        status.withLock { $0 = Status() }
    }

    private func startTicker() {
        ticker?.cancel()
        guard let interval = tickInterval else { return }
        ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self.tick()
            }
        }
    }

    private func startSensors() -> Bool {
        if sensorsRunning { return true }
        guard locations.authorization == .whenInUse else { return false }
        startLocationUpdates()
        // Brak akcelerometru nie przerywa jazdy — tylko bez rytmu (strumień kończy się od razu).
        let samples = motion.samples()
        motionTask = Task {
            for await sample in samples { self.onSample(sample) }
        }
        sensorsRunning = true
        return true
    }

    /// Nowy strumień lokalizacji; jego nieoczekiwany koniec (błąd systemu) obsługuje `locationStreamEnded`.
    private func startLocationUpdates() {
        locationGeneration += 1
        let generation = locationGeneration
        let points = locations.updates()
        locationTask = Task {
            for await sample in points { await self.onLocation(sample) }
            if Task.isCancelled { return }
            await self.locationStreamEnded(generation)
        }
    }

    /// Strumień lokalizacji skończył się sam (nie przez `stopSensors`): wpis w dzienniku (tylko nazwa typu błędu), ponowne uruchomienie
    /// odbioru, a po `maxLocationRestarts` próbach bez punktu albo bez zgody — przerwanie jazdy (`.interrupted`, powiadomienie).
    private func locationStreamEnded(_ generation: Int) async {
        guard generation == locationGeneration, sensorsRunning, let machine = recorder, let id = sessionId, !finishing else { return }
        let cause = locations.lastStreamError ?? "bez błędu"
        locationTask = nil
        locationRestarts += 1
        if locationRestarts <= Self.maxLocationRestarts && locations.authorization == .whenInUse {
            log(entry("Odbiór GPS zakończył się (\(cause)) — ponowne uruchomienie \(locationRestarts) z \(Self.maxLocationRestarts)", machine))
            startLocationUpdates()
        } else {
            await abort(machine, id, reason: "Odbiór GPS zakończył się (\(cause)) — nagrywanie przerwane", notify: true)
        }
    }

    private func stopSensors(keepBackgroundActivity: Bool) {
        locationGeneration += 1
        stationarySample = nil
        locationTask?.cancel()
        locationTask = nil
        motionTask?.cancel()
        motionTask = nil
        if keepBackgroundActivity { locations.stopUpdates() } else { locations.stop() }
        motion.stop()
        window.clear()
        sensorsRunning = false
    }

    /// Migawka do strumienia i — gdy zmieniła się widoczna treść — aktualizacja Live Activity.
    private func publish() async {
        guard let machine = recorder else { return }
        let snapshot = machine.snapshot()
        snapshotContinuation.yield(snapshot)
        let state = RideActivityState(snapshot)
        guard let last = activityState, !last.sameDisplay(as: state) else { return }
        activityState = state
        await activity.update(state)
    }

    /// Wpis dziennika: zdarzenie, czas jazdy, liczba punktów i ostatnia dokładność — bez współrzędnych i nazwy konia.
    private func entry(_ what: String, _ machine: RideRecorder) -> String {
        let accuracy: String
        if let value = lastAccuracyM, value.isFinite, value >= 0, value < 1_000_000 {
            accuracy = "\(Int(value.rounded())) m"
        } else {
            accuracy = "brak"
        }
        return "\(what) — czas jazdy \(machine.snapshot().activeSeconds) s, punkty \(machine.pointCount), dokładność \(accuracy)"
    }

    /// Powtarzający się błąd (co kilka sekund) nie zalewa dziennika: pierwsze kilka wpisów wystarcza do diagnozy.
    private func logFailure(_ message: String) {
        guard failuresLogged < Self.maxFailuresLogged else { return }
        failuresLogged += 1
        log(message)
    }

    private static func typeName(_ error: any Error) -> String {
        String(describing: type(of: error))
    }

    private static func describe(_ authorization: LocationAuthorization) -> String {
        switch authorization {
        case .notDetermined: "brak decyzji"
        case .denied: "odmowa"
        case .reducedAccuracy: "przybliżona"
        case .whenInUse: "podczas używania"
        }
    }
}

// MARK: - Przyciski Live Activity

/// „Pauza”, „Wznów” i „Zakończ” z Live Activity (`RideActivityActions`, Task 16). Gdy przycisk uruchomił aplikację w tle, akcja czeka na
/// zaplanowane wznowienie jazdy (`prepareRelaunch`).
extension RideRecordingController: RideActivityActionHandler {
    public func pauseRide() async {
        await awaitPendingRelaunch()
        await pause()
    }

    public func resumeRide() async {
        await awaitPendingRelaunch()
        await resume()
    }

    public func finishRide() async -> String? {
        await awaitPendingRelaunch()
        return await finish()
    }

    private func awaitPendingRelaunch() async {
        let pending = pendingRelaunch.withLock { $0 }
        await pending?.value
    }
}
