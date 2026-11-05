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
