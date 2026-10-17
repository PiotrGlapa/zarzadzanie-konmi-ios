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

/// Maszyna stanów blokady aplikacji (poprawka 2.0.2, FR-001…FR-005): czysta logika w pamięci, bez `LocalAuthentication`
/// i bez zegara systemowego — czas podaje wywołujący, więc sekwencje zdarzeń sprawdzają testy pakietu.
///
/// Zimny start blokuje (proces zabity w tle zawsze startuje zablokowany), więc czasu przejścia w tło nie trzeba trwale
/// zapisywać: trwały znacznik, nigdy niezerowany, powodował ponowne blokowanie zaraz po odblokowaniu, bo okno
/// uwierzytelniania przełącza scenę `inactive → active`.
public struct AppLockMachine: Equatable, Sendable {
    public private(set) var enabled: Bool
    /// Ekran „Aplikacja zablokowana” widoczny.
    public private(set) var locked = false
    /// Zasłona w przełączniku aplikacji (aplikacja nie jest na pierwszym planie).
    public private(set) var covered = false
    /// Moment przejścia w tło po odblokowaniu; tylko w pamięci.
    public private(set) var backgroundedAt: Date?
    /// Trwa okno uwierzytelniania systemu.
    public private(set) var authenticating = false
    /// Czy ekran blokady może sam otworzyć okno uwierzytelniania — raz na epizod blokady.
    public private(set) var autoPromptAvailable = false
    /// Telefon utracił blokadę ekranu: blokada aplikacji została wyłączona i trzeba o tym poinformować.
    public private(set) var disabledNotice = false

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    /// Zimny start.
    public mutating func launch() {
        guard enabled else { return }
        lock()
    }

    /// Zmiana ustawienia „Blokada aplikacji”. Włączenie w działającej aplikacji nie blokuje bieżącej sesji
    /// (użytkownik właśnie się uwierzytelnił); wyłączenie zdejmuje blokadę i zasłonę.
    public mutating func setEnabled(_ newValue: Bool) {
        guard newValue != enabled else { return }
        enabled = newValue
        backgroundedAt = nil
        if !newValue {
            locked = false
            covered = false
            authenticating = false
            autoPromptAvailable = false
        }
    }

    public mutating func didEnterBackground(at time: Date) {
        guard enabled else { return }
        covered = true
        if !locked { backgroundedAt = time }
    }

    /// Scena przestaje być aktywna (przełącznik aplikacji, centrum powiadomień, a także okno uwierzytelniania systemu).
    public mutating func willResignActive() {
        guard enabled, !authenticating else { return }
        covered = true
    }

    public mutating func didBecomeActive(at time: Date, passcodeAvailable: Bool = true) {
        covered = false
        defer { backgroundedAt = nil }
        guard enabled else { return }
        guard passcodeAvailable else {
            enabled = false
            locked = false
            authenticating = false
            autoPromptAvailable = false
            disabledNotice = true
            return
        }
        if let backgroundedAt, AppLockPolicy.requiresUnlock(enabled: true, backgroundedAt: backgroundedAt, now: time) {
            lock()
        }
    }

    public mutating func authenticationStarted() {
        guard locked, !authenticating else { return }
        authenticating = true
        autoPromptAvailable = false
    }

    public mutating func authenticationFinished(success: Bool) {
        authenticating = false
        guard success else { return }
        locked = false
        backgroundedAt = nil
    }

    public mutating func acknowledgeNotice() {
        disabledNotice = false
    }

    private mutating func lock() {
        locked = true
        autoPromptAvailable = true
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
