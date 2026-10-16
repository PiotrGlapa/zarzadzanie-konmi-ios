import Foundation
import HorselyCore
import Security
import Testing
@testable import HorselyKit

/// Przypinanie certyfikatu (T075; zasady zaufania z contracts/android/pairing-and-connection.md).
struct TrustEvaluatorTests {
    private func trust(host: String = "stajnia.local") throws -> SecTrust {
        let der = try #require(Data(base64Encoded: TestCertificate.base64))
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, host as CFString), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    @Test func theLeafFingerprintIsUppercaseHexOfTheDerSha256() throws {
        #expect(TrustEvaluator.leafFingerprint(try trust()) == TestCertificate.fingerprint)
    }

    @Test func aMatchingFingerprintIsAcceptedWithoutCheckingTheHostName() throws {
        let evaluator = TrustEvaluator()
        #expect(evaluator.evaluate(try trust(host: "192.168.1.20"), host: "192.168.1.20", mode: .pinned, pinnedSha256: TestCertificate.fingerprint) == .accept)
        #expect(evaluator.evaluate(try trust(), host: "stajnia.local", mode: .pinned, pinnedSha256: TestCertificate.fingerprint.lowercased()) == .accept)
    }

    @Test func anotherFingerprintIsRejectedAsAChangedCertificate() throws {
        let other = String(repeating: "AB", count: 32)
        #expect(TrustEvaluator().evaluate(try trust(), host: "stajnia.local", mode: .pinned, pinnedSha256: other) == .rejectChanged)
    }

    @Test func aTrustedIssuerIsAcceptedOnlyWhenTheSystemTrustsTheCertificate() throws {
        let trusting = TrustEvaluator(systemTrusts: { _, _ in true })
        #expect(trusting.evaluate(try trust(), host: "stajnia.example.com", mode: .trustedIssuer, pinnedSha256: nil) == .accept)
        #expect(trusting.probeSummary(try trust(), host: "stajnia.example.com") == "Wystawca: stajnia.local, dla: stajnia.example.com")
    }

    @Test func aSelfSignedCertificateWithoutAKnownFingerprintIsRejected() throws {
        let system = TrustEvaluator()
        #expect(system.evaluate(try trust(), host: "stajnia.local", mode: .trustedIssuer, pinnedSha256: nil) == .reject)
        #expect(system.evaluate(try trust(), host: "stajnia.local", mode: .pinned, pinnedSha256: nil) == .reject)
        #expect(system.probeSummary(try trust(), host: "stajnia.local") == nil)
    }

    @Test func plainHttpNeverAcceptsATlsHandshake() throws {
        #expect(TrustEvaluator(systemTrusts: { _, _ in true }).evaluate(try trust(), host: "x", mode: .plainHttpConfirmed, pinnedSha256: nil) == .reject)
    }
}
