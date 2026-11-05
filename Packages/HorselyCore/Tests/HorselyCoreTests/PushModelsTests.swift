import Foundation
import Testing
@testable import HorselyCore

/// Modele API push i dekodowanie tolerancyjne (spec 003, T007, research R17).
struct PushModelsTests {
    // MARK: PushDevice

    @Test func aDeviceIsDecodedWithSevenFractionDigitsAndANullDeliveryDate() throws {
        let device = try #require(PushDevice.decode(Fixtures.data("push/device.json")))
        #expect(device.platform == "Ios")
        #expect(device.tokenPrefix == "dGhpcyBp")
        let expected = Date(timeIntervalSince1970: 1_793_787_300) // 2026-11-04T10:15:00Z
        #expect(device.registeredAt == expected)
        #expect(device.lastSeenAt == expected)
        #expect(device.lastDeliveredAt == nil)
    }

    @Test func instantsAcceptAnyNumberOfFractionDigits() {
        let base = Date(timeIntervalSince1970: 1_793_787_300)
        #expect(PushInstant.parse("2026-11-04T10:15:00Z") == base)
        #expect(PushInstant.parse("2026-11-04T10:15:00.0000000Z") == base)
        // Ułamek sprowadzony do milisekund; porównanie z tolerancją, bo `Date` jest zmiennoprzecinkowa.
        let half = PushInstant.parse("2026-11-04T10:15:00.5Z")
        #expect(abs((half?.timeIntervalSince(base) ?? -1) - 0.5) < 0.001)
        let truncated = PushInstant.parse("2026-11-04T10:15:00.1234567Z")
        #expect(abs((truncated?.timeIntervalSince(base) ?? -1) - 0.123) < 0.001)
        #expect(PushInstant.parse("nie data") == nil)
    }

    @Test func aDeviceWithMissingOrBrokenFieldsStillDecodes() throws {
        let device = try #require(PushDevice.decode(Data(#"{"platform":"Ios","registeredAt":"zepsuta","nowe":{"a":1}}"#.utf8)))
        #expect(device.tokenPrefix == "")
        #expect(device.registeredAt == nil)
        #expect(PushDevice.decode(Data("[]".utf8)) == nil)
        #expect(PushDevice.decode(Data("to nie json".utf8)) == nil)
    }

    // MARK: ClientPushRule

    @Test func rulesKeepTheServerOrderAndIgnoreUnknownFieldsAndTypes() throws {
        let rules = try #require(ClientPushRule.decodeList(Fixtures.data("push/rules.json")))
        #expect(rules.map(\.id) == ["r1", "r2"], "element bez description jest pominięty")
        #expect(rules[0].type == "Reminder")
        #expect(rules[0].reminderKind == "Farrier")
        #expect(rules[0].offsetDays == 1)
        #expect(rules[0].sendTime == "08:00")
        #expect(rules[0].repeatTime == "07:00")
        #expect(rules[0].description == "Kowal: dzień przed o 08:00, powtórka o 07:00")
        #expect(rules[1].type == "SomethingNew")
        #expect(rules[1].reminderKind == nil && rules[1].offsetDays == nil && rules[1].sendTime == nil && rules[1].repeatTime == nil)
    }

    @Test func anEmptyListAndANonListAreDistinguished() {
        #expect(ClientPushRule.decodeList(Data("[]".utf8)) == [])
        #expect(ClientPushRule.decodeList(Data(#"{"items":[]}"#.utf8)) == nil)
        #expect(ClientPushRule.decodeList(Data("śmieci".utf8)) == nil)
        #expect(ClientPushRule.decodeList(Data(#"[{"id":"x","description":"   "}]"#.utf8)) == [])
    }

    // MARK: DeviceRegistration

    @Test func theRegistrationBodyHasExactlyThePlatformAndTheToken() throws {
        let registration = try #require(DeviceRegistration(token: "abc:DEF_123-xyz"))
        let json = String(decoding: registration.jsonData(), as: UTF8.self)
        #expect(json == #"{"platform":"Ios","token":"abc:DEF_123-xyz"}"#)
        #expect(registration.prefix == "abc:DEF_")
    }

    @Test func aTokenMustBeNonEmptyShortAndWithoutWhitespace() {
        #expect(DeviceRegistration(token: "") == nil)
        #expect(DeviceRegistration(token: "ab cd") == nil)
        #expect(DeviceRegistration(token: "ab\ncd") == nil)
        #expect(DeviceRegistration(token: String(repeating: "a", count: 4096)) != nil)
        #expect(DeviceRegistration(token: String(repeating: "a", count: 4097)) == nil)
    }

    @Test func theValidationProblemListsTheTokenField() throws {
        let problem = ApiProblem.parse(status: 400, body: try Fixtures.data("push/problem-400.json"))
        #expect(problem.errors.keys.sorted() == ["token"])
    }
}
