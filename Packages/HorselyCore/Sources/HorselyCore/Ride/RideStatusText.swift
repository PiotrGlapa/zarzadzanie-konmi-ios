import Foundation

// Treść bieżącego stanu nagrywania (port `RideNotification.contentText` z Androida 3.0.2): „Grom · 24 min · 3,2 km · kłus”. Na iOS pokazuje ją
// Live Activity (Task 16) — ekran blokady i Dynamic Island — a ostrzeżenia idą jako powiadomienia lokalne (HorselyKit). Czysta logika
// w rdzeniu, żeby rozszerzenie widżetów (`HorselyRideActivity`) i aplikacja formatowały tym samym kodem. Bez współrzędnych — treść widać na
// ekranie blokady (konstytucja 3.0.0).

/// Szablony tekstów ze `strings.xml` Androida (klucze `ride_*` w `Localizable.xcstrings`, format po `scripts/sync-strings.ps1`: `%1$@`,
/// `%1$lld`). Rdzeń nie ma katalogu tekstów — aplikacja i rozszerzenie podają je z katalogu (`RideNotificationTexts.app` w `Shared/`),
/// testy pakietów — te same teksty przepisane ze `strings.xml`.
public struct RideNotificationTexts: Sendable, Hashable {
    /// `ride_notification_title` — „Nagrywanie jazdy”.
    public var title: String
    /// `ride_notification_weak_gps` — „Słaby sygnał GPS”.
    public var weakGps: String
    /// `ride_notification_paused` — „pauza”.
    public var paused: String
    /// `ride_gait_stop`, `ride_gait_walk`, `ride_gait_trot`, `ride_gait_canter`.
    public var gaitStop: String
    public var gaitWalk: String
    public var gaitTrot: String
    public var gaitCanter: String
    /// `ride_duration_minutes` — „%1$lld min”.
    public var durationMinutes: String
    /// `ride_duration_hours_minutes` — „%1$lld h %2$02lld min”.
    public var durationHoursMinutes: String
    /// `ride_distance_km` — „%1$@ km”.
    public var distanceKm: String
    /// `ride_battery_low` — „Bateria %1$lld%% — nagrywanie trwa, podłącz telefon albo zakończ jazdę.”.
    public var batteryLow: String
    /// `ride_auto_finished` — „Nagrywanie zakończone po 8 godzinach.”.
    public var autoFinished: String
    /// `ride_interrupted` — „Nagrywanie przerwane — otwórz aplikację, aby zapisać jazdę”.
    public var interrupted: String

    public init(
        title: String, weakGps: String, paused: String, gaitStop: String, gaitWalk: String, gaitTrot: String, gaitCanter: String,
        durationMinutes: String, durationHoursMinutes: String, distanceKm: String, batteryLow: String, autoFinished: String, interrupted: String
    ) {
        self.title = title
        self.weakGps = weakGps
        self.paused = paused
        self.gaitStop = gaitStop
        self.gaitWalk = gaitWalk
        self.gaitTrot = gaitTrot
        self.gaitCanter = gaitCanter
        self.durationMinutes = durationMinutes
        self.durationHoursMinutes = durationHoursMinutes
        self.distanceKm = distanceKm
        self.batteryLow = batteryLow
        self.autoFinished = autoFinished
        self.interrupted = interrupted
    }
}

/// Stan jazdy pokazywany na żywo (Live Activity): czas aktywny, dystans, chód, słaby GPS i pauza — bez współrzędnych i bez nazwy konia
/// (ta jest stałym atrybutem aktywności). Aplikacja przekłada go na `RideActivityAttributes.ContentState` (`Shared/`).
public struct RideActivityState: Sendable, Hashable, Codable {
    public var activeSeconds: Int
    public var distanceMeters: Int
    public var gait: Gait?
    public var weakGps: Bool
    public var paused: Bool

    public init(activeSeconds: Int, distanceMeters: Int, gait: Gait?, weakGps: Bool, paused: Bool) {
        self.activeSeconds = activeSeconds
        self.distanceMeters = distanceMeters
        self.gait = gait
        self.weakGps = weakGps
        self.paused = paused
    }

    public init(_ snapshot: RideSnapshot) {
        self.init(
            activeSeconds: snapshot.activeSeconds, distanceMeters: snapshot.distanceMeters, gait: snapshot.gait, weakGps: snapshot.weakGps,
            paused: snapshot.state == .paused
        )
    }

