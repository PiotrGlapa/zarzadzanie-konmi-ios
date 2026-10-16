import Foundation
import GRDB
import HorselyCore

// Adresy programu (tabela `address`, data-model.md §2): kolejność prób, zasada zaufania, ostatni sukces i wstrzymanie
// (401/403/429/certyfikat). Klucz API jest poza bazą — w Keychain.
extension RecordAccess {
    public func addresses() throws -> [ServerAddress] {
        try Row.fetchAll(db, sql: "SELECT * FROM address ORDER BY position, id").compactMap(Self.address)
    }

    public func saveAddress(_ address: ServerAddress) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO address (id, url, position, trustMode, certSha256, issuerSummary, isRemote, lastOkAt, heldUntil, heldReason)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                address.id, address.url, address.position, address.trustMode.rawValue, address.certSha256, address.issuerSummary, address.isRemote,
                address.lastOkAt, address.hold.until, address.hold.reason?.rawValue,
            ]
        )
    }

    public func deleteAddress(_ id: String) throws {
        try db.execute(sql: "DELETE FROM address WHERE id = ?", arguments: [id])
    }

    public func clearAddresses() throws {
        try db.execute(sql: "DELETE FROM address")
    }

    public func setHold(_ id: String, _ hold: AddressHold) throws {
        try db.execute(sql: "UPDATE address SET heldReason = ?, heldUntil = ? WHERE id = ?", arguments: [hold.reason?.rawValue, hold.until, id])
    }

    public func markAddressOk(_ id: String, at: Date) throws {
        try db.execute(sql: "UPDATE address SET lastOkAt = ? WHERE id = ?", arguments: [at, id])
    }

    static func address(_ row: Row) -> ServerAddress? {
        let rawTrust: String = row["trustMode"]
        let rawReason: String? = row["heldReason"]
        guard let trust = TrustMode(rawValue: rawTrust) else { return nil }
        return ServerAddress(
            id: row["id"], url: row["url"], position: row["position"], trustMode: trust, certSha256: row["certSha256"], issuerSummary: row["issuerSummary"],
            isRemote: row["isRemote"], lastOkAt: row["lastOkAt"], hold: AddressHold(reason: rawReason.flatMap(BlockReason.init(rawValue:)), until: row["heldUntil"])
        )
    }
}

/// Zapamiętane parowanie: wersja programu, chwila parowania, możliwości i stan pobierania (`local_meta`).
public struct PairingInfo: Equatable, Sendable {
    public var programVersion: String?
    public var pairedAt: Date?
    public var capabilities: ProgramCapabilities
    public var lastSyncAt: Date?
    public var unversioned: Bool

    public init(programVersion: String? = nil, pairedAt: Date? = nil, capabilities: ProgramCapabilities = .none, lastSyncAt: Date? = nil, unversioned: Bool = false) {
        self.programVersion = programVersion
        self.pairedAt = pairedAt
        self.capabilities = capabilities
        self.lastSyncAt = lastSyncAt
        self.unversioned = unversioned
    }
}

public enum PairingMetaKey {
    public static let pairedAt = "pairing.pairedAt"
}

extension RecordAccess {
    public func pairingInfo() throws -> PairingInfo {
        PairingInfo(
            programVersion: try meta(SyncMetaKey.programVersion),
            pairedAt: try meta(PairingMetaKey.pairedAt).flatMap(RefreshPlan.parseInstant),
            capabilities: ProgramCapabilities(serialized: try meta(SyncMetaKey.capabilities)),
            lastSyncAt: try meta(SyncMetaKey.lastSyncAt).flatMap(RefreshPlan.parseInstant),
            unversioned: try meta(SyncMetaKey.unversioned) == "true"
        )
    }

    /// Stan pobierania z `local_meta`.
    public func syncMetaState() throws -> SyncMetaState {
        SyncMetaState(
            dataStamp: try meta(SyncMetaKey.dataStamp),
            nextUpdatedSince: try meta(SyncMetaKey.nextUpdatedSince),
            lastFullAt: try meta(SyncMetaKey.lastFullAt).flatMap(RefreshPlan.parseInstant),
            forceFull: try meta(SyncMetaKey.forceFull) == "true"
        )
    }

    /// Zapomina cały stan współpracy z programem (rozłączenie, ponowne parowanie, tryb samodzielny).
    public func clearSyncState() throws {
        for key in SyncMetaKey.all + [PairingMetaKey.pairedAt] { try setMeta(key, nil) }
    }
}
