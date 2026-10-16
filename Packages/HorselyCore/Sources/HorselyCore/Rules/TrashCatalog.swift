import Foundation

/// Pozycja kosza: korzeń partii (`id` = id partii), opis jak w programie, koń, czas usunięcia i liczba rekordów usuniętych razem z nim.
public struct TrashEntry: Equatable, Sendable, Identifiable {
    public let type: RecordType
    public let id: String
    public let description: String
    public let horseId: String?
    public let horseName: String?
    public let deletedAt: LocalDateTime
    public let dependentCount: Int

    public init(type: RecordType, id: String, description: String, horseId: String?, horseName: String?, deletedAt: LocalDateTime, dependentCount: Int) {
        self.type = type
        self.id = id
        self.description = description
        self.horseId = horseId
        self.horseName = horseName
        self.deletedAt = deletedAt
        self.dependentCount = dependentCount
    }
}

/// Plan trwałego usunięcia partii: rekordy do usunięcia na zawsze (partia i usunięte wcześniej rekordy, które się do niej odwołują)
/// oraz zakupy, z których znika trwale usunięty koń.
public struct PurgePlan: Sendable {
    public let deletes: [(type: RecordType, id: String)]
    public let purchases: [LocalPurchase]

    /// Załączniki usuwane na zawsze — ich pliki znikają z telefonu.
    public var attachmentIds: [String] { deletes.filter { $0.type == .attachment }.map(\.id) }
}

public struct TrashBatchNotFound: Error, Equatable, Sendable {
    public let batchId: String
}

/// Kosz trybu samodzielnego (T124, FR-SAM-04; `TrashRules.kt`): lista partii, opisy i trwałe usuwanie.
public enum TrashCatalog {
    static let horseOwned: [RecordType] = [.vetVisit, .farrierVisit, .physioVisit, .specialistVisit, .note, .training, .competitionStart, .reminder]

    /// Pozycje kosza (korzenie partii), najnowsze pierwsze. `trashed` — wszystkie rekordy w koszu z czasem usunięcia.
    public static func entries(_ trashed: [(row: SourceRow, deletedAt: LocalDateTime)], source: RecordSource) -> [TrashEntry] {
        var counts: [String: Int] = [:]
        for item in trashed { counts[item.row.deletionBatchId ?? "", default: 0] += 1 }
        var names: [String: String] = [:]
        func horseName(_ id: String?) -> String? {
            guard let id else { return nil }
            if let name = names[id] { return name }
            let name = (try? source.get(.horse, id: id))?.record as? LocalHorse
            names[id] = name?.name
            return name?.name
        }
        return trashed.filter { $0.row.record.id == $0.row.deletionBatchId }
            .map { item in
                let (text, horseId) = describe(item.row.record, source: source)
                return TrashEntry(
                    type: item.row.record.recordType, id: item.row.record.id, description: text, horseId: horseId, horseName: horseName(horseId),
                    deletedAt: item.deletedAt, dependentCount: (counts[item.row.record.id] ?? 1) - 1
                )
            }
            .sorted { ($0.deletedAt, $0.id) > ($1.deletedAt, $1.id) }
    }

