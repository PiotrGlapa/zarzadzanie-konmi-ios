import Foundation
import HorselyCore

/// Wynik rozstrzygnięcia jednego konfliktu.
public enum ResolveResult: Equatable, Sendable {
    case done
    /// „Zachowaj moją” przywróci z kosza programu partię z `records` rekordami — wymaga potwierdzenia.
    case needsConfirmation(records: Int)
    /// Przywrócenie z kosza albo odczyt się nie udały — konflikt zostaje do ponownej próby.
    case failed(ApiFailure)
    /// Konfliktu albo jego operacji już nie ma.
    case gone
}

/// Wynik akcji zbiorczej.
public struct BulkResult: Equatable, Sendable {
    public let resolved: Int
    public let failed: Int
}

/// Rozstrzyganie konfliktów (FR-SYN2-07, contracts/android/mode-and-sync.md §6; `ConflictResolver.kt`):
///
/// | Rodzaj | „Zachowaj moją” | „Przyjmij z programu” |
/// |---|---|---|
/// | `EditEdit` | operacja wraca z wersją bazową programu (`PUT` z `If-Match`) | lokalnie rekord z programu jako `Synced` |
/// | `EditDelete` w koszu | przywrócenie partii z kosza, potem `PUT` | lokalnie usuń rekord |
/// | `EditDelete` poza koszem | `POST` nowego rekordu (nowe `id`), zależne przepięte | lokalnie usuń rekord |
/// | `DeleteEdit` | operacja wraca z wersją programu (`DELETE`) | lokalnie rekord z programu jako `Synced` |
///
/// Po „Zachowaj moją” wysyłkę wykonuje procesor kolejki — wołający uruchamia go po rozstrzygnięciu.
public struct ConflictResolver: Sendable {
    let store: RecordStore
    let client: ApiClient
    let capabilities: @Sendable () async -> ProgramCapabilities
    let now: @Sendable () -> Date
    let newId: @Sendable () -> String

    public init(
        store: RecordStore, client: ApiClient, capabilities: @escaping @Sendable () async -> ProgramCapabilities = { .none },
        now: @escaping @Sendable () -> Date = { Date() }, newId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.store = store
        self.client = client
        self.capabilities = capabilities
        self.now = now
        self.newId = newId
    }

    public func resolve(_ conflictId: String, _ resolution: ConflictResolution, confirmed: Bool = false) async -> ResolveResult {
        guard let conflict = try? await store.read({ try $0.conflict(conflictId) }), conflict.isOpen else { return .gone }
        guard let operation = try? await store.read({ try $0.operation(conflict.operationId) }), operation.state == .conflict else {
            await finish(conflict, .acceptTheirs)
            return .gone
        }
        switch resolution {
        case .acceptTheirs:
            return await acceptTheirs(conflict, operation)
        case .keepMine:
            switch conflict.kind {
            case .editEdit, .deleteEdit: return await keepWithVersion(conflict, operation, version: conflict.theirsVersion)
            case .editDelete: return await keepAfterDelete(conflict, operation, confirmed: confirmed)
            }
        }
    }

    /// Ten sam wybór dla wszystkich nierozstrzygniętych (po potwierdzeniu z liczbą w interfejsie).
    public func resolveAll(_ resolution: ConflictResolution) async -> BulkResult {
        let open = (try? await store.read { try $0.openConflicts() }) ?? []
        var resolved = 0
        var failed = 0
        for conflict in open {
            switch await resolve(conflict.id, resolution, confirmed: true) {
            case .done, .gone: resolved += 1
            default: failed += 1
            }
        }
        return BulkResult(resolved: resolved, failed: failed)
    }

    // MARK: „Zachowaj moją”

    private func keepWithVersion(_ conflict: Conflict, _ operation: OutboxOperation, version: Int?) async -> ResolveResult {
        let moment = now()
        let rebaseRow = conflict.kind != .deleteEdit
        do {
            try await store.write { access in
                try access.updateOperation(operation.id, expected: [.conflict]) { Self.requeued($0, version: version, at: moment) }
                if rebaseRow { try Self.rebased(access, conflict, version: version) }
                try access.putConflict(Self.closed(conflict, .keepMine, at: moment))
            }
            return .done
        } catch {
            return .failed(.badResponse)
        }
    }

