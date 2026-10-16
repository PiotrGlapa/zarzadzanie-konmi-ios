import Foundation

/// Komunikaty reguł — dosłowne teksty z zasobów programu (`ValidationMessages.resx`, `AppTexts.resx`), żeby błąd w trybie
/// samodzielnym brzmiał tak samo jak odpowiedź programu (contracts/android/rules-parity.md). Zmiana tekstu w programie = czerwony
/// test zgodności. Port `Messages.kt` z Androida 2.0.1 (kolejne komunikaty dochodzą z regułami wpisów w fazie 4).
public enum Messages {
    public static let required = "Pole jest wymagane."
    public static func maxLength(_ max: Int) -> String { "Maksymalna długość to \(max) znaków." }
    public static let parentIsDeleted = "Nie można przywrócić rekordu, ponieważ rekord nadrzędny jest w koszu. Najpierw przywróć rekord nadrzędny."
    public static let uniqueViolation = "Rekord o takiej wartości już istnieje."
    public static let dateInFuture = "Data nie może być z przyszłości."
    public static let uelnFormat = "UELN zwykle ma 15 znaków (cyfry i wielkie litery). Sprawdź numer."
    public static let microchipFormat = "Numer chipa zwykle ma 15 cyfr. Sprawdź numer."
    public static let farrierIntervalRange = "Interwał kowalski musi mieścić się w zakresie 1–26 tygodni."
    public static let statusDateRequired = "Podaj datę zmiany statusu."
    public static let statusDateBeforeBirth = "Data statusu nie może być wcześniejsza niż data urodzenia."
    public static let passportNotUnique = "Koń z tym numerem paszportu już istnieje."
    public static let foalNameNotUnique = "Źrebak bez paszportu o tym imieniu już istnieje — nadaj inne imię albo wpisz numer paszportu."
    public static let horseRevived = "Koń miał status „Padł”. Upewnij się, że przywrócenie statusu „Aktywny” jest zamierzone."
    public static let moneyInvalid = "Kwota musi być nieujemna, mieć najwyżej 2 miejsca po przecinku i nie przekraczać 10 000 000,00 zł."
    public static let horsePhotoInvalid = "Zdjęciem konia może być tylko obraz z jego załączników."
    public static let purchaseBeforeBirth = "Data zakupu jest wcześniejsza niż data urodzenia konia."
    public static let saleBeforePurchase = "Data sprzedaży jest wcześniejsza niż data zakupu."
    public static let invalidValue = "Nieprawidłowa wartość."
    public static let recordChanged = "Rekord został zmieniony w międzyczasie."
}

/// Wynik walidacji pól: błędy blokują zapis, ostrzeżenia nie. Klucze pól jak w odpowiedzi programu (`finance.purchasePrice`, `name`…).
public struct ValidationReport: Equatable, Sendable {
    public private(set) var errors: [String: [String]] = [:]
    public private(set) var warnings: [String: [String]] = [:]
    /// Kolejność pierwszego wystąpienia pól z błędem — do ustawienia fokusu na pierwszym błędzie.
    public private(set) var errorOrder: [String] = []

    public init() {}

    public var hasErrors: Bool { !errors.isEmpty }

    public mutating func error(_ field: String, _ message: String) {
        if errors[field] == nil { errorOrder.append(field) }
        var list = errors[field] ?? []
        if !list.contains(message) { list.append(message) }
        errors[field] = list
    }

    public mutating func warning(_ field: String, _ message: String) {
        var list = warnings[field] ?? []
        if !list.contains(message) { list.append(message) }
        warnings[field] = list
    }

    /// `NotEmpty()` dla tekstu: brak, pusty albo same spacje.
    mutating func notBlank(_ field: String, _ value: String?) {
        if value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { error(field, Messages.required) }
    }

    mutating func maxLength(_ field: String, _ value: String?, _ max: Int) {
        if let value, value.count > max { error(field, Messages.maxLength(max)) }
    }

    /// Kwota w PLN: ≥ 0, najwyżej 2 miejsca po przecinku, ≤ 10 000 000,00 (`MoneyRules`).
    mutating func money(_ field: String, _ value: Money?) {
        if let value, !ValidationReport.isValidMoney(value) { error(field, Messages.moneyInvalid) }
    }

    mutating func futureDate(_ field: String, _ value: LocalDate?, today: LocalDate, message: String = Messages.dateInFuture) {
        if let value, value > today { error(field, message) }
    }

    public static func isValidMoney(_ value: Money) -> Bool {
        guard value.value >= 0, value.value <= Decimal(10_000_000) else { return false }
        return value.rounded(places: 2) == value
    }
}
