import Foundation
import GRDB
import HorselyCore

// Trwała kolejka wysyłki (tabele `queue_operation`, `queue_history`, data-model.md §4). Operacje kolejki są częścią tej samej bazy
// co rekordy, więc zapis „rekord `Pending` + operacja” idzie w jednej transakcji (konstytucja IV). Przejścia stanów są warunkowe
// (`expected`): procesor wysyłki i edytor w interfejsie nie wezmą tej samej operacji jednocześnie.
extension RecordAccess {
    // MARK: Operacje

    /// Zapisuje operację na końcu kolejki (nadaje `sequence`); plik załącznika — w `fileRef`.
    @discardableResult
    public func enqueue(_ operation: OutboxOperation, file: OutboxFile? = nil) throws -> OutboxOperation {
        var stored = operation
        stored.sequence = (try Int64.fetchOne(db, sql: "SELECT MAX(seq) FROM queue_operation") ?? 0) + 1
        try saveOperation(stored, file: file, insert: true)
        return stored
    }

    public func operation(_ id: String) throws -> OutboxOperation? {
        try Row.fetchOne(db, sql: "SELECT * FROM queue_operation WHERE id = ?", arguments: [id]).map(Self.operation)
    }

    /// Wszystkie operacje według `sequence`.
    public func operations() throws -> [OutboxOperation] {
        try Row.fetchAll(db, sql: "SELECT * FROM queue_operation ORDER BY seq").map(Self.operation)
    }

    public func outboxFile(_ operationId: String) throws -> OutboxFile? {
        guard let text = try String.fetchOne(db, sql: "SELECT fileRef FROM queue_operation WHERE id = ?", arguments: [operationId]) else { return nil }
        return try? JSONDecoder().decode(StoredFile.self, from: Data(text.utf8)).file(operationId)
    }

    /// Zmienia operację tylko wtedy, gdy jej stan należy do `expected`; `nil` — operacji nie ma albo ktoś ją zmienił.
    @discardableResult
    public func updateOperation(_ id: String, expected: Set<OutboxState>, _ transform: (OutboxOperation) -> OutboxOperation) throws -> OutboxOperation? {
        guard let current = try operation(id), expected.contains(current.state) else { return nil }
        var next = transform(current)
        next.id = current.id
        next.sequence = current.sequence
        try saveOperation(next, file: nil, insert: false)
        return next
    }

    /// `Pending → Sending` z zapisem licznika przed wysyłką — tylko gdy operacja nie zmieniła się od obliczenia licznika.
    public func markSending(_ id: String, countBefore: Int?, expectedUpdatedAt: Date, now: Date) throws -> OutboxOperation? {
        guard let current = try operation(id), current.state == .pending, abs(current.updatedAt.timeIntervalSince(expectedUpdatedAt)) < 0.001 else { return nil }
        var next = current
        next.state = .sending
        next.countBefore = countBefore
        next.updatedAt = now
        try saveOperation(next, file: nil, insert: false)
        return next
    }

    /// Usuwa operację (gdy jej stan należy do `allowed`) razem z zależnymi, przechodnio; zwraca usunięte (pierwsza — wskazana)
    /// i pliki do skasowania.
    public func deleteOperation(_ id: String, allowed: Set<OutboxState> = OutboxState.editable) throws -> (removed: [OutboxOperation], files: [OutboxFile]) {
        guard let first = try operation(id), allowed.contains(first.state) else { return ([], []) }
        let all = try operations()
        let ids = OperationCoalescer.withDependents(id, in: all)
        var removed: [OutboxOperation] = []
        var files: [OutboxFile] = []
        for opId in ids {
            guard let op = all.first(where: { $0.id == opId }) else { continue }
            if let file = try outboxFile(opId) { files.append(file) }
            try db.execute(sql: "DELETE FROM queue_operation WHERE id = ?", arguments: [opId])
            removed.append(op)
        }
        return (removed, files)
    }

