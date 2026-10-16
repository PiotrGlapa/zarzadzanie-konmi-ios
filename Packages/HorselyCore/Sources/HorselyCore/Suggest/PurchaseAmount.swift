import Foundation

/// Kwota zakupu i „Razem” (FR-M-WPI-04).
public enum PurchaseAmount {
    /// Kwota zakupu = ilość × cena jednostkowa, zaokrąglona w górę od połowy do grosza; brak ilości albo ceny — brak podpowiedzi.
    public static func suggest(quantity: Money?, unitPrice: Money?) -> Money? {
        guard let quantity, let unitPrice else { return nil }
        return (quantity * unitPrice).rounded(places: 2)
    }

    /// „Razem” = kwota + koszt dostawy; bez kwoty nie ma sumy.
    public static func total(amount: Money?, delivery: Money?) -> Money? {
        guard let amount else { return nil }
        return (amount + (delivery ?? .zero)).rounded(places: 2)
    }
}

/// Stan podpowiedzi kwoty zakupu: dopóki użytkownik nie zmieni kwoty ręcznie, ilość × cena nadpisuje pole; po ręcznej zmianie
/// podpowiedź jest wyłączona i kwota zostaje taka, jaką wpisał.
public struct AmountSuggestion: Sendable {
    private var manual = false

    public init() {}

    public mutating func onManualEdit() { manual = true }

    /// Zwraca tekst, który ma być w polu kwoty (`current` — dotychczasowy tekst z przecinkiem dziesiętnym).
    public func apply(current: String, quantity: String, unitPrice: String) -> String {
        if manual { return current }
        guard case let .valid(q) = MoneyInput.parseDecimal(quantity), case let .valid(p) = MoneyInput.parseDecimal(unitPrice),
              let suggested = PurchaseAmount.suggest(quantity: q, unitPrice: p) else { return current }
        return MoneyInput.format(suggested)
    }
}