    /// Opis pozycji kosza i koń, którego dotyczy (jak `TrashRules.describe` w Androidzie).
    public static func describe(_ record: any LocalRecord, source: RecordSource) -> (String, String?) {
        func dictionary(_ id: String?) -> String {
            guard let id else { return "" }
            return ((try? source.get(.dictionary, id: id))?.record as? LocalDictionaryItem)?.value ?? ""
        }
        func date(_ day: LocalDate) -> String { Formats.date(day) }
        switch record {
        case let horse as LocalHorse:
            let passport = horse.passportNumber?.trimmingCharacters(in: .whitespaces) ?? ""
            return (passport.isEmpty ? "Koń: \(horse.name)" : "Koń: \(horse.name) (\(passport))", horse.id)
        case let contact as LocalContact: return ("Kontakt: \(contact.name)", nil)
        case let item as LocalDictionaryItem: return ("Wartość słownika: \(item.value)", nil)
        case let visit as LocalVetVisit: return ("Wizyta weterynaryjna \(date(visit.visitDateTime.date)): \(dictionary(visit.visitTypeId))", visit.horseId)
        case let visit as LocalFarrierVisit: return ("Wizyta kowala \(date(visit.visitDate)): \(dictionary(visit.serviceId))", visit.horseId)
        case let visit as LocalPhysioVisit: return ("Wizyta fizjoterapeuty \(date(visit.visitDate))", visit.horseId)
        case let visit as LocalSpecialistVisit: return ("Wizyta specjalisty \(date(visit.visitDate)): \(dictionary(visit.specialistTypeId))", visit.horseId)
        case let training as LocalTraining: return ("Trening \(date(training.trainingDate)): \(dictionary(training.trainingTypeId))", training.horseId)
        case let note as LocalNote: return ("Notatka \(date(note.noteDate)): \(note.title)", note.horseId)
        case let purchase as LocalPurchase:
            return ("Zakup \(date(purchase.purchaseDate)): \(purchase.productName) (\(Formats.money(purchase.totalAmount + purchase.deliveryCost)))", nil)
        case let competition as LocalCompetition: return ("Zawody \(date(competition.dateFrom)): \(competition.name)", nil)
        case let start as LocalCompetitionStart:
            let competition = (try? source.get(.competition, id: start.competitionId))?.record as? LocalCompetition
            let day = start.startDate ?? competition?.dateFrom
            return ("Start \(day.map(date) ?? ""): \(competition?.name ?? "")", start.horseId)
        case let reminder as LocalReminder: return ("Termin \(date(reminder.dueDate)): \(reminder.title)", reminder.horseId)
        case let attachment as LocalAttachment: return ("Załącznik: \(attachment.fileName)", attachment.horseId)
        default: return (record.recordType.rawValue, nil)
        }
    }

    /// Plan trwałego usunięcia partii `batchId` (razem z usuniętymi wcześniej rekordami konia albo zawodów z tej partii).
    public static func purgePlan(source: RecordSource, batchId: String, now: LocalDateTime) throws -> PurgePlan {
        var order: [String] = []
        var batch: [String: SourceRow] = [:]
        func key(_ row: SourceRow) -> String { "\(row.record.recordType.rawValue):\(row.record.id)" }
        func add(_ row: SourceRow) -> Bool {
            let k = key(row)
            guard batch[k] == nil else { return false }
            batch[k] = row
            order.append(k)
            return true
        }
        var queue = try source.byBatch(batchId)
        guard !queue.isEmpty else { throw TrashBatchNotFound(batchId: batchId) }
        queue.forEach { _ = add($0) }
        while !queue.isEmpty {
            let row = queue.removeFirst()
            var referencing: [SourceRow] = []
            switch row.record.recordType {
            case .horse:
                for type in horseOwned {
                    referencing += try source.query(type, horseId: row.record.id, from: nil, to: nil, includeDeleted: true).filter(\.isDeleted)
                }
            case .competition:
                referencing += try source.byOwner(.competitionStart, ownerId: row.record.id, includeDeleted: true).filter(\.isDeleted)
            default:
                break
            }
            // Załączniki trwale usuwanego rekordu (także usunięte wcześniej osobno) — inaczej zostałyby w koszu bez właściciela.
            if row.record.recordType != .attachment {
                referencing += try source.byOwner(.attachment, ownerId: row.record.id, includeDeleted: true).filter(\.isDeleted)
            }
            for other in referencing where add(other) { queue.append(other) }
        }
        let horses = order.compactMap { batch[$0] }.filter { $0.record.recordType == .horse }.map(\.record.id)
        var purchases: [String: LocalPurchase] = [:]
        for horseId in horses {
            for row in try source.query(.purchase, horseId: horseId, from: nil, to: nil, includeDeleted: true) {
                guard var purchase = (purchases[row.record.id] ?? row.record as? LocalPurchase) else { continue }
                purchase.horseIds.removeAll { $0 == horseId }
                purchase.assignment = purchase.horseIds.isEmpty ? .general : (purchase.horseIds.count == 1 ? .singleHorse : .multipleHorses)
                purchases[row.record.id] = purchase
            }
        }
        let changed = purchases.values.sorted { $0.id < $1.id }.compactMap { purchase -> LocalPurchase? in
            guard let current = try? source.get(.purchase, id: purchase.id) else { return nil }
            return purchase.withAudit(version: current.record.version + 1, updatedAt: now)
        }
        return PurgePlan(deletes: order.compactMap { batch[$0] }.map { ($0.record.recordType, $0.record.id) }, purchases: changed)
    }
}
