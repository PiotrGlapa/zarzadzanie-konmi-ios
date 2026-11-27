import Foundation

/// Chwile UTC w JSON (`Instant` z Androida → `Date`): odczyt `yyyy-MM-ddTHH:mm:ss[.ułamek](Z|±HH:mm)` i zapis jak `Instant.toString()`
/// (`2026-09-01T07:02:11Z`, ułamek w grupach po 3 cyfry: `.482Z`, `.482113Z`). Dokładność — mikrosekundy (`Date` to `Double`).
public enum InstantText {
    /// Chwila z tekstu; `nil` bez strefy albo dla innego kształtu.
    public static func parse(_ text: String) -> Date? {
        var offsetSeconds = 0
        if text.hasSuffix("Z") || text.hasSuffix("z") {
            offsetSeconds = 0
        } else if text.count >= 6 {
            let zone = text.suffix(6)
            let parts = zone.dropFirst().split(separator: ":", omittingEmptySubsequences: false)
            guard let sign = zone.first, sign == "+" || sign == "-", parts.count == 2, parts[0].count == 2, parts[1].count == 2,
                  let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
            offsetSeconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        } else {
            return nil
        }
        guard let local = LocalDateTime(text) else { return nil }
        return date(local, offsetSeconds: offsetSeconds)
    }

    /// Zapis chwili w UTC jak `Instant.toString()` w Javie.
    public static func format(_ date: Date) -> String {
        let local = localDateTime(date)
        var text = local.date.description + String(format: "T%02d:%02d:%02d", local.hour, local.minute, local.second)
        let micros = local.nanosecond / 1000
        if micros != 0 {
            text += micros % 1000 == 0 ? String(format: ".%03d", micros / 1000) : String(format: ".%06d", micros)
        }
        return text + "Z"
    }

    /// Chwila jako czas lokalny UTC (kolumny magazynu); ułamek zaokrąglony do mikrosekund.
    public static func localDateTime(_ date: Date) -> LocalDateTime {
        let interval = date.timeIntervalSince1970
        var seconds = Int(interval.rounded(.down))
        var micros = Int(((interval - Double(seconds)) * 1_000_000).rounded())
        if micros >= 1_000_000 {
            seconds += 1
            micros -= 1_000_000
        }
        let days = Int((Double(seconds) / 86_400).rounded(.down))
        let secondOfDay = seconds - days * 86_400
        return LocalDateTime(
            date: LocalDate(dayNumber: days),
            hour: secondOfDay / 3600,
            minute: secondOfDay % 3600 / 60,
            second: secondOfDay % 60,
            nanosecond: micros * 1000
        )!
    }

    /// Chwila z czasu lokalnego UTC (`LocalDateTime` rekordu → `Date` nagrania).
    public static func date(_ local: LocalDateTime) -> Date {
        date(local, offsetSeconds: 0)
    }

    private static func date(_ local: LocalDateTime, offsetSeconds: Int) -> Date {
        let seconds = local.date.dayNumber * 86_400 + local.hour * 3600 + local.minute * 60 + local.second - offsetSeconds
        return Date(timeIntervalSince1970: Double(seconds) + Double(local.nanosecond) / 1_000_000_000)
    }

    /// `Instant.EPOCH` — czasy nowego, jeszcze niewysłanego nagrania.
    public static let epoch = Date(timeIntervalSince1970: 0)
}

public extension LocalDateTime {
    /// Czas nieznany (`UNKNOWN_TIME` z Androida, 1970-01-01T00:00) — profil konia i ustawienia jazd bez czasów z serwera.
    static let unknownTime = LocalDateTime(year: 1970, month: 1, day: 1)!
}
