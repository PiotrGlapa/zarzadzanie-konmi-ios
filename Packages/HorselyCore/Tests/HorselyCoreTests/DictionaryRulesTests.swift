import Testing
@testable import HorselyCore

/// Słowniki trybu samodzielnego (T122, FR-001…FR-004): domyślny zestaw programu 2.0.0, dopisanie rodzajów treningów, porównywanie nazw,
/// zakaz usunięcia wartości systemowych i używanych, kolejność.
struct DictionaryRulesTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 1, hour: 9)!
    private let dates = FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 5)!)

    private func item(_ id: String, _ value: String, _ type: DictionaryType = .trainingType, order: Int = 1, system: String? = nil, active: Bool = true) -> LocalDictionaryItem {
        LocalDictionaryItem(
            id: id, createdAt: stamp, updatedAt: stamp, version: 1, dictionaryType: type, value: value, sortOrder: order, isActive: active,
            isSystem: system != nil, systemKey: system
        )
    }

    private func source(_ records: [any LocalRecord]) -> InMemoryRecordSource {
        InMemoryRecordSource(rows: records.map { SourceRow(record: $0, dateKey: $0.dateKey) })
    }

    private func apply(_ outcome: RuleOutcome, to source: InMemoryRecordSource) throws {
        let saved = try #require(outcome.saved, "\(String(describing: outcome.problem))")
        for write in saved.writes {
            source.upsert(SourceRow(record: write.record, dateKey: write.dateKey, isDeleted: write.deletedAt != nil, deletionBatchId: write.deletionBatchId))
        }
    }

    // MARK: Zestaw domyślny i dopisanie 2.0.0

    @Test func theDefaultTrainingTypesAreTheProgram200Set() {
        #expect(DefaultDictionaries.values(of: .trainingType).map(\.value) == [
            "Ujeżdżenie", "Skoki", "Teren", "Lonża", "Karuzela", "Spacer", "Zajeżdżanie", "Gimnastyka", "Wszechstronny", "Inne",
        ])
        #expect(DefaultDictionaries.values(of: .trainingType).first { $0.value == "Skoki" }?.systemKey == DefaultDictionaries.trainingJumping)
    }

    @Test func namesAreComparedWithoutCaseSpacesAndPolishMarks() {
        #expect(DictionaryNames.normalize("  Zajeżdżanie ") == DictionaryNames.normalize("zajezdzanie"))
        #expect(DictionaryNames.normalize("Łonża") == "lonza")
        #expect(DictionaryNames.normalize("   ") == "")
        #expect(DictionaryNames.missing(["Zajeżdżanie", "Gimnastyka", "Wszechstronny"], existing: ["ZAJEZDZANIE", " gimnastyka"]) == ["Wszechstronny"])
    }

    @Test func missingTrainingTypesAreAddedOnceAtTheEnd() {
        var counter = 0
        let existing = [item("t1", "Ujeżdżenie", order: 1), item("t2", "Skoki", order: 2, system: DefaultDictionaries.trainingJumping), item("t3", "gimnastyka", order: 7, active: false)]
        let added = DictionaryUpgrades.missingTrainingTypes(existing: existing, newId: { counter += 1; return "n\(counter)" }, now: stamp)
        #expect(added.map(\.value) == ["Zajeżdżanie", "Wszechstronny"])
        #expect(added.map(\.sortOrder) == [8, 9])
        #expect(added.allSatisfy { $0.isActive && !$0.isSystem })
    }

    @Test func withoutAnyTrainingTypeTheFullListIsAdded() {
        var counter = 0
        let added = DictionaryUpgrades.missingTrainingTypes(existing: [item("u1", "kg", .unit)], newId: { counter += 1; return "n\(counter)" }, now: stamp)
        #expect(added.map(\.value) == DefaultDictionaries.values(of: .trainingType).map(\.value))
        #expect(added.first { $0.value == "Skoki" }?.isSystem == true)
    }

    @Test func schemaVersionsBefore15LackThe200TrainingTypes() {
        #expect(DictionaryUpgrades.isBeforeTrainingTypes200("1.4"))
        #expect(DictionaryUpgrades.isBeforeTrainingTypes200("1.3"))
        #expect(!DictionaryUpgrades.isBeforeTrainingTypes200("1.5"))
        #expect(!DictionaryUpgrades.isBeforeTrainingTypes200("2.0"))
        #expect(!DictionaryUpgrades.isBeforeTrainingTypes200("x"))
    }

    // MARK: Edycja

    @Test func addingAValueGoesToTheEndAndDuplicatesAreRejected() throws {
        let source = source([item("t1", "Ujeżdżenie", order: 1), item("t2", "Skoki", order: 2)])
        let created = RuleEngine(source: source, dates: dates, newId: { "t3" }).createDictionaryItem(type: .trainingType, value: "  Hipoterapia ")
        let saved = try #require(created.saved?.record as? LocalDictionaryItem)
        #expect(saved.value == "Hipoterapia")
        #expect(saved.sortOrder == 3)
        let duplicate = RuleEngine(source: source, dates: dates).createDictionaryItem(type: .trainingType, value: "skoki")
        #expect(duplicate.problem == .conflict(reason: .unique, message: Messages.dictionaryValueNotUnique))
        let empty = RuleEngine(source: source, dates: dates).createDictionaryItem(type: .trainingType, value: "  ")
        #expect(empty.problem == .validation(errors: ["value": [Messages.required]]))
    }

    @Test func systemValuesCanBeRenamedButNotHiddenOrDeleted() throws {
        let source = source([item("t2", "Skoki", order: 2, system: DefaultDictionaries.trainingJumping)])
        let renamed = RuleEngine(source: source, dates: dates).updateDictionaryItem(id: "t2", value: "Skoki przez przeszkody")
        #expect((renamed.saved?.record as? LocalDictionaryItem)?.value == "Skoki przez przeszkody")
        let hidden = RuleEngine(source: source, dates: dates).updateDictionaryItem(id: "t2", value: "Skoki", isActive: false)
        #expect(hidden.problem == .conflict(reason: .invalidState, message: Messages.dictionarySystemValue))
        let deleted = RuleEngine(source: source, dates: dates).deleteDictionaryItem(id: "t2")
        #expect(deleted.problem == .conflict(reason: .invalidState, message: Messages.dictionarySystemValue))
    }

    @Test func aValueUsedEvenByATrashedEntryCannotBeDeletedButCanBeHidden() throws {
        let training = LocalTraining(id: "tr1", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", trainingDate: LocalDate("2026-10-02")!, trainingTypeId: "t1")
        let source = source([item("t1", "Teren", order: 1), item("t9", "Pusty", order: 2)])
        source.upsert(SourceRow(record: training, dateKey: training.dateKey, isDeleted: true, deletionBatchId: "tr1"))
        #expect(RuleEngine(source: source, dates: dates).deleteDictionaryItem(id: "t1").problem == .conflict(reason: .inUse, message: Messages.dictionaryValueInUse))
        try apply(RuleEngine(source: source, dates: dates).updateDictionaryItem(id: "t1", value: "Teren", isActive: false), to: source)
        #expect((try source.get(.dictionary, id: "t1")?.record as? LocalDictionaryItem)?.isActive == false)
        try apply(RuleEngine(source: source, dates: dates).deleteDictionaryItem(id: "t9"), to: source)
        #expect(try source.get(.dictionary, id: "t9")?.isDeleted == true)
    }

    @Test func reorderingNumbersFromOneAndNeedsTheWholeList() throws {
        let source = source([item("a", "A", order: 1), item("b", "B", order: 2), item("c", "C", order: 3)])
        let saved = try #require(RuleEngine(source: source, dates: dates).reorderDictionary(type: .trainingType, orderedIds: ["c", "a", "b"]).saved)
        let orders = Dictionary(uniqueKeysWithValues: saved.writes.compactMap { $0.record as? LocalDictionaryItem }.map { ($0.id, $0.sortOrder) })
        #expect(orders == ["c": 1, "a": 2, "b": 3])
        let partial = RuleEngine(source: source, dates: dates).reorderDictionary(type: .trainingType, orderedIds: ["c", "a"])
        #expect(partial.problem == .validation(errors: ["orderedIds": [Messages.dictionaryReorderMismatch]]))
    }
}
