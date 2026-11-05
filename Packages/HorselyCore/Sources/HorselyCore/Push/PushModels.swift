import Foundation

/// Ciało `PUT push/device`: wyłącznie platforma i token (FR-030) — nic więcej o telefonie ani o koniach.
public struct DeviceRegistration: Encodable, Equatable, Sendable {
    public static let platform = "Ios"
    public static let maxTokenLength = 4096

    public let token: String

    /// `nil` dla tokenu pustego, dłuższego niż 4096 znaków albo z białymi znakami — traktowane jak brak tokenu (research R7).
    public init?(token: String) {
        guard Self.isValid(token) else { return nil }
        self.token = token
    }

    public static func isValid(_ token: String) -> Bool {
        !token.isEmpty && token.count <= maxTokenLength && !token.contains { $0.isWhitespace }
    }

    private enum CodingKeys: String, CodingKey { case platform, token }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.platform, forKey: .platform)
        try container.encode(token, forKey: .token)
    }

    /// JSON w stałej kolejności kluczy: `{"platform":"Ios","token":"…"}`.
    public func jsonData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// 8 pierwszych znaków tokenu — jedyna jego część, która trafia do ustawień i dziennika (FR-028).
    public var prefix: String { String(token.prefix(8)) }
}

/// Urządzenie z `GET push/device` (data-model.md §4). Dekodowanie tolerancyjne: nieznane pola pomijane, brak daty — `nil`.
public struct PushDevice: Equatable, Sendable {
    public let platform: String
    public let tokenPrefix: String
    public let registeredAt: Date?
    public let lastSeenAt: Date?
    public let lastDeliveredAt: Date?

    public init(platform: String, tokenPrefix: String, registeredAt: Date?, lastSeenAt: Date? = nil, lastDeliveredAt: Date? = nil) {
        self.platform = platform
        self.tokenPrefix = tokenPrefix
        self.registeredAt = registeredAt
        self.lastSeenAt = lastSeenAt
        self.lastDeliveredAt = lastDeliveredAt
    }

    /// `nil`, gdy treść nie jest obiektem JSON.
    public static func decode(_ data: Data) -> PushDevice? {
        guard let fields = JSONValue.object(data) else { return nil }
        return PushDevice(
            platform: fields["platform"]?.stringValue ?? "", tokenPrefix: fields["tokenPrefix"]?.stringValue ?? "",
            registeredAt: instant(fields["registeredAt"]), lastSeenAt: instant(fields["lastSeenAt"]),
            lastDeliveredAt: instant(fields["lastDeliveredAt"])
        )
    }

    private static func instant(_ value: JSONValue?) -> Date? {
        guard case let .string(text)? = value else { return nil }
        return PushInstant.parse(text)
    }
}

/// Czas z serwera (.NET): do 7 cyfr ułamka sekundy, np. `2026-11-04T10:15:00.0000000Z` (research R17).
/// `ISO8601DateFormatter` nie przyjmuje każdej liczby cyfr, więc ułamek jest sprowadzany do 3 cyfr przed odczytem.
public enum PushInstant {
    public static func parse(_ text: String) -> Date? {
        RefreshPlan.parseInstant(normalized(text))
    }

    static func normalized(_ text: String) -> String {
        guard let dot = text.firstIndex(of: ".") else { return text }
        let afterDot = text.index(after: dot)
        var end = afterDot
        while end < text.endIndex, text[end].isASCII, text[end].isNumber { end = text.index(after: end) }
        let digits = String(text[afterDot ..< end])
        guard !digits.isEmpty else { return text }
        let fixed = String((digits + "000").prefix(3))
        return String(text[text.startIndex ..< afterDot]) + fixed + String(text[end...])
    }
}

/// Reguła przypisana telefonowi (`GET push/rules`, data-model.md §5). Ekran pokazuje tylko `description`, w kolejności z serwera
/// (FR-023); pozostałe pola służą diagnostyce. Nieznany `type` jest zachowany jako napis.
public struct ClientPushRule: Equatable, Sendable {
    public let id: String
    public let type: String
    public let reminderKind: String?
    public let offsetDays: Int?
    public let sendTime: String?
    public let repeatTime: String?
    public let description: String

    public init(id: String, type: String, reminderKind: String? = nil, offsetDays: Int? = nil, sendTime: String? = nil, repeatTime: String? = nil, description: String) {
        self.id = id
        self.type = type
        self.reminderKind = reminderKind
        self.offsetDays = offsetDays
        self.sendTime = sendTime
        self.repeatTime = repeatTime
        self.description = description
    }

    /// Lista reguł z odpowiedzi; element bez niepustego `description` jest pomijany i nie przerywa listy.
    /// `nil`, gdy treść nie jest tablicą JSON.
    public static func decodeList(_ data: Data) -> [ClientPushRule]? {
        guard let json = try? JSONValue.parse(data), let items = json.arrayValue else { return nil }
        return items.compactMap(rule)
    }

    private static func rule(_ item: JSONValue) -> ClientPushRule? {
        guard case let .string(description)? = item["description"],
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ClientPushRule(
            id: item["id"]?.stringValue ?? "", type: item["type"]?.stringValue ?? "", reminderKind: item["reminderKind"]?.stringValue,
            offsetDays: item["offsetDays"]?.intValue, sendTime: item["sendTime"]?.stringValue, repeatTime: item["repeatTime"]?.stringValue,
            description: description
        )
    }
}