    /// Usuwa wysłane operacje, od których nie zależy żadna niewysłana (wynik jest w historii).
    public func purgeSent() throws {
        let all = try operations()
        let needed = Set(all.filter(\.state.isUnsent).flatMap(\.dependsOn))
        for op in all where !op.state.isUnsent && !needed.contains(op.id) {
            try db.execute(sql: "DELETE FROM queue_operation WHERE id = ?", arguments: [op.id])
        }
    }

    /// Start aplikacji: operacje `Sending` mają wynik nieznany (`Unknown`).
    @discardableResult
    public func recoverInterrupted(now: Date) throws -> Int {
        try db.execute(sql: "UPDATE queue_operation SET state = ?, updatedAt = ? WHERE state = ?", arguments: [OutboxState.unknown.rawValue, now, OutboxState.sending.rawValue])
        return db.changesCount
    }

    /// Rekordy z niewysłaną operacją kolejki — ich lokalne zmiany pobranie zostawia.
    public func liveRecords() throws -> Set<RecordRef> {
        let rows = try Row.fetchAll(db, sql: "SELECT recordType, recordId, state FROM queue_operation WHERE recordType IS NOT NULL AND recordId IS NOT NULL")
        var refs = Set<RecordRef>()
        for row in rows {
            let rawType: String = row["recordType"]
            let rawState: String = row["state"]
            guard let type = RecordType(rawValue: rawType), let state = OutboxState(rawValue: rawState), state.isUnsent else { continue }
            refs.insert(RecordRef(type: type, id: row["recordId"]))
        }
        return refs
    }

    public func clearQueue() throws {
        try db.execute(sql: "DELETE FROM queue_operation")
        try db.execute(sql: "DELETE FROM queue_history")
    }

    // MARK: Historia

    public func addHistory(_ entry: QueueHistoryEntry) throws {
        try db.execute(
            sql: "INSERT INTO queue_history (operationId, kind, outcome, summary, at) VALUES (?, ?, ?, ?, ?)",
            arguments: [entry.operationId, entry.kind.rawValue, entry.outcome.rawValue, entry.summary, entry.at]
        )
    }

    /// Historia od najnowszych.
    public func history() throws -> [QueueHistoryEntry] {
        try Row.fetchAll(db, sql: "SELECT * FROM queue_history ORDER BY at DESC, id DESC").compactMap { row in
            let kind: String = row["kind"]
            let outcome: String = row["outcome"]
            guard let operationKind = OperationKind(rawValue: kind), let result = HistoryOutcome(rawValue: outcome) else { return nil }
            return QueueHistoryEntry(operationId: row["operationId"], kind: operationKind, summary: row["summary"], outcome: result, at: row["at"])
        }
    }

    /// FR-M-SYN-13: historia 30 dni.
    public func purgeHistory(before: Date) throws {
        try db.execute(sql: "DELETE FROM queue_history WHERE at < ?", arguments: [before])
    }

    // MARK: Zapis wiersza

    private struct StoredFile: Codable {
        let path: String
        let fileName: String
        let contentType: String
        let sizeBytes: Int64
        let sha256: String
        let description: String?

        init(_ file: OutboxFile) {
            path = file.path
            fileName = file.fileName
            contentType = file.contentType
            sizeBytes = file.sizeBytes
            sha256 = file.sha256
            description = file.description
        }

        func file(_ operationId: String) -> OutboxFile {
            OutboxFile(operationId: operationId, path: path, fileName: fileName, contentType: contentType, sizeBytes: sizeBytes, sha256: sha256, description: description)
        }
    }

