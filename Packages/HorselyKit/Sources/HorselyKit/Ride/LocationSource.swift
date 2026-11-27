import CoreLocation
import Foundation
import HorselyCore

// Źródło lokalizacji nagrywania jazdy (Task 15, odpowiednik `AndroidLocationSource.kt` z Androida 3.0.2). Lokalizacja tylko w czasie
// nagrywania uruchomionego przez użytkownika (zasada II konstytucji 3.0.0), uprawnienie wyłącznie „Podczas używania” — nigdy „Zawsze”.
// Współrzędne nie trafiają do dziennika diagnostycznego: to źródło niczego nie zapisuje w dzienniku.

/// Punkt z GPS bez czasu (Android: `GpsFix`): czas odbioru nadaje kontroler nagrywania jednym zegarem dla punktów i tików, a maszyna
/// nagrywania bierze największy widziany czas. Kontroler zamienia go na `TrackPoint` (rytm i intensywność dopisują okna akcelerometru).
public struct LocationSample: Sendable, Hashable {
    public let lat: Double
    public let lon: Double
    public let altM: Double?
    public let speedMs: Double?
    public let hAccM: Double?

    /// Core Location zgłosił bezruch (`CLLocationUpdate.stationary`) — kolejne punkty mogą nie przychodzić, dopóki urządzenie się nie ruszy.
    public let stationary: Bool

    public init(lat: Double, lon: Double, altM: Double?, speedMs: Double?, hAccM: Double?, stationary: Bool = false) {
        self.lat = lat
        self.lon = lon
        self.altM = altM
        self.speedMs = speedMs
        self.hAccM = hAccM
        self.stationary = stationary
    }

    /// Punkt z `CLLocation`: wartości ujemne (Core Location oznacza tak wartość nieznaną) dają `nil` — jak `hasAltitude()`/`hasSpeed()`
    /// na Androidzie. Ujemna dokładność pozioma oznacza nieważne współrzędne, więc taki punkt (i punkt z nieważnymi współrzędnymi) to `nil`.
    public init?(_ location: CLLocation, stationary: Bool = false) {
        guard location.horizontalAccuracy >= 0, CLLocationCoordinate2DIsValid(location.coordinate) else { return nil }
        self.lat = location.coordinate.latitude
        self.lon = location.coordinate.longitude
        self.altM = location.verticalAccuracy >= 0 ? location.altitude : nil
        self.speedMs = location.speed >= 0 ? location.speed : nil
        self.hAccM = location.horizontalAccuracy
        self.stationary = stationary
    }

    /// Punkt trasy z czasem odbioru `tMillis` (epoka, ms), bez danych ruchu.
    public func trackPoint(tMillis: Int64) -> TrackPoint {
        TrackPoint(tMillis: tMillis, lat: lat, lon: lon, altM: altM, speedMs: speedMs, hAccM: hAccM, cadence: nil, intensity: nil)
    }
}

/// Zgoda na lokalizację z punktu widzenia nagrywania: nagrywać wolno tylko przy `.whenInUse` (dokładna lokalizacja „Podczas używania”);
/// `.reducedAccuracy` — zgoda jest, ale tylko przybliżona (nagrywanie zablokowane z wyjaśnieniem, [ZAK] 6 i kryterium 10.4).
public enum LocationAuthorization: Sendable, Hashable {
    case notDetermined
    case denied
    case reducedAccuracy
    case whenInUse
}

/// Źródło punktów GPS; w testach zaślepka. Kontrakt:
/// - `updates()` zaczyna odbiór (poprzedni strumień kończy, sesję aktywności w tle zakłada, gdy jej nie ma) i zwraca strumień punktów;
/// - `stopUpdates()` kończy tylko odbiór punktów — sesja aktywności w tle zostaje (pauza: „Wznów” z ekranu blokady musi móc
///   ponownie uruchomić lokalizację w tle);
/// - `stop()` kończy odbiór i zwalnia sesje w tle (bezpieczne bez wcześniejszego startu);
/// - `authorization` to bieżąca zgoda — kontroler sprawdza ją przed startem i przy każdym tiku (cofnięcie zgody w trakcie jazdy, najpóźniej
///   po 1 s); źródło systemowe uwzględnia w niej też flagi odmowy i przybliżonej lokalizacji z `CLLocationUpdate`;
/// - strumień `updates()` może skończyć się sam (błąd systemu) — wtedy `lastStreamError` to nazwa typu błędu (bez danych), a kontroler
///   ponawia odbiór;
/// - `beginBackgroundActivity()` — tylko ponowne uruchomienie aplikacji przez system w tle: sesję aktywności w tle trzeba odtworzyć
///   synchronicznie, zanim skończy się uruchamianie aplikacji (zob. `RideRecordingController.prepareRelaunch()`).
public protocol LocationSource: Sendable {
    var authorization: LocationAuthorization { get }
    var lastStreamError: String? { get }
    func updates() -> AsyncStream<LocationSample>
    func stopUpdates()
    func stop()
    func beginBackgroundActivity()
}

