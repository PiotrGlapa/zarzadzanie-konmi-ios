import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Planista powiadomień (T119): zastępuje zaplanowane `daily-…`/`due-…`, nie rusza innych, wyłączenie usuwa plan, „Ukryj
/// szczegóły” — treść bez imion.
struct NotificationSchedulerTests {
    final class FakeCenter: NotificationCenterClient, @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [String: NotificationRequest] = [:]

        init(existing: [String]) {
            for id in existing {
                pending[id] = NotificationRequest(identifier: id, components: DateComponents(), title: "", body: "", link: "")
            }
        }

        var requests: [NotificationRequest] { lock.withLock { Array(pending.values).sorted { $0.identifier < $1.identifier } } }

        func pendingIdentifiers() async -> [String] { lock.withLock { Array(pending.keys) } }
        func remove(_ identifiers: [String]) { lock.withLock { identifiers.forEach { pending.removeValue(forKey: $0) } } }
        func add(_ request: NotificationRequest) async throws { lock.withLock { pending[request.identifier] = request } }
    }

    private let stamp = LocalDateTime(year: 2026, month: 10, day: 1, hour: 10)!
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var now: Date { utc.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 7))! }

    private func store() async throws -> RecordStore {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let horse = LocalHorse(id: "h1", createdAt: stamp, updatedAt: stamp, name: "Grom", passportNumber: nil)
        let reminder = LocalReminder(id: "r1", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", kind: .farrier, dueDate: LocalDate("2026-10-05")!, title: "Kowal")
        try await store.upsert([try StoredRecord.of(horse, syncState: .local), try StoredRecord.of(reminder, syncState: .local)])
        return store
    }

    @Test func thePlanReplacesOldReminderNoticesAndKeepsOthers() async throws {
        let center = FakeCenter(existing: ["daily-2026-01-01", "due-old", "backup-error"])
        let scheduler = NotificationScheduler(store: try await store(), center: center)
        let plan = await scheduler.reschedule(enabled: true, settings: NotificationPlanSettings(onDueDate: true), hideDetails: false, now: now, fetchedAt: nil, calendar: utc)

        let ids = center.requests.map(\.identifier)
        #expect(ids.contains("backup-error"))
        #expect(!ids.contains("daily-2026-01-01") && !ids.contains("due-old"))
        #expect(ids.contains("daily-2026-10-05") && ids.contains("due-r1"))
        #expect(plan.count == ids.count - 1)
        let due = try #require(center.requests.first { $0.identifier == "due-r1" })
        #expect(due.body == "Grom — kowal, dziś")
        #expect(due.link == "horsely://reminders/r1")
        #expect(due.components.hour == 8 && due.components.day == 5)
    }

    @Test func hiddenDetailsUseTheTextWithoutNames() async throws {
        let center = FakeCenter(existing: [])
        let scheduler = NotificationScheduler(store: try await store(), center: center)
        await scheduler.reschedule(enabled: true, settings: NotificationPlanSettings(onDueDate: true), hideDetails: true, now: now, fetchedAt: nil, calendar: utc)
        #expect(center.requests.allSatisfy { !$0.body.contains("Grom") })
    }

    @Test func turningNotificationsOffRemovesThePlan() async throws {
        let center = FakeCenter(existing: ["daily-2026-10-06", "due-r1", "queue-needsfix"])
        let scheduler = NotificationScheduler(store: try await store(), center: center)
        let plan = await scheduler.reschedule(enabled: false, settings: NotificationPlanSettings(), hideDetails: false, now: now, fetchedAt: nil, calendar: utc)
        #expect(plan.isEmpty)
        #expect(center.requests.map(\.identifier) == ["queue-needsfix"])
    }
}
