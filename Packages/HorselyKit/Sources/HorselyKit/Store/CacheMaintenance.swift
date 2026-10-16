import Foundation
import GRDB
import HorselyCore

/// „Wyczyść pamięć podręczną” (T131, FR-M-UST-03, tylko tryb online): dane z programu, pobrane załączniki i miniatury znikają;
/// kolejka wysyłki i rekordy z niewysłanymi zmianami zostają, a następne odświeżenie pobiera wszystko od nowa.
extension RecordStore {
    /// Usuwa pamięć podręczną; zwraca identyfikatory załączników, których pliki zostają (niewysłane).
    @discardableResult
    public func clearCache(files: LocalFileStore) async throws -> Set<String> {
        let keep = try await write { access -> Set<String> in
            access.state.dirty = true
            try access.db.execute(sql: "DELETE FROM local_record WHERE syncState IN (?, ?)", arguments: [SyncState.synced.rawValue, SyncState.projected.rawValue])
            try access.db.execute(sql: "DELETE FROM record_horse WHERE NOT EXISTS (SELECT 1 FROM local_record r WHERE r.type = record_horse.type AND r.id = record_horse.id)")
            let pending = Set(try access.query(.attachment, includeDeleted: true).map(\.id))
            let rows = try Row.fetchAll(access.db, sql: "SELECT DISTINCT attachmentId FROM local_file")
            for row in rows {
                let id: String = row["attachmentId"]
                if !pending.contains(id) { try access.deleteFiles(attachmentId: id) }
            }
            for key in [SyncMetaKey.dataStamp, SyncMetaKey.nextUpdatedSince, SyncMetaKey.lastFullAt, SyncMetaKey.lastSyncAt] { try access.setMeta(key, nil) }
            try access.setMeta(SyncMetaKey.forceFull, "true")
            return pending
        }
        files.retain(keep)
        return keep
    }

    /// Miejsce zajęte przez pliki załączników w telefonie (bajty).
    public func filesSize() async throws -> Int64 {
        try await read { access in
            try Int64.fetchOne(access.db, sql: "SELECT COALESCE(SUM(sizeBytes), 0) FROM local_file") ?? 0
        }
    }
}
