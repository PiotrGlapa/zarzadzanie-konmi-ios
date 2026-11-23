// Zaokrąglanie HALF_UP „od zera" na `Decimal`.
// Odpowiednik Androida `RoundingMode.HALF_UP` z odchyleniem od zera — przy remisie (0,5) oddala od zera.

import Foundation

/// Enum zaokrągleń HALF_UP „od zera" — równoważnik Androida `RoundingMode.HALF_UP` z odchyleniem od zera.
public enum HalfUp {
    /// Zaokrągla `value` do `scale` miejsc po przecinku, HALF_UP „od zera".
    /// Przykład: `2.345` → `2.35`, `-2.345` → `-2.35`, `2.5` → `3`.
    public static func round(_ value: Decimal, scale: Int) -> Decimal {
        let handler = NSDecimalNumberHandler(roundingMode: .plain, scale: scale, raiseOnExact: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        let number = NSDecimalNumber(decimal: value)
        return number.decimalNumber(byRoundingAgainst: handler).decimalValue
    }
}
