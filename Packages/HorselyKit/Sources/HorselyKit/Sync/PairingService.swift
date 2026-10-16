import Foundation
import HorselyCore

/// Dane parowania z kodu QR albo wpisane ręcznie.
public struct PairingRequest: Sendable, Equatable {
    public let url: CheckedAddress
    public let key: String
    public let certSha256: String?
    public let remoteUrl: CheckedAddress?
    /// Adres ręczny `https` bez odcisku: wystawca potwierdzony przez użytkownika („Ufać temu adresowi?”).
    public let trustedIssuerSummary: String?

    public init(url: CheckedAddress, key: String, certSha256: String? = nil, remoteUrl: CheckedAddress? = nil, trustedIssuerSummary: String? = nil) {
        self.url = url
        self.key = key
        self.certSha256 = certSha256
        self.remoteUrl = remoteUrl
        self.trustedIssuerSummary = trustedIssuerSummary
    }

    public init(code: PairingCode) {
        self.init(url: code.url, key: code.key, certSha256: code.certSha256, remoteUrl: code.remoteUrl)
    }

    /// Adresy do zapisania: lokalny pierwszy, `remoteUrl` z QR drugi.
    func addresses() -> [ServerAddress] {
        var result = [Self.address(url, position: 0, certSha256: certSha256, issuer: trustedIssuerSummary)]
        if let remoteUrl { result.append(Self.address(remoteUrl, position: 1, certSha256: certSha256, issuer: trustedIssuerSummary)) }
        return result
    }

    static func address(_ checked: CheckedAddress, position: Int, certSha256: String?, issuer: String?) -> ServerAddress {
        let trust: TrustMode = !checked.isHttps ? .plainHttpConfirmed : (certSha256 != nil ? .pinned : .trustedIssuer)
        return ServerAddress(
            id: UUID().uuidString.lowercased(), url: checked.baseUrl, position: position, trustMode: trust, certSha256: trust == .pinned ? certSha256 : nil,
            issuerSummary: trust == .trustedIssuer ? issuer : nil, isRemote: !checked.isLocal
        )
    }
}

/// Wynik sprawdzenia programu przed zapisem parowania (ekran „Wynik parowania”).
public struct PairingResult: Sendable, Equatable {
    public let programVersion: String
    public let versionCheck: VersionCheck
    public let horseCount: Int
    public let capabilities: ProgramCapabilities
    /// Połączenie bez szyfrowania (`http`) — ostrzeżenie.
    public let unencrypted: Bool
}

public enum PairingFailure: Error, Equatable, Sendable {
    /// Program starszy niż 1.5.0 — „Zaktualizuj program na komputerze do wersji 1.5.0 lub nowszej”.
    case programTooOld(String)
    case unknownVersion
    case api(ApiFailure)

    public var message: String {
        switch self {
        case .programTooOld: "Zaktualizuj program na komputerze do wersji 1.5.0 lub nowszej"
        case .unknownVersion: "Nie rozpoznaję wersji programu na komputerze"
        case let .api(failure): PairingFailure.message(for: failure)
        }
    }

    static func message(for failure: ApiFailure) -> String {
        switch failure {
        case .certificateRejected: "Certyfikat komputera się zmienił — zeskanuj nowy kod QR"
        case .unauthorized: "Klucz został unieważniony — połącz aplikację ponownie"
        case .keyHomeOnly: "Ten klucz działa tylko w sieci domowej. Włącz dla niego dostęp spoza domu w programie (Ustawienia → API → klucz) albo połącz się przez domowe Wi‑Fi"
        case .remoteAccessDisabled: "Dostęp spoza domu jest wyłączony w programie. Włącz go na komputerze (Ustawienia → API → Dostęp spoza sieci domowej) albo połącz się przez domowe Wi‑Fi"
        case .noNetwork: "Telefon nie ma połączenia z siecią"
        default: "Brak połączenia z komputerem. Sprawdź, czy program jest uruchomiony i telefon jest w tej samej sieci."
        }
    }
}

/// Parowanie z programem (contracts/android/pairing-and-connection.md, mode-and-sync.md §4):
/// 1. `GET /system/info` z kluczem (pierwsze żądanie bez nagłówka cech) — wersja ≥ 1.5.0;
/// 2. `GET /dictionaries` i `GET /horses?status=all&pageSize=1` — wersja programu i liczba koni;
/// 3. zapis parowania w jednej transakcji (przy zmianie trybu samodzielny → online — usunięcie danych telefonu dopiero tutaj);
/// 4. przy niepustej kolejce — rozpoznanie tej samej stajni (FR-M-POL-08).
public struct PairingService: Sendable {
    let store: RecordStore
    let client: ApiClient
    let secrets: SecretStore
    let files: LocalFileStore?

    public init(store: RecordStore, client: ApiClient, secrets: SecretStore, files: LocalFileStore? = nil) {
        self.store = store
        self.client = client
        self.secrets = secrets
        self.files = files
    }