    private func saveOperation(_ op: OutboxOperation, file: OutboxFile?, insert: Bool) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let dependsOn = String(decoding: try encoder.encode(op.dependsOn), as: UTF8.self)
        let horses = String(decoding: try encoder.encode(op.horseRefs), as: UTF8.self)
        let problem = try op.problem.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        let values: [(String, (any DatabaseValueConvertible)?)] = [
            ("id", op.id), ("seq", op.sequence), ("kind", op.kind.rawValue), ("recordType", op.recordType?.rawValue), ("recordId", op.recordId),
            ("baseVersion", op.baseVersion), ("payload", op.payload.text()), ("dependsOn", dependsOn), ("state", op.state.rawValue),
            ("attempts", op.attempts), ("nextAttemptAt", op.nextAttemptAt), ("lastError", problem), ("countBefore", op.countBefore),
            ("createdAt", op.createdAt), ("updatedAt", op.updatedAt), ("localRef", op.localRef), ("horseRefs", horses), ("summary", op.summary),
            ("resultId", op.resultId),
        ]
        if insert {
            let fileText = try file.map { String(decoding: try encoder.encode(StoredFile($0)), as: UTF8.self) }
            let all = values + [("fileRef", fileText)]
            try db.execute(
                sql: "INSERT INTO queue_operation (\(all.map(\.0).joined(separator: ", "))) VALUES (\(RecordAccess.placeholders(all.count)))",
                arguments: StatementArguments(all.map(\.1))
            )
        } else {
            let rest = Array(values.dropFirst())
            var arguments: [(any DatabaseValueConvertible)?] = rest.map(\.1)
            arguments.append(op.id)
            try db.execute(
                sql: "UPDATE queue_operation SET \(rest.map { "\($0.0) = ?" }.joined(separator: ", ")) WHERE id = ?",
                arguments: StatementArguments(arguments)
            )
        }
    }

    static func operation(_ row: Row) throws -> OutboxOperation {
        let decoder = JSONDecoder()
        let rawKind: String = row["kind"]
        let rawState: String = row["state"]
        guard let kind = OperationKind(rawValue: rawKind), let state = OutboxState(rawValue: rawState) else {
            throw StoreError.corruptRow("operacja \(rawKind) \(rawState)")
        }
        let payloadText: String? = row["payload"]
        let dependsText: String? = row["dependsOn"]
        let horsesText: String? = row["horseRefs"]
        let problemText: String? = row["lastError"]
        let rawType: String? = row["recordType"]
        let id: String = row["id"]
        let localRef: String? = row["localRef"]
        return OutboxOperation(
            id: id, sequence: row["seq"], kind: kind, localRef: localRef ?? id,
            payload: payloadText.flatMap { try? JSONValue.parse($0) } ?? .object([:]),
            dependsOn: dependsText.flatMap { try? decoder.decode([String].self, from: Data($0.utf8)) } ?? [],
            horseRefs: horsesText.flatMap { try? decoder.decode([HorseRef].self, from: Data($0.utf8)) } ?? [],
            summary: row["summary"] ?? "", state: state, countBefore: row["countBefore"], attempts: row["attempts"], nextAttemptAt: row["nextAttemptAt"],
            problem: problemText.flatMap { try? decoder.decode(ApiProblem.self, from: Data($0.utf8)) }, resultId: row["resultId"],
            createdAt: row["createdAt"], updatedAt: row["updatedAt"], recordType: rawType.flatMap(RecordType.init(rawValue:)), recordId: row["recordId"],
            baseVersion: row["baseVersion"]
        )
    }
}

// MARK: - Konflikty

