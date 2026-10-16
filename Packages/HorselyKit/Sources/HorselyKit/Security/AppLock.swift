import Foundation
import LocalAuthentication

/// Blokada aplikacji (T132, FR-TRB-09, FR-M-UST-08): zabezpieczenie telefonu (Face ID / Touch ID / kod), bez własnego PIN-u;
/// odblokowanie przy otwarciu i po powrocie po ponad 5 minutach w tle.
public enum AppLockPolicy {
    public static let timeout: TimeInterval = 5 * 60

    /// Czy po powrocie na pierwszy plan trzeba odblokować: blokada włączona i aplikacja była w tle dłużej niż 5 minut
    /// (brak zapisanego czasu — tak, np. pierwsze otwarcie).
    public static func requiresUnlock(enabled: Bool, backgroundedAt: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let backgroundedAt else { return true }
        return now.timeIntervalSince(backgroundedAt) > timeout
    }
}

/// Czy telefon ma zabezpieczenie, którym można odblokować aplikację.
public enum AppLockAvailability: Equatable, Sendable {
    case available
    /// Brak blokady ekranu (kodu urządzenia) — przełącznik nieaktywny z wyjaśnieniem.
    case noPasscode
    case unavailable
}

/// Odblokowanie zabezpieczeniem telefonu (`LocalAuthentication`, `deviceOwnerAuthentication` — biometria z kodem jako zapasowym).
public struct AppLockAuthenticator: Sendable {
    public init() {}

    public func availability() -> AppLockAvailability {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { return .available }
        if let code = error.map({ LAError.Code(rawValue: $0.code) }), code == .passcodeNotSet { return .noPasscode }
        return .unavailable
    }

    /// `true` — użytkownik potwierdził tożsamość.
    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
