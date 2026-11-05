import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Klient API push na zaślepce programu (spec 003, T009, contracts/push-api-client.md): dane komórkowe, ponowienia po zerwanym
/// połączeniu, odczyty bez zmian, dziennik połączeń bez tokenu.
struct ApiClientPushTests {
    private let token = "dGhpcyBpcyBhIHRva2Vu:APA91bFakeToken-123_xyz"

    private func registration() throws -> DeviceRegistration {
        try #require(DeviceRegistration(token: token))
    }

    private let deviceJson = #"{"platform":"Ios","tokenPrefix":"dGhpcyBp","registeredAt":"2026-11-04T10:15:00.0000000Z","lastSeenAt":null,"lastDeliveredAt":null}"#

    // MARK: Dane komórkowe

    @Test func registrationGoesOutOnCellularToTheOnlyRemoteAddressEvenWithWifiOnly() async throws {
        let program = FakeProgram()
        program.pushCapability = true
        // `wifiOnly` w kliencie testowym jest włączone (jak domyślne ustawienie), sieć — komórkowa, adres — zewnętrzny.
        let (client, _) = program.client(addresses: [program.address(remote: true)], network: .cellular)
        let outcome = await PushApi(client: client).registerDevice(token: try registration())
        guard case let .ok(device) = outcome else { Issue.record("rejestracja nie wyszła: \(outcome)"); return }
        #expect(device.tokenPrefix == "dGhpcyBp")
        #expect(program.requests("PUT", "push/device").count == 1)
        #expect(program.registeredPushToken == token)
    }

    @Test func theRegistrationBodyAndHeadersAreExactlyWhatTheContractSays() async throws {
        let program = FakeProgram()
        program.pushCapability = true
        let (client, _) = program.client()
        _ = await PushApi(client: client).registerDevice(token: try registration())
        let request = try #require(program.requests("PUT", "push/device").first)
        #expect(request.header("X-Api-Key") == "hk_test")
        #expect(request.header("Idempotency-Key") == nil)
        #expect(request.header("Content-Type")?.hasPrefix("application/json") == true)
        #expect(request.json?.objectValue?.keys.sorted() == ["platform", "token"])
        #expect(request.json?["platform"]?.stringValue == "Ios")
        #expect(request.json?["token"]?.stringValue == token)
    }

    // MARK: Zerwane połączenie

    @Test func aPutIsRepeatedTwiceAfterTheConnectionDropsAndThenSucceeds() async throws {
        let program = FakeProgram()
        program.on("PUT", "push/device", .fail(.networkConnectionLost), .fail(.networkConnectionLost), .json(200, deviceJson))
        let (client, _) = program.client()
        let outcome = await PushApi(client: client).registerDevice(token: try registration())
        guard case .ok = outcome else { Issue.record("trzecia próba powinna się udać: \(outcome)"); return }
        #expect(program.requests("PUT", "push/device").count == 3)
    }

    @Test func threeDropsInARowEndAsATransientNetworkError() async throws {
        let program = FakeProgram()
        program.on("PUT", "push/device", .fail(.networkConnectionLost))
        let (client, _) = program.client()
        let outcome = await PushApi(client: client).registerDevice(token: try registration())
        #expect(outcome.isTransient)
        #expect(program.requests("PUT", "push/device").count == 3, "pierwsza próba i dwa ponowienia")
    }

    @Test func aDeleteIsRepeatedLikeAPut() async {
        let program = FakeProgram()
        program.on("DELETE", "push/device", .fail(.networkConnectionLost), .empty(204))
        let (client, _) = program.client()
        guard case .ok = await PushApi(client: client).unregisterDevice() else { Issue.record("DELETE nie przeszedł"); return }
        #expect(program.requests("DELETE", "push/device").count == 2)
    }

    @Test func aGetKeepsTheSingleRetry() async {
        let program = FakeProgram()
        program.on("GET", "push/device", .fail(.networkConnectionLost))
        let (client, _) = program.client()
        #expect(await PushApi(client: client).device().isTransient)
        #expect(program.requests("GET", "push/device").count == 2)
    }

