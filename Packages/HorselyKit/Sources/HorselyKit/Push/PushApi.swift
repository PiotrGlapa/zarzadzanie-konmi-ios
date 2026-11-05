import Foundation
import HorselyCore

/// Wynik wywołania API push — mapowanie `ApiFailure` na to, czego potrzebuje rejestrator (contracts/push-api-client.md).
public enum PushCallOutcome<Value: Sendable>: Sendable {
    case ok(Value)
    /// `400` — serwer odrzucił treść; tylko nazwy pól z `errors` (bez wartości, bez tokenu).
    case invalid(fields: [String])
    /// `404` — serwer nie zna tego urządzenia.
    case notRegistered
    /// Sieć, brak adresu, `5xx`, nieczytelna odpowiedź — warto spróbować później.
    case transient
    /// `401`/`403`/`429`, wstrzymany adres, odrzucony certyfikat — obsłużone już przez `ApiClient` (wstrzymanie adresu i ekran
    /// połączenia); rejestracja push nie dokłada własnego komunikatu.
    case access
}

extension PushCallOutcome: Equatable where Value: Equatable {}

/// Wywołania `push/*` programu 2.0 przez zwykły `ApiClient` (klucz API, przypinanie certyfikatu, ogranicznik, dziennik połączeń).
/// Wszystkie żądania mają `forFile: false`, więc „tylko przez Wi‑Fi” nie wyklucza adresu zewnętrznego na danych komórkowych.
/// Token FCM występuje wyłącznie w ciele `PUT` — dziennik połączeń nie zapisuje treści.
public struct PushApi: Sendable {
    /// Liczba natychmiastowych ponowień `PUT`/`DELETE` po zerwanym połączeniu (research R8).
    public static let retryOnDrop = 2

    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// `PUT push/device` — idempotentna rejestracja tokenu; `200` z urządzeniem.
    public func registerDevice(token: DeviceRegistration) async -> PushCallOutcome<PushDevice> {
        let request = ApiRequest(
            .put, "push/device", body: token.jsonData(), contentType: "application/json; charset=utf-8", forFile: false, retryOnDrop: Self.retryOnDrop
        )
        switch await client.execute(request) {
        case let .success(response):
            // Rejestracja się udała nawet wtedy, gdy treść odpowiedzi jest nieczytelna.
            return .ok(PushDevice.decode(response.body) ?? PushDevice(platform: DeviceRegistration.platform, tokenPrefix: token.prefix, registeredAt: nil))
        case let .failure(failure):
            return Self.outcome(failure)
        }
    }

    /// `DELETE push/device` — wyrejestrowanie (`204`). Wołający ignoruje każdy wynik poza logiem.
    public func unregisterDevice() async -> PushCallOutcome<Void> {
        switch await client.execute(ApiRequest(.delete, "push/device", forFile: false, retryOnDrop: Self.retryOnDrop)) {
        case .success: return .ok(())
        case let .failure(failure): return Self.outcome(failure)
        }
    }

    /// `GET push/device` — daty rejestracji i doręczeń na ekranie „Powiadomienia”; `404` → `notRegistered`.
    public func device() async -> PushCallOutcome<PushDevice> {
        switch await client.execute(ApiRequest(.get, "push/device", forFile: false)) {
        case let .success(response):
            guard let device = PushDevice.decode(response.body) else { return .transient }
            return .ok(device)
        case let .failure(failure):
            return Self.outcome(failure)
        }
    }

    /// `GET push/rules` — reguły przypisane telefonowi, w kolejności serwera.
    public func rules() async -> PushCallOutcome<[ClientPushRule]> {
        switch await client.execute(ApiRequest(.get, "push/rules", forFile: false)) {
        case let .success(response):
            guard let rules = ClientPushRule.decodeList(response.body) else { return .transient }
            return .ok(rules)
        case let .failure(failure):
            return Self.outcome(failure)
        }
    }

    static func outcome<Value: Sendable>(_ failure: ApiFailure) -> PushCallOutcome<Value> {
        switch failure {
        case let .validationFailed(problem): .invalid(fields: problem.errors.keys.sorted())
        case .notFound: .notRegistered
        case .unauthorized, .keyHomeOnly, .remoteAccessDisabled, .forbidden, .rateLimited, .suspended, .certificateRejected: .access
        default: .transient
        }
    }
}
