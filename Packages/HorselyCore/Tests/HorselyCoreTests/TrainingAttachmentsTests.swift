import Testing
@testable import HorselyCore

/// Załączniki treningu w regułach (ZAT-01, ZAT-06): zmiana konia treningu przenosi jego załączniki, a oferta załączników treningu zależy od
/// trybu i możliwości programu (`TrainingAttachmentsHorseTest.kt`, `TrainingAttachmentsTest.kt` Androida).
struct TrainingAttachmentsTests {
    private let stamp = LocalDateTime(year: 2026, month: 9, day: 28, hour: 10)!
    private let dates = FixedDateProvider(today: LocalDate(year: 2026, month: 9, day: 28)!)

    private func attachment(_ id: String, owner: AttachmentOwnerType, ownerId: String, horseId: String) -> LocalAttachment {
        LocalAttachment(
            id: id, createdAt: stamp, updatedAt: stamp, version: 1, ownerType: owner, ownerId: ownerId, horseId: horseId, fileName: "\(id).jpg",
            contentType: "image/jpeg", sizeBytes: 3, sha256: String(repeating: "a", count: 64)
        )
    }

    private func horse(_ id: String, _ name: String) -> LocalHorse {
        LocalHorse(id: id, createdAt: stamp, updatedAt: stamp, version: 1, name: name, passportNumber: "PL-\(id)")
    }

    @Test func changingTheHorseOfATrainingMovesItsAttachmentsToTheNewHorse() throws {
        let type = LocalDictionaryItem(id: "type-1", createdAt: stamp, updatedAt: stamp, version: 1, dictionaryType: .trainingType, value: "Ujeżdżenie", sortOrder: 1)
        let training = LocalTraining(
            id: "t1", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", trainingDate: LocalDate(year: 2026, month: 9, day: 20)!, trainingTypeId: "type-1"
        )
        let records: [any LocalRecord] = [
            horse("h1", "Grom"), horse("h2", "Iskra"), type, training,
            attachment("own", owner: .training, ownerId: "t1", horseId: "h1"),
            attachment("foreign", owner: .note, ownerId: "t1", horseId: "h1"),
        ]
        let source = InMemoryRecordSource(rows: records.map { SourceRow(record: $0, dateKey: $0.dateKey) })
        var input = TrainingInput()
        input.horseId = "h2"
        input.trainingDate = LocalDate(year: 2026, month: 9, day: 20)
        input.trainingTypeId = "type-1"

        let outcome = RuleEngine(source: source, dates: dates).updateTraining(id: "t1", input, expectedVersion: 1)

        let saved = try #require(outcome.saved, "zapis treningu: \(String(describing: outcome.problem))")
        for write in saved.writes {
            source.upsert(SourceRow(record: write.record, dateKey: write.dateKey, isDeleted: write.deletedAt != nil, deletionBatchId: write.deletionBatchId))
        }
        let own = try #require(try source.get(.attachment, id: "own")?.record as? LocalAttachment)
        let foreign = try #require(try source.get(.attachment, id: "foreign")?.record as? LocalAttachment)
        #expect(own.horseId == "h2")
        #expect(foreign.horseId == "h1", "załącznik innego właściciela zostaje")
    }

    @Test func availabilityFollowsTheProgramInOnlineModeAndIsAlwaysOnWhenStandalone() {
        let none = ProgramCapabilities.none
        let v3 = ProgramCapabilities(names: [ProgramCapabilities.trainingAttachmentsName])

        #expect(!trainingAttachmentsAvailable(mode: .online, capabilities: none), "starszy program ukrywa sekcję")
        #expect(trainingAttachmentsAvailable(mode: .online, capabilities: v3), "program 3.0.0 pokazuje sekcję")
        #expect(trainingAttachmentsAvailable(mode: .standalone, capabilities: none), "tryb samodzielny nie potrzebuje programu")
    }
}
