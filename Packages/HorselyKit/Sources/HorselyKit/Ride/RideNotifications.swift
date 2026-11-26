import Foundation
import HorselyCore
import UserNotifications

// Treści nagrywania jazdy (port `RideNotification.kt` z Androida 3.0.2): tekst bieżącego stanu „Grom · 24 min · 3,2 km · kłus” (na iOS dla
// Live Activity, Task 16) oraz ostrzeżenia jako powiadomienia lokalne ([ZAK] 6: bateria 15 %, koniec po 8 h, słaby GPS, przerwane
// nagranie). Bez współrzędnych — powiadomienie widać na ekranie blokady (konstytucja 3.0.0).

/// Szablony tekstów ze `strings.xml` Androida (klucze `ride_*` w `Localizable.xcstrings`, format po `scripts/sync-strings.ps1`: `%1$@`,
/// `%1$lld`). Pakiet nie ma własnego katalogu tekstów — aplikacja podaje je z katalogu (`RideNotificationTexts.app` w celu Horsely),
/// testy pakietu — te same teksty przepisane ze `strings.xml`.
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

/// Teksty z szablonów (czysta logika, jak `RideNotification.contentText` w Androidzie).
public enum RideNotificationContent {
    private static let separator = " · "
    private static let polish = Locale(identifier: "pl_PL")

    /// Koń · czas aktywny · dystans · chód albo „Słaby sygnał GPS”/„pauza” (bez prędkości — bez ostatniego członu).
    public static func contentText(horseName: String, snapshot: RideSnapshot, texts: RideNotificationTexts) -> String {
        var parts = [horseName, duration(snapshot.activeSeconds, texts), distance(snapshot.distanceMeters, texts)]
        if snapshot.state == .paused {
            parts.append(texts.paused)
        } else if snapshot.weakGps {
            parts.append(texts.weakGps)
        } else if let gait = snapshot.gait {
            parts.append(gaitName(gait, texts))
        }
        return parts.joined(separator: separator)
    }

    /// „Bateria 15% — …” z ostatnim odczytem baterii.
    public static func batteryLow(percent: Int, texts: RideNotificationTexts) -> String {
        String(format: texts.batteryLow, locale: polish, Int64(percent))
    }

    /// `%d min` do godziny, potem `%d h %02d min` (minuty pełne, jak w Androidzie).
    static func duration(_ activeSeconds: Int, _ texts: RideNotificationTexts) -> String {
        let minutes = Int64(max(0, activeSeconds) / 60)
        if minutes < 60 { return String(format: texts.durationMinutes, locale: polish, minutes) }
        return String(format: texts.durationHoursMinutes, locale: polish, minutes / 60, minutes % 60)
    }

    /// Kilometry z jedną cyfrą po przecinku. Android: `String.format(pl-PL, "%.1f", m / 1000.0)` — Java zaokrągla zapis dziesiętny
    /// „połówką w górę” (3 250 m → 3,3), a `printf` w C zaokrąglałby połówkę do parzystej (3,2). Dla całych metrów zapis m / 1000 jest
    /// dokładny, więc liczymy w liczbach całkowitych: dziesiąte części km = (m + 50) / 100.
    static func distance(_ meters: Int, _ texts: RideNotificationTexts) -> String {
        let tenths = (max(0, meters) + 50) / 100
        let value = "\(tenths / 10),\(tenths % 10)"
        return String(format: texts.distanceKm, locale: polish, value as NSString)
    }

    static func gaitName(_ gait: Gait, _ texts: RideNotificationTexts) -> String {
        switch gait {
        case .stop: texts.gaitStop
        case .walk: texts.gaitWalk
        case .trot: texts.gaitTrot
        case .canter: texts.gaitCanter
        }
    }
}

/// Ostrzeżenie nagrywania jako powiadomienie lokalne (do pokazania od razu).
public struct RideAlert: Sendable, Hashable {
    /// Identyfikatory powiadomień (stałe, więc kolejne ostrzeżenie tego samego rodzaju zastępuje poprzednie).
    public enum Kind: String, Sendable, CaseIterable {
        case batteryLow = "ride-battery-low"
        case autoFinished = "ride-auto-finished"
        case interrupted = "ride-interrupted"
        case weakGps = "ride-weak-gps"
    }

    public let kind: Kind
    public let title: String
    public let body: String

    public init(kind: Kind, title: String, body: String) {
        self.kind = kind
        self.title = title
        self.body = body
    }
}

/// Skutki nagrywania widoczne dla użytkownika (Android: `RideRecordingController.Listener` + `RideNotification`). Wołane z aktora
/// kontrolera; implementacja nie może blokować.
public protocol RideNotifier: Sendable {
    func batteryLow(percent: Int) async
    func autoFinished() async
    func interrupted() async
    func weakGps(started: Bool) async
    /// Zdejmuje „Nagrywanie przerwane” (po zapisaniu albo odrzuceniu jazdy — Task 17).
    func clearInterrupted() async
}

/// Wysyłka powiadomień lokalnych (w testach zaślepka).
public protocol RideAlertPoster: Sendable {
    func post(_ alert: RideAlert) async
    func remove(_ kind: RideAlert.Kind) async
}

/// Powiadomienia lokalne nagrywania: treści z `RideNotificationTexts`, wysyłka przez `RideAlertPoster`.
public struct LocalRideNotifier: RideNotifier {
    private let texts: RideNotificationTexts
    private let poster: any RideAlertPoster

    public init(texts: RideNotificationTexts, poster: any RideAlertPoster = SystemRideAlertPoster()) {
        self.texts = texts
        self.poster = poster
    }

    public func batteryLow(percent: Int) async {
        await poster.post(RideAlert(kind: .batteryLow, title: texts.title, body: RideNotificationContent.batteryLow(percent: percent, texts: texts)))
    }

    public func autoFinished() async {
        await poster.post(RideAlert(kind: .autoFinished, title: texts.title, body: texts.autoFinished))
    }

    public func interrupted() async {
        await poster.post(RideAlert(kind: .interrupted, title: texts.title, body: texts.interrupted))
    }

    public func weakGps(started: Bool) async {
        if started {
            await poster.post(RideAlert(kind: .weakGps, title: texts.title, body: texts.weakGps))
        } else {
            await poster.remove(.weakGps)
        }
    }

    public func clearInterrupted() async {
        await poster.remove(.interrupted)
    }
}

/// `UNUserNotificationCenter`: powiadomienie bez wyzwalacza (od razu); bez zgody na powiadomienia system je pomija (jak
/// `areNotificationsEnabled()` w Androidzie).
public struct SystemRideAlertPoster: RideAlertPoster {
    public init() {}

    public func post(_ alert: RideAlert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = "ride"
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alert.kind.rawValue, content: content, trigger: nil))
    }

    public func remove(_ kind: RideAlert.Kind) async {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [kind.rawValue])
        center.removePendingNotificationRequests(withIdentifiers: [kind.rawValue])
    }
}
