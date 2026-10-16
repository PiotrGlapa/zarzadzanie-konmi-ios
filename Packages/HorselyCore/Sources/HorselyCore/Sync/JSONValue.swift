import Foundation

/// Wartość JSON (treści operacji kolejki, rekordy z odpowiedzi programu, `current` z `409`). Liczby jako `Decimal` — kwoty
/// nie przechodzą przez `Double` (zasada V). Kolejność kluczy przy zapisie jest stała (`sortedKeys`).
public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .number(Decimal(value))
        } else if let value = try? container.decode(Double.self) {
            guard value.isFinite, let decimal = Decimal(string: "\(value)", locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Niepoprawna liczba"))
            }
            self = .number(decimal)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    // MARK: Odczyt

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    /// Obiekt z tekstu albo `nil`, gdy treść nie jest obiektem JSON.
    public static func object(_ data: Data) -> [String: JSONValue]? {
        guard case let .object(fields)? = try? parse(data) else { return nil }
        return fields
    }

    public static func object(_ text: String) -> [String: JSONValue]? {
        object(Data(text.utf8))
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func text() -> String {
        (try? data()).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    public subscript(key: String) -> JSONValue? {
        if case let .object(fields) = self { return fields[key] }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(fields) = self { return fields }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(items) = self { return items }
        return nil
    }

    /// Napis albo liczba jako tekst; `nil` dla `null`, obiektów i tablic.
    public var stringValue: String? {
        switch self {
        case let .string(value): value
        case let .number(value): NSDecimalNumber(decimal: value).stringValue
        case let .bool(value): value ? "true" : "false"
        default: nil
        }
    }

    public var intValue: Int? {
        switch self {
        case let .number(value): Int(NSDecimalNumber(decimal: value).int64Value)
        case let .string(value): Int(value)
        default: nil
        }
    }

    public var decimalValue: Decimal? {
        switch self {
        case let .number(value): value
        case let .string(value): Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        default: nil
        }
    }

    public var isNull: Bool { self == .null }

    // MARK: Zmiany

    /// Zamienia podnapis `from` na `to` we wszystkich napisach (odwołania do rekordów tworzonych w kolejce).
    public func replacingStrings(_ from: String, with to: String) -> JSONValue {
        switch self {
        case let .string(value): .string(value.replacingOccurrences(of: from, with: to))
        case let .array(items): .array(items.map { $0.replacingStrings(from, with: to) })
        case let .object(fields): .object(fields.mapValues { $0.replacingStrings(from, with: to) })
        default: self
        }
    }

    /// Zamienia napisy równe `from` (całe wartości) na `to` — podstawienie `id` z programu za odwołanie do rekordu z kolejki.
    public func replacingValues(_ from: String, with to: String) -> JSONValue {
        switch self {
        case let .string(value): value == from ? .string(to) : self
        case let .array(items): .array(items.map { $0.replacingValues(from, with: to) })
        case let .object(fields): .object(fields.mapValues { $0.replacingValues(from, with: to) })
        default: self
        }
    }

    /// Czy któryś napis zawiera `text`.
    public func containsString(_ text: String) -> Bool {
        switch self {
        case let .string(value): value.contains(text)
        case let .array(items): items.contains { $0.containsString(text) }
        case let .object(fields): fields.values.contains { $0.containsString(text) }
        default: false
        }
    }

    /// Obiekt bez wskazanych kluczy (np. `competitionId` — część adresu startu, nie treści).
    public func removing(_ keys: String...) -> JSONValue {
        guard case var .object(fields) = self else { return self }
        for key in keys { fields.removeValue(forKey: key) }
        return .object(fields)
    }

    /// Czy każde niepuste pole `self` ma w `other` tę samą wartość (liczby po wartości, obiekty rekurencyjnie) — rozpoznanie
    /// „program ma już moją treść” (`ConflictDetector.subset`).
    public func isSubset(of other: JSONValue?) -> Bool {
        switch self {
        case .null: return true
        case let .object(fields):
            guard case let .object(theirs)? = other else { return false }
            return fields.allSatisfy { key, value in value.isNull || value.isSubset(of: theirs[key]) }
        case let .array(items):
            guard case let .array(theirs)? = other, items.count == theirs.count else { return false }
            return zip(items, theirs).allSatisfy { $0.isSubset(of: $1) }
        default:
            guard let other else { return false }
            if self == other { return true }
            if let a = stringValue, let b = other.stringValue, a == b { return true }
            if let a = decimalValue, let b = other.decimalValue { return a == b }
            return false
        }
    }
}
