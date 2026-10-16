import Foundation

/// Dane z kodu QR parowania (contracts/android/pairing-and-connection.md). `key` jest tajny — opis tekstowy go nie ujawnia.
public struct PairingCode: Equatable, Sendable, CustomStringConvertible {
    /// Adres lokalny (`url`): `https`, albo `http` tylko dla sieci lokalnej; znormalizowany, kończy się `/api/v1`.
    public let url: CheckedAddress
    public let key: String
    /// Odcisk SHA‑256 certyfikatu: 64 znaki HEX wielkimi literami; `nil`, gdy HTTPS wyłączone.
    public let certSha256: String?
    /// Adres zdalny (`remoteUrl`) — tylko `https`; dodawany jako drugi adres.
    public let remoteUrl: CheckedAddress?

    public init(url: CheckedAddress, key: String, certSha256: String?, remoteUrl: CheckedAddress?) {
        self.url = url
        self.key = key
        self.certSha256 = certSha256
        self.remoteUrl = remoteUrl
    }

    public var description: String {
        "PairingCode(url=\(url.baseUrl), key=***, certSha256=\(certSha256 ?? "nil"), remoteUrl=\(remoteUrl?.baseUrl ?? "nil"))"
    }
}

public enum PairingCodeError: String, Error, Equatable, Sendable {
    case notAPairingCode
    case badAddress
    case badFingerprint

    public var message: String {
        switch self {
        case .notAPairingCode: "To nie jest kod parowania z programu Horsely"
        case .badAddress: "Kod parowania zawiera niepoprawny adres programu"
        case .badFingerprint: "Kod parowania zawiera niepoprawny odcisk certyfikatu"
        }
    }
}

/// Parser kodu QR (`PairingCode.kt`): nieznane pola są ignorowane, kod nieczytelny lub niekompletny daje `notAPairingCode`.
public struct PairingCodeParser: Sendable {
    public static let keyPrefix = "hk_"
    private static let fingerprintLength = 64

    private let rules: AddressRules

    public init(rules: AddressRules = .default) {
        self.rules = rules
    }

    public func parse(_ text: String) -> Result<PairingCode, PairingCodeError> {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\u{FEFF}") { trimmed.removeFirst() }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any]
        else { return .failure(.notAPairingCode) }

        guard let urlText = Self.string(fields["url"]) else { return .failure(.notAPairingCode) }
        guard let key = Self.string(fields["key"]), key.hasPrefix(Self.keyPrefix), key.count > Self.keyPrefix.count else { return .failure(.notAPairingCode) }
        guard let url = rules.check(urlText).address else { return .failure(.badAddress) }

        var fingerprint: String?
        if let raw = fields["certSha256"], !(raw is NSNull) {
            guard let normalized = Self.normalizeFingerprint(Self.string(raw)) else { return .failure(.badFingerprint) }
            fingerprint = normalized
        }

        var remote: CheckedAddress?
        if let raw = fields["remoteUrl"], !(raw is NSNull) {
            guard let remoteText = Self.string(raw), let checked = rules.check(remoteText, remoteQr: true).address else { return .failure(.badAddress) }
            remote = checked
        }
        return .success(PairingCode(url: url, key: key, certSha256: fingerprint, remoteUrl: remote))
    }

    /// 64 znaki `[0-9A-Fa-f]` → wielkie litery; inaczej `nil` (bez separatorów — tak podaje program).
    public static func normalizeFingerprint(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespaces), value.count == fingerprintLength,
              value.allSatisfy({ $0.isHexDigit && $0.isASCII })
        else { return nil }
        return value.uppercased()
    }

    /// Niepusty napis JSON; liczby i inne typy to brak wartości.
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !(value is NSNumber) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
