import Foundation

/// Rodzaj wiadomości push z serwera (klucz `type` w danych wiadomości, contracts/push-message.md).
public enum PushKind: Equatable, Sendable {
    case reminder
    case summary
    case backup
    case analytic
    case test
    /// Rodzaj nieznany tej wersji — wiadomość jest pokazana, a dotknięcie otwiera Pulpit.
    case other(String)

    init(type: String) {
        switch type {
        case "reminder": self = .reminder
        case "summary": self = .summary
        case "backup": self = .backup
        case "analytic": self = .analytic
        case "test": self = .test
        default: self = .other(type)
        }
    }
}

/// Wiadomość z serwera odczytana z `userInfo` powiadomienia (data-model.md §6). Wiadomość z serwera ma klucz `type`;
/// powiadomienia lokalne mają klucz `link` i nie mają `type`. Klucze `aps`, `gcm.*`, `google.*` i nieznane są pomijane;
/// tytuł i treść (`aps.alert`) nie są czytane — nigdy nie trafiają do dziennika (FR-028).
public struct PushMessage: Equatable, Sendable {
    public let kind: PushKind
    public let reminderId: String?
    public let horseId: String?
    /// Data, której dotyczy wiadomość; zła data (np. `2026-13-01`) — `nil`.
    public let targetDate: LocalDate?

    /// `nil`, gdy w danych nie ma napisu `type` (to nie jest wiadomość z serwera).
    public init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String, !type.isEmpty else { return nil }
        kind = PushKind(type: type)
        reminderId = Self.text(userInfo["reminderId"])
        horseId = Self.text(userInfo["horseId"])
        targetDate = Self.text(userInfo["targetDate"]).flatMap { LocalDate($0) }
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}
