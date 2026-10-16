import Foundation
import HorselyCore
import UserNotifications

/// Zaplanowane żądanie powiadomienia w kształcie niezależnym od `UNUserNotificationCenter` (testy).
public struct NotificationRequest: Equatable, Sendable {
    public let identifier: String
    public let components: DateComponents
    public let title: String
    public let body: String
    public let link: String
}

/// Centrum powiadomień systemu (w testach — zaślepka).
public protocol NotificationCenterClient: Sendable {
    func pendingIdentifiers() async -> [String]
    func remove(_ identifiers: [String])
    func add(_ request: NotificationRequest) async throws
}

/// `UNUserNotificationCenter` aplikacji.
public struct SystemNotificationCenter: NotificationCenterClient {
    public init() {}

    public func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    public func remove(_ identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func add(_ request: NotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [NotificationScheduler.linkKey: request.link]
        content.threadIdentifier = request.identifier.hasPrefix("due-") ? "due" : "daily"
        let trigger = UNCalendarNotificationTrigger(dateMatching: request.components, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }
}

/// Planowanie powiadomień o terminach (T119, FR-M-POW-01…04): plan z `ReminderDigest` na podstawie terminów i koni w magazynie,
/// zastępujący poprzednio zaplanowane `daily-…`/`due-…` (inne powiadomienia aplikacji zostają). Wołane po odświeżeniu danych,
/// po każdej zmianie w magazynie (akcje na terminach), po zmianie ustawień i w zadaniu w tle; zaplanowane powiadomienia system
/// zachowuje po ponownym uruchomieniu telefonu.
public final class NotificationScheduler: Sendable {
    public static let linkKey = "link"
    public static let title = "Horsely"

    private let store: RecordStore
    private let center: NotificationCenterClient

    public init(store: RecordStore, center: NotificationCenterClient = SystemNotificationCenter()) {
        self.store = store
        self.center = center
    }

    /// Przelicza plan. `enabled == false` — usuwa zaplanowane powiadomienia o terminach.
    @discardableResult
    public func reschedule(
        enabled: Bool, settings: NotificationPlanSettings, hideDetails: Bool, now: Date, fetchedAt: Date?, calendar: Calendar = .current
    ) async -> [PlannedNotice] {
        var plan: [PlannedNotice] = []
        if enabled {
            let data = try? await store.read { access in
                (try access.query(.reminder).compactMap { try $0.record(as: LocalReminder.self) },
                 try access.query(.horse).compactMap { try $0.record(as: LocalHorse.self) })
            }
            if let data {
                plan = ReminderDigest.plan(
                    reminders: data.0, horses: data.1, settings: settings, now: Self.local(now, calendar: calendar),
                    fetchedAt: fetchedAt.map { Self.local($0, calendar: calendar) }
                )
            }
        }
        let wanted = Set(plan.map(\.identifier))
        let stale = await center.pendingIdentifiers().filter { ($0.hasPrefix("daily-") || $0.hasPrefix("due-")) && !wanted.contains($0) }
        if !stale.isEmpty { center.remove(stale) }
        for notice in plan {
            try? await center.add(Self.request(notice, hideDetails: hideDetails))
        }
        return plan
    }

    static func request(_ notice: PlannedNotice, hideDetails: Bool) -> NotificationRequest {
        var components = DateComponents()
        components.year = notice.fireAt.date.year
        components.month = notice.fireAt.date.month
        components.day = notice.fireAt.date.day
        components.hour = notice.fireAt.hour
        components.minute = notice.fireAt.minute
        return NotificationRequest(
            identifier: notice.identifier, components: components, title: title, body: hideDetails ? notice.publicText : notice.text, link: notice.deepLink
        )
    }

    /// Chwila w czasie lokalnym telefonu.
    public static func local(_ date: Date, calendar: Calendar = .current) -> LocalDateTime {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return LocalDateTime(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1, hour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0)
            ?? LocalDateTime(year: 2000, month: 1, day: 1)!
    }
}
