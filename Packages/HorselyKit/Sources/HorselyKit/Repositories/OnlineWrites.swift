import Foundation
import HorselyCore

/// Rodzaj operacji kolejki dla zapisu w trybie online, gdy nie wynika on z samego rekordu.
public enum OnlineHint: Sendable, Equatable {
    case automatic
    case completeReminder
    case dismissReminder
    case reschedule
}

/// Zapis z formularza w trybie online (T085, research R8/R9; `WriteService.kt`): zmiana od razu w telefonie — rekord główny
/// `Pending` (z wersją bazową z programu), skutki reguł `Projected` — i operacja w kolejce połączona z poprzednimi zmianami tego
/// rekordu (`OperationCoalescer`). Wszystko w transakcji wołającego: po przerwaniu nie zostaje rekord bez operacji ani odwrotnie.
enum OnlineWrites {
    struct Applied {
        var steps: [UndoStep] = []
        var operationIds: [String] = []
    }

    static func apply(_ saved: RuleSaved, hint: OnlineHint, access: RecordAccess, now: Date, includePhoto: Bool = false) throws -> Applied {
        var applied = Applied()
        let primary = saved.writes.first(where: \.primary)
        let deletedBatch = primary?.deletedAt != nil ? primary?.deletionBatchId : nil
        var rows: [StoredRecord] = []
        for write in saved.writes {
            let type = write.record.recordType
            let id = write.record.id
            let previous = try access.get(type, id: id)
            applied.steps.append(UndoStep(type: type, id: id, previous: previous))
            if write.deletedAt != nil {
                // Usunięcie w trybie online: rekord (i zależne z tej samej partii) znika z telefonu; kosz prowadzi program.
                if previous != nil && (write.primary || (deletedBatch != nil && write.deletionBatchId == deletedBatch)) { try access.deleteHard(type, id: id) }
                if write.primary, let previous {
                    let base = previous.syncState.isUnsent ? previous.baseVersion : previous.version
                    if let operation = operation(.deleteRecord, record: write.record, previous: previous, baseVersion: base, access: access, now: now, includePhoto: includePhoto) {
                        try queue(operation, access: access, now: now, into: &applied)
                    }
                }
                continue
            }
            if write.primary {
                let base: Int? = previous.map { $0.syncState == .synced || $0.syncState == .projected ? $0.version : $0.baseVersion } ?? nil
                rows.append(try StoredRecord.of(write.record, syncState: .pending, baseVersion: base, dateKey: write.dateKey))
                let kind: OperationKind?
                switch hint {
                case .completeReminder: kind = .completeReminder
                case .dismissReminder: kind = .dismissReminder
                case .reschedule: kind = previous == nil ? OperationKind.create(for: type) : .rescheduleReminder
                case .automatic: kind = previous == nil ? OperationKind.create(for: type) : .updateRecord
                }
                if let kind, let operation = operation(kind, record: write.record, previous: previous, baseVersion: previous == nil ? nil : base, access: access, now: now, includePhoto: includePhoto) {
                    try queue(operation, access: access, now: now, into: &applied)
                }
            } else if let previous, previous.syncState.isUnsent {
                // Skutek na rekordzie, który sam czeka na wysłanie — zostaje w swoim stanie.
                rows.append(try StoredRecord.of(write.record, syncState: previous.syncState, baseVersion: previous.baseVersion, dateKey: write.dateKey))
            } else {
                rows.append(try StoredRecord.of(write.record, syncState: .projected, baseVersion: previous?.version, dateKey: write.dateKey))
            }
        }
        if !rows.isEmpty { try access.upsert(rows) }
        return applied
    }