extension RecordAccess {
    public func putConflict(_ conflict: Conflict) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO conflict
            (id, operationId, recordType, recordId, kind, mine, theirs, theirsVersion, trashBatchId, trashBatchSize, detectedAt, resolvedAt, resolution)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                conflict.id, conflict.operationId, conflict.recordType.rawValue, conflict.recordId, conflict.kind.rawValue, conflict.mine, conflict.theirs,
                conflict.theirsVersion, conflict.trashBatchId, conflict.trashBatchSize, conflict.detectedAt, conflict.resolvedAt, conflict.resolution?.rawValue,
            ]
        )
    }

    public func conflict(_ id: String) throws -> Conflict? {
        try Row.fetchOne(db, sql: "SELECT * FROM conflict WHERE id = ?", arguments: [id]).flatMap(Self.conflict)
    }

    /// Nierozstrzygnięte, od najstarszego.
    public func openConflicts() throws -> [Conflict] {
        try Row.fetchAll(db, sql: "SELECT * FROM conflict WHERE resolvedAt IS NULL ORDER BY detectedAt, id").compactMap(Self.conflict)
    }

    public func openConflict(forOperation operationId: String) throws -> Conflict? {
        try Row.fetchOne(db, sql: "SELECT * FROM conflict WHERE operationId = ? AND resolvedAt IS NULL", arguments: [operationId]).flatMap(Self.conflict)
    }

    public func purgeResolvedConflicts(before: Date) throws {
        try db.execute(sql: "DELETE FROM conflict WHERE resolvedAt IS NOT NULL AND resolvedAt < ?", arguments: [before])
    }

    public func clearConflicts() throws {
        try db.execute(sql: "DELETE FROM conflict")
    }

    static func conflict(_ row: Row) -> Conflict? {
        let rawType: String = row["recordType"]
        let rawKind: String = row["kind"]
        let rawResolution: String? = row["resolution"]
        guard let type = RecordType(rawValue: rawType), let kind = ConflictKind(rawValue: rawKind) else { return nil }
        return Conflict(
            id: row["id"], operationId: row["operationId"] ?? "", recordType: type, recordId: row["recordId"], kind: kind, mine: row["mine"], theirs: row["theirs"],
            theirsVersion: row["theirsVersion"], trashBatchId: row["trashBatchId"], trashBatchSize: row["trashBatchSize"], detectedAt: row["detectedAt"],
            resolvedAt: row["resolvedAt"], resolution: rawResolution.flatMap(ConflictResolution.init(rawValue:))
        )
    }
}

// MARK: - Obserwacja kolejki

/// Stan kolejki dla ekranów: operacje i liczba nierozstrzygniętych konfliktów (licznik „Więcej”, oznaczenia na listach).
public struct QueueSnapshot: Equatable, Sendable {
    public let operations: [OutboxOperation]
    public let openConflicts: [Conflict]

    public init(operations: [OutboxOperation] = [], openConflicts: [Conflict] = []) {
        self.operations = operations
        self.openConflicts = openConflicts
    }

    /// Niewysłane (licznik na „Więcej”).
    public var unsentCount: Int { operations.filter(\.state.isUnsent).count }

    /// Oznaczenie rekordu na listach (FR „czeka na wysłanie” / „wymaga poprawy” / „konflikt”).
    public func marker(_ type: RecordType, id: String) -> RecordMarker? {
        let related = operations.filter { $0.recordType == type && $0.recordId == id && $0.state.isUnsent }
        if related.isEmpty { return nil }
        if related.contains(where: { $0.state == .conflict }) { return .conflict }
        if related.contains(where: { $0.state == .needsFix || $0.state == .held }) { return .needsFix }
        return .pending
    }
}

/// Oznaczenie rekordu z niewysłaną zmianą.
public enum RecordMarker: String, Sendable {
    case pending
    case needsFix
    case conflict
}

extension RecordStore {
    /// Kolejka i konflikty jako strumień (po każdej zmianie tabel).
    public func observeQueue() -> AsyncValueObservation<QueueSnapshot> {
        ValueObservation
            .tracking { db in
                let access = RecordAccess(db: db, state: RecordAccess.WriteState())
                return QueueSnapshot(operations: try access.operations(), openConflicts: try access.openConflicts())
            }
            .removeDuplicates()
            .values(in: database.writer)
    }

    public func queueSnapshot() async throws -> QueueSnapshot {
        try await read { QueueSnapshot(operations: try $0.operations(), openConflicts: try $0.openConflicts()) }
    }
}
