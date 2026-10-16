import Foundation

/// Porządek tekstów jak w programie: polskie litery po swoich podstawowych (ą po a, ł po l, ż po z), wielkość liter bez znaczenia,
/// ogonki znaczące (odpowiednik `StringComparer.Create(pl-PL, ignoreCase: true)`).
public enum PolishNames {
    private static let locale = Locale(identifier: "pl_PL")

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.caseInsensitive], range: nil, locale: locale)
    }

    public static func isOrdered(_ lhs: String, before rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    /// Porządek listy koni: wielkość liter jako rozstrzygnięcie remisu (jak `Collator` z domyślną siłą w Androidzie).
    public static func compareForList(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [], range: nil, locale: locale)
    }
}

extension String {
    /// `NOCASE` SQLite: wielkość liter ignorowana tylko dla liter ASCII (`Łania` ≠ `łania`) — tak program porównuje paszporty
    /// i wartości słowników.
    var asciiFolded: String {
        String(unicodeScalars.map { scalar in
            (scalar.value >= 65 && scalar.value <= 90) ? Character(UnicodeScalar(scalar.value + 32)!) : Character(scalar)
        })
    }
}
