import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Klient programu z zaślepką `URLProtocol` (T074; contracts/android/pairing-and-connection.md, connection-behavior.md,
/// program-2.0-integration.md §2).
struct ApiClientTests {
    private let info = #"{"appVersion":"2.0.0","apiVersion":"v1","schemaVersion":"1.5","capabilities":["horseStatusInjured"],"dataStamp":"0123456789abcdef"}"#

    @Test func everyRequestCarriesTheKeyAndAcceptsJson() async {
        let program = FakeProgram()
        program.on("GET", "system/info", .json(200, info))
        program.on("POST", "notes", .json(201, #"{"id":"n1"}"#))
        let (client, _) = program.client()
        _ = await client.get("system/info")
        _ = await client.execute(.json(.post, "notes", .object(["title": .string("A")])))
        #expect(program.requests.count == 2)
        for request in program.requests {
            #expect(request.header("X-Api-Key") == "hk_test")
            #expect(request.header("Accept") == "application/json")
        }
    }

    @Test func a401SuspendsTheAddressWithoutRepeating() async {
        let program = FakeProgram()
        program.on("GET", "horses", .json(401, #"{"title":"Klucz odrzucony"}"#))
        let (client, book) = program.client()
        #expect(await client.get("horses").failure == .unauthorized(ApiProblem(title: "Klucz odrzucony", status: 401)))
        #expect(await book.addresses().first?.hold.reason == .keyRejected)
        guard case .suspended(.keyRejected, _)? = await client.get("horses").failure else {
            Issue.record("adres nie został wstrzymany")
            return
        }
        #expect(program.requests.count == 1)
    }

    @Test func a403WithAndWithoutBodyFromARemoteAddress() async {
        let program = FakeProgram()
        program.on("GET", "horses", .json(403, #"{"type":"https://zk/errors/key-home-only","title":"Tylko dom"}"#))
        let (client, book) = program.client(addresses: [program.address(remote: true)])
        guard case .keyHomeOnly? = await client.get("horses").failure else { Issue.record("brak key-home-only"); return }
        #expect(await book.addresses().first?.hold.reason == .keyHomeOnly)

        let other = FakeProgram()
        other.on("GET", "horses", .empty(403))
        let (remoteClient, remoteBook) = other.client(addresses: [other.address(remote: true)])
        #expect(await remoteClient.get("horses").failure == .remoteAccessDisabled)
        #expect(await remoteBook.addresses().first?.hold.reason == .remoteAccessDisabled)
    }

    @Test func a429WaitsQuietlyForAShortRetryAfterAndBlocksForALongOne() async {
        let program = FakeProgram()
        program.on("GET", "horses", .json(429, "{}", headers: ["Retry-After": "5"]))
        let (client, book) = program.client()
        guard case .rateLimited(5, _)? = await client.get("horses").failure else { Issue.record("brak 429"); return }
        let hold = await book.addresses().first?.hold
        #expect(hold?.reason == .rateLimited)
        #expect(hold?.until != nil)
        _ = await client.get("horses")
        #expect(program.requests.count == 1, "bez pętli ponowień")

        let blocked = FakeProgram()
        blocked.on("GET", "horses", .json(429, "{}", headers: ["Retry-After": "600"]))
        let events = EventLog()
        let (blockedClient, blockedBook) = blocked.client(events: { events.add($0) })
        _ = await blockedClient.get("horses")
        #expect(await blockedBook.addresses().first?.hold.reason == .addressBlocked)
        guard case .denied(.addressBlocked, _)? = events.all.last else { Issue.record("brak komunikatu blokady"); return }
    }

    @Test func a409CarriesTheCurrentRecordAnd413And415AreMapped() async {
        let program = FakeProgram()
        program.on("PUT", "notes/n1", .json(409, #"{"title":"Zmieniono","reason":"VersionMismatch","current":{"id":"n1","version":4}}"#))
        program.on("POST", "attachments", .json(413, "{}"), .json(415, "{}"))
        let (client, _) = program.client()
        guard case let .conflict(problem)? = await client.execute(.json(.put, "notes/n1", .object([:]), ifMatch: 3)).failure else { Issue.record("brak 409"); return }
        #expect(problem.conflictReason == .versionMismatch)
        #expect(problem.current?["version"]?.intValue == 4)
        #expect(program.requests.first?.header("If-Match") == "\"3\"")
        guard case .payloadTooLarge? = await client.execute(ApiRequest(.post, "attachments")).failure else { Issue.record("brak 413"); return }
        guard case .unsupportedMediaType? = await client.execute(ApiRequest(.post, "attachments")).failure else { Issue.record("brak 415"); return }
    }

    @Test func aReadIsRetriedOnceOnTheSameAddressAndThenOnTheNext() async {
        let program = FakeProgram()
        program.on("GET", "horses", .fail(.networkConnectionLost), .json(200, #"{"items":[],"totalCount":0}"#))
        let (client, _) = program.client()
        #expect(await client.get("horses").success != nil, "odczyt ponowiony na tym samym adresie")
        #expect(program.requests("GET", "horses").count == 2)

        let down = FakeProgram()
        down.on("GET", "horses", .fail(.networkConnectionLost))
        let up = FakeProgram()
        up.on("GET", "horses", .json(200, "{}"))
        let (both, _) = down.client(addresses: [down.address(id: "a", position: 0), up.address(id: "b", position: 1)])
        #expect(await both.get("horses").success != nil)
        #expect(down.requests.count == 2)
        #expect(up.requests.count == 1)
    }

    @Test func aWriteIsNotRepeatedAfterTheBodyWasSentButMovesOnWhenItWasNot() async {
        let lost = FakeProgram()
        lost.on("POST", "notes", .fail(.networkConnectionLost))
        let other = FakeProgram()
        other.on("POST", "notes", .json(201, #"{"id":"n1"}"#))
        let (client, _) = lost.client(addresses: [lost.address(id: "a", position: 0), other.address(id: "b", position: 1)])
        #expect(await client.execute(.json(.post, "notes", .object([:]))).failure == .network(sentBody: true, idempotent: false))
        #expect(lost.requests.count == 1)
        #expect(other.requests.isEmpty)

        let refused = FakeProgram()
        refused.on("POST", "notes", .fail(.cannotConnectToHost))
        let (fallback, _) = refused.client(addresses: [refused.address(id: "a", position: 0), other.address(id: "b", position: 1)])
        #expect(await fallback.execute(.json(.post, "notes", .object([:]))).success != nil)
        #expect(other.requests.count == 1)
    }

    @Test func clientFeaturesOnlyWithInjuredAndNothingNewForProgram161() async {
        let program = FakeProgram()
        program.on("GET", "horses", .json(200, "{}"))
        let (modern, _) = program.client(capabilities: ProgramCapabilities(names: ["horseStatusInjured"]))
        _ = await modern.get("horses")
        #expect(program.requests.last?.header("X-Client-Features") == "horse-status-injured")

        let old = FakeProgram()
        old.on("GET", "horses", .json(200, "{}"))
        old.on("POST", "notes", .json(201, "{}"))
        let (legacy, _) = old.client(capabilities: .none)
        _ = await legacy.get("horses")
        _ = await legacy.execute(.json(.post, "notes", .object([:])))
        for request in old.requests {
            #expect(request.header("X-Client-Features") == nil)
            #expect(request.header("Idempotency-Key") == nil)
            #expect(request.header("If-Match") == nil)
        }
    }

    @Test func noNetworkSendsNothingAndAllAddressesDownReportOffline() async {
        let program = FakeProgram()
        program.on("GET", "horses", .fail(.timedOut))
        let events = EventLog()
        let (offline, _) = program.client(events: { events.add($0) }, network: .none)
        #expect(await offline.get("horses").failure == .noNetwork)
        #expect(program.requests.isEmpty)
        #expect(events.all == [.noNetwork])

        let (client, _) = program.client(events: { events.add($0) })
        guard case .network? = await client.get("horses").failure else { Issue.record("brak błędu sieci"); return }
        #expect(events.all.last == .unreachable)
    }

    @Test func aCertificateRejectionHoldsTheAddressAndSendsNoKeyAfterwards() async {
        let transport = RejectingTransport()
        let book = InMemoryAddressBook([ServerAddress(id: "a", url: "https://192.168.1.20:5080/api/v1", position: 0, trustMode: .pinned, certSha256: TestCertificate.fingerprint, isRemote: false)])
        let client = ApiClient(addresses: book, secrets: InMemorySecretStore("hk_test"), transport: transport, probe: AlwaysReachable())
        #expect(await client.get("system/info").failure == .certificateRejected)
        #expect(await book.addresses().first?.hold.reason == .certificateChanged)
        guard case .suspended(.certificateChanged, _)? = await client.get("system/info").failure else { Issue.record("adres nie wstrzymany"); return }
        #expect(transport.calls == 1)
    }
}

/// Transport, w którym uzgodnienie TLS zawsze odrzuca certyfikat (żądanie z kluczem nie wychodzi).
final class RejectingTransport: ProgramTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func send(_ request: URLRequest, to address: ServerAddress, bodyFile: URL?, download: Bool, progress: (@Sendable (Int64, Int64?) -> Void)?) async -> TransportOutcome {
        lock.withLock { count += 1 }
        return .certificateRejected(.rejectChanged)
    }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ConnectionEvent] = []

    func add(_ event: ConnectionEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var all: [ConnectionEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

extension Result {
    var failure: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }

    var success: Success? {
        if case let .success(value) = self { return value }
        return nil
    }
}
