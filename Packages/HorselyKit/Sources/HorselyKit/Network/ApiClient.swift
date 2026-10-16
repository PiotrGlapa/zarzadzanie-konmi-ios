import Foundation
import HorselyCore

/// Adresy programu i ich wstrzymania (w aplikacji — tabela `address`, w testach — pamięć).
public protocol AddressBook: Sendable {
    func addresses() async -> [ServerAddress]
    func setHold(_ id: String, _ hold: AddressHold) async
    func markOk(_ id: String, at: Date) async
}

/// Adresy w magazynie (tabela `address`).
public struct StoreAddressBook: AddressBook {
    let store: RecordStore

    public init(store: RecordStore) {
        self.store = store
    }

    public func addresses() async -> [ServerAddress] {
        (try? await store.read { try $0.addresses() }) ?? []
    }

    public func setHold(_ id: String, _ hold: AddressHold) async {
        try? await store.writeQuietly { try $0.setHold(id, hold) }
    }

    public func markOk(_ id: String, at: Date) async {
        try? await store.writeQuietly { try $0.markAddressOk(id, at: at) }
    }
}

/// Adresy w pamięci — testy i parowanie (adres jeszcze niezapisany).
public actor InMemoryAddressBook: AddressBook {
    private var items: [ServerAddress]

    public init(_ addresses: [ServerAddress]) {
        items = addresses
    }

    public func addresses() -> [ServerAddress] { items }

    public func setHold(_ id: String, _ hold: AddressHold) {
        if let index = items.firstIndex(where: { $0.id == id }) { items[index].hold = hold }
    }

    public func markOk(_ id: String, at: Date) {
        if let index = items.firstIndex(where: { $0.id == id }) { items[index].lastOkAt = at }
    }
}

/// Stan sieci telefonu potrzebny regule „tylko przez Wi‑Fi” i wykrywaniu braku sieci (w aplikacji — `NWPathMonitor`).
public protocol NetworkConditions: Sendable {
    var isAvailable: Bool { get }
    /// Sieć z limitem (komórkowa, hotspot) — `NWPath.isExpensive`.
    var isExpensive: Bool { get }
    /// Rodzaj sieci do dziennika połączeń: „Wi‑Fi”, „komórkowa”, „Ethernet”, „brak sieci”.
    var label: String { get }
}

public struct FixedNetwork: NetworkConditions {
    public let isAvailable: Bool
    public let isExpensive: Bool
    public let label: String

    public init(isAvailable: Bool = true, isExpensive: Bool = false, label: String = "Wi‑Fi") {
        self.isAvailable = isAvailable
        self.isExpensive = isExpensive
        self.label = label
    }

    public static let wifi = FixedNetwork()
    public static let cellular = FixedNetwork(isExpensive: true, label: "komórkowa")
    public static let none = FixedNetwork(isAvailable: false, label: "brak sieci")
}

/// Zdarzenie dla stanu połączenia (contracts/android/connection-behavior.md §2): każde żądanie je zgłasza.
public enum ConnectionEvent: Equatable, Sendable {
    /// Program odpowiedział (dowolny status) — brak problemu „offline”.
    case answered
    /// Brak odpowiedzi z wszystkich adresów.
    case unreachable
    /// Odmowa programu albo certyfikat — mają pierwszeństwo przed „offline”.
    case denied(BlockReason, until: Date?)
    /// Telefon nie ma sieci.
    case noNetwork
}

/// Klient programu (research R8, konstytucja III): brama po adresach (`AddressGateway`) ze strażnikiem dostępu (`AccessGuard`).
///
/// Każde żądanie:
/// 1. nie wychodzi do adresu wstrzymanego (401/403/429/certyfikat) — zero ruchu (SC-M-08);
/// 2. przechodzi przez ogranicznik tempa (80 / 10 s);
/// 3. niesie `X-Api-Key`, `Accept: application/json`, a przy programie z `horseStatusInjured` — `X-Client-Features`;
/// 4. po `401`/`403`/`429` wstrzymuje adres bez ponawiania w pętli.
///
/// Kolejność adresów: ostatnio działający, potem wg `position`. Odczyt (GET) po błędzie sieci jest ponawiany raz na tym samym
/// adresie, potem na kolejnych; zapis przechodzi na kolejny adres tylko wtedy, gdy treść nie wyszła (konstytucja IV).
public final class ApiClient: Sendable {
    public static let apiKeyHeader = "X-Api-Key"
    /// `Retry-After` do tego progu to ciche odczekanie; powyżej — blokada adresu z komunikatem (FR-M-POL-11).
    public static let silentWaitLimit: TimeInterval = 60
    /// Udana próba połączenia jest ważna przez minutę (bez ponownej sondy TCP).
    static let probeValidity: TimeInterval = 60

