import Foundation
import HorselyCore

/// Zapis w magazynie po udanej wysyłce (`RecordReconciler.kt`): rekord dostaje odpowiedź programu (wersję) i stan `Synced`,
/// nowy rekord — `id` nadane przez program (telefon używał własnego UUID). Gdy rekord ma w kolejce kolejne niewysłane operacje,
/// zostaje `Pending` z lokalną treścią, a one dostają nową wersję bazową. Każda metoda — jedna transakcja.
struct RecordReconciler: Sendable {
    let store: RecordStore

    /// Po `POST`: `serverId` z odpowiedzi, `response` — rekord z programu (`nil`, gdy ustalono tylko `id`).
    func created(_ op: OutboxOperation, response: JSONValue?, serverId: String) async throws {
        guard let type = op.recordType, let localId = op.recordId else { return }
        try await store.write { access in
            let others = try Self.unsent(access, except: op, type: type, id: localId)
            let row = try access.get(type, id: localId)
            let server = response.flatMap { ApiRecordMapping.record(type, from: $0, parentId: op.text("competitionId")) }
            let version = server?.version ?? row?.version ?? 1
            if serverId != localId { try Self.remap(access, sentId: op.id, type: type, from: localId, to: serverId, version: version) }
            if let row {
                if serverId != localId { try access.deleteHard(type, id: localId) }
                try access.upsert([try Self.settled(row, server: server, id: serverId, version: version, final: others.isEmpty)])
            }
            try Self.rebase(access, others, id: serverId, version: version)
        }
    }

    /// Po `PUT` albo akcji na terminie: rekord z odpowiedzi programu.
    func updated(_ op: OutboxOperation, response: JSONValue?) async throws {
        guard let type = op.recordType, let id = op.recordId else { return }
        try await store.write { access in
            let others = try Self.unsent(access, except: op, type: type, id: id)
            let server = response.flatMap { ApiRecordMapping.record(type, from: $0, parentId: op.text("competitionId")) }
            // Odpowiedź bez rekordu: program zwiększa wersję o jeden przy każdej zmianie; pełne pobranie poprawi resztę.
            let version = server?.version ?? ((op.baseVersion ?? 0) + 1)
            if let row = try access.get(type, id: id), !row.isDeleted {
                try access.upsert([try Self.settled(row, server: server, id: id, version: version, final: others.isEmpty)])
            }
            try Self.rebase(access, others, id: id, version: version)
        }
    }

    /// Po `DELETE`: lokalnie rekordu już nie ma; porządkujemy ewentualny wiersz `Synced`.
    func deleted(_ op: OutboxOperation) async throws {
        guard let type = op.recordType, let id = op.recordId else { return }
        try await store.write { access in
            if let row = try access.get(type, id: id), !row.isDeleted, row.syncState == .synced { try access.deleteHard(type, id: id) }
        }
    }

    /// Zmienia `id` rekordu `from` na `to` w niewysłanych wierszach i operacjach.
    static func remap(_ access: RecordAccess, sentId: String?, type: RecordType, from: String, to: String, version: Int?) throws {
        let rows = try access.withState(.pending) + access.withState(.projected) + access.withState(.conflict)
        var rewritten: [StoredRecord] = []
        for row in rows where !(row.type == type && row.id == from) && row.body.contains(from) {
            let record = try RecordCodec.decode(row.type, from: row.body.replacingOccurrences(of: from, with: to))
            rewritten.append(try StoredRecord.of(record, syncState: row.syncState, baseVersion: row.baseVersion, dateKey: row.dateKey, deletedAt: row.deletedAt, deletionBatchId: row.deletionBatchId))
        }
        if !rewritten.isEmpty { try access.upsert(rewritten) }
        for operation in try access.operations() where operation.id != sentId && operation.state.isUnsent {
            guard operation.payload.containsString(from) || operation.recordId == from else { continue }
            try access.updateOperation(operation.id, expected: Set(OutboxState.allCases)) { current in
                var next = current
                let same = current.recordId == from
                next.payload = current.payload.replacingValues(from, with: to)
                if same {
                    next.recordId = to
                    if current.kind.isChange { next.baseVersion = version }
                }
                return next
            }
        }
    }

    private static func unsent(_ access: RecordAccess, except op: OutboxOperation, type: RecordType, id: String) throws -> [OutboxOperation] {
        try access.operations().filter { $0.id != op.id && $0.recordType == type && $0.recordId == id && $0.state.isUnsent }
    }

    /// Wiersz po wysyłce: z odpowiedzi programu (`Synced`), z lokalną treścią i wersją programu (`Synced`, gdy odpowiedzi nie ma)
    /// albo — gdy czekają dalsze zmiany — z lokalną treścią jako `Pending` z nową wersją bazową.
    private static func settled(_ row: StoredRecord, server: (any LocalRecord)?, id: String, version: Int, final: Bool) throws -> StoredRecord {
        if final, let server { return try StoredRecord.of(server, syncState: .synced, dateKey: row.dateKey ?? server.dateKey) }
        let body = row.id == id ? row.body : row.body.replacingOccurrences(of: row.id, with: id)
        let decoded = try RecordCodec.decode(row.type, from: body)
        let record = decoded.withAudit(version: version, updatedAt: decoded.updatedAt)
        return final
            ? try StoredRecord.of(record, syncState: .synced, dateKey: row.dateKey)
            : try StoredRecord.of(record, syncState: .pending, baseVersion: version, dateKey: row.dateKey)
    }

