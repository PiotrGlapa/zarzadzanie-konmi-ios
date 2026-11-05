import Foundation
import Testing
@testable import HorselyCore

/// Rozpoznanie wiadomości z serwera w `userInfo` (spec 003, T015; mapowanie na cel nawigacji dochodzi w US5).
struct PushMessageTests {
    @Test func theTypeKeyMakesAServerMessageAndMapsToAKind() throws {
        let cases: [(String, PushKind)] = [
            ("reminder", .reminder), ("summary", .summary), ("backup", .backup), ("analytic", .analytic), ("test", .test),
            ("cosNowego", .other("cosNowego")),
        ]
        for (type, kind) in cases {
            let message = try #require(PushMessage(userInfo: ["type": type]))
            #expect(message.kind == kind, "\(type)")
        }
    }

    @Test func withoutATypeItIsNotAServerMessage() {
        #expect(PushMessage(userInfo: [:]) == nil)
        #expect(PushMessage(userInfo: ["link": "horsely://dashboard"]) == nil, "powiadomienie lokalne ma klucz link")
        #expect(PushMessage(userInfo: ["type": ""]) == nil)
        #expect(PushMessage(userInfo: ["type": 5]) == nil)
    }

    @Test func onlyReminderAndSummaryTriggerASync() throws {
        for (type, expected) in [("reminder", true), ("summary", true), ("backup", false), ("analytic", false), ("test", false), ("inny", false)] {
            let message = try #require(PushMessage(userInfo: ["type": type]))
            #expect(message.triggersSync == expected, "\(type)")
        }
    }

    // MARK: Cel nawigacji (contracts/push-message.md)

    private func link(_ info: [AnyHashable: Any]) throws -> String {
        PushDeepLink.url(for: try #require(PushMessage(userInfo: info)))
    }

    @Test func everyKindMapsToItsScreen() throws {
        #expect(try link(["type": "reminder", "reminderId": "6F1C"]) == "horsely://reminders/6F1C")
        #expect(try link(["type": "reminder"]) == "horsely://dashboard", "bez identyfikatora terminu — Pulpit")
        #expect(try link(["type": "reminder", "reminderId": ""]) == "horsely://dashboard")
        #expect(try link(["type": "summary"]) == "horsely://reminders")
        #expect(try link(["type": "backup"]) == "horsely://server-backup")
        #expect(try link(["type": "analytic"]) == "horsely://dashboard")
        #expect(try link(["type": "test"]) == "horsely://dashboard")
        #expect(try link(["type": "cosNowego", "reminderId": "x"]) == "horsely://dashboard")
    }

    @Test func serviceKeysAndUnknownKeysDoNotChangeTheTarget() throws {
        let info: [AnyHashable: Any] = [
            "type": "reminder", "reminderId": "6F1C", "aps": ["alert": ["title": "Horsely", "body": "Kowal"]],
            "gcm.message_id": "0:1", "google.c.a.e": "1", "przyszłyKlucz": "x",
        ]
        #expect(try link(info) == "horsely://reminders/6F1C")
    }

    @Test func anIdentifierThatCouldBreakTheAddressFallsBackToTheDashboard() throws {
        #expect(try link(["type": "reminder", "reminderId": "a/b"]) == "horsely://dashboard")
        #expect(try link(["type": "reminder", "reminderId": "z spacją"]) == "horsely://reminders/z%20spacj%C4%85")
    }

    @Test func identifiersAreNonEmptyStringsAndTheDateIsValidated() throws {
        let message = try #require(PushMessage(userInfo: [
            "type": "reminder", "reminderId": "6F1C", "horseId": "A0B2", "targetDate": "2026-11-05",
            "aps": ["alert": ["title": "Horsely", "body": "Kowal: Gniada, jutro"]], "gcm.message_id": "x", "google.c.a.e": "1",
        ]))
        #expect(message.reminderId == "6F1C")
        #expect(message.horseId == "A0B2")
        #expect(message.targetDate == LocalDate(year: 2026, month: 11, day: 5))

        let broken = try #require(PushMessage(userInfo: ["type": "reminder", "reminderId": "", "horseId": 7, "targetDate": "2026-13-01"]))
        #expect(broken.reminderId == nil)
        #expect(broken.horseId == nil)
        #expect(broken.targetDate == nil)
    }
}