    private let book: AddressBook
    private let secrets: SecretStore
    private let transport: ProgramTransport
    private let probe: ConnectProbe
    private let limiter: RateLimiter
    private let network: @Sendable () -> NetworkConditions
    private let wifiOnly: @Sendable () -> Bool
    private let capabilities: @Sendable () async -> ProgramCapabilities
    private let now: @Sendable () -> Date
    private let events: @Sendable (ConnectionEvent) -> Void
    private let connectionLog: ConnectionLog?
    private let probes = ProbeMemory()

    public init(
        addresses: AddressBook, secrets: SecretStore, transport: ProgramTransport = URLSessionTransport(), probe: ConnectProbe = TCPConnectProbe(),
        limiter: RateLimiter = RateLimiter(), network: @escaping @Sendable () -> NetworkConditions = { FixedNetwork.wifi },
        wifiOnly: @escaping @Sendable () -> Bool = { true }, capabilities: @escaping @Sendable () async -> ProgramCapabilities = { .none },
        now: @escaping @Sendable () -> Date = { Date() }, events: @escaping @Sendable (ConnectionEvent) -> Void = { _ in }, connectionLog: ConnectionLog? = nil
    ) {
        book = addresses
        self.secrets = secrets
        self.transport = transport
        self.probe = probe
        self.limiter = limiter
        self.network = network
        self.wifiOnly = wifiOnly
        self.capabilities = capabilities
        self.now = now
        self.events = events
        self.connectionLog = connectionLog
    }

    // MARK: Brama po adresach

    /// Wykonuje żądanie na kolejnych adresach (contracts/android/connection-behavior.md §1).
    public func execute(_ request: ApiRequest, progress: (@Sendable (Int64, Int64?) -> Void)? = nil) async -> ApiResult {
        let conditions = network()
        guard conditions.isAvailable else {
            connectionLog?.skipped("brak sieci", address: nil, network: conditions.label)
            events(.noNetwork)
            return .failure(.noNetwork)
        }
        let all = await book.addresses()
        let moment = now()
        let ordered = AddressOrder.order(all, now: moment)
        if ordered.isEmpty {
            for address in AddressOrder.blocked(all, now: moment) {
                connectionLog?.skipped("adres wstrzymany (\(address.hold.reason?.rawValue ?? "?"))", address: address, network: conditions.label)
            }
            if let blocked = AddressOrder.blocked(all, now: moment).first, let reason = blocked.hold.reason {
                events(.denied(reason, until: blocked.hold.until))
                return .failure(.suspended(reason, until: blocked.hold.until))
            }
            connectionLog?.skipped("brak adresu", address: nil, network: conditions.label)
            return .failure(.noUsableAddress)
        }
        let skipRemote = request.forFile && wifiOnly() && conditions.isExpensive
        if skipRemote {
            for address in ordered where address.isRemote {
                connectionLog?.skipped("adres zewnętrzny tylko przez Wi‑Fi", address: address, network: conditions.label)
            }
        }
        let candidates = skipRemote ? ordered.filter(\.isLocal) : ordered
        guard !candidates.isEmpty else { return .failure(.noUsableAddress) }

        var last: ApiResult = .failure(.noUsableAddress)
        for address in candidates {
            let result = await executeOn(address, request, progress: progress)
            guard case let .failure(failure) = result else {
                events(.answered)
                return result
            }
            let tryNext: Bool
            switch failure {
            case let .network(sentBody, idempotent): tryNext = idempotent || !sentBody
            case .certificateRejected, .suspended, .keyHomeOnly, .remoteAccessDisabled: tryNext = true
            default: tryNext = false
            }
            if !tryNext {
                report(failure)
                return result
            }
            last = result
        }
        if case let .failure(failure) = last { report(failure) }
        return last
    }

