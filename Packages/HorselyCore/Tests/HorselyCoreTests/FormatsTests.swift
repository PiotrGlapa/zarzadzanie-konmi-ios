import Foundation
import Testing
@testable import HorselyCore

/// Przypadki z `FormatsTest`, `MoneyInputTest` i `StarsTest` z Androida 2.0.1 (T015): wynik musi być identyczny.
struct FormatsTests {
    private let nbsp = "\u{00A0}"

    private func money(_ text: String) -> Money { Money(string: text)! }

    // MARK: Kwoty

    @Test func moneyUsesNonBreakingSpaceAndDecimalComma() {
        #expect(Formats.money(money("1250")) == "1\(nbsp)250,00 zł")
        #expect(Formats.money(money("0.5")) == "0,50 zł")
        #expect(Formats.money(money("-3336.12")) == "-3\(nbsp)336,12 zł")
        #expect(Formats.money(.zero) == "0,00 zł")
        #expect(Formats.money(money("1234567.89")) == "1\(nbsp)234\(nbsp)567,89 zł")
        #expect(Formats.money(money("999")) == "999,00 zł")
    }

    @Test func moneyRoundsHalfUp() {
        #expect(Formats.money(money("2.345")) == "2,35 zł")
        #expect(Formats.money(money("2.344")) == "2,34 zł")
    }

    @Test func missingMoneyIsADash() {
        #expect(Formats.money(nil) == "—")
    }

    @Test func decimalWithOnePlaceUsesAComma() {
        #expect(Formats.decimal1(money("3.5")) == "3,5")
        #expect(Formats.decimal1(money("52.50")) == "52,5")
        #expect(Formats.decimal1(money("2")) == "2,0")
    }

    // MARK: Daty i czas

    @Test func dataStampHasACommaBetweenDateAndTime() {
        #expect(Formats.dataStamp(LocalDateTime(year: 2026, month: 10, day: 5, hour: 9, minute: 5)!) == "05.10.2026, 09:05")
    }

    @Test func dateIsDdMmYyyy() {
        #expect(Formats.date(LocalDate(year: 2026, month: 10, day: 5)) == "05.10.2026")
        #expect(Formats.date(nil) == "—")
    }

    @Test func durationIsShownInHoursAndMinutes() {
        #expect(Formats.duration(minutes: 45) == "45 min")
        #expect(Formats.duration(minutes: 60) == "1 h 0 min")
        #expect(Formats.duration(minutes: 65) == "1 h 5 min")
        #expect(Formats.duration(minutes: 1410) == "23 h 30 min")
        #expect(Formats.duration(minutes: 59) == "59 min")
    }

    @Test func durationOfNilOrZeroIsADash() {
        #expect(Formats.duration(minutes: nil) == "—")
        #expect(Formats.duration(minutes: 0) == "—")
    }

    @Test func theWeekStartsOnMonday() {
        // 2026-09-23 to środa; poniedziałek tego tygodnia to 2026-09-21, niedziela 2026-09-27.
        let wednesday = LocalDate(year: 2026, month: 9, day: 23)!
        #expect(Formats.weekStart(wednesday) == LocalDate(year: 2026, month: 9, day: 21))
        #expect(Formats.weekEnd(wednesday) == LocalDate(year: 2026, month: 9, day: 27))
        #expect(Formats.weekStart(LocalDate(year: 2026, month: 9, day: 21)!) == LocalDate(year: 2026, month: 9, day: 21))
        #expect(Formats.weekStart(LocalDate(year: 2026, month: 9, day: 27)!) == LocalDate(year: 2026, month: 9, day: 21))
        #expect(Formats.weekStart(LocalDate(year: 2026, month: 9, day: 28)!) == LocalDate(year: 2026, month: 9, day: 28))
    }

    @Test func searchKeyIgnoresCaseAndPolishDiacritics() {
        #expect(Formats.searchKey("Łąka Źrebię") == "laka zrebie")
        #expect(Formats.searchKey("  GROMEK ") == "gromek")
        #expect(Formats.searchKey("Żółć") == "zolc")
        #expect(Formats.searchKey("") == "")
    }

    // MARK: Wprowadzanie kwot

    private func amount(_ text: String) -> Money? {
        if case let .valid(value) = MoneyInput.parse(text) { return value }
        return nil
    }

    private func reason(_ text: String) -> MoneyParse.Reason? {
        if case let .invalid(reason) = MoneyInput.parse(text) { return reason }
        return nil
    }

    @Test func aDecimalCommaAndADecimalPointAreBothAccepted() {
        #expect(amount("350,5") == money("350.50"))
        #expect(amount("350.5") == money("350.50"))
        #expect(amount("350") == money("350"))
        #expect(amount(",99") == money("0.99"))
        #expect(amount("12,") == money("12"))
    }

