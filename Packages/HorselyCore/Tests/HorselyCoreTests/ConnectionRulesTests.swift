import Foundation
import Testing
@testable import HorselyCore

/// Reguły adresów, kod QR i wersje programu (T071; przypadki z `AddressRulesTest`, `PairingCodeTest`, `ProgramVersionTest`).
struct ConnectionRulesTests {
    private let rules = AddressRules()
    private let parser = PairingCodeParser()
    private let fingerprint = "3F9A" + String(repeating: "C1", count: 30)

    // MARK: Adresy

    @Test func privateRangesAndDotLocalNamesAreLocal() {
        for host in ["10.0.0.5", "172.16.0.1", "172.31.255.255", "192.168.1.20", "169.254.1.1", "[fd00::1]", "fd00::1", "[fe80::1]", "fe80::1%wlan0",
                     "komputer.local", "KOMPUTER.LOCAL", "stajnia.moj.local"] {
            #expect(rules.isLocalHost(host), "powinien być lokalny: \(host)")
        }
    }

    @Test func publicAddressesAndOtherNamesAreNotLocal() {
        for host in ["172.32.0.1", "172.15.255.255", "100.64.0.1", "203.0.113.25", "8.8.8.8", "stajnia.dyndns.org", "stajnia.lan", "localhost",
                     "localhost.localdomain", "local", ".local", "127.0.0.1", "[::1]", "2001:db8::1", "192.169.1.1", "11.0.0.1", "10.0.0", "10.0.0.256",
                     "komputer.local.example.com", "", "ta-nazwa-nie-istnieje-zk-test.invalid", "2001:0db8:85a3::8a2e:370:7334"] {
            #expect(!rules.isLocalHost(host), "nie powinien być lokalny: '\(host)'")
        }
    }

    @Test func httpIsAcceptedOnlyForLocalAddresses() {
        let local = rules.check("http://192.168.1.20:5080/api/v1").address
        #expect(local?.isLocal == true)
        #expect(local?.isHttps == false)
        #expect(rules.check("http://stajnia.lan:5080/api/v1").reason == .insecureNonLocal)
        #expect(rules.check("http://stajnia.dyndns.org/api/v1").reason == .insecureNonLocal)
        #expect(rules.check("http://203.0.113.25:5080/api/v1").reason == .insecureNonLocal)
        #expect(rules.check("http://100.64.0.1:5080/api/v1").reason == .insecureNonLocal)
        #expect(rules.check("https://100.64.0.1:5080/api/v1").address != nil)
    }

    @Test func httpsIsAcceptedForAnyHost() {
        let remote = rules.check("https://stajnia.dyndns.org:48123/api/v1").address
        #expect(remote?.isLocal == false)
        #expect(remote?.isHttps == true)
        #expect(remote?.baseUrl == "https://stajnia.dyndns.org:48123/api/v1")
    }

    @Test func theAddressIsNormalised() {
        #expect(rules.check("192.168.1.20:5080").address?.baseUrl == "https://192.168.1.20:5080/api/v1")
        #expect(rules.check("  https://192.168.1.20:5080/api/v1/  ").address?.baseUrl == "https://192.168.1.20:5080/api/v1")
        #expect(rules.check("http://komputer.local:5080").address?.baseUrl == "http://komputer.local:5080/api/v1")
        #expect(rules.check("https://stajnia.example.com").address?.baseUrl == "https://stajnia.example.com/api/v1")
        #expect(rules.check("https://[fd00::1]:5080/api/v1").address?.baseUrl == "https://[fd00::1]:5080/api/v1")
        #expect(rules.check("HTTPS://Stajnia.Example.com/API/V1").address?.baseUrl == "https://stajnia.example.com/api/v1")
    }

    @Test func aDifferentPathOrSchemeOrGarbageIsRejected() {
        #expect(rules.check("https://192.168.1.20/inne").reason == .malformed)
        #expect(rules.check("ftp://192.168.1.20/api/v1").reason == .unsupportedScheme)
        #expect(rules.check("").reason == .malformed)
        #expect(rules.check("https://").reason == .malformed)
        #expect(rules.check("https://192.168.1.20:99999/api/v1").reason == .malformed)
    }

    @Test func theRemoteAddressFromAQrCodeMustBeHttps() {
        #expect(rules.check("https://stajnia.dyndns.org:48123/api/v1", remoteQr: true).address != nil)
        #expect(rules.check("http://192.168.1.20:5080/api/v1", remoteQr: true).reason == .remoteMustBeHttps)
    }

    @Test func loopbackIsLocalOnlyWhenTheTestSwitchIsOn() {
        #expect(!AddressRules().isLocalHost("127.0.0.1"))
        #expect(AddressRules(treatLoopbackAsLocal: true).isLocalHost("127.0.0.1"))
        #expect(AddressRules(treatLoopbackAsLocal: true).isLocalHost("[::1]"))
    }

