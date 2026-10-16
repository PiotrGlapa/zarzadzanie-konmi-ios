import Foundation
import HorselyCore

/// Szczegółowy dziennik połączeń (FR-029/FR-030): wpis na każde żądanie do programu — metoda, ścieżka **bez zapytania**,
/// `host:port`, IP z metryk, adres lokalny/zewnętrzny, sieć, wynik i czas trwania; także adresy pominięte bez żądania.
/// Bez klucza API i bez treści wpisów (konstytucja II). Włączany na ograniczony czas w ustawieniach połączenia
/// (`connectionLog.until`); wpisy trafiają do dziennika diagnostycznego (kategoria „połączenie”).
public final class ConnectionLog: Sendable {
    public static let category = "połączenie"

    private let log: DiagnosticLog
    private let enabled: @Sendable () -> Bool

    public init(log: DiagnosticLog, enabled: @escaping @Sendable () -> Bool) {
        self.log = log
        self.enabled = enabled
    }

    /// Dziennik włączony do chwili zapisanej w ustawieniach.
    public static func isEnabled(until: String?, now: Date = Date()) -> Bool {
        guard let until, let moment = RefreshPlan.parseInstant(until) else { return false }
        return now < moment
    }

    public var isEnabled: Bool { enabled() }

    func request(_ request: ApiRequest, address: ServerAddress, ip: String?, network: String, result: String, started: Date) {
        guard enabled() else { return }
        let millis = Int(Date().timeIntervalSince(started) * 1000)
        log.log(Self.category, Self.line(
            method: request.method.rawValue, path: request.pathWithoutQuery, hostPort: address.hostAndPort, ip: ip, remote: address.isRemote,
            network: network, result: result, millis: millis
        ))
    }

    func skipped(_ reason: String, address: ServerAddress?, network: String) {
        guard enabled() else { return }
        let target = address.map { "\($0.hostAndPort) (\($0.isRemote ? "zewnętrzny" : "lokalny"))" } ?? "-"
        log.log(Self.category, "pominięto \(target): \(reason), sieć: \(network)")
    }

    func note(_ text: String, address: ServerAddress, network: String) {
        guard enabled() else { return }
        log.log(Self.category, "\(text) \(address.hostAndPort), sieć: \(network)")
    }

    /// Wynik sprawdzenia jednego adresu („Sprawdź połączenie”).
    public func check(address: ServerAddress, result: String, network: String) {
        guard enabled() else { return }
        log.log(Self.category, "sprawdzenie \(address.hostAndPort) (\(address.isRemote ? "zewnętrzny" : "lokalny")): \(result), sieć: \(network)")
    }

    /// Jedna linia wpisu: `GET /horses 192.168.1.20:5080 [192.168.1.20] lokalny, Wi‑Fi → HTTP 200, 84 ms`.
    static func line(method: String, path: String, hostPort: String, ip: String?, remote: Bool, network: String, result: String, millis: Int) -> String {
        let shownPath = path.hasPrefix("/") ? path : "/" + path
        return "\(method) \(shownPath) \(hostPort) [\(ip ?? "-")] \(remote ? "zewnętrzny" : "lokalny"), \(network) → \(result), \(millis) ms"
    }
}