    @Test func thousandSeparatorsAreIgnored() {
        #expect(amount("1 250,00") == money("1250"))
        #expect(amount("1\u{00A0}250") == money("1250"))
        #expect(amount("1\u{202F}234\u{202F}567,89") == money("1234567.89"))
    }

    @Test func anEmptyFieldIsNotAnError() {
        #expect(MoneyInput.parse("") == .empty)
        #expect(MoneyInput.parse("   ") == .empty)
    }

    @Test func atMostTwoDecimalPlacesAreAllowed() {
        #expect(reason("3,333") == .tooManyDecimals)
        #expect(amount("3,300") == money("3.30"))
    }

    @Test func negativeValuesAndTextAreRefused() {
        #expect(reason("-5") == .negative)
        #expect(reason("abc") == .notANumber)
        #expect(reason("1,2,3") == .notANumber)
        #expect(reason("12zł") == .notANumber)
        #expect(reason(".") == .notANumber)
    }

    @Test func theContractLimitIsTenMillion() {
        #expect(amount("10000000") == money("10000000"))
        #expect(reason("10000000,01") == .tooLarge)
    }

    @Test func aStoredAmountIsShownWithADecimalComma() {
        #expect(MoneyInput.format(money("350")) == "350,00")
        #expect(MoneyInput.format(money("1250.5")) == "1250,50")
        #expect(MoneyInput.format(nil) == "")
    }

    @Test func plainDecimalsKeepTheirScale() {
        #expect(MoneyInput.parseDecimal("2,5") == .valid(money("2.5")))
        #expect(MoneyInput.parseDecimal("0,12345") == .invalid(.tooManyDecimals))
    }

    // MARK: Gwiazdki

    @Test func aRatingIsShownAsFilledStarsFollowedByEmptyOnes() {
        #expect(Stars.format(3) == "★★★☆☆")
        #expect(Stars.format(5) == "★★★★★")
        #expect(Stars.format(1) == "★☆☆☆☆")
        #expect(Stars.format(4) == "★★★★☆")
    }

    @Test func noRatingAndValuesOutsideOneToFiveHaveNoStars() {
        #expect(Stars.format(nil) == nil)
        #expect(Stars.format(0) == nil)
        #expect(Stars.format(6) == nil)
        #expect(Stars.format(-2) == nil)
    }
}

struct LocalDateTests {
    @Test func parsesAndPrintsIsoDates() {
        let date = LocalDate("2026-10-05")
        #expect(date == LocalDate(year: 2026, month: 10, day: 5))
        #expect(date?.description == "2026-10-05")
        #expect(LocalDate("2026-02-30") == nil)
        #expect(LocalDate("2026-1-5") == nil)
    }

    @Test func arithmeticCrossesMonthsAndLeapYears() {
        let date = LocalDate(year: 2024, month: 2, day: 28)!
        #expect(date.adding(days: 1) == LocalDate(year: 2024, month: 2, day: 29))
        #expect(date.adding(days: 2) == LocalDate(year: 2024, month: 3, day: 1))
        #expect(LocalDate(year: 2026, month: 1, day: 31)!.adding(months: 1) == LocalDate(year: 2026, month: 2, day: 28))
        #expect(LocalDate(year: 2026, month: 1, day: 15)!.adding(months: -2) == LocalDate(year: 2025, month: 11, day: 15))
        #expect(LocalDate(year: 2026, month: 10, day: 5)!.days(since: LocalDate(year: 2026, month: 9, day: 28)!) == 7)
    }

    @Test func weekdaysAreCorrect() {
        #expect(LocalDate(year: 1970, month: 1, day: 1)!.weekday == .thursday)
        #expect(LocalDate(year: 2026, month: 10, day: 5)!.weekday == .monday)
        #expect(LocalDate(year: 2026, month: 10, day: 11)!.weekday == .sunday)
    }

    @Test func dayNumberRoundTrips() {
        for offset in stride(from: -800_000, through: 800_000, by: 997) {
            let date = LocalDate(dayNumber: offset)
            #expect(date.dayNumber == offset)
        }
    }

    @Test func dateTimeToleratesZoneAndFraction() {
        #expect(LocalDateTime("2026-09-28T10:00:00Z")?.description == "2026-09-28T10:00:00")
        #expect(LocalDateTime("2026-09-30T14:30:00")?.description == "2026-09-30T14:30:00")
        #expect(LocalDateTime("2026-09-30T14:30:00.5+02:00")?.description == "2026-09-30T14:30:00.5")
        #expect(LocalDateTime("2026-09-30T14:30")?.description == "2026-09-30T14:30:00")
        #expect(LocalDateTime("2026-09-30T25:00:00") == nil)
    }
}
