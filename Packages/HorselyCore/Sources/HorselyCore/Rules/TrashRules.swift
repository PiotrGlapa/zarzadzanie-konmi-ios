import Foundation

/// Kosz (`TrashService`) — część potrzebna wpisom (faza 4): usunięcie rekordu wraz z zależnymi w jednej partii (id korzenia) i
/// przywrócenie partii z kontrolą rodziców. Podgląd kosza, trwałe usunięcie i opróżnianie dochodzą w zadaniach T121–T126.
enum TrashRules {
    private static let ownerTypes: [AttachmentOwnerType: RecordType] = [
        .horse: .horse, .vetVisit: .vetVisit, .farrierVisit: .farrierVisit, .physioVisit: .physioVisit, .specialistVisit: .specialistVisit,
        .competition: .competition, .competitionStart: .competitionStart, .purchase: .purchase, .note: .note, .contact: .contact,
    ]

    private static let horseOwned: [RecordType] = [.vetVisit, .farrierVisit, .physioVisit, .specialistVisit, .note, .training, .competitionStart, .reminder]

    private static let sourceType: [RecordType: String] = [
        .vetVisit: "VetVisit", .farrierVisit: "FarrierVisit", .physioVisit: "PhysioVisit", .specialistVisit: "SpecialistVisit", .competitionStart: "CompetitionStart",
    ]

    /// Zależni (aktywni) od `root`: koń → jego wpisy i terminy, zawody → starty, wizyta/start → jej termin, każdy właściciel → załączniki.
    private static func dependents(_ session: RuleSession, of root: any LocalRecord) throws -> [any LocalRecord] {
        var result: [any LocalRecord] = []
        switch root.recordType {
        case .horse:
            for type in horseOwned { result += try session.records(type, horseId: root.id) }
        case .competition:
            result += try session.ownerRecords(.competitionStart, root.id)
        default:
            break
        }
        if let source = sourceType[root.recordType] {
            result += try session.byOwner(.reminder, root.id, as: LocalReminder.self).filter { $0.sourceType == source }
        }
        if let ownerType = ownerTypes.first(where: { $0.value == root.recordType })?.key {
            result += try session.byOwner(.attachment, root.id, as: LocalAttachment.self).filter { $0.ownerType == ownerType }
        }
        return result
    }

    /// Korzeń i zależni rekursywnie (kolejność: korzeń, potem w głąb), bez powtórzeń.
    private static func collect(_ session: RuleSession, root: any LocalRecord) throws -> [any LocalRecord] {
        var seen: [String] = []
        var ordered: [any LocalRecord] = []
        func visit(_ record: any LocalRecord) throws {
            let key = "\(record.recordType.rawValue):\(record.id)"
            guard !seen.contains(key) else { return }
            seen.append(key)
            ordered.append(record)
            for dependent in try dependents(session, of: record) { try visit(dependent) }
        }
        try visit(root)
        return ordered
    }

    /// Przenosi rekord z zależnymi do kosza; zwraca id partii (id korzenia).
    static func softDelete(_ session: RuleSession, type: RecordType, id: String) throws -> String {
        guard let row = try session.row(type, id) else { throw session.notFound(type.rawValue, id) }
        let batch = try collect(session, root: row.record)
        let deletedIds = Set(batch.map(\.id))
        for record in batch { try session.trash(record, batchId: id, primary: record.id == id) }
        try reopenRemindersCompleted(by: deletedIds, session)
        try clearDeletedHorsePhotos(batch, session)
        return id
    }

    /// Termin zamknięty przez wpis, który idzie do kosza, jest znowu otwarty (poza partią — razem z nią zostaje, jaki był).
    private static func reopenRemindersCompleted(by deletedIds: Set<String>, _ session: RuleSession) throws {
        for reminder in try session.all(.reminder, as: LocalReminder.self) {
            if reminder.status == .completed, let by = reminder.completedById, deletedIds.contains(by), !deletedIds.contains(reminder.id) {
                try session.replaceDerived(old: reminder, with: ReminderAutomation.reopen(reminder))
            }
        }
    }

    /// Zdjęcie konia usunięte osobno jest zdejmowane z konia (inaczej trwałe usunięcie załącznika wymagałoby usunięcia konia).
    private static func clearDeletedHorsePhotos(_ batch: [any LocalRecord], _ session: RuleSession) throws {
        let photos = Set(batch.compactMap { $0 as? LocalAttachment }.filter { $0.ownerType == .horse }.map(\.id))
        guard !photos.isEmpty else { return }
        for horse in try session.all(.horse, as: LocalHorse.self) where horse.photoAttachmentId.map(photos.contains) == true {
            var copy = horse
            copy.photoAttachmentId = nil
            try session.replaceDerived(old: horse, with: copy)
        }
    }

    /// Przywraca całą partię z kosza; rekord, którego rodzic (koń, zawody) jest w koszu poza tą partią, blokuje przywrócenie.
    static func restore(_ session: RuleSession, source: RecordSource, batchId: String) throws {
        let rows = try source.byBatch(batchId)
        guard !rows.isEmpty else { throw session.invalid("batchId", Messages.trashBatchNotFound) }
        let ids = Set(rows.map(\.record.id))
        for row in rows {
            let record = row.record
            if let horseId = record.primaryHorseId, record.recordType != .horse, !ids.contains(horseId), try session.horse(horseId) == nil {
                throw session.conflict(.invalidState, Messages.parentIsDeleted)
            }
            if let start = record as? LocalCompetitionStart, !ids.contains(start.competitionId), try session.competition(start.competitionId) == nil {
                throw session.conflict(.invalidState, Messages.parentIsDeleted)
            }
            if let horse = record as? LocalHorse {
                let others = try session.all(.horse, as: LocalHorse.self)
                if let problem = HorseRules.uniquenessProblem(name: horse.name, passportNumber: horse.passportNumber, isFoal: horse.isFoal, among: others, excluding: horse.id) {
                    throw session.conflict(.unique, problem.message)
                }
            }
        }
        // Korzeń (id partii) pierwszy, żeby rekordy zależne widziały rodzica jako aktywnego.
        for row in rows.sorted(by: { $0.record.id == batchId && $1.record.id != batchId }) {
            try session.untrash(row.record, primary: row.record.id == batchId)
        }
    }
}