    @Test func aWriteWithoutRetryOnDropStillIsNotRepeated() async {
        let program = FakeProgram()
        program.on("POST", "notes", .fail(.networkConnectionLost))
        let (client, _) = program.client()
        #expect(await client.execute(.json(.post, "notes", .object([:]))).failure == .network(sentBody: true, idempotent: false))
        #expect(program.requests("POST", "notes").count == 1)
    }

    @Test func afterTheRetriesAreSpentTheNextAddressIsTried() async throws {
        let down = FakeProgram()
        down.on("PUT", "push/device", .fail(.networkConnectionLost))
        let up = FakeProgram()
        up.on("PUT", "push/device", .json(200, deviceJson))
        let (client, _) = down.client(addresses: [down.address(id: "a", position: 0), up.address(id: "b", position: 1)])
        guard case .ok = await PushApi(client: client).registerDevice(token: try registration()) else { Issue.record("brak przejścia na kolejny adres"); return }
        #expect(down.requests.count == 3)
        #expect(up.requests.count == 1)
    }

    // MARK: Mapowanie wyników

    @Test func serverAnswersMapToTheOutcomesTheRegistrarNeeds() async throws {
        let program = FakeProgram()
        program.on("PUT", "push/device", .json(400, #"{"title":"Błąd walidacji","status":400,"errors":{"token":["Token jest wymagany."]}}"#))
        program.on("GET", "push/device", .json(404, #"{"title":"Nie znaleziono","status":404}"#))
        program.on("GET", "push/rules", .json(503, #"{"title":"Niedostępne"}"#))
        let (client, _) = program.client()
        let api = PushApi(client: client)
        let device = try registration()
        #expect(await api.registerDevice(token: device) == .invalid(fields: ["token"]))
        #expect(await api.device() == .notRegistered)
        #expect(await api.rules().isTransient)
    }

    @Test func aRejectedKeyIsAnAccessIssueNotAPushError() async throws {
        let program = FakeProgram()
        program.on("PUT", "push/device", .json(401, #"{"title":"Klucz odrzucony"}"#))
        let (client, _) = program.client()
        let device = try registration()
        #expect(await PushApi(client: client).registerDevice(token: device) == .access)
    }

    @Test func anUnreadableSuccessBodyStillCountsAsRegistered() async throws {
        let program = FakeProgram()
        program.on("PUT", "push/device", .empty(200))
        let (client, _) = program.client()
        guard case let .ok(device) = await PushApi(client: client).registerDevice(token: try registration()) else { Issue.record("200 bez treści to sukces"); return }
        #expect(device.tokenPrefix == String(token.prefix(8)))
        #expect(device.registeredAt == nil)
    }

    @Test func rulesAreReadInTheServerOrder() async {
        let program = FakeProgram()
        program.pushCapability = true
        program.setPushRules(#"[{"id":"r1","type":"Reminder","description":"Kowal: dzień przed"},{"id":"r2","type":"DailySummary","description":"Podsumowanie o 08:00"}]"#)
        let (client, _) = program.client()
        guard case let .ok(rules) = await PushApi(client: client).rules() else { Issue.record("brak listy"); return }
        #expect(rules.map(\.description) == ["Kowal: dzień przed", "Podsumowanie o 08:00"])
    }

    // MARK: Dziennik połączeń (FR-028)

    @Test func theConnectionLogShowsMethodPathAndResultButNeverTheToken() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-pushlog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory)
        let program = FakeProgram()
        program.on("PUT", "push/device", .fail(.networkConnectionLost), .json(200, deviceJson))
        let (client, _) = program.client(connectionLog: ConnectionLog(log: log, enabled: { true }))
        _ = await PushApi(client: client).registerDevice(token: try registration())
        let text = log.text()
        #expect(text.contains("PUT /push/device"))
        #expect(text.contains("HTTP 200"))
        #expect(text.contains("ponowienie zapisu idempotentnego"))
        #expect(!text.contains(token))
        #expect(!text.contains(String(token.dropFirst(8))))
    }
}