    // MARK: Kod QR

    private func valid(_ json: String) -> PairingCode? {
        if case let .success(code) = parser.parse(json) { return code }
        return nil
    }

    private func invalid(_ json: String) -> PairingCodeError? {
        if case let .failure(error) = parser.parse(json) { return error }
        return nil
    }

    @Test func aFullCodeFromTheProgramIsRead() throws {
        let code = try #require(valid("""
        { "url": "https://192.168.1.20:5080/api/v1", "key": "hk_Abc123", "certSha256": "\(fingerprint)",
          "remoteUrl": "https://stajnia.dyndns.org:48123/api/v1" }
        """))
        #expect(code.url.baseUrl == "https://192.168.1.20:5080/api/v1")
        #expect(code.url.isLocal)
        #expect(code.key == "hk_Abc123")
        #expect(code.certSha256 == fingerprint)
        #expect(code.remoteUrl?.baseUrl == "https://stajnia.dyndns.org:48123/api/v1")
        #expect(code.remoteUrl?.isLocal == false)
    }

    @Test func aMinimalHttpCodeForALocalAddressIsAccepted() throws {
        let code = try #require(valid(#"{"url":"http://192.168.1.20:5080/api/v1","key":"hk_k"}"#))
        #expect(!code.url.isHttps)
        #expect(code.certSha256 == nil)
        #expect(code.remoteUrl == nil)
    }

    @Test func unknownFieldsAreIgnoredAndANullFingerprintMeansHttpsIsOff() throws {
        let code = try #require(valid(#"{"url":"http://komputer.local:5080/api/v1","key":"hk_k","certSha256":null,"remoteUrl":null,"nowePole":{"a":[1]},"version":2}"#))
        #expect(code.certSha256 == nil)
        #expect(code.remoteUrl == nil)
    }

    @Test func theFingerprintIsNormalisedAndMustBe64HexCharacters() {
        #expect(valid(#"{"url":"https://192.168.1.20:5080/api/v1","key":"hk_k","certSha256":"\#(fingerprint.lowercased())"}"#)?.certSha256 == fingerprint)
        let pairs = stride(from: 0, to: fingerprint.count, by: 2).map { offset -> String in
            let start = fingerprint.index(fingerprint.startIndex, offsetBy: offset)
            return String(fingerprint[start..<fingerprint.index(start, offsetBy: 2)])
        }
        for bad in [String(fingerprint.dropLast()), fingerprint + "A", String(repeating: "G", count: 64), pairs.joined(separator: ":"), ""] {
            #expect(invalid(#"{"url":"https://192.168.1.20:5080/api/v1","key":"hk_k","certSha256":"\#(bad)"}"#) == .badFingerprint, "\(bad)")
        }
    }

    @Test func aMissingUrlOrKeySaysItIsNotAPairingCode() {
        let samples = [
            #"{"key":"hk_k"}"#,
            #"{"url":"https://192.168.1.20:5080/api/v1"}"#,
            #"{"url":"https://192.168.1.20:5080/api/v1","key":""}"#,
            #"{"url":"https://192.168.1.20:5080/api/v1","key":"abc"}"#,
            #"{"url":"https://192.168.1.20:5080/api/v1","key":"hk_"}"#,
            #"{"url":42,"key":"hk_k"}"#,
            "{}", "to nie jest json", "", "[1,2,3]", "https://192.168.1.20:5080/api/v1",
        ]
        for json in samples {
            #expect(invalid(json)?.message == "To nie jest kod parowania z programu Horsely", "\(json)")
        }
    }

    @Test func aRemoteUrlWithHttpOrAnUnencryptedNonLocalUrlIsRejected() {
        #expect(invalid(#"{"url":"https://192.168.1.20:5080/api/v1","key":"hk_k","remoteUrl":"http://stajnia.dyndns.org:48123/api/v1"}"#) == .badAddress)
        #expect(invalid(#"{"url":"https://192.168.1.20:5080/api/v1","key":"hk_k","remoteUrl":"http://192.168.1.21:5080/api/v1"}"#) == .badAddress)
        #expect(invalid(#"{"url":"http://stajnia.lan:5080/api/v1","key":"hk_k"}"#) == .badAddress)
        #expect(invalid(#"{"url":"http://203.0.113.25:5080/api/v1","key":"hk_k"}"#) == .badAddress)
    }

    @Test func theKeyNeverAppearsInTheStringForm() throws {
        let code = try #require(valid(#"{"url":"https://192.168.1.20:5080/api/v1","key":"hk_SekretnyKlucz"}"#))
        #expect(!String(describing: code).contains("SekretnyKlucz"))
    }

    // MARK: Wersje programu

    @Test func aProgramBelowTheMinimumIsRefused() {
        #expect(ProgramVersion.check("1.4.9") == .tooOld)
        #expect(ProgramVersion.check("0.9") == .tooOld)
        #expect(!VersionCheck.tooOld.isUsable)
    }

    @Test func theMinimumAndTheTestedVersionAreAccepted() {
        for version in ["1.5.0", "1.5.3", "1.6.1", "1.6", "1.7.0", "2.0.0"] {
            #expect(ProgramVersion.check(version) == .supported, "\(version)")
        }
        #expect(ProgramVersion.tested == ProgramVersion(major: 2, minor: 0, patch: 0))
    }

    @Test func aNewerProgramThanTestedProducesAWarningButWorks() {
        #expect(ProgramVersion.check("2.0.1") == .newerThanTested)
        #expect(ProgramVersion.check("2.1.0") == .newerThanTested)
        #expect(VersionCheck.newerThanTested.isUsable)
    }

    @Test func aBuildSuffixIsIgnoredAndInvalidTextIsNotAVersion() {
        #expect(ProgramVersion.check("1.6.1+abc") == .supported)
        #expect(ProgramVersion.check("1.6.1-beta") == .supported)
        #expect(ProgramVersion("") == nil)
        #expect(ProgramVersion("abc") == nil)
        #expect(ProgramVersion("1.x.0") == nil)
        #expect(ProgramVersion.check("abc") == .unknown)
        #expect(ProgramVersion("1.10.0")! > ProgramVersion("1.9.9")!)
        #expect(ProgramVersion("1.5") == ProgramVersion("1.5.0"))
    }

    // MARK: Możliwości programu

    @Test func capabilitiesIgnoreUnknownNamesAndRoundTrip() {
        let capabilities = ProgramCapabilities(names: ["dataStamp", "updatedSince", "przyszłaMożliwość", "horseStatusInjured"])
        #expect(capabilities.serialized == "dataStamp,horseStatusInjured,updatedSince")
        #expect(ProgramCapabilities(serialized: capabilities.serialized) == capabilities)
        #expect(ProgramCapabilities(serialized: nil) == .none)
        #expect(ClientFeatures.value(for: capabilities) == "horse-status-injured")
        #expect(ClientFeatures.value(for: .none) == nil)
    }

    @Test func aProgram161WithoutCapabilitiesGetsNoNewBehaviour() throws {
        let info = try JSONDecoder().decode(ProgramInfo.self, from: Data(#"{"appVersion":"1.6.1","apiVersion":"v1","schemaVersion":"1.4","serverTime":"2026-10-05T10:00:00Z"}"#.utf8))
        #expect(info.programCapabilities == .none)
        #expect(info.dataStamp == nil)
        #expect(ClientFeatures.value(for: info.programCapabilities) == nil)
    }

    @Test func aChangeOfUpdatedSinceOrInjuredForcesAFullDownload() {
        let before = ProgramCapabilities(names: ["dataStamp"])
        #expect(CapabilitiesChange(before: before, after: ProgramCapabilities(names: ["dataStamp", "updatedSince"])).forcesFullSync)
        #expect(CapabilitiesChange(before: before, after: ProgramCapabilities(names: ["dataStamp", "horseStatusInjured"])).forcesFullSync)
        #expect(!CapabilitiesChange(before: before, after: ProgramCapabilities(names: ["dataStamp", "idempotencyKey"])).forcesFullSync)
        #expect(CapabilitiesChange(before: before, after: .none).refreshIntervalChanged)
    }

    // MARK: Kolejność adresów

    @Test func theLastWorkingAddressGoesFirstAndSuspendedOnesAreSkipped() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let local = ServerAddress(id: "a", url: "https://192.168.1.20:5080/api/v1", position: 0, trustMode: .pinned, isRemote: false)
        var remote = ServerAddress(id: "b", url: "https://stajnia.dyndns.org:48123/api/v1", position: 1, trustMode: .pinned, isRemote: true)
        #expect(AddressOrder.order([remote, local], now: now).map(\.id) == ["a", "b"])
        remote.lastOkAt = now.addingTimeInterval(-10)
        #expect(AddressOrder.order([local, remote], now: now).map(\.id) == ["b", "a"])
        remote.hold = AddressHold(reason: .rateLimited, until: now.addingTimeInterval(30))
        #expect(AddressOrder.order([local, remote], now: now).map(\.id) == ["a"])
        #expect(AddressOrder.order([local, remote], now: now.addingTimeInterval(31)).map(\.id) == ["b", "a"])
        #expect(AddressOrder.connectTimeout == 3)
    }
}
