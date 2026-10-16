import Testing
@testable import HorselyCore

/// Treść i plan powiadomień o terminach (T118, FR-M-POW-02…04; przypadki `ReminderDigestTest`).
struct ReminderDigestTests {
    private let today = LocalDate(year: 2026, month: 10, day: 5)!
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 5, hour: 10)!
    private let now = LocalDateTime(year: 2026, month: 10, day: 5, hour: 7)!

    private func reminder(_ id: String, _ due: String, _ kind: ReminderKind = .farrier, horse: String = "h1", title: String? = nil, status: ReminderStatus = .open) -> LocalReminder {
        LocalReminder(id: id, createdAt: stamp, updatedAt: stamp, version: 1, horseId: horse, kind: kind, dueDate: LocalDate(due)!, title: title ?? "Termin \(id)", status: status)
    }

    private func horse(_ id: String, _ name: String, _ status: HorseStatus = .active) -> LocalHorse {
        var horse = LocalHorse(id: id, createdAt: stamp, updatedAt: stamp, name: name, passportNumber: nil)
        horse.status = status
        return horse
    }

    private var horses: [LocalHorse] { [horse("h1", "Grom"), horse("h2", "Iskra")] }

    private func summary(_ open: [LocalReminder], fetchedAt: LocalDateTime? = nil) -> String? {
        ReminderDigest.dailySummary(open, day: today, fetchedAt: fetchedAt, at: LocalDateTime(date: today, hour: 8, minute: 0)!)
    }

    // MARK: Podsumowanie dnia

    @Test func theSummaryCountsOverdueAndTodayOrTomorrow() {
        let open = [reminder("a", "2026-10-01"), reminder("b", "2026-10-02"), reminder("c", "2026-10-05"), reminder("d", "2026-10-06"), reminder("e", "2026-10-20")]
        #expect(summary(open) == "2 przeterminowanych, 2 na dziś i jutro")
    }

    @Test func onlyTheNonEmptyPartIsShown() {
        #expect(summary([reminder("a", "2026-10-01")]) == "1 przeterminowanych")
        #expect(summary([reminder("a", "2026-10-06")]) == "1 na dziś i jutro")
    }

    @Test func nothingToReportMeansNoNotification() {
        #expect(summary([]) == nil)
        #expect(summary([reminder("far", "2026-12-01")]) == nil)
        let plan = ReminderDigest.plan(reminders: [], horses: horses, settings: NotificationPlanSettings(onDueDate: true), now: now, fetchedAt: nil)
        #expect(plan.isEmpty)
    }

    @Test func dataOlderThanSevenDaysGetANoteWithTheDate() throws {
        let old = LocalDateTime(year: 2026, month: 9, day: 27, hour: 8)!
        let text = try #require(summary([reminder("a", "2026-10-01")], fetchedAt: old))
        #expect(text.hasPrefix("1 przeterminowanych\n"))
        #expect(text.contains("Dane z 27.09.2026, 08:00 — połącz się z komputerem, aby je odświeżyć"))
    }

    @Test func dataFromExactlySevenDaysAgoHaveNoNote() {
        let week = LocalDateTime(year: 2026, month: 9, day: 28, hour: 8)!
        #expect(summary([reminder("a", "2026-10-01")], fetchedAt: week)?.contains("Dane z") == false)
    }

    // MARK: W dniu terminu

    @Test func linesDescribeTheDistanceToTheDueDate() {
        func line(_ due: String, _ kind: ReminderKind = .farrier) -> String { ReminderDigest.line(reminder("a", due, kind), horseName: "Grom", today: today) }
        #expect(line("2026-10-05") == "Grom — kowal, dziś")
        #expect(line("2026-10-06") == "Grom — kowal, jutro")
        #expect(line("2026-10-09") == "Grom — kowal, termin za 4 dni")
        #expect(line("2026-10-04") == "Grom — kowal, termin minął wczoraj")
        #expect(line("2026-10-02") == "Grom — kowal, termin minął 3 dni temu")
        #expect(line("2026-10-05", .deworming) == "Grom — odrobaczanie, dziś")
    }

    @Test func aCustomReminderIsDescribedByItsTitleAndAMissingHorseNameIsSkipped() {
        let custom = reminder("a", "2026-10-05", .other, title: "Wymiana podków")
        #expect(ReminderDigest.line(custom, horseName: nil, today: today) == "Wymiana podków, dziś")
        #expect(ReminderDigest.line(custom, horseName: "Grom", today: today) == "Grom — Wymiana podków, dziś")
    }

    @Test func dueDayNoticesNameTheHorseAndHideItOnTheLockScreen() {
        let open = [reminder("a", "2026-10-05", .farrier, horse: "h1"), reminder("b", "2026-10-05", .vaccination, horse: "h2")]
        let plan = ReminderDigest.plan(reminders: open, horses: horses, settings: NotificationPlanSettings(onDueDate: true), now: now, fetchedAt: nil)
        let due = plan.filter { $0.identifier.hasPrefix("due-") }
        #expect(due.map(\.text) == ["Grom — kowal, dziś", "Iskra — szczepienie, dziś"])
        #expect(due.map(\.deepLink) == ["horsely://reminders/a", "horsely://reminders/b"])
        #expect(due.allSatisfy { !$0.publicText.contains("Grom") && !$0.publicText.contains("Iskra") })
        #expect(due.allSatisfy { $0.fireAt == LocalDateTime(year: 2026, month: 10, day: 5, hour: 8) })
    }

    // MARK: Plan

    @Test func fourteenDailySummariesEachCountedForItsOwnDay() throws {
        let plan = ReminderDigest.plan(reminders: [reminder("a", "2026-10-10")], horses: horses, settings: NotificationPlanSettings(), now: now, fetchedAt: nil)
        // Termin 10.10: jutro dla 9.10, dziś dla 10.10, potem przeterminowany aż do końca planu.
        #expect(plan.first?.identifier == "daily-2026-10-09")
        #expect(plan.first?.text == "1 na dziś i jutro")
        let last = try #require(plan.last)
        #expect(last.identifier == "daily-2026-10-18")
        #expect(last.text == "1 przeterminowanych")
        #expect(plan.allSatisfy { $0.deepLink == ReminderDigest.dashboardLink })
    }

    @Test func todaysSummaryIsSkippedWhenTheHourHasPassed() {
        let late = LocalDateTime(year: 2026, month: 10, day: 5, hour: 9)!
        let plan = ReminderDigest.plan(reminders: [reminder("a", "2026-10-01")], horses: horses, settings: NotificationPlanSettings(), now: late, fetchedAt: nil)
        #expect(plan.first?.identifier == "daily-2026-10-06")
        #expect(plan.count == 13)
    }

    @Test func thePlanNeverExceedsSixtyNotices() {
        let many = (0 ..< 100).map { reminder("r\($0)", LocalDate(year: 2026, month: 10, day: 5)!.adding(days: $0).description) }
        let plan = ReminderDigest.plan(reminders: many, horses: horses, settings: NotificationPlanSettings(onDueDate: true), now: now, fetchedAt: nil)
        #expect(plan.count == ReminderDigest.limit)
        #expect(plan.filter { $0.identifier.hasPrefix("daily-") }.count == 14)
        #expect(plan.filter { $0.identifier.hasPrefix("due-") }.first?.identifier == "due-r0", "najbliższe terminy pierwsze")
    }

    @Test func anInjuredHorseCountsLikeAnActiveOneAndSoldHorsesAndClosedRemindersDoNot() {
        let stable = [horse("h1", "Grom", .injured), horse("h2", "Iskra", .sold)]
        let open = [reminder("a", "2026-10-05", horse: "h1"), reminder("b", "2026-10-05", horse: "h2"), reminder("c", "2026-10-05", horse: "h1", status: .completed)]
        #expect(ReminderDigest.relevant(open, horses: stable).map(\.id) == ["a"])
    }

    @Test func theSummaryTimeComesFromTheSettings() {
        #expect(NotificationPlanSettings(time: "19:45", onDueDate: false) == NotificationPlanSettings(hour: 19, minute: 45))
        #expect(NotificationPlanSettings(time: "zła", onDueDate: true) == NotificationPlanSettings(hour: 8, minute: 0, onDueDate: true))
    }
}
