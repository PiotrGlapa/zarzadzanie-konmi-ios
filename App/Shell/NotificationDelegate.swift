import HorselyKit
import UserNotifications

/// Dotknięcie powiadomienia otwiera jego adres `horsely://` (Pulpit albo szczegóły terminu); powiadomienie przy otwartej
/// aplikacji pokazuje się jako baner.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let open: @Sendable @MainActor (URL) -> Void

    init(open: @escaping @Sendable @MainActor (URL) -> Void) {
        self.open = open
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo[NotificationScheduler.linkKey] as? String, let url = URL(string: link) else { return }
        await open(url)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
