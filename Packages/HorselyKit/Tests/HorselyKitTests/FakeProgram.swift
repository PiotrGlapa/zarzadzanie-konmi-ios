import Foundation
import HorselyCore
@testable import HorselyKit

/// Zaślepka programu w procesie testowym (`URLProtocol`): odpowiedzi według metody i ścieżki, zapis żądań (z nagłówkami i treścią).
/// Każda zaślepka ma własny host, więc testy uruchamiane równolegle się nie mieszają.
final class FakeProgram: @unchecked Sendable {
    enum Reply: Sendable {
        case json(Int, String, headers: [String: String] = [:])
        case empty(Int, headers: [String: String] = [:])
        /// Błąd sieci (np. `.networkConnectionLost` — zerwanie po wysłaniu, `.cannotConnectToHost` — przed).
        case fail(URLError.Code)
        /// Odpowiedź JSON po opóźnieniu (zapis z połączeniem dłuższy niż 1 s).
        case delayed(TimeInterval, Int, String)
        /// Odpowiedź binarna (obraz) po opcjonalnym opóźnieniu — miniatury i pliki załączników.
        case bytes(Int, Data, contentType: String = "image/jpeg", delay: TimeInterval = 0)
    }

    struct Recorded: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        var json: JSONValue? { body.flatMap { try? JSONValue.parse($0) } }
    }

    let host: String
    private let lock = NSLock()
    private var routes: [(method: String, path: String, replies: [Reply])] = []
    private var recorded: [Recorded] = []

    init() {
        host = "t\(UUID().uuidString.prefix(8).lowercased()).local"
        StubProtocol.register(self)
    }

    var baseUrl: String { "http://\(host):5080/api/v1" }

    /// Kolejne odpowiedzi na `method path` (ścieżka bez zapytania, względem `/api/v1/`); ostatnia powtarza się.
    func on(_ method: String, _ path: String, _ replies: Reply...) {
        lock.lock()
        routes.append((method, path, replies))
        lock.unlock()
    }

    var requests: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func requests(_ method: String, _ path: String) -> [Recorded] {
        requests.filter { $0.method == method && $0.path == path }
    }

    func reply(to request: URLRequest) -> Reply {
        let url = request.url!
        let path = String(url.path.dropFirst("/api/v1/".count))
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            body = data
        }
        let method = request.httpMethod ?? "GET"
        lock.lock()
        defer { lock.unlock() }
        recorded.append(Recorded(method: method, path: path, headers: request.allHTTPHeaderFields ?? [:], body: body))
        guard let index = routes.lastIndex(where: { $0.method == method && ($0.path == path || ($0.path.hasSuffix("*") && path.hasPrefix(String($0.path.dropLast())))) }) else {
            return .json(404, #"{"title":"Nie znaleziono"}"#)
        }
        let replies = routes[index].replies
        if replies.count > 1 { routes[index].replies.removeFirst() }
        return replies[0]
    }

    func address(id: String = "a", position: Int = 0, remote: Bool = false) -> ServerAddress {
        ServerAddress(id: id, url: baseUrl, position: position, trustMode: .plainHttpConfirmed, isRemote: remote)
    }

    /// Klient z tą zaślepką.
    func client(
        addresses: [ServerAddress]? = nil, capabilities: ProgramCapabilities = .none, events: @escaping @Sendable (ConnectionEvent) -> Void = { _ in },
        network: FixedNetwork = .wifi
    ) -> (ApiClient, InMemoryAddressBook) {
        let book = InMemoryAddressBook(addresses ?? [address()])
        let transport = URLSessionTransport(configure: { $0.protocolClasses = [StubProtocol.self] })
        let client = ApiClient(
            addresses: book, secrets: InMemorySecretStore("hk_test"), transport: transport, probe: AlwaysReachable(),
            limiter: RateLimiter(maxRequests: 1000), network: { network }, capabilities: { capabilities }, events: events
        )
        return (client, book)
    }
}

/// `URLProtocol` kierujący żądania do zaślepki według hosta.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var programs: [String: FakeProgram] = [:]

    static func register(_ program: FakeProgram) {
        lock.lock()
        programs[program.host] = program
        lock.unlock()
    }

    static func program(for host: String?) -> FakeProgram? {
        lock.lock()
        defer { lock.unlock() }
        return host.flatMap { programs[$0] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let program = Self.program(for: request.url?.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        switch program.reply(to: request) {
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .json(status, text, headers):
            respond(status, headers.merging(["Content-Type": "application/json"]) { a, _ in a }, Data(text.utf8))
        case let .empty(status, headers):
            respond(status, headers, Data())
        case let .delayed(seconds, status, text):
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
                respond(status, ["Content-Type": "application/json"], Data(text.utf8))
            }
        case let .bytes(status, data, contentType, delay):
            if delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
                    respond(status, ["Content-Type": contentType], data)
                }
            } else {
                respond(status, ["Content-Type": contentType], data)
            }
        }
    }

    private func respond(_ status: Int, _ headers: [String: String], _ body: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Samopodpisany certyfikat testowy (CN=stajnia.local) i jego odcisk SHA‑256.
enum TestCertificate {
    static let base64 = "MIIDETCCAfmgAwIBAgIUM+G2o1lUqH3ttDg1zzYg5iZa0AswDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc3Rham5pYS5sb2NhbDAeFw0yNjEwMTYwOTM1NTdaFw0zNjEwMTMwOTM1NTdaMBgxFjAUBgNVBAMMDXN0YWpuaWEubG9jYWwwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDKSaaIcesPE9wJRomsaCFxNVfS/uyQjPeEwe2cALl2fhbZuptg6KuR12TAJNrygOHQD9pNzeZeTAKn6gRaT0ZAAsi+8BpFy3s8NQacI4z9gAKAM0xaK5xia9/GjJxgtAw0lKQoeCw+nwl2svfTbyY+qYdRGqcnQ+rsN6NFzyUq2K/QID2xtpjFdZCfnQw2ec2snxaS8kGIvbAXfJzOaYErxb+l9tz68DD/EbeL5Xw4Up9DUa+WW/tz15yYqRN4MNZ39MQxgPlau2Zu64e1IJIb3fYUU3sZpH7L16JyG6dLpAU72yXw8j4dplToP8SqRcy4bJOybldsELNLgWWvjpFXAgMBAAGjUzBRMB0GA1UdDgQWBBTUH75GuLzWRcQgBra1mu6kNp8ehjAfBgNVHSMEGDAWgBTUH75GuLzWRcQgBra1mu6kNp8ehjAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQCYrNlDbeFSyi3IrHH/HJyUt0wcSRidSQ4QQQFAZRfoDH0xoFedNpOizEIpWvq3DMN3sPrJQezv0W3E2/8PLB7R13qn0bosezgL8IlP6SeclISkPdEVHE5JtmVaGt1ahtjamVxcukWZ/sVS0him3ut2Z2Pio0xWgZbk/LHxUeI3zgt0Kl498mGdVYlSTcJ/VNIRsEv1dbxCr/iVQA8Xs1NGQl2n9ZJPpZBAqbFPYjPsaWjWD80lCjPR2+rLOertz4T+f5aFMj6RSxW5UTmUe8LwhsSMZtaOgseMCNt6ZxvNnV07HroQDpUZORS7B97fpj/sUe4NJBJ1/Qvu0KxIo2l6"
    static let fingerprint = "E1D73E1C14D3E5ADC814C90A663E5C3D918606D326B90F578FCB91086D822BFC"
}