    /// Operacja kolejki dla rekordu: treść żądania programu, zależności od rekordów tworzonych w kolejce, konie i opis bez treści.
    static func operation(
        _ kind: OperationKind, record: any LocalRecord, previous: StoredRecord?, baseVersion: Int?, access: RecordAccess, now: Date, includePhoto: Bool
    ) -> OutboxOperation? {
        let payload: JSONValue
        switch kind {
        case .completeReminder, .dismissReminder:
            payload = .object(["id": .string(record.id)])
        case .deleteRecord:
            payload = record.recordType == .competitionStart ? .object(["competitionId": .string(record.parentId ?? "")]) : .object([:])
        default:
            var body = ApiRecordMapping.input(record, includePhoto: includePhoto && kind.isUpdate)
            if record.recordType == .competitionStart, case var .object(fields) = body {
                fields["competitionId"] = .string(record.parentId ?? "")
                body = .object(fields)
            }
            payload = body
        }
        let queue = (try? access.operations()) ?? []
        // Rekordy tworzone w kolejce, do których odwołuje się treść (koń, kontakt, zawody) — wysyłka czeka na nie.
        let dependsOn = queue.filter { $0.kind.isCreate && $0.state.isUnsent && $0.recordId != record.id && ($0.recordId.map { payload.containsString($0) } ?? false) }.map(\.id)
        let horses = record.horseIds.compactMap { id -> HorseRef? in
            if record.recordType == .horse, let horse = record as? LocalHorse { return HorseRef(horse) }
            guard let row = try? access.get(.horse, id: id), let horse = try? row.record(as: LocalHorse.self) else { return nil }
            return HorseRef(horse)
        }
        let selfRef = (record as? LocalHorse).map { [HorseRef($0)] } ?? []
        let refs = horses.isEmpty ? selfRef : horses
        let who: String
        if refs.isEmpty {
            who = record.recordType == .purchase ? "cała stajnia" : "stajnia"
        } else if refs.count <= 2 {
            who = refs.map(\.name).joined(separator: ", ")
        } else {
            who = refs.prefix(2).map(\.name).joined(separator: ", ") + " +\(refs.count - 2)"
        }
        let label = kind.isCreate ? kind.label : "\(kind.label) · \(RecordLabels.name(record.recordType))"
        let date = record.dateKey.map { " · " + Formats.date($0) } ?? ""
        let id = UUID().uuidString.lowercased()
        return OutboxOperation(
            id: id, kind: kind, localRef: record.id, payload: payload, dependsOn: dependsOn, horseRefs: refs,
            summary: "\(label) · \(who)\(date)", createdAt: now, updatedAt: now, recordType: record.recordType, recordId: record.id, baseVersion: baseVersion
        )
    }

    /// Dodaje operację z łączeniem (FR-SYN2-04).
    static func queue(_ operation: OutboxOperation, access: RecordAccess, now: Date, into applied: inout Applied) throws {
        switch OperationCoalescer.decide(operation, queue: try access.operations(), now: now) {
        case let .queue(op):
            try access.enqueue(op)
            applied.operationIds.append(op.id)
        case let .merge(merged):
            if try access.updateOperation(merged.id, expected: OutboxState.editable, { _ in merged }) != nil {
                applied.operationIds.append(merged.id)
            } else {
                try access.enqueue(operation)
                applied.operationIds.append(operation.id)
            }
        case let .cancel(removed):
            for id in removed {
                let result = try access.deleteOperation(id, allowed: Set(OutboxState.allCases))
                result.files.forEach(OutboxProcessor.release)
            }
        }
    }
}

/// Nazwy rodzajów rekordów do opisów kolejki (bez treści wpisów).
enum RecordLabels {
    static func name(_ type: RecordType) -> String {
        switch type {
        case .dictionary: "słownik"
        case .contact: "kontakt"
        case .horse: "koń"
        case .vetVisit: "wizyta weterynaryjna"
        case .farrierVisit: "wizyta kowala"
        case .physioVisit: "fizjoterapia"
        case .specialistVisit: "wizyta specjalisty"
        case .competition: "zawody"
        case .competitionStart: "start"
        case .purchase: "zakup"
        case .note: "notatka"
        case .training: "trening"
        case .reminder: "termin"
        case .attachment: "załącznik"
        }
    }
}