    private func keepAfterDelete(_ conflict: Conflict, _ operation: OutboxOperation, confirmed: Bool) async -> ResolveResult {
        guard let path = RecordPaths.item(conflict.recordType, id: conflict.recordId, parentId: operation.text("competitionId")) else {
            return await restoreAsNew(conflict, operation)
        }
        // Najpierw: może rekord już jest w programie (przywrócony w poprzedniej, przerwanej próbie).
        switch await version(path) {
        case let .found(version): return await keepWithVersion(conflict, operation, version: version)
        case let .failed(failure): return .failed(failure)
        case .gone: break
        }
        guard let batchId = conflict.trashBatchId else { return await restoreAsNew(conflict, operation) }
        let trash: [JSONValue]
        switch await client.get("trash") {
        case let .success(response): trash = response.json?.arrayValue ?? []
        case let .failure(failure): return .failed(failure)
        }
        guard let batch = trash.first(where: { $0["id"]?.stringValue == batchId }), let batchType = batch["type"]?.stringValue else {
            return await restoreAsNew(conflict, operation)
        }
        let size = (batch["dependentCount"]?.intValue ?? 0) + 1
        if size > 1 && !confirmed { return .needsConfirmation(records: size) }
        // Program 2.0.0 sprawdza wersję korzenia partii w tym samym żądaniu; starszy przywraca bez sprawdzenia.
        let guardVersion = await capabilities().ifMatchDelete ? batch["rootVersion"]?.intValue : nil
        switch await client.execute(ApiRequest(.post, "trash/\(batchType)/\(batchId)/restore", ifMatch: guardVersion)) {
        case .success: break
        case .failure(.notFound): return await restoreAsNew(conflict, operation)
        case let .failure(failure): return .failed(failure)
        }
        switch await version(path) {
        case let .found(version): return await keepWithVersion(conflict, operation, version: version)
        case let .failed(failure): return .failed(failure)
        case .gone: return await restoreAsNew(conflict, operation)
        }
    }

    /// Rekordu nie ma w programie nawet w koszu: moja treść idzie jako nowy rekord z nowym `id`, zależne przepięte.
    private func restoreAsNew(_ conflict: Conflict, _ operation: OutboxOperation) async -> ResolveResult {
        guard let kind = OperationKind.create(for: conflict.recordType) else {
            return await acceptDeleted(conflict, operation, reason: "Rekordu nie da się odtworzyć w programie.")
        }
        let fresh = newId()
        let moment = now()
        do {
            try await store.write { access in
                try RecordReconciler.remap(access, sentId: operation.id, type: conflict.recordType, from: conflict.recordId, to: fresh, version: nil)
                if let row = try access.get(conflict.recordType, id: conflict.recordId) {
                    try access.deleteHard(row.type, id: row.id)
                    let decoded = try RecordCodec.decode(row.type, from: row.body.replacingOccurrences(of: conflict.recordId, with: fresh))
                    try access.upsert([try StoredRecord.of(decoded.withAudit(version: 1, updatedAt: decoded.updatedAt), syncState: .pending, dateKey: row.dateKey)])
                }
                // Operacje odwołujące się do rekordu wysyłamy dopiero po jego ponownym utworzeniu.
                for other in try access.operations() where other.id != operation.id && other.state.isUnsent && other.payload.containsString(fresh) {
                    try access.updateOperation(other.id, expected: Set(OutboxState.allCases)) { current in
                        var next = current
                        if !next.dependsOn.contains(operation.id) { next.dependsOn.append(operation.id) }
                        return next
                    }
                }
                try access.updateOperation(operation.id, expected: [.conflict]) { current in
                    var next = Self.requeued(current, version: nil, at: moment)
                    next.kind = kind
                    next.recordId = fresh
                    next.localRef = fresh
                    next.baseVersion = nil
                    next.countBefore = nil
                    next.payload = current.payload.replacingValues(conflict.recordId, with: fresh)
                    return next
                }
                try access.putConflict(Self.closed(conflict, .keepMine, at: moment))
            }
            return .done
        } catch {
            return .failed(.badResponse)
        }
    }

    // MARK: „Przyjmij z programu”

    private func acceptTheirs(_ conflict: Conflict, _ operation: OutboxOperation) async -> ResolveResult {
        if conflict.kind == .editDelete { return await acceptDeleted(conflict, operation, reason: "Rekord został usunięty w programie.") }
        let moment = now()
        do {
            try await store.write { access in
                if let text = conflict.theirs, let theirs = try? RecordCodec.decode(conflict.recordType, from: text) {
                    let row = try access.get(conflict.recordType, id: conflict.recordId)
                    try access.upsert([try StoredRecord.of(theirs, syncState: .synced, dateKey: row?.dateKey ?? theirs.dateKey)])
                }
                try Self.discard(access, operation, dependentsFix: nil, at: moment)
                try access.putConflict(Self.closed(conflict, .acceptTheirs, at: moment))
            }
            return .done
        } catch {
            return .failed(.badResponse)
        }
    }

