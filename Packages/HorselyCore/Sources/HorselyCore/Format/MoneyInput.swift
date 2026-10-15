import Foundation

/// Wynik odczytu kwoty wpisanej w polu formularza.
public enum MoneyParse: Equatable, Sendable {
    /// Pole puste (brak kwoty).
    case empty
    case valid(Money)
    case invalid(Reason)

    public enum Reason: Equatable, Sendable {
        case notANumber
        case negative
        case tooManyDecimals
        case tooLarge

        public var message: String {
            switch self {
            case .notANumber: "Wpisz kwotę cyframi, np. 350 albo 350,50"
            case .negative: "Kwota nie może być ujemna"
            case .tooManyDecimals: "Kwota może mieć najwyżej dwa miejsca po przecinku"
            case .tooLarge: "Kwota jest za duża"
            }
        }
    }
}

/// Odczyt kwoty z pola tekstowego (polska klawiatura): przecinek albo kropka jako separator dziesiętny, spacje (także niełamliwe)
/// jako separator tysięcy. Wynik ma skalę 2 (`350` → `350.00`). To wygoda — walidację rozstrzyga program (zasada I); limity z kontraktu:
/// ≥ 0, najwyżej 2 miejsca po przecinku, ≤ 10 000 000.
public enum MoneyInput {
    public static let max = Money(10_000_000)

    private static let spaces: Set<Character> = [" ", "\u{00A0}", "\u{202F}", "\t", "\n", "\r"]

    private static func normalize(_ text: String) -> String {
        String(text.filter { !spaces.contains($0) })
    }

    /// Ciąg cyfr z co najwyżej jednym separatorem dziesiętnym → liczba; `nil`, gdy to nie liczba.
    private static func number(_ cleaned: String) -> Decimal? {
        let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
        let dots = normalized.filter { $0 == "." }.count
        guard dots <= 1, normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), normalized != "." else { return nil }
        var text = normalized
        if text.hasPrefix(".") { text = "0" + text }
        if text.hasSuffix(".") { text.removeLast() }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Liczba miejsc po przecinku bez zer końcowych.
    private static func significantScale(_ value: Decimal) -> Int {
        let text = NSDecimalNumber(decimal: value).stringValue
        guard let dot = text.firstIndex(of: ".") else { return 0 }
        var fraction = text[text.index(after: dot)...]
        while fraction.hasSuffix("0") { fraction = fraction.dropLast() }
        return fraction.count
    }

    public static func parse(_ text: String) -> MoneyParse {
        let cleaned = normalize(text)
        if cleaned.isEmpty { return .empty }
        if cleaned.hasPrefix("-") { return .invalid(.negative) }
        guard let value = number(cleaned) else { return .invalid(.notANumber) }
        if significantScale(value) > 2 { return .invalid(.tooManyDecimals) }
        let amount = Money(value).rounded(places: 2)
        if amount > max { return .invalid(.tooLarge) }
        return .valid(amount)
    }

    /// Liczba dziesiętna bez zaokrąglania do groszy (ilość, cena jednostkowa): do `maxScale` miejsc po przecinku, nieujemna.
    public static func parseDecimal(_ text: String, maxScale: Int = 4) -> MoneyParse {
        let cleaned = normalize(text)
        if cleaned.isEmpty { return .empty }
        if cleaned.hasPrefix("-") { return .invalid(.negative) }
        guard let value = number(cleaned) else { return .invalid(.notANumber) }
        if significantScale(value) > maxScale { return .invalid(.tooManyDecimals) }
        return .valid(Money(value))
    }

    /// Tekst do pola z zapisanej kwoty: `350.00` → `350,00`; brak → pusty.
    public static func format(_ amount: Money?) -> String {
        guard let amount else { return "" }
        return Formats.fixed(amount.value, places: 2, grouping: false)
    }
}
