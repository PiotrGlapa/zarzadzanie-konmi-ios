import Foundation
import HorselyCore

/// Odpowiedź programu ze statusem sukcesu.
public struct ApiResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data
    /// `ETag` (np. `"3"`) — wersja rekordu do `If-Match`.
    public let etag: String?
    public let location: String?
    /// `Idempotent-Replayed: true` — program zwrócił zapamiętaną odpowiedź dla tego samego `Idempotency-Key`.
    public let replayed: Bool
    /// Plik z treścią (pobranie eksportu); usuwa go wołający.
    public let file: URL?

    public init(status: Int, body: Data = Data(), etag: String? = nil, location: String? = nil, replayed: Bool = false, file: URL? = nil) {
        self.status = status
        self.body = body
        self.etag = etag
        self.location = location
        self.replayed = replayed
        self.file = file
    }

    public var json: JSONValue? { try? JSONValue.parse(body) }

    public func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: body)
    }
}

/// Każdy wynik inny niż sukces; błędy programu i sieci są wartościami (mapowanie wg contracts/android/outbox-operations.md
/// i pairing-and-connection.md).
public enum ApiFailure: Error, Equatable, Sendable {
    /// `400` — błędy walidacji przy polach.
    case validationFailed(ApiProblem)
    /// `409` — konflikt wersji / unikalności / użycia / stanu / klucza idempotencji w toku.
    case conflict(ApiProblem)
    case notFound(ApiProblem)
    case payloadTooLarge(ApiProblem)
    case unsupportedMediaType(ApiProblem)
    /// `422` — np. `…/idempotency-key-reused`.
    case unprocessable(ApiProblem)
    /// `401` — klucz odrzucony.
    case unauthorized(ApiProblem)
    /// `403` z typem `key-home-only`.
    case keyHomeOnly(ApiProblem)
    /// `403` bez treści z adresu nielokalnego.
    case remoteAccessDisabled
    /// Inny `403`.
    case forbidden(ApiProblem)
    /// `429` — sekundy z `Retry-After`.
    case rateLimited(retryAfter: TimeInterval, ApiProblem)
    /// Pozostałe `4xx`/`5xx`.
    case serverError(status: Int, ApiProblem)
    /// Błąd sieci. `sentBody` — treść żądania wysłana, odpowiedzi brak (wynik nieznany); `idempotent` — odczyt (GET).
    case network(sentBody: Bool, idempotent: Bool)
    /// Żądanie nie wyszło: adres wstrzymany — zero ruchu do działania użytkownika lub upływu `Retry-After`.
    case suspended(BlockReason, until: Date?)
    /// Certyfikat adresu nie przeszedł weryfikacji — klucz nie został wysłany.
    case certificateRejected
    /// Odpowiedź, której nie da się odczytać.
    case badResponse
    /// Brak adresu, z którego można teraz skorzystać.
    case noUsableAddress
    /// Telefon nie ma sieci — żądania nie są wysyłane.
    case noNetwork

    /// Problem programu (dla odpowiedzi z treścią).
    public var problem: ApiProblem? {
        switch self {
        case let .validationFailed(p), let .conflict(p), let .notFound(p), let .payloadTooLarge(p), let .unsupportedMediaType(p), let .unprocessable(p),
             let .unauthorized(p), let .keyHomeOnly(p), let .forbidden(p), let .rateLimited(_, p), let .serverError(_, p):
            return p
        default:
            return nil
        }
    }

    /// Błąd, po którym program odpowiedział (stan połączenia: „komputer odpowiada”).
    public var programAnswered: Bool {
        switch self {
        case .network, .suspended, .certificateRejected, .noUsableAddress, .noNetwork: false
        default: true
        }
    }

    /// Błąd zatrzymujący odświeżanie i kolejkę (brak sieci, odmowa, wstrzymanie).
    public var stopsWork: Bool {
        switch self {
        case .network, .unauthorized, .keyHomeOnly, .remoteAccessDisabled, .rateLimited, .suspended, .certificateRejected, .noUsableAddress, .noNetwork: true
        default: false
        }
    }

    /// Mapowanie odpowiedzi odmownej; dla statusów sukcesu — `nil`.
    /// - Parameter remote: adres nielokalny (rozpoznanie `403`).
    public static func map(status: Int, body: Data, retryAfter: String?, remote: Bool) -> ApiFailure? {
        guard status >= 400 else { return nil }
        let problem = ApiProblem.parse(status: status, body: body)
        switch status {
        case 400: return .validationFailed(problem)
        case 401: return .unauthorized(problem)
        case 403:
            if problem.isKeyHomeOnly { return .keyHomeOnly(problem) }
            if remote && body.isEmpty { return .remoteAccessDisabled }
            return .forbidden(problem)
        case 404: return .notFound(problem)
        case 409: return .conflict(problem)
        case 413: return .payloadTooLarge(problem)
        case 415: return .unsupportedMediaType(problem)
        case 422: return .unprocessable(problem)
        case 429: return .rateLimited(retryAfter: parseRetryAfter(retryAfter), problem)
        default: return .serverError(status: status, problem)
        }
    }

    /// `Retry-After` w sekundach; brak lub niepoprawna wartość → 60 s (ostrożne wstrzymanie bez pętli).
    public static func parseRetryAfter(_ value: String?) -> TimeInterval {
        guard let value, let seconds = Int(value.trimmingCharacters(in: .whitespaces)) else { return defaultRetryAfter }
        return TimeInterval(max(seconds, 1))
    }

    public static let defaultRetryAfter: TimeInterval = 60
}

public typealias ApiResult = Result<ApiResponse, ApiFailure>

/// Metoda HTTP żądania do programu.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"

    public var isIdempotentRead: Bool { self == .get }
}

/// Żądanie do programu: ścieżka względem `/api/v1/` (z zapytaniem), treść JSON albo plik (`multipart/form-data`).
public struct ApiRequest: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var body: Data?
    public var contentType: String?
    /// Treść z pliku (wysyłka załącznika) — strumieniowo, bez wczytywania do pamięci.
    public var bodyFile: URL?
    /// `If-Match: "<wersja>"`.
    public var ifMatch: Int?
    /// `Idempotency-Key` (= `id` operacji kolejki).
    public var idempotencyKey: String?
    /// Wysyłka pliku: „tylko przez Wi‑Fi” wyklucza adresy nielokalne w sieci z limitem.
    public var forFile: Bool
    /// Pobranie do pliku (eksport) z postępem.
    public var downloadToFile: Bool

    public init(
        _ method: HTTPMethod, _ path: String, body: Data? = nil, contentType: String? = nil, bodyFile: URL? = nil, ifMatch: Int? = nil,
        idempotencyKey: String? = nil, forFile: Bool = false, downloadToFile: Bool = false
    ) {
        self.method = method
        self.path = path
        self.body = body
        self.contentType = contentType
        self.bodyFile = bodyFile
        self.ifMatch = ifMatch
        self.idempotencyKey = idempotencyKey
        self.forFile = forFile
        self.downloadToFile = downloadToFile
    }

    public static func get(_ path: String) -> ApiRequest { ApiRequest(.get, path) }

    public static func json(_ method: HTTPMethod, _ path: String, _ value: JSONValue, ifMatch: Int? = nil, idempotencyKey: String? = nil) -> ApiRequest {
        ApiRequest(method, path, body: try? value.data(), contentType: "application/json; charset=utf-8", ifMatch: ifMatch, idempotencyKey: idempotencyKey)
    }

    /// Ścieżka bez zapytania — do dziennika połączeń (FR-030).
    public var pathWithoutQuery: String {
        path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    }
}