    private func report(_ failure: ApiFailure) {
        switch failure {
        case .network, .noUsableAddress: events(.unreachable)
        case .noNetwork: events(.noNetwork)
        case let .suspended(reason, until): events(.denied(reason, until: until))
        case .certificateRejected: events(.denied(.certificateChanged, until: nil))
        case .unauthorized: events(.denied(.keyRejected, until: nil))
        case .keyHomeOnly: events(.denied(.keyHomeOnly, until: nil))
        case .remoteAccessDisabled: events(.denied(.remoteAccessDisabled, until: nil))
        case let .rateLimited(seconds, _):
            events(seconds > Self.silentWaitLimit ? .denied(.addressBlocked, until: now().addingTimeInterval(seconds)) : .answered)
        default: events(.answered)
        }
    }

    // MARK: Jeden adres

    /// Jedna próba na wskazanym adresie (z jednym ponowieniem odczytu), bez przechodzenia na inne adresy — „Sprawdź połączenie”,
    /// parowanie, sondowanie adresów po kolei.
    /// - Parameters:
    ///   - apiKey: klucz parowania (adres jeszcze niezapisany); domyślnie z Keychain.
    ///   - features: możliwości do nagłówka cech klienta; domyślnie zapamiętane.
    public func executeOn(
        _ address: ServerAddress, _ request: ApiRequest, apiKey: String? = nil, features: ProgramCapabilities? = nil,
        progress: (@Sendable (Int64, Int64?) -> Void)? = nil
    ) async -> ApiResult {
        var result = await attempt(address, request, apiKey: apiKey, features: features, progress: progress)
        if case let .failure(.network(sentBody, idempotent)) = result, idempotent, sentBody {
            connectionLog?.note("ponowienie odczytu", address: address, network: network().label)
            result = await attempt(address, request, apiKey: apiKey, features: features, progress: progress)
        }
        return result
    }

