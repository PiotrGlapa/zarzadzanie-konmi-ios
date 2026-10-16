import Foundation
import HorselyCore

/// Kosz trybu samodzielnego (T126, FR-SAM-04): partie z opisami, przywrócenie (reguły — kontrola rodzica i unikalności),
/// trwałe usunięcie z plikami załączników i opróżnienie.
public final class TrashRepository: Sendable {
    private let store: RecordStore
    private let entries: EntryRepository
    private let files: LocalFileStore
    private let dates: any DateProvider

    public init(store: RecordStore, entries: EntryRepository, files: LocalFileStore, dates: any DateProvider = SystemDateProvider()) {
        self.store = store
        self.entries = entries
        self.files = files
        self.dates = dates
    }

    /// Pozycje kosza, najnowsze pierwsze.
    public func list() async throws -> [TrashEntry] {
        try await store.read { access in
            let source = AccessRecordSource(access: access)
            let trashed = try access.trashed().compactMap { row -> (row: SourceRow, deletedAt: LocalDateTime)? in
                guard let deletedAt = row.deletedAt else { return nil }
                return (SourceRow(record: try row.record(), dateKey: row.dateKey, isDeleted: true, deletionBatchId: row.deletionBatchId), deletedAt)
            }
            return TrashCatalog.entries(trashed, source: source)
        }
    }

    public func restore(batchId: String) async throws -> EntryResult {
        try await entries.perform { $0.restore(batchId: batchId) }
    }

    /// Trwałe usunięcie partii (z usuniętymi wcześniej rekordami konia/zawodów); koń znika z zakupów, pliki załączników z telefonu.
    public func purge(batchId: String) async throws {
        let now = dates.now()
        let removed = try await store.write { access -> [String] in
            let plan = try TrashCatalog.purgePlan(source: AccessRecordSource(access: access), batchId: batchId, now: now)
            try Self.apply(plan, access: access)
            return plan.attachmentIds
        }
        removed.forEach(files.delete)
    }

    /// Opróżnia kosz (wszystkie partie).
    public func empty() async throws {
        let now = dates.now()
        let removed = try await store.write { access -> [String] in
            var attachments: [String] = []
            while let root = try access.trashed().first(where: { $0.id == $0.deletionBatchId }) {
                let plan = try TrashCatalog.purgePlan(source: AccessRecordSource(access: access), batchId: root.id, now: now)
                try Self.apply(plan, access: access)
                attachments += plan.attachmentIds
            }
            // Rekordy w koszu bez korzenia partii (np. z uszkodzonej kopii) też znikają.
            for row in try access.trashed() {
                try access.deleteHard(row.type, id: row.id)
                if row.type == .attachment {
                    try access.deleteFiles(attachmentId: row.id)
                    attachments.append(row.id)
                }
            }
            return attachments
        }
        removed.forEach(files.delete)
    }

    static func apply(_ plan: PurgePlan, access: RecordAccess) throws {
        for purchase in plan.purchases {
            guard let row = try access.get(.purchase, id: purchase.id) else { continue }
            try access.upsert([try StoredRecord.of(purchase, syncState: row.syncState, baseVersion: row.baseVersion, dateKey: row.dateKey, deletedAt: row.deletedAt, deletionBatchId: row.deletionBatchId)])
        }
        for item in plan.deletes {
            try access.deleteHard(item.type, id: item.id)
            if item.type == .attachment { try access.deleteFiles(attachmentId: item.id) }
        }
    }
}
