import Foundation
import HorselyCore

/// Opisy słowami do dziennika diagnostycznego (kategoria `push`, FR-028): po polsku, bez nazw typów Swift i **bez** pełnego
/// tokenu, tytułu, treści ani identyfikatorów wiadomości — tylko 8-znakowy prefiks tokenu i rodzaj wiadomości.
public enum PushDiagnostics {
    public static let category = "push"

    public static let noToken = "brak tokenu FCM"
    public static let apnsRefused = "APNs odmówił rejestracji"
    public static let unreadableResponse = "nieczytelna odpowiedź serwera"

    public static func registered(prefix: String) -> String { "rejestracja ok token=\(prefix)…" }

    public static func registrationFailed(_ reason: String) -> String { "rejestracja nieudana: \(reason)" }

    public static func registrationRejected(fields: [String]) -> String {
        "rejestracja odrzucona przez serwer (400): \(fields.isEmpty ? "bez szczegółów" : fields.joined(separator: ", "))"
    }

    public static func message(kind: PushKind) -> String { "wiadomość type=\(name(of: kind))" }

    public static func unregistered(_ result: String) -> String { "wyrejestrowanie: \(result)" }

    public static func name(of kind: PushKind) -> String {
        switch kind {
        case .reminder: "reminder"
        case .summary: "summary"
        case .backup: "backup"
        case .analytic: "analytic"
        case .test: "test"
        // Nieznany rodzaj zapisujemy jako „other” — treść `type` pochodzi z sieci, więc nie trafia do dziennika.
        case .other: "other"
        }
    }

    /// `ApiFailure` → opis po polsku (nigdy nazwa typu ani treść odpowiedzi).
    public static func describe(_ failure: ApiFailure) -> String {
        switch failure {
        case let .network(sentBody, _): sentBody ? "brak połączenia (zerwane połączenie)" : "brak połączenia"
        case .noNetwork: "telefon bez sieci"
        case .noUsableAddress: "brak dostępnego adresu serwera"
        case let .serverError(status, _): "serwer odpowiedział błędem \(status)"
        case .badResponse: unreadableResponse
        case .validationFailed: "serwer odrzucił treść (400)"
        case .notFound: "serwer nie zna urządzenia (404)"
        case .unauthorized: "klucz odrzucony przez serwer"
        case .keyHomeOnly, .remoteAccessDisabled, .forbidden: "dostęp zabroniony"
        case .rateLimited: "serwer ogranicza liczbę żądań"
        case .suspended: "adres serwera wstrzymany"
        case .certificateRejected: "certyfikat serwera odrzucony"
        default: "nieoczekiwana odpowiedź serwera"
        }
    }
}