    /// Sprawdza program pod adresem z kodu przed zapisem.
    public func verify(_ request: PairingRequest) async -> Result<PairingResult, PairingFailure> {
        var lastFailure: ApiFailure = .noUsableAddress
        for address in request.addresses() {
            let info: ProgramInfo
            switch await client.executeOn(address, .get("system/info"), apiKey: request.key, features: ProgramCapabilities.none) {
            case let .success(response):
                guard let decoded = response.decode(ProgramInfo.self) else { return .failure(.api(.badResponse)) }
                info = decoded
            case let .failure(failure):
                lastFailure = failure
                continue
            }
            let check = ProgramVersion.check(info.appVersion)
            if check == .tooOld { return .failure(.programTooOld(info.appVersion)) }
            if check == .unknown { return .failure(.unknownVersion) }
            let features = info.programCapabilities
            if case let .failure(failure) = await client.executeOn(address, .get("dictionaries"), apiKey: request.key, features: features) {
                return .failure(.api(failure))
            }
            let horses: Int
            switch await client.executeOn(address, .get("horses?status=all&pageSize=1"), apiKey: request.key, features: features) {
            case let .success(response): horses = response.json?["totalCount"]?.intValue ?? 0
            case let .failure(failure): return .failure(.api(failure))
            }
            return .success(PairingResult(programVersion: info.appVersion, versionCheck: check, horseCount: horses, capabilities: features, unencrypted: !address.isHttps))
        }
        return .failure(.api(lastFailure))
    }

    /// Zapisuje parowanie. `replacingStandaloneData` — zmiana trybu samodzielny → online: dane telefonu znikają w tej samej transakcji.
    /// Zwraca wynik rozpoznania stajni dla niepustej kolejki (ponowne parowanie).
    public func commit(_ request: PairingRequest, result: PairingResult, replacingStandaloneData: Bool, now: Date = Date()) async throws -> StableIdentity {
        try secrets.save(request.key)
        let addresses = request.addresses()
        let attachmentIds: [String] = try await store.write { access in
            var removedFiles: [String] = []
            if replacingStandaloneData {
                removedFiles = try access.query(.attachment, includeDeleted: true).map(\.id)
                try access.clear()
                try access.db.execute(sql: "DELETE FROM local_file")
                try access.clearQueue()
                try access.clearConflicts()
            }
            try access.clearAddresses()
            for address in addresses { try access.saveAddress(address) }
            try access.clearSyncState()
            try access.setMeta(SyncMetaKey.programVersion, result.programVersion)
            try access.setMeta(SyncMetaKey.capabilities, result.capabilities.serialized.isEmpty ? nil : result.capabilities.serialized)
            try access.setMeta(PairingMetaKey.pairedAt, RefreshPlan.formatInstant(now))
            return removedFiles
        }
        if let files { for id in attachmentIds { files.delete(attachmentId: id) } }
        return await checkStable(now: now)
    }

    /// Rozpoznanie tej samej stajni po ponownym parowaniu: niezgodna → operacje `Held`.
    public func checkStable(now: Date = Date()) async -> StableIdentity {
        let operations = (try? await store.read { try $0.operations() }) ?? []
        guard operations.contains(where: { StableIdentityCheck.considered.contains($0.state) }) else { return .match }
        guard case let .success(items) = await client.pages("horses?status=all") else { return .match }
        let program = items.compactMap { item -> HorseRef? in
            guard let id = item["id"]?.stringValue, let name = item["name"]?.stringValue else { return nil }
            return HorseRef(id: id, name: name, passportNumber: item["passportNumber"]?.stringValue)
        }
        let cached = ((try? await store.query(.horse)) ?? []).compactMap { try? $0.record(as: LocalHorse.self) }.map(HorseRef.init)
        let result = StableIdentityCheck.check(operations: operations, programHorses: program, cachedHorses: cached)
        try? await hold(result, now: now)
        return result
    }

    /// Wstrzymuje operacje z wyniku niezgodnego (`Held`).
    public func hold(_ result: StableIdentity, now: Date) async throws {
        guard case let .mismatch(_, ids) = result else { return }
        try await store.writeQuietly { access in
            for id in ids {
                try access.updateOperation(id, expected: StableIdentityCheck.considered) { current in
                    var next = current
                    next.state = .held
                    next.updatedAt = now
                    return next
                }
            }
        }
    }

    /// „Wyślij mimo to”: wstrzymane operacje wracają do kolejki.
    public func release(now: Date = Date()) async throws {
        try await store.writeQuietly { access in
            for op in try access.operations() where op.state == .held {
                try access.updateOperation(op.id, expected: [.held]) { current in
                    var next = current
                    next.state = .pending
                    next.updatedAt = now
                    return next
                }
            }
        }
    }

    /// „Usuń kolejkę”.
    public func dropQueue() async throws {
        try await store.writeQuietly { access in
            for op in try access.operations() {
                if let file = try access.outboxFile(op.id) { OutboxProcessor.release(file) }
            }
            try access.clearQueue()
            try access.clearConflicts()
        }
    }

    /// „Rozłącz”: usunięcie klucza, pamięci, kolejki, konfliktów i adresów (przypomnienie o unieważnieniu klucza pokazuje ekran).
    public func disconnect() async throws {
        try? secrets.delete()
        let attachmentIds: [String] = try await store.write { access in
            let ids = try access.query(.attachment, includeDeleted: true).map(\.id)
            try access.clear()
            try access.db.execute(sql: "DELETE FROM local_file")
            try access.clearQueue()
            try access.clearConflicts()
            try access.clearAddresses()
            try access.clearSyncState()
            return ids
        }
        if let files { for id in attachmentIds { files.delete(attachmentId: id) } }
    }
}