    /// Czy treść na ekranie byłaby taka sama (pełne minuty, dziesiąte części kilometra, ostatni człon) — kontroler nie wysyła wtedy
    /// aktualizacji Live Activity (tik co sekundę nie zmienia napisu „24 min”).
    public func sameDisplay(as other: RideActivityState) -> Bool {
        Self.minutes(activeSeconds) == Self.minutes(other.activeSeconds)
            && Self.tenthsOfKm(distanceMeters) == Self.tenthsOfKm(other.distanceMeters)
            && status == other.status
    }

    /// Ostatni człon treści: pauza, słaby GPS albo chód (w tej kolejności, jak w Androidzie).
    var status: RideStatusPart? {
        if paused { return .paused }
        if weakGps { return .weakGps }
        return gait.map(RideStatusPart.gait)
    }

    static func minutes(_ activeSeconds: Int) -> Int { max(0, activeSeconds) / 60 }

    /// Dziesiąte części km zaokrąglone „połówką w górę” (zob. `RideNotificationContent.distance`).
    static func tenthsOfKm(_ meters: Int) -> Int { (max(0, meters) + 50) / 100 }
}

/// Ostatni człon treści stanu jazdy.
enum RideStatusPart: Hashable {
    case paused
    case weakGps
    case gait(Gait)
}

/// Teksty z szablonów (czysta logika, jak `RideNotification.contentText` w Androidzie).
public enum RideNotificationContent {
    private static let separator = " · "
    private static let polish = Locale(identifier: "pl_PL")

    /// Koń · czas aktywny · dystans · chód albo „Słaby sygnał GPS”/„pauza” (bez prędkości — bez ostatniego członu).
    public static func contentText(horseName: String, snapshot: RideSnapshot, texts: RideNotificationTexts) -> String {
        contentText(horseName: horseName, state: RideActivityState(snapshot), texts: texts)
    }

    /// To samo dla stanu Live Activity.
    public static func contentText(horseName: String, state: RideActivityState, texts: RideNotificationTexts) -> String {
        var parts = [horseName, duration(state.activeSeconds, texts), distance(state.distanceMeters, texts)]
        if let status = status(state, texts) { parts.append(status) }
        return parts.joined(separator: separator)
    }

    /// Dystans i ostatni człon bez konia i czasu („3,2 km · kłus”) — rozwinięta Dynamic Island pokazuje czas osobno.
    public static func distanceAndStatus(state: RideActivityState, texts: RideNotificationTexts) -> String {
        var parts = [distance(state.distanceMeters, texts)]
        if let status = status(state, texts) { parts.append(status) }
        return parts.joined(separator: separator)
    }

    /// Ostatni człon: „pauza”, „Słaby sygnał GPS”, nazwa chodu albo `nil` (bez prędkości).
    public static func status(_ state: RideActivityState, _ texts: RideNotificationTexts) -> String? {
        switch state.status {
        case .paused: texts.paused
        case .weakGps: texts.weakGps
        case let .gait(gait): gaitName(gait, texts)
        case nil: nil
        }
    }

    /// „Bateria 15% — …” z ostatnim odczytem baterii.
    public static func batteryLow(percent: Int, texts: RideNotificationTexts) -> String {
        String(format: texts.batteryLow, locale: polish, Int64(percent))
    }

    /// `%d min` do godziny, potem `%d h %02d min` (minuty pełne, jak w Androidzie).
    public static func duration(_ activeSeconds: Int, _ texts: RideNotificationTexts) -> String {
        let minutes = Int64(RideActivityState.minutes(activeSeconds))
        if minutes < 60 { return String(format: texts.durationMinutes, locale: polish, minutes) }
        return String(format: texts.durationHoursMinutes, locale: polish, minutes / 60, minutes % 60)
    }

    /// Kilometry z jedną cyfrą po przecinku. Android: `String.format(pl-PL, "%.1f", m / 1000.0)` — Java zaokrągla zapis dziesiętny
    /// „połówką w górę” (3 250 m → 3,3), a `printf` w C zaokrąglałby połówkę do parzystej (3,2). Dla całych metrów zapis m / 1000 jest
    /// dokładny, więc liczymy w liczbach całkowitych: dziesiąte części km = (m + 50) / 100.
    public static func distance(_ meters: Int, _ texts: RideNotificationTexts) -> String {
        let tenths = RideActivityState.tenthsOfKm(meters)
        let value = "\(tenths / 10),\(tenths % 10)"
        return String(format: texts.distanceKm, locale: polish, value as NSString)
    }

    public static func gaitName(_ gait: Gait, _ texts: RideNotificationTexts) -> String {
        switch gait {
        case .stop: texts.gaitStop
        case .walk: texts.gaitWalk
        case .trot: texts.gaitTrot
        case .canter: texts.gaitCanter
        }
    }
}
