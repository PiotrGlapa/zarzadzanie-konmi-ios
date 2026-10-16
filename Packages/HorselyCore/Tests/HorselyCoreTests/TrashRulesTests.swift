import Testing
@testable import HorselyCore

/// Kosz trybu samodzielnego (T121): partie z zależnymi, przywrócenie z kontrolą rodzica, trwałe usunięcie (koń znika z zakupów),
/// opróżnienie i opisy pozycji.
struct TrashRulesTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 1, hour: 9)!
    private let dates = FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 5)!)

    private func source() -> InMemoryRecordSource {
        let horse = LocalHorse(id: "h1", createdAt: stamp, updatedAt: stamp, version: 1, name: "Grom", passportNumber: "PL-1")
        let other = LocalHorse(id: "h2", createdAt: stamp, updatedAt: stamp, version: 1, name: "Iskra", passportNumber: "PL-2")
        let note = LocalNote(id: "n1", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", noteDate: LocalDate("2026-10-02")!, title: "Kulawizna")
        let reminder = LocalReminder(id: "r1", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", kind: .farrier, dueDate: LocalDate("2026-10-20")!, title: "Kowal")
        let attachment = LocalAttachment(
            id: "a1", createdAt: stamp, updatedAt: stamp, version: 1, ownerType: .note, ownerId: "n1", horseId: "h1", fileName: "rana.jpg",
            contentType: "image/jpeg", sizeBytes: 10, sha256: "abc"
        )
        let purchase = LocalPurchase(
            id: "p1", createdAt: stamp, updatedAt: stamp, version: 1, purchaseDate: LocalDate("2026-10-03")!, productName: "Siano", categoryId: "c1",
            totalAmount: Money(300), deliveryCost: .zero, assignment: .multipleHorses, horseIds: ["h1", "h2"]
        )
        let rows: [any LocalRecord] = [horse, other, note, reminder, attachment, purchase]
        return InMemoryRecordSource(rows: rows.map { SourceRow(record: $0, dateKey: $0.dateKey) })
    }

    private func apply(_ outcome: RuleOutcome, to source: InMemoryRecordSource) throws -> RuleSaved {
        let saved = try #require(outcome.saved, "\(String(describing: outcome.problem))")
        for write in saved.writes {
            source.upsert(SourceRow(record: write.record, dateKey: write.dateKey, isDeleted: write.deletedAt != nil, deletionBatchId: write.deletionBatchId))
        }
        return saved
    }

    private func trashed(_ source: InMemoryRecordSource) throws -> [(row: SourceRow, deletedAt: LocalDateTime)] {
        try RecordType.allCases.flatMap { try source.query($0, horseId: nil, from: nil, to: nil, includeDeleted: true) }
            .filter(\.isDeleted).map { ($0, stamp) }
    }

    @Test func deletingAHorseTrashesItsEntriesRemindersAndAttachmentsInOneBatch() throws {
        let source = source()
        let saved = try apply(RuleEngine(source: source, dates: dates).delete(.horse, id: "h1"), to: source)
        #expect(saved.batchId == "h1")
        let batch = try source.byBatch("h1").map(\.record.id).sorted()
        #expect(batch == ["a1", "h1", "n1", "r1"])
        let entries = TrashCatalog.entries(try trashed(source), source: source)
        #expect(entries.count == 1)
        #expect(entries.first?.description == "Koń: Grom (PL-1)")
        #expect(entries.first?.dependentCount == 3)
    }

    @Test func restoringAnEntryOfAHorseInTheTrashIsBlocked() throws {
        let source = source()
        _ = try apply(RuleEngine(source: source, dates: dates).delete(.note, id: "n1"), to: source)
        _ = try apply(RuleEngine(source: source, dates: dates).delete(.horse, id: "h1"), to: source)
        let blocked = RuleEngine(source: source, dates: dates).restore(batchId: "n1")
        #expect(blocked.problem == .conflict(reason: .invalidState, message: Messages.parentIsDeleted))
        _ = try apply(RuleEngine(source: source, dates: dates).restore(batchId: "h1"), to: source)
        _ = try apply(RuleEngine(source: source, dates: dates).restore(batchId: "n1"), to: source)
        #expect(try source.get(.note, id: "n1")?.isDeleted == false)
        #expect(try source.get(.attachment, id: "a1")?.isDeleted == false)
    }

    @Test func purgingAHorseTakesItsEarlierTrashedEntriesAndRemovesItFromPurchases() throws {
        let source = source()
        _ = try apply(RuleEngine(source: source, dates: dates).delete(.note, id: "n1"), to: source)
        _ = try apply(RuleEngine(source: source, dates: dates).delete(.horse, id: "h1"), to: source)
        let plan = try TrashCatalog.purgePlan(source: source, batchId: "h1", now: stamp)
        let deleted = plan.deletes.map(\.id).sorted()
        #expect(deleted == ["a1", "h1", "n1", "r1"], "notatka usunięta wcześniej odchodzi z koniem")
        #expect(plan.attachmentIds == ["a1"])
        let purchase = try #require(plan.purchases.first)
        #expect(purchase.horseIds == ["h2"])
        #expect(purchase.assignment == .singleHorse)
        #expect(purchase.version == 2)
    }

    @Test func purgingAnUnknownBatchFails() {
        #expect(throws: TrashBatchNotFound.self) { try TrashCatalog.purgePlan(source: source(), batchId: "brak", now: stamp) }
    }

    @Test func entriesAreNewestFirstWithDescriptionsLikeTheProgram() throws {
        let source = source()
        _ = try apply(RuleEngine(source: source, dates: dates).delete(.purchase, id: "p1"), to: source)
        _ = try apply(RuleEngine(source: source, dates: dates).delete(.note, id: "n1"), to: source)
        let rows = try RecordType.allCases.flatMap { try source.query($0, horseId: nil, from: nil, to: nil, includeDeleted: true) }.filter(\.isDeleted)
        let trashed = rows.map { row in (row: row, deletedAt: row.record.recordType == .purchase ? stamp : LocalDateTime(year: 2026, month: 10, day: 4, hour: 8)!) }
        let entries = TrashCatalog.entries(trashed, source: source)
        #expect(entries.map(\.id) == ["n1", "p1"])
        #expect(entries.map(\.description) == ["Notatka 02.10.2026: Kulawizna", "Zakup 03.10.2026: Siano (300,00 zł)"])
        #expect(entries.first?.horseName == "Grom")
    }
}
