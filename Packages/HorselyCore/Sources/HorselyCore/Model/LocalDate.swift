import Foundation

/// Dzień tygodnia; poniedziałek = 1 (tydzień polski, jak w programie).
public enum Weekday: Int, Sendable, CaseIterable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
}

/// Data kalendarzowa bez strefy (`yyyy-MM-dd`) — zasada V konstytucji: dat programu nie przelicza się przez strefę urządzenia.
/// Obliczenia na liczbie dni od 1970-01-01 (algorytm „civil from days”), bez `Calendar`.
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Zwraca `nil` dla daty nieistniejącej (np. 31 kwietnia).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= LocalDate.daysIn(month: month, year: year) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Data z liczby dni od 1970-01-01 (może być ujemna).
    public init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.year = year
        self.month = month
        self.day = day
    }

    /// `yyyy-MM-dd`; `nil` dla innego kształtu lub daty nieistniejącej.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Liczba dni od 1970-01-01.
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthIndex = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public var weekday: Weekday {
        // 1970-01-01 był czwartkiem.
        let index = ((dayNumber % 7) + 7 + 3) % 7
        return Weekday(rawValue: index + 1)!
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(dayNumber: dayNumber + days)
    }

    /// Dodaje miesiące; dzień ograniczany do długości miesiąca wynikowego (31 stycznia + 1 miesiąc = 28/29 lutego).
    public func adding(months: Int) -> LocalDate {
        let total = year * 12 + (month - 1) + months
        let newYear = Int((Double(total) / 12).rounded(.down))
        let newMonth = total - newYear * 12 + 1
        return LocalDate(year: newYear, month: newMonth, day: min(day, LocalDate.daysIn(month: newMonth, year: newYear)))!
    }

    /// Liczba dni od [other] do tej daty (dodatnia, gdy ta data jest późniejsza).
    public func days(since other: LocalDate) -> Int {
        dayNumber - other.dayNumber
    }

    /// Poniedziałek tygodnia tej daty.
    public var weekStart: LocalDate { adding(days: -(weekday.rawValue - 1)) }

    public var weekEnd: LocalDate { weekStart.adding(days: 6) }

    public var firstOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1)! }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let date = LocalDate(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Niepoprawna data: \(text)"))
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Data i czas lokalny bez strefy (`2026-09-30T14:30:00`). Przy odczycie toleruje ułamki sekund i pomija przesunięcie strefy
/// (`Z`, `+02:00`) — czas urządzenia nie decyduje o danych programu (zasada V).
public struct LocalDateTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let date: LocalDate
    public let hour: Int
    public let minute: Int
    public let second: Int
    /// Część ułamkowa sekundy w nanosekundach (zachowana, żeby zapis i odczyt nie zmieniały wartości).
    public let nanosecond: Int

    public init?(date: LocalDate, hour: Int, minute: Int, second: Int = 0, nanosecond: Int = 0) {
        guard (0..<24).contains(hour), (0..<60).contains(minute), (0..<60).contains(second), (0..<1_000_000_000).contains(nanosecond) else { return nil }
        self.date = date
        self.hour = hour
        self.minute = minute
        self.second = second
        self.nanosecond = nanosecond
    }

    public init?(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) {
        guard let date = LocalDate(year: year, month: month, day: day) else { return nil }
        self.init(date: date, hour: hour, minute: minute, second: second)
    }

    /// `yyyy-MM-ddTHH:mm[:ss[.fraction]][Z|±HH:mm]`; strefa jest pomijana.
    public init?(_ text: String) {
        guard let separator = text.firstIndex(where: { $0 == "T" || $0 == " " }), let date = LocalDate(String(text[..<separator])) else { return nil }
        var rest = Substring(text[text.index(after: separator)...])
        if rest.hasSuffix("Z") || rest.hasSuffix("z") {
            rest = rest.dropLast()
        } else if let sign = rest.lastIndex(where: { $0 == "+" || $0 == "-" }), rest.distance(from: sign, to: rest.endIndex) >= 3 {
            rest = rest[..<sign]
        }
        let clock = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard clock.count >= 2, clock.count <= 3, let hour = Int(clock[0]), let minute = Int(clock[1]) else { return nil }
        var second = 0
        var nanosecond = 0
        if clock.count == 3 {
            let secondPart = clock[2].split(separator: ".", omittingEmptySubsequences: false)
            guard let parsedSecond = Int(secondPart[0]) else { return nil }
            second = parsedSecond
            if secondPart.count == 2 {
                let digits = String(secondPart[1].prefix(9))
                guard !digits.isEmpty, let fraction = Int(digits) else { return nil }
                nanosecond = fraction * Int(pow(10, Double(9 - digits.count)))
            } else if secondPart.count > 2 {
                return nil
            }
        }
        self.init(date: date, hour: hour, minute: minute, second: second, nanosecond: nanosecond)
    }

    /// Jak `LocalDateTime.toString()` w Javie / ISO_LOCAL_DATE_TIME w programie: sekundy zawsze, ułamek tylko gdy niezerowy.
    public var description: String {
        var text = date.description + String(format: "T%02d:%02d:%02d", hour, minute, second)
        if nanosecond != 0 {
            var fraction = String(format: "%09d", nanosecond)
            while fraction.hasSuffix("0") { fraction.removeLast() }
            text += "." + fraction
        }
        return text
    }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        (lhs.date, lhs.hour, lhs.minute, lhs.second, lhs.nanosecond) < (rhs.date, rhs.hour, rhs.minute, rhs.second, rhs.nanosecond)
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let value = LocalDateTime(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Niepoprawna data i czas: \(text)"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