    /// Rekord usunięty w programie: znika lokalnie, zależne operacje dostają wyjaśnienie w „Wymaga poprawy”.
    private func acceptDeleted(_ conflict: Conflict, _ operation: OutboxOperation, reason: String) async -> ResolveResult {
        let moment = now()
        do {
            try await store.write { access in
                if try access.get(conflict.recordType, id: conflict.recordId) != nil { try access.deleteHard(conflict.recordType, id: conflict.recordId) }
                try Self.discard(access, operation, dependentsFix: reason, at: moment)
                try access.putConflict(Self.closed(conflict, .acceptTheirs, at: moment))
            }
            return .done
        } catch {
            return .failed(.badResponse)
        }
    }

    // MARK: Wspólne

    static func requeued(_ operation: OutboxOperation, version: Int?, at moment: Date) -> OutboxOperation {
        var next = operation
        next.state = .pending
        if let version { next.baseVersion = version }
        next.problem = nil
        next.attempts = 0
        next.nextAttemptAt = nil
        next.updatedAt = moment
        return next
    }

    static func closed(_ conflict: Conflict, _ resolution: ConflictResolution, at moment: Date) -> Conflict {
        var next = conflict
        next.resolvedAt = moment
        next.resolution = resolution
        return next
    }

    /// Lokalny wiersz po „Zachowaj moją”: moja treść na nowej wersji bazowej z programu.
    static func rebased(_ access: RecordAccess, _ conflict: Conflict, version: Int?) throws {
        guard let row = try access.get(conflict.recordType, id: conflict.recordId), !row.isDeleted else { return }
        let decoded = try row.record()
        let record = version.map { decoded.withAudit(version: $0, updatedAt: decoded.updatedAt) } ?? decoded
        try access.upsert([try StoredRecord.of(record, syncState: .pending, baseVersion: version, dateKey: row.dateKey)])
    }

    /// Usuwa operację konfliktu (wpis „Usunięto” w historii). Zależne: `dependentsFix == nil` — tracą tylko zależność; inaczej
    /// trafiają do „Wymaga poprawy” z wyjaśnieniem, a późniejsze zmiany tego samego (usuniętego) rekordu wypadają z kolejki.
    static func discard(_ access: RecordAccess, _ operation: OutboxOperation, dependentsFix: String?, at moment: Date) throws {
        for other in try access.operations() where other.id != operation.id {
            if dependentsFix != nil && other.sameRecord(as: operation) && other.sequence > operation.sequence && other.state.isEditable {
                let removed = try access.deleteOperation(other.id, allowed: Set(OutboxState.allCases))
                removed.files.forEach(OutboxProcessor.release)
                try access.addHistory(QueueHistoryEntry(operationId: other.id, kind: other.kind, summary: other.summary, outcome: .deleted, at: moment))
                continue
            }
            let attachmentOfRecord = dependentsFix != nil && other.kind == .createAttachment && (operation.recordId.map { other.payload.containsString($0) } ?? false)
            guard other.dependsOn.contains(operation.id) || attachmentOfRecord else { continue }
            try access.updateOperation(other.id, expected: Set(OutboxState.allCases)) { current in
                var next = current
                next.dependsOn.removeAll { $0 == operation.id }
                if let dependentsFix {
                    next.state = .needsFix
                    next.problem = ApiProblem(title: dependentsFix)
                    next.updatedAt = moment
                }
                return next
            }
        }
        if let file = try access.outboxFile(operation.id) { OutboxProcessor.release(file) }
        try access.db.execute(sql: "DELETE FROM queue_operation WHERE id = ?", arguments: [operation.id])
        try access.addHistory(QueueHistoryEntry(operationId: operation.id, kind: operation.kind, summary: operation.summary, outcome: .deleted, at: moment))
    }

    private func finish(_ conflict: Conflict, _ resolution: ConflictResolution) async {
        let moment = now()
        _ = try? await store.writeQuietly { try $0.putConflict(Self.closed(conflict, resolution, at: moment)) }
    }

    private enum Version {
        case found(Int)
        case gone
        case failed(ApiFailure)
    }

    private func version(_ path: String) async -> Version {
        switch await client.get(path) {
        case let .success(response):
            guard let version = response.json?["version"]?.intValue else { return .failed(.badResponse) }
            return .found(version)
        case .failure(.notFound):
            return .gone
        case let .failure(failure):
            return .failed(failure)
        }
    }
}
