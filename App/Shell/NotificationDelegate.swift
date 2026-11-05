import HorselyCore
import HorselyKit
import UserNotifications

/// Dotknięcie powiadomienia otwiera jego adres `horsely://` (Pulpit albo szczegóły terminu); powiadomienie przy otwartej
/// aplikacji pokazuje się jako baner. Wiadomości z serwera (klucz `type`, spec 003) przy otwartej aplikacji pokazuje
/// `presentServerMessage` — wg stanu push (FR-016): tylko przy zarejestrowanym telefonie, inaczej nic (powiadomienia planuje telefon).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let open: @Sendable @MainActor (URL) -> Void
    private let presentServerMessage: @Sendable @MainActor (PushMessage) -> UNNotificationPresentationOptions

    init(
        open: @escaping @Sendable @MainActor (URL) -> Void,
        presentServerMessage: @escaping @Sendable @MainActor (PushMessage) -> UNNotificationPresentationOptions
    ) {
        self.open = open
        self.presentServerMessage = presentServerMessage
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo[NotificationScheduler.linkKey] as? String, let url = URL(string: link) else { return }
        await open(url)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Powiadomienia lokalne nie mają klucza `type` — pokazują się jak dotąd.
        guard let message = PushMessage(userInfo: notification.request.content.userInfo) else { return [.banner, .list, .sound] }
        return await presentServerMessage(message)
    }
}
