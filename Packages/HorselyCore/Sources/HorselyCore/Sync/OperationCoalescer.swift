import Foundation

/// Decyzja łączenia nowej operacji z kolejką (research R5, `OperationCoalescer.kt`).
public enum CoalesceDecision: Equatable, Sendable {
    /// Nowa operacja trafia na koniec kolejki.
    case queue(OutboxOperation)
    /// Nowa zmiana weszła do istniejącej, jeszcze niewysłanej operacji (`merged` — stan po połączeniu).
    case merge(OutboxOperation)
    /// Utworzenie i usunięcie tego samego rekordu zniosły się: `removed` — operacje do usunięcia (z zależnymi, przechodnio).
    case cancel(removed: [String])
}

/// Łączy zmiany tego samego rekordu przed wysłaniem (FR-SYN2-04: do programu trafia stan końcowy, bez wersji pośrednich).
/// Łączone są tylko operacje niewysłane i niezablokowane (`OutboxState.isEditable`):
///
/// | Istnieje w kolejce | Nowa | Wynik |
/// |---|---|---|
/// | Create | Update | Create z treścią końcową |
/// | Create | Delete | obie usunięte z kolejki (z zależnymi, np. załącznikami nowego wpisu) |
/// | Update | Update | jedna Update z treścią końcową, `baseVersion` pierwszej |
/// | Update | Delete | Delete z `baseVersion` pierwszej |
///
/// Operacja `Sending`, `Unknown` albo `Conflict` nie jest łączona — nowa zmiana staje za nią.
public enum OperationCoalescer {
    /// - Parameter queue: operacje kolejki według `sequence`.
    public static func decide(_ operation: OutboxOperation, queue: [OutboxOperation], now: Date) -> CoalesceDecision {
        guard let type = operation.recordType, let recordId = operation.recordId, operation.kind.isChange else { return .queue(operation) }
        let latest = queue.last { $0.recordType == type && $0.recordId == recordId && ($0.kind.isCreate || $0.kind.isChange) }
        guard let latest, latest.state.isEditable, !latest.kind.isDelete else { return .queue(operation) }

        if latest.kind.isCreate && operation.kind.isUpdate {
            return .merge(merged(latest, operation, kind: latest.kind, baseVersion: nil, now: now))
        }
        if latest.kind.isCreate && operation.kind.isDelete {
            return .cancel(removed: withDependents(latest.id, in: queue))
        }
        if latest.kind.isUpdate && operation.kind.isUpdate {
            let kind: OperationKind = latest.kind == .rescheduleReminder && operation.kind == .rescheduleReminder ? .rescheduleReminder : .updateRecord
            return .merge(merged(latest, operation, kind: kind, baseVersion: latest.baseVersion, now: now))
        }
        if latest.kind.isUpdate && operation.kind.isDelete {
            return .merge(merged(latest, operation, kind: .deleteRecord, baseVersion: latest.baseVersion, now: now))
        }
        return .queue(operation)
    }

    private static func merged(_ existing: OutboxOperation, _ next: OutboxOperation, kind: OperationKind, baseVersion: Int?, now: Date) -> OutboxOperation {
        var result = existing
        result.kind = kind
        result.payload = next.payload
        // Nowa treść może odwoływać się do rekordów, które powstają w kolejce — wysyłka czeka na nie razem z poprzednikami.
        var dependencies: [String] = []
        for id in existing.dependsOn + next.dependsOn where id != existing.id && !dependencies.contains(id) { dependencies.append(id) }
        result.dependsOn = dependencies
        result.horseRefs = next.horseRefs.isEmpty ? existing.horseRefs : next.horseRefs
        result.summary = next.summary
        result.baseVersion = baseVersion
        // Poprawiona operacja z „Wymaga poprawy” wraca do wysyłki.
        result.state = .pending
        result.problem = nil
        result.attempts = 0
        result.nextAttemptAt = nil
        result.updatedAt = now
        return result
    }

    /// Operacja i wszystkie od niej zależne (przechodnio), w kolejności odkrycia.
    public static func withDependents(_ id: String, in queue: [OutboxOperation]) -> [String] {
        var ids = [id]
        var grew = true
        while grew {
            grew = false
            for operation in queue where !ids.contains(operation.id) && operation.dependsOn.contains(where: ids.contains) {
                ids.append(operation.id)
                grew = true
            }
        }
        return ids
    }

    /// Niewysłane operacje rekordu (tworzenie, zmiany, akcje na terminie) do usunięcia razem z zależnymi — rekord znika z programu
    /// razem z korzeniem usuwanej partii. Operacje w drodze zostają.
    public static func drop(type: RecordType, recordId: String, queue: [OutboxOperation]) -> [String] {
        var result: [String] = []
        for operation in queue
        where operation.recordType == type && operation.recordId == recordId && operation.state.isEditable
            && (operation.kind.isCreate || operation.kind.isUpdate || operation.kind.isReminderAction) {
            for id in withDependents(operation.id, in: queue) where !result.contains(id) { result.append(id) }
        }
        return result
    }

    /// Załączniki dodane (w kolejce) do usuwanego właściciela.
    public static func dropAttachments(ownerId: String, queue: [OutboxOperation]) -> [String] {
        var result: [String] = []
        for operation in queue where operation.kind == .createAttachment && operation.payload.containsString(ownerId) && operation.state.isEditable {
            for id in withDependents(operation.id, in: queue) where !result.contains(id) { result.append(id) }
        }
        return result
    }
}
