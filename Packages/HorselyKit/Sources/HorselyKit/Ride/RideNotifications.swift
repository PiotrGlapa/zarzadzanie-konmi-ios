import Foundation
import HorselyCore
import UserNotifications

// Ostrzeżenia nagrywania jazdy (port `RideNotification.kt` z Androida 3.0.2) jako powiadomienia lokalne ([ZAK] 6: bateria 15 %, koniec
// po 8 h, słaby GPS, przerwane nagranie). Teksty i treść bieżącego stanu („Grom · 24 min · 3,2 km · kłus”, Live Activity — Task 16) są
// w rdzeniu (`HorselyCore/Ride/RideStatusText.swift`). Bez współrzędnych — powiadomienie widać na ekranie blokady (konstytucja 3.0.0).

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
