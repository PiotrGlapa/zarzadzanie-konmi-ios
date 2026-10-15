import Foundation

/// Kwota (i inne liczby dziesiętne programu: ilość, cena jednostkowa, punkty, wynik w %) jako `Decimal` — nigdy `Double`
/// (zasada V). Odczyt z JSON przechodzi przez najkrótszy zapis dziesiętny liczby, więc `0.1` zostaje dokładnie `0.1`.
public struct Money: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var value: Decimal

    public init(_ value: Decimal) {
        self.value = value
    }

    public init(_ integer: Int) {
        self.value = Decimal(integer)
    }

    /// `"12.50"`, `"-3"`; zawsze z kropką dziesiętną (niezależnie od ustawień regionalnych).
    public init?(string: String) {
        guard let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        self.value = decimal
    }

    public static let zero = Money(Decimal.zero)

    /// Zaokrąglenie do liczby miejsc po przecinku „jak program”: połowa od zera w górę (HALF_UP, jak w Androidzie i programie).
    public func rounded(places: Int = 2) -> Money {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, places, .plain)
        return Money(result)
    }

    /// Zapis z kropką bez notacji naukowej, np. `"1250.5"`.
    public var description: String {
        NSDecimalNumber(decimal: value).stringValue
    }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.value < rhs.value }
    public static func + (lhs: Money, rhs: Money) -> Money { Money(lhs.value + rhs.value) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(lhs.value - rhs.value) }
    public static func * (lhs: Money, rhs: Money) -> Money { Money(lhs.value * rhs.value) }
    public static prefix func - (operand: Money) -> Money { Money(-operand.value) }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(Int64.self) {
            self.value = Decimal(integer)
            return
        }
        let double = try container.decode(Double.self)
        guard double.isFinite, let decimal = Decimal(string: "\(double)", locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Niepoprawna kwota: \(double)"))
        }
        self.value = decimal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