    /// Operacje czekające za wysłaną dostają wersję bazową z odpowiedzi programu.
    private static func rebase(_ access: RecordAccess, _ others: [OutboxOperation], id: String, version: Int) throws {
        for operation in others {
            try access.updateOperation(operation.id, expected: Set(OutboxState.allCases)) { current in
                var next = current
                next.recordId = id
                if current.kind.isChange { next.baseVersion = version }
                return next
            }
        }
    }
}

/// Wynik rozpoznania konfliktu przy wysyłce zmiany.
enum Detection: Sendable {
    /// Prawdziwy konflikt — do zapisania i rozstrzygnięcia.
    case found(Conflict)
    /// Program ma już dokładnie moją treść (powtórzona wysyłka po zerwaniu) — operacja wysłana.
    case sameAsMine(JSONValue)
    /// Nie udało się ustalić — operacja czeka na kolejną próbę.
    case failed(ApiFailure)
}

/// Rozpoznanie konfliktów (research R6, contracts/android/mode-and-sync.md §3; `ConflictDetector.kt`):
/// `409` na `PUT` → zmiana–zmiana; `404` na `PUT` → zmiana–usunięcie (z partią kosza, gdy rekord tam jest); przed `DELETE`
/// wersja w programie wyższa niż bazowa → usunięcie–zmiana.
struct ConflictDetector: Sendable {
    let client: ApiClient
    let store: RecordStore
    let now: @Sendable () -> Date
    let newId: @Sendable () -> String

    func editEdit(_ op: OutboxOperation, current: JSONValue?) async -> Detection {
        var theirs = current
        if theirs == nil || theirs == .null {
            switch await fetch(op) {
            case let .record(json): theirs = json
            case .gone: return await editDelete(op)
            case let .failed(failure): return .failed(failure)
            }
        }
        guard let theirs, let type = op.recordType, let recordId = op.recordId else { return .failed(.badResponse) }
        if op.payload.removing("competitionId").isSubset(of: theirs) { return .sameAsMine(theirs) }
        let record = ApiRecordMapping.record(type, from: theirs, parentId: op.text("competitionId"))
        return .found(Conflict(
            id: newId(), operationId: op.id, recordType: type, recordId: recordId, kind: .editEdit, mine: await mine(op),
            theirs: record.flatMap { try? RecordCodec.encodeString($0) }, theirsVersion: record?.version ?? theirs["version"]?.intValue, detectedAt: now()
        ))
    }

    func editDelete(_ op: OutboxOperation) async -> Detection {
        guard let type = op.recordType, let recordId = op.recordId else { return .failed(.badResponse) }
        let row = try? await store.get(type, id: recordId)
        var candidates: Set<String> = [recordId]
        if let row {
            if let horse = row.horseId { candidates.insert(horse) }
            if let owner = row.ownerId { candidates.insert(owner) }
            candidates.formUnion(row.horseIds)
        }
        let trash: [JSONValue]
        switch await client.get("trash") {
        case let .success(response): trash = response.json?.arrayValue ?? []
        case let .failure(failure): return .failed(failure)
        }
        let batch = trash.first { $0["id"]?.stringValue.map(candidates.contains) ?? false }
        return .found(Conflict(
            id: newId(), operationId: op.id, recordType: type, recordId: recordId, kind: .editDelete, mine: await mine(op), theirs: nil, theirsVersion: nil,
            trashBatchId: batch?["id"]?.stringValue, trashBatchSize: batch.map { ($0["dependentCount"]?.intValue ?? 0) + 1 }, detectedAt: now()
        ))
    }

    func deleteEdit(_ op: OutboxOperation, theirs: JSONValue) -> Detection {
        guard let type = op.recordType, let recordId = op.recordId else { return .failed(.badResponse) }
        let record = ApiRecordMapping.record(type, from: theirs, parentId: op.text("competitionId"))
        return .found(Conflict(
            id: newId(), operationId: op.id, recordType: type, recordId: recordId, kind: .deleteEdit, mine: nil,
            theirs: record.flatMap { try? RecordCodec.encodeString($0) }, theirsVersion: record?.version ?? theirs["version"]?.intValue, detectedAt: now()
        ))
    }

    enum Fetched {
        case record(JSONValue)
        case gone
        case failed(ApiFailure)
    }

    /// `GET` rekordu z programu.
    func fetch(_ op: OutboxOperation) async -> Fetched {
        guard let type = op.recordType, let id = op.recordId, let path = RecordPaths.item(type, id: id, parentId: op.text("competitionId")) else { return .gone }
        switch await client.get(path) {
        case let .success(response):
            guard let json = response.json, json.objectValue != nil else { return .failed(.badResponse) }
            return .record(json)
        case .failure(.notFound):
            return .gone
        case let .failure(failure):
            return .failed(failure)
        }
    }

    private func mine(_ op: OutboxOperation) async -> String? {
        guard let type = op.recordType, let id = op.recordId, let row = try? await store.get(type, id: id), !row.isDeleted else { return nil }
        return row.body
    }
}
