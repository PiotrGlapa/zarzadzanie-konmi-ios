import Foundation
import HorselyKit

/// Teksty nagrywania jazdy z `Localizable.xcstrings` (klucze `ride_*` ze `strings.xml` Androida 3.0.2) — szablony formatu, bez
/// podstawiania (podstawia `RideNotificationContent`).
extension RideNotificationTexts {
    static var app: RideNotificationTexts {
        RideNotificationTexts(
            title: tr("ride_notification_title"),
            weakGps: tr("ride_notification_weak_gps"),
            paused: tr("ride_notification_paused"),
            gaitStop: tr("ride_gait_stop"),
            gaitWalk: tr("ride_gait_walk"),
            gaitTrot: tr("ride_gait_trot"),
            gaitCanter: tr("ride_gait_canter"),
            durationMinutes: tr("ride_duration_minutes"),
            durationHoursMinutes: tr("ride_duration_hours_minutes"),
            distanceKm: tr("ride_distance_km"),
            batteryLow: tr("ride_battery_low"),
            autoFinished: tr("ride_auto_finished"),
            interrupted: tr("ride_interrupted")
        )
    }
}

/// Kontroler nagrywania dla delegata aplikacji (`applicationWillTerminate`), który nie ma dostępu do środowiska — jak `PushBridge`.
final class RideBridge: @unchecked Sendable {
    static let shared = RideBridge()

    private let lock = NSLock()
    private var current: RideRecordingController?

    var controller: RideRecordingController? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}
