import CryptoKit
import Foundation
import HorselyCore
import Security

/// Decyzja zaufania dla uzgodnienia TLS.
public enum TrustDecision: Equatable, Sendable {
    case accept
    /// Adres z przypiętym odciskiem, a certyfikat inny — „Certyfikat komputera się zmienił — zeskanuj nowy kod QR”.
    case rejectChanged
    /// Certyfikat nieważny / samopodpisany bez znanego odcisku / zaufany wystawca przestał się zgadzać.
    case reject
}

/// Zasady zaufania TLS (contracts/android/pairing-and-connection.md, konstytucja III):
///
/// | Sytuacja | Wynik |
/// |---|---|
/// | SHA‑256 liścia = odcisk z parowania | akceptacja, nazwa hosta nie jest sprawdzana |
/// | odcisk znany, certyfikat inny | odmowa (`CertificateChanged`) — klucz nie jest wysyłany |
/// | zaufany wystawca: certyfikat ważny wg systemowych urzędów i nazwa zgodna | akceptacja |
/// | samopodpisany bez znanego odcisku | odmowa |
///
/// Decyzja zapada w delegacie sesji **przed** wysłaniem żądania, więc odrzucony certyfikat nigdy nie dostaje klucza API.
public struct TrustEvaluator: Sendable {
    /// Ocena systemowa (urzędy certyfikacji systemu + zgodność nazwy) — wstrzykiwana w testach.
    let systemTrusts: @Sendable (SecTrust, String) -> Bool

    public init(systemTrusts: @escaping @Sendable (SecTrust, String) -> Bool = TrustEvaluator.evaluateWithSystem) {
        self.systemTrusts = systemTrusts
    }

    public func evaluate(_ trust: SecTrust, host: String, mode: TrustMode, pinnedSha256: String?) -> TrustDecision {
        switch mode {
        case .pinned:
            guard let pinned = PairingCodeParser.normalizeFingerprint(pinnedSha256) else { return .reject }
            return Self.leafFingerprint(trust) == pinned ? .accept : .rejectChanged
        case .trustedIssuer:
            return systemTrusts(trust, host) ? .accept : .reject
        case .plainHttpConfirmed:
            // Adres `http` nie powinien uzgadniać TLS — przekierowanie na `https` bez potwierdzenia jest odrzucane.
            return .reject
        }
    }

    /// Sonda adresu ręcznego bez odcisku: „Wystawca: <CN wystawcy>, dla: <nazwa>” do potwierdzenia, gdy certyfikat jest ważny
    /// wg systemu; `nil` — samopodpisany albo nieważny (odmowa).
    public func probeSummary(_ trust: SecTrust, host: String) -> String? {
        guard systemTrusts(trust, host) else { return nil }
        return Self.issuerSummary(trust, host: host)
    }

    // MARK: Certyfikaty

    public static func certificates(_ trust: SecTrust) -> [SecCertificate] {
        (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
    }

    /// SHA‑256 certyfikatu liścia: 64 znaki HEX wielkimi literami, bez separatorów (tak podaje program).
    public static func leafFingerprint(_ trust: SecTrust) -> String? {
        certificates(trust).first.map(fingerprint)
    }

    public static func fingerprint(_ certificate: SecCertificate) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined()
    }

    public static func issuerSummary(_ trust: SecTrust, host: String) -> String {
        let chain = certificates(trust)
        let issuer = chain.count > 1 ? chain[1] : chain.first
        let issuerName = issuer.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? "?"
        return "Wystawca: \(issuerName), dla: \(host)"
    }

    /// Ocena wg systemowych urzędów certyfikacji z zasadą SSL dla nazwy hosta. Certyfikaty dodane przez użytkownika nie są
    /// w iOS zaufane bez jawnego włączenia — tak jak w Androidzie.
    public static let evaluateWithSystem: @Sendable (SecTrust, String) -> Bool = { trust, host in
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        return SecTrustEvaluateWithError(trust, nil)
    }
}