#if os(iOS)
/// Systemowe źródło lokalizacji ([ZAK] 5.2): strumień `CLLocationUpdate.liveUpdates(.fitness)`, `CLBackgroundActivitySession` trzymana przez
/// cały czas nagrywania (bez niej iOS nie dostarcza punktów w tle przy uprawnieniu „Podczas używania” i nie uruchamia aplikacji ponownie
/// po zamknięciu jej przez system) oraz `CLServiceSession(authorization: .whenInUse)`.
///
/// Bez `fullAccuracyPurposeKey`: prośba o tymczasową dokładną lokalizację wymaga klucza `NSLocationTemporaryUsageDescriptionDictionary`,
/// którego nie ma w zgodach z Global Constraints; przybliżona lokalizacja blokuje start z wyjaśnieniem (kontroler).
public final class SystemLocationSource: LocationSource, @unchecked Sendable {
    private let lock = NSLock()
    private let manager = CLLocationManager()
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<LocationSample>.Continuation?
    private var background: CLBackgroundActivitySession?
    private var service: CLServiceSession?
    private var streamError: String?

    /// Zgoda wynikająca z flag ostatniej aktualizacji (`authorizationDenied…` → `.denied`, `accuracyLimited` → `.reducedAccuracy`); `nil`, gdy
    /// ostatnia aktualizacja nie zgłaszała problemu. Kontroler przy tiku traktuje ją jak cofnięcie zgody.
    private var updateAuthorization: LocationAuthorization?

    public init() {}

    public var authorization: LocationAuthorization {
        let (status, accuracy, fromUpdate) = lock.withLock { (manager.authorizationStatus, manager.accuracyAuthorization, updateAuthorization) }
        let system = Self.authorization(status: status, accuracy: accuracy)
        guard system == .whenInUse, let fromUpdate else { return system }
        return fromUpdate
    }

    public var lastStreamError: String? { lock.withLock { streamError } }

    /// Zgoda z `CLAuthorizationStatus` i `CLAccuracyAuthorization`: „Zawsze” aplikacja nigdy nie prosi, ale gdyby ją miała — traktuje jak
    /// „Podczas używania”.
    public static func authorization(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) -> LocationAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways:
            return accuracy == .fullAccuracy ? .whenInUse : .reducedAccuracy
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    /// Flagi diagnostyczne iOS 18: odmowa (także globalna i ograniczenie) i przybliżona lokalizacja.
    private func noteFlags(_ update: CLLocationUpdate) {
        let flagged: LocationAuthorization?
        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
            flagged = .denied
        } else if update.accuracyLimited {
            flagged = .reducedAccuracy
        } else {
            flagged = nil
        }
        lock.withLock { updateAuthorization = flagged }
    }

    public func beginBackgroundActivity() {
        lock.withLock {
            if background == nil { background = CLBackgroundActivitySession() }
            if service == nil { service = CLServiceSession(authorization: .whenInUse) }
        }
    }

    public func updates() -> AsyncStream<LocationSample> {
        stopUpdates()
        beginBackgroundActivity()
        let (stream, continuation) = AsyncStream<LocationSample>.makeStream(bufferingPolicy: .bufferingNewest(120))
        lock.withLock {
            streamError = nil
            updateAuthorization = nil
        }
        let task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    if Task.isCancelled { break }
                    self?.noteFlags(update)
                    if let location = update.location, let sample = LocationSample(location, stationary: update.stationary) {
                        continuation.yield(sample)
                    }
                }
            } catch {
                // Kontroler zobaczy koniec strumienia, zapisze nazwę typu błędu w dzienniku i ponowi odbiór.
                self?.lock.withLock { self?.streamError = String(describing: type(of: error)) }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        lock.withLock {
            self.task = task
            self.continuation = continuation
        }
        return stream
    }

    public func stop() {
        stopUpdates()
        let (background, service) = lock.withLock { () -> (CLBackgroundActivitySession?, CLServiceSession?) in
            defer {
                self.background = nil
                self.service = nil
            }
            return (self.background, self.service)
        }
        background?.invalidate()
        service?.invalidate()
    }

    public func stopUpdates() {
        let (task, continuation) = lock.withLock { () -> (Task<Void, Never>?, AsyncStream<LocationSample>.Continuation?) in
            defer {
                self.task = nil
                self.continuation = nil
            }
            return (self.task, self.continuation)
        }
        task?.cancel()
        continuation?.finish()
    }
}

/// Prośba o zgodę na lokalizację „Podczas używania” przed startem nagrywania (Task 17, NAG-04): pytanie systemu pada dopiero na kroku
/// „Dokładna lokalizacja” ekranu startu, po dotknięciu „Zezwól” — nigdy poza nagrywaniem i nigdy o „Zawsze”. Wynik w tym samym kształcie
/// co `SystemLocationSource.authorization` (przybliżona lokalizacja = `.reducedAccuracy`, start zablokowany z wyjaśnieniem).
@MainActor
public final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<LocationAuthorization, Never>] = []

    override public init() {
        super.init()
        manager.delegate = self
    }

    /// Bieżąca zgoda (bez pytania).
    public var current: LocationAuthorization {
        SystemLocationSource.authorization(status: manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
    }

    /// Pyta system, gdy zgoda nie jest jeszcze ustalona, i czeka na odpowiedź; inaczej od razu zwraca bieżącą zgodę (ponownego pytania
    /// system i tak nie pokazuje — po odmowie zostają ustawienia).
    public func request() async -> LocationAuthorization {
        guard manager.authorizationStatus == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor in self.answered(status: status, accuracy: accuracy) }
    }

    private func answered(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
        // Pierwsze wywołanie delegata (zaraz po utworzeniu menedżera) zgłasza stan nieustalony — to jeszcze nie odpowiedź.
        guard status != .notDetermined, !waiting.isEmpty else { return }
        let result = SystemLocationSource.authorization(status: status, accuracy: accuracy)
        let resumed = waiting
        waiting = []
        for continuation in resumed { continuation.resume(returning: result) }
    }
}
#endif
