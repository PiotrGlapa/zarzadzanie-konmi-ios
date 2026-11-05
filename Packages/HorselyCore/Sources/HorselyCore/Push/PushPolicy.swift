import Foundation

/// Zgoda telefonu na powiadomienia (`UNAuthorizationStatus`): `provisional` i `ephemeral` liczą się jako zgoda.
public enum PushAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed
}

/// Trwały stan rejestracji telefonu na serwerze (data-model.md §1). Pełnego tokenu FCM aplikacja nie zapisuje —
/// trzyma go SDK; tu jest tylko 8-znakowy prefiks do diagnostyki (FR-028).
public struct PushRegistration: Equatable, Sendable {
    /// Ostatni `PUT push/device` zwrócił `200` dla bieżącego klucza.
    public var registered: Bool
    public var tokenPrefix: String?
    /// Czas ostatniej udanej rejestracji — także podstawa „najwyżej raz na dobę” (FR-003).
    public var registeredAt: Date?
    /// Pierwsze niepowodzenie z bieżącej serii; `nil` po sukcesie (FR-004).
    public var failingSince: Date?
    /// `400` od serwera albo 24 h nieudanych prób (FR-005).
    public var permanentFailure: Bool
    /// `404` z `GET push/device` — jednorazowy komunikat do czasu „Rozumiem” (FR-025).
    public var deviceRemovedNotice: Bool
    /// System odmówił rejestracji do powiadomień zdalnych (APNs niedostępny, research R5).
    public var apnsRefused: Bool

    public init(
        registered: Bool = false, tokenPrefix: String? = nil, registeredAt: Date? = nil, failingSince: Date? = nil,
        permanentFailure: Bool = false, deviceRemovedNotice: Bool = false, apnsRefused: Bool = false
    ) {
        self.registered = registered
        self.tokenPrefix = tokenPrefix
        self.registeredAt = registeredAt
        self.failingSince = failingSince
        self.permanentFailure = permanentFailure
        self.deviceRemovedNotice = deviceRemovedNotice
        self.apnsRefused = apnsRefused
    }
}

/// Powód powrotu do powiadomień lokalnych (tryb awaryjny, FR-008…FR-011).
public enum PushFallbackReason: Equatable, Sendable {
    /// Serwer nie ogłasza `push` (program 1.x, push wyłączony, brak konta usługi Firebase).
    case serverHasNoPush
    /// Telefon nie może odbierać powiadomień zdalnych (APNs odmówił).
    case apnsUnavailable
    /// Serwer odrzucił rejestrację (`400`) albo 24 h bez powodzenia.
    case registrationFailed
}

/// Stan push wyliczany z danych wejściowych (data-model.md §2) — jedno źródło prawdy dla ekranu, rejestratora i planisty.
public enum PushState: Equatable, Sendable {
    /// Tryb samodzielny albo brak wyboru trybu: powiadomienia lokalne według ustawień, jak w 2.0.2.
    case standalone
    case fallback(PushFallbackReason)
    /// Telefon nie ma zgody na powiadomienia; `asked` — użytkownik już odpowiedział na pytanie systemu (odmowa), więc ekran
    /// może mówić o odmowie (FR-012a).
    case noPermission(asked: Bool)
    /// Zgoda jest, serwer ma `push`, rejestracja trwa albo nie powiodła się jeszcze na tyle, by uznać ją za błąd.
    case pending
    case registered

    /// Telefon planuje własne powiadomienia o terminach i podsumowanie (wyłącznie `registered` je wyłącza — FR-006, FR-007).
    public var localRemindersActive: Bool { self != .registered }

    /// Rejestrator próbuje tylko w tych stanach; przy `registered` — odświeżenie najwyżej raz na dobę albo przy zmianie tokenu.
    public var registrationAllowed: Bool {
        switch self {
        case .pending, .registered, .fallback(.registrationFailed): true
        default: false
        }
    }
}

/// Dane wejściowe decyzji o stanie push.
public struct PushInput: Equatable, Sendable {
    public var workMode: WorkMode
    public var serverHasPush: Bool
    public var authorization: PushAuthorization
    public var registration: PushRegistration

    public init(workMode: WorkMode, serverHasPush: Bool, authorization: PushAuthorization, registration: PushRegistration = PushRegistration()) {
        self.workMode = workMode
        self.serverHasPush = serverHasPush
        self.authorization = authorization
        self.registration = registration
    }
}

public enum PushPolicy {
    /// Warunki sprawdzane w tej kolejności (data-model.md §2): brak `push` wygrywa z brakiem zgody, brak zgody z `apnsRefused`,
    /// `apnsRefused` z `permanentFailure`.
    public static func decide(_ input: PushInput) -> PushState {
        guard input.workMode == .online else { return .standalone }
        guard input.serverHasPush else { return .fallback(.serverHasNoPush) }
        switch input.authorization {
        case .notDetermined: return .noPermission(asked: false)
        case .denied: return .noPermission(asked: true)
        case .allowed: break
        }
        if input.registration.apnsRefused { return .fallback(.apnsUnavailable) }
        if input.registration.permanentFailure { return .fallback(.registrationFailed) }
        return input.registration.registered ? .registered : .pending
    }
}
