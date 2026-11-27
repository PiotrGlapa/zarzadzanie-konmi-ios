import ActivityKit
import Foundation
import HorselyCore

// Wspólne dla aplikacji (`Horsely`) i rozszerzenia widżetów (`HorselyRideActivity`) — Task 16, FR-NAG-05, SPECYFIKACJA_MOBILE_IOS.md 9.5.

/// Live Activity nagrywanej jazdy. Atrybut stały: nazwa konia (widoczna na ekranie blokady własnego telefonu — nigdy w dzienniku);
/// stan: czas aktywny, dystans, chód, słaby GPS i pauza. **Bez współrzędnych** (konstytucja 3.0.0).
struct RideActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var activeSeconds: Int
        var distanceMeters: Int
        /// Surowa wartość `Gait` („Stop”, „Walk”, „Trot”, „Canter”) albo `nil` (bez prędkości).
        var gait: String?
        var weakGps: Bool
        var paused: Bool
    }

    var horseName: String
}

extension RideActivityAttributes.ContentState {
    init(_ state: RideActivityState) {
        self.init(
            activeSeconds: state.activeSeconds, distanceMeters: state.distanceMeters, gait: state.gait?.rawValue, weakGps: state.weakGps,
            paused: state.paused
        )
    }

    /// Stan dla formatera z rdzenia (nieznana wartość chodu — bez chodu).
    var rideState: RideActivityState {
        RideActivityState(
            activeSeconds: activeSeconds, distanceMeters: distanceMeters, gait: gait.flatMap(Gait.init(rawValue:)), weakGps: weakGps, paused: paused
        )
    }
}

/// Teksty Live Activity z `Localizable.xcstrings` (klucze ze `strings.xml` Androida 3.0.2). Katalog jest w obu celach, więc `Bundle.main`
/// to pakiet aplikacji albo rozszerzenia.
private func rideActivityText(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

extension RideNotificationTexts {
    /// Szablony tekstów nagrywania (`ride_*`) — bez podstawiania (podstawia `RideNotificationContent`).
    static var app: RideNotificationTexts {
        RideNotificationTexts(
            title: rideActivityText("ride_notification_title"),
            weakGps: rideActivityText("ride_notification_weak_gps"),
            paused: rideActivityText("ride_notification_paused"),
            gaitStop: rideActivityText("ride_gait_stop"),
            gaitWalk: rideActivityText("ride_gait_walk"),
            gaitTrot: rideActivityText("ride_gait_trot"),
            gaitCanter: rideActivityText("ride_gait_canter"),
            durationMinutes: rideActivityText("ride_duration_minutes"),
            durationHoursMinutes: rideActivityText("ride_duration_hours_minutes"),
            distanceKm: rideActivityText("ride_distance_km"),
            batteryLow: rideActivityText("ride_battery_low"),
            autoFinished: rideActivityText("ride_auto_finished"),
            interrupted: rideActivityText("ride_interrupted")
        )
    }
}

/// Napisy przycisków Live Activity — te same co przyciski powiadomienia nagrywania w Androidzie.
struct RideActivityButtonTexts: Sendable, Hashable {
    /// `ride_notification_pause` — „Pauza”.
    var pause: String
    /// `ride_notification_resume` — „Wznów”.
    var resume: String
    /// `ride_notification_finish` — „Zakończ”.
    var finish: String

    static var app: RideActivityButtonTexts {
        RideActivityButtonTexts(
            pause: rideActivityText("ride_notification_pause"),
            resume: rideActivityText("ride_notification_resume"),
            finish: rideActivityText("ride_notification_finish")
        )
    }
}
