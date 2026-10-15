import Foundation

/// Źródło „dziś” i „teraz” wstrzykiwane do logiki (research R20): reguły terminów, Pulpit i powiadomienia nie czytają zegara
/// systemowego wprost, więc testy i zrzuty ekranów działają na stałej dacie (np. 2026-10-05).
public protocol DateProvider: Sendable {
    func today() -> LocalDate
    func now() -> LocalDateTime
}

/// Zegar systemu w lokalnej strefie urządzenia.
public struct SystemDateProvider: DateProvider {
    public init() {}

    public func now() -> LocalDateTime {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: Date())
        return LocalDateTime(
            date: LocalDate(year: parts.year!, month: parts.month!, day: parts.day!)!,
            hour: parts.hour!, minute: parts.minute!, second: parts.second!, nanosecond: 0
        )!
    }

    public func today() -> LocalDate { now().date }
}

/// Stała chwila — testy, zrzuty ekranów, argument uruchomienia `-UITestToday`.
public struct FixedDateProvider: DateProvider {
    public let moment: LocalDateTime

    public init(_ moment: LocalDateTime) {
        self.moment = moment
    }

    /// Stały dzień, południe.
    public init(today: LocalDate) {
        self.moment = LocalDateTime(date: today, hour: 12, minute: 0)!
    }

    public func now() -> LocalDateTime { moment }
    public func today() -> LocalDate { moment.date }
}
