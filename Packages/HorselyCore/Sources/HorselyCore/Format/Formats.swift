import Foundation

/// Formaty po polsku zgodne z programem (research R20): kwoty `1 250,00 zł` (separator tysięcy U+00A0 jak `N2` w .NET `pl-PL`),
/// daty `dd.MM.yyyy`, czas trwania „X h Y min”, tydzień od poniedziałku, klucz wyszukiwania bez polskich znaków.
/// Wszystko liczone ręcznie (bez `DateFormatter`/`NumberFormatter`), więc wynik nie zależy od ustawień regionalnych urządzenia
/// i jest bajt w bajt taki sam jak w Androidzie (CSV, raporty).
public enum Formats {
    public static let dash = "—"

    /// Spacja niełamliwa U+00A0 — separator tysięcy jak w programie.
    public static let thousandsSeparator = "\u{00A0}"

    /// `1 250,00 zł`; brak wartości → „—”.
    public static func money(_ amount: Money?) -> String {
        guard let amount else { return dash }
        return "\(fixed(amount.value, places: 2, grouping: true)) zł"
    }

    /// Liczba z jednym miejscem po przecinku (`3,5`).
    public static func decimal1(_ value: Money) -> String {
        fixed(value.value, places: 1, grouping: false)
    }

    public static func date(_ date: LocalDate?) -> String {
        guard let date else { return dash }
        return String(format: "%02d.%02d.%04d", date.day, date.month, date.year)
    }

    /// „Dane z …”: `05.10.2026, 10:00` (FR-M-SYN-03).
    public static func dataStamp(_ dateTime: LocalDateTime) -> String {
        "\(date(dateTime.date)), \(time(dateTime))"
    }

    public static func dateTime(_ dateTime: LocalDateTime?) -> String {
        guard let dateTime else { return dash }
        return "\(date(dateTime.date)) \(time(dateTime))"
    }

    public static func time(_ dateTime: LocalDateTime) -> String {
        String(format: "%02d:%02d", dateTime.hour, dateTime.minute)
    }

    /// „45 min”, „1 h 5 min”, „23 h 30 min”; brak lub 0 → „—”.
    public static func duration(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return dash }
        let hours = minutes / 60
        let rest = minutes % 60
        return hours == 0 ? "\(rest) min" : "\(hours) h \(rest) min"
    }

    public static func weekStart(_ date: LocalDate) -> LocalDate { date.weekStart }

    public static func weekEnd(_ date: LocalDate) -> LocalDate { date.weekEnd }

    /// Klucz wyszukiwania: małe litery bez znaków diakrytycznych („Łąka Źrebię” → „laka zrebie”).
    public static func searchKey(_ text: String) -> String {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "ł", with: "l")
        let decomposed = lower.decomposedStringWithCanonicalMapping
        return String(String.UnicodeScalarView(decomposed.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }))
    }

    // MARK: Pomocnicze

    /// Liczba z `places` miejscami po przecinku (HALF_UP jak `RoundingMode.HALF_UP` w Androidzie), przecinek dziesiętny,
    /// opcjonalnie separator tysięcy U+00A0, znak minus `-`.
    static func fixed(_ value: Decimal, places: Int, grouping: Bool) -> String {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, places, .plain)
        let negative = rounded < 0
        let plain = NSDecimalNumber(decimal: negative ? -rounded : rounded).stringValue
        let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
        var integer = String(parts[0])
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        while fraction.count < places { fraction += "0" }
        if grouping {
            var grouped = ""
            for (offset, character) in integer.reversed().enumerated() {
                if offset > 0, offset % 3 == 0 { grouped.append(contentsOf: thousandsSeparator.reversed()) }
                grouped.append(character)
            }
            integer = String(grouped.reversed())
        }
        let sign = negative && (rounded != 0) ? "-" : ""
        return places == 0 ? sign + integer : "\(sign)\(integer),\(fraction)"
    }
}