    private func attempt(
        _ address: ServerAddress, _ request: ApiRequest, apiKey: String?, features: ProgramCapabilities?, progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async -> ApiResult {
        let moment = now()
        if address.hold.isBlocked(at: moment), let reason = address.hold.reason {
            return .failure(.suspended(reason, until: address.hold.until))
        }
        // Wstrzymanie czasowe wygasło — adres znów jest aktywny.
        if address.hold.reason != nil { await book.setHold(address.id, .active) }

        guard let url = URL(string: address.url + "/" + request.path) else { return .failure(.noUsableAddress) }
        let conditions = network()

        // Limit połączenia 3 s: niedostępny adres nie zatrzymuje żądania na 30 s.
        let probed = await probes.isFresh(address.id, at: moment)
        let recentlyOk = address.lastOkAt.map { moment.timeIntervalSince($0) < Self.probeValidity } ?? false
        if !probed && !recentlyOk {
            let host = Self.host(of: address)
            let started = Date()
            let reachable = await probe.canConnect(host: host.name, port: host.port, timeout: AddressOrder.connectTimeout)
            if !reachable {
                connectionLog?.request(request, address: address, ip: nil, network: conditions.label, result: "brak połączenia (limit 3 s)", started: started)
                return .failure(.network(sentBody: false, idempotent: request.method.isIdempotentRead))
            }
            await probes.remember(address.id, at: moment)
        }

        await limiter.acquire()

        let key: String
        if let apiKey {
            key = apiKey
        } else if let stored = try? secrets.read() {
            key = stored
        } else {
            return .failure(.unauthorized(ApiProblem(title: "Brak klucza API", status: 401)))
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue(key, forHTTPHeaderField: Self.apiKeyHeader)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let featureSet: ProgramCapabilities
        if let features { featureSet = features } else { featureSet = await capabilities() }
        if let value = ClientFeatures.value(for: featureSet) { urlRequest.setValue(value, forHTTPHeaderField: ClientFeatures.header) }
        if let version = request.ifMatch { urlRequest.setValue("\"\(version)\"", forHTTPHeaderField: "If-Match") }
        if let idempotencyKey = request.idempotencyKey { urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let contentType = request.contentType { urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let body = request.body { urlRequest.httpBody = body }

        let started = Date()
        let outcome = await transport.send(urlRequest, to: address, bodyFile: request.bodyFile, download: request.downloadToFile, progress: progress)
        switch outcome {
        case let .certificateRejected(decision):
            connectionLog?.request(request, address: address, ip: nil, network: conditions.label, result: "certyfikat odrzucony", started: started)
            if decision == .rejectChanged || address.trustMode == .trustedIssuer {
                await book.setHold(address.id, AddressHold(reason: .certificateChanged))
            }
            return .failure(.certificateRejected)
        case let .failure(sentBody, code):
            connectionLog?.request(request, address: address, ip: nil, network: conditions.label, result: "błąd sieci \(code.map { String($0.rawValue) } ?? "-")", started: started)
            return .failure(.network(sentBody: sentBody, idempotent: request.method.isIdempotentRead))
        case let .response(status, headers, body, file, remoteIP):
            connectionLog?.request(request, address: address, ip: remoteIP, network: conditions.label, result: "HTTP \(status)", started: started)
            await inspect(address, status: status, headers: headers, body: body, at: moment)
            if let failure = ApiFailure.map(status: status, body: body, retryAfter: headers["retry-after"], remote: address.isRemote) {
                if let file { try? FileManager.default.removeItem(at: file) }
                return .failure(failure)
            }
            return .success(ApiResponse(
                status: status, body: body, etag: headers["etag"], location: headers["location"],
                replayed: headers["idempotent-replayed"]?.lowercased() == "true", file: file
            ))
        }
    }

    /// Wstrzymania po odmowach i zapis ostatniego sukcesu.
    private func inspect(_ address: ServerAddress, status: Int, headers: [String: String], body: Data, at moment: Date) async {
        switch status {
        case 401:
            await book.setHold(address.id, AddressHold(reason: .keyRejected))
        case 403:
            let problem = ApiProblem.parse(status: 403, body: body)
            // `403` z adresu lokalnego nie jest opisany w kontrakcie — ostrożnie jak odrzucony klucz (zero ponowień).
            let reason: BlockReason = problem.isKeyHomeOnly ? .keyHomeOnly : (address.isRemote ? .remoteAccessDisabled : .keyRejected)
            await book.setHold(address.id, AddressHold(reason: reason))
        case 429:
            let seconds = ApiFailure.parseRetryAfter(headers["retry-after"])
            let reason: BlockReason = seconds > Self.silentWaitLimit ? .addressBlocked : .rateLimited
            await book.setHold(address.id, AddressHold(reason: reason, until: moment.addingTimeInterval(seconds)))
        case 200..<300:
            await book.markOk(address.id, at: moment)
        default:
            break
        }
    }

    static func host(of address: ServerAddress) -> (name: String, port: Int) {
        let checked = AddressRules(treatLoopbackAsLocal: true).check(address.url).address
        return (checked?.host ?? address.hostAndPort, checked?.port ?? (address.isHttps ? 443 : 80))
    }

    // MARK: Skróty

    public func get(_ path: String) async -> ApiResult {
        await execute(.get(path))
    }

    /// `GET /system/info`.
    public func systemInfo() async -> Result<ProgramInfo, ApiFailure> {
        switch await get("system/info") {
        case let .success(response):
            guard let info = response.decode(ProgramInfo.self) else { return .failure(.badResponse) }
            return .success(info)
        case let .failure(failure):
            return .failure(failure)
        }
    }

    /// Wszystkie strony listy (`items`, `totalCount`) — `pageSize=200`.
    public func pages(_ path: String) async -> Result<[JSONValue], ApiFailure> {
        var all: [JSONValue] = []
        var page = 1
        let separator = path.contains("?") ? "&" : "?"
        while true {
            switch await get("\(path)\(separator)page=\(page)&pageSize=\(MatchSpec.pageSize)") {
            case let .failure(failure):
                return .failure(failure)
            case let .success(response):
                guard let json = response.json else { return .failure(.badResponse) }
                let items = json["items"]?.arrayValue ?? []
                all += items
                let total = json["totalCount"]?.intValue ?? all.count
                if items.count < MatchSpec.pageSize || all.count >= total { return .success(all) }
                page += 1
            }
        }
    }
}

/// Pamięć udanych prób połączenia (sonda TCP).
actor ProbeMemory {
    private var stamps: [String: Date] = [:]

    func isFresh(_ id: String, at moment: Date) -> Bool {
        stamps[id].map { moment.timeIntervalSince($0) < ApiClient.probeValidity } ?? false
    }

    func remember(_ id: String, at moment: Date) {
        stamps[id] = moment
    }
}

extension RecordStore {
    /// Zapis bez zwiększania licznika zmian (stan techniczny: adresy, kolejka, konflikty — nie dane użytkownika).
    public func writeQuietly<T: Sendable>(_ block: @Sendable @escaping (RecordAccess) throws -> T) async throws -> T {
        try await database.writer.write { db in
            try block(RecordAccess(db: db, state: RecordAccess.WriteState()))
        }
    }
}
