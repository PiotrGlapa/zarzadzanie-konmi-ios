import Foundation

/// Zasada zaufania adresu (konstytucja III, data-model.md §2): przypięty odcisk, zaufany wystawca albo potwierdzony jawny `http`
/// w sieci lokalnej. Nazwy są wartościami kolumny `address.trustMode`.
public enum TrustMode: String, Codable, Sendable, CaseIterable {
    case pinned = "Pinned"
    case trustedIssuer = "TrustedIssuer"
    case plainHttpConfirmed = "PlainHttpConfirmed"
}

/// Powód wstrzymania adresu. `keyRejected`, `keyHomeOnly`, `remoteAccessDisabled` i `certificateChanged` trwają do działania
/// użytkownika (FR-M-POL-12); `rateLimited` i `addressBlocked` wygasają z upływem `until`.
public enum BlockReason: String, Codable, Sendable, CaseIterable {
    case keyRejected = "KeyRejected"
    case keyHomeOnly = "KeyHomeOnly"
    case remoteAccessDisabled = "RemoteAccessDisabled"
    case rateLimited = "RateLimited"
    case addressBlocked = "AddressBlocked"
    case certificateChanged = "CertificateChanged"

    /// Odmowa wymagająca działania użytkownika (czerwona ikonka); `rateLimited` to ciche odczekanie.
    public var needsUser: Bool { self != .rateLimited }
}

/// Stan wstrzymania adresu: `reason == nil` — aktywny. Każdy inny stan to zero żądań do adresu (SC-M-08).
public struct AddressHold: Equatable, Sendable {
    public var reason: BlockReason?
    public var until: Date?

    public static let active = AddressHold()

    public init(reason: BlockReason? = nil, until: Date? = nil) {
        self.reason = reason
        self.until = until
    }

    /// Czy żądania są teraz zablokowane — z uwzględnieniem upływu czasu wstrzymania.
    public func isBlocked(at now: Date) -> Bool {
        guard reason != nil else { return false }
        guard let until else { return true }
        return now < until
    }
}

/// Adres programu (tabela `address`). `isRemote` — adres spoza sieci lokalnej (literał hosta, `AddressRules`), `position` —
/// kolejność prób (adres `remoteUrl` z QR jest drugi).
public struct ServerAddress: Equatable, Sendable, Identifiable {
    public var id: String
    public var url: String
    public var position: Int
    public var trustMode: TrustMode
    /// Odcisk SHA‑256 liścia (HEX wielkimi literami) dla `pinned`.
    public var certSha256: String?
    /// „Wystawca: <CN>, dla: <nazwa>” potwierdzony przez użytkownika (`trustedIssuer`).
    public var issuerSummary: String?
    public var isRemote: Bool
    public var lastOkAt: Date?
    public var hold: AddressHold

    public init(
        id: String, url: String, position: Int, trustMode: TrustMode, certSha256: String? = nil, issuerSummary: String? = nil,
        isRemote: Bool, lastOkAt: Date? = nil, hold: AddressHold = .active
    ) {
        self.id = id
        self.url = url
        self.position = position
        self.trustMode = trustMode
        self.certSha256 = certSha256
        self.issuerSummary = issuerSummary
        self.isRemote = isRemote
        self.lastOkAt = lastOkAt
        self.hold = hold
    }

    public var isLocal: Bool { !isRemote }
    public var isHttps: Bool { url.lowercased().hasPrefix("https://") }

    /// `host:port` do dziennika połączeń i ekranów (bez ścieżki).
    public var hostAndPort: String {
        let rest = url.components(separatedBy: "://").last ?? url
        return rest.split(separator: "/", maxSplits: 1).first.map(String.init) ?? rest
    }
}

/// Kolejność prób adresów (`AddressSelector.kt`, contracts/android/pairing-and-connection.md): ostatnio działający pierwszy,
/// potem pozostałe wg `position`. Adresy wstrzymane są pomijane — zero żądań do nich (SC-M-08).
public enum AddressOrder {
    /// Limit połączenia na adres (research R6).
    public static let connectTimeout: TimeInterval = 3

    public static func order(_ addresses: [ServerAddress], now: Date) -> [ServerAddress] {
        let usable = addresses.filter { !$0.hold.isBlocked(at: now) }
        let lastWorking = usable.filter { $0.lastOkAt != nil }.max { $0.lastOkAt! < $1.lastOkAt! }
        let rest = usable.filter { $0.id != lastWorking?.id }.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
        return (lastWorking.map { [$0] } ?? []) + rest
    }

    /// Adresy zablokowane w tej chwili — do komunikatu, gdy nie ma żadnego aktywnego.
    public static func blocked(_ addresses: [ServerAddress], now: Date) -> [ServerAddress] {
        addresses.filter { $0.hold.isBlocked(at: now) }
    }
}
