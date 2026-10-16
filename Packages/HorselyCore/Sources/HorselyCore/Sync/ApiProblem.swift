import Foundation

/// `application/problem+json` programu (RFC 9457: `Problem`, `ValidationProblem`, `ConflictProblem`). `errors` mapuje klucze pól
/// (także z kropką, np. `coaching.trainerContactId`) na komunikaty po polsku, które pokazujemy przy polach formularza.
public struct ApiProblem: Codable, Hashable, Sendable {
    public static let keyHomeOnlySuffix = "/errors/key-home-only"
    public static let idempotencyInProgressSuffix = "/errors/idempotency-key-in-progress"
    public static let idempotencyReusedSuffix = "/errors/idempotency-key-reused"

    public static let empty = ApiProblem()

    public var type: String?
    public var title: String?
    public var status: Int?
    public var detail: String?
    public var errors: [String: [String]]
    public var warnings: [String: [String]]
    public var reason: String?
    /// Aktualna wersja rekordu (dla `VersionMismatch`).
    public var current: JSONValue?

    public init(
        type: String? = nil, title: String? = nil, status: Int? = nil, detail: String? = nil, errors: [String: [String]] = [:],
        warnings: [String: [String]] = [:], reason: String? = nil, current: JSONValue? = nil
    ) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
        self.errors = errors
        self.warnings = warnings
        self.reason = reason
        self.current = current
    }

    private enum CodingKeys: String, CodingKey { case type, title, status, detail, errors, warnings, reason, current }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        status = try? c.decodeIfPresent(Int.self, forKey: .status)
        detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        errors = (try? c.decodeIfPresent([String: [String]].self, forKey: .errors)) ?? [:]
        warnings = (try? c.decodeIfPresent([String: [String]].self, forKey: .warnings)) ?? [:]
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        current = try? c.decodeIfPresent(JSONValue.self, forKey: .current)
    }

    /// Odczyt treści błędu; pusta lub niepoprawna treść daje problem tylko ze statusem (np. `403` bez treści).
    public static func parse(status: Int, body: Data?) -> ApiProblem {
        guard let body, !body.isEmpty, var parsed = try? JSONDecoder().decode(ApiProblem.self, from: body) else { return ApiProblem(status: status) }
        if parsed.status == nil { parsed.status = status }
        return parsed
    }

    public var conflictReason: ConflictReason? { reason.flatMap(ConflictReason.init(rawValue:)) }

    private func typeEnds(with suffix: String) -> Bool {
        guard var text = type else { return false }
        while text.hasSuffix("/") { text.removeLast() }
        return text.hasSuffix(suffix)
    }

    /// `403` z typem `…/key-home-only`.
    public var isKeyHomeOnly: Bool { typeEnds(with: Self.keyHomeOnlySuffix) }
    /// `409` `…/idempotency-key-in-progress`: pierwsze żądanie z tym kluczem jeszcze trwa — ponów po odstępie.
    public var isIdempotencyKeyInProgress: Bool { typeEnds(with: Self.idempotencyInProgressSuffix) }
    /// `422` `…/idempotency-key-reused`: klucz użyty wcześniej z inną treścią — „Wymaga poprawy”.
    public var isIdempotencyKeyReused: Bool { typeEnds(with: Self.idempotencyReusedSuffix) }

    /// Komunikat do pokazania: szczegóły albo tytuł programu; `nil`, gdy program nic nie podał.
    public var message: String? {
        if let detail, !detail.trimmingCharacters(in: .whitespaces).isEmpty { return detail }
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        return nil
    }

    /// Problem z tytułem domyślnym, gdy program nie podał komunikatu.
    public func withDefaultTitle(_ text: String) -> ApiProblem {
        guard message == nil else { return self }
        var copy = self
        copy.title = text
        return copy
    }

    /// Pierwszy komunikat: przy polu, potem szczegóły/tytuł.
    public var firstMessage: String? {
        errors.sorted { $0.key < $1.key }.first?.value.first ?? message
    }
}
