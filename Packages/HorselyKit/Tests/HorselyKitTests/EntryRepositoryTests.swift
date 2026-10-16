import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Zapis wpisów w magazynie (T062): jedna transakcja z regułami, skutki (termin), „Cofnij” i widoki.
struct EntryRepositoryTests {
    private let today = LocalDate(year: 2026, month: 10, day: 5)!

    private struct Setup {
        let entries: EntryRepository
        let reminders: ReminderRepository
        let trainings: TrainingRepository
        let store: RecordStore
        let horseId: String
        let directory: URL
    }

    private func makeSetup() async throws -> Setup {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-files-\(UUID().uuidString)")
        let dates = FixedDateProvider(today: today)
        let horses = HorseRepository(store: store, files: try LocalFileStore(root: directory), dates: dates)
        var draft = HorseDraft()
        draft.name = "Grom"
        draft.passportNumber = "PL-1"
        guard case let .saved(horse, _) = try await horses.save(draft) else { fatalError("koń nie zapisany") }
        let entries = EntryRepository(store: store, dates: dates)
        try await entries.seedDictionariesIfNeeded()
        return Setup(
            entries: entries, reminders: ReminderRepository(entries: entries), trainings: TrainingRepository(entries: entries),
            store: store, horseId: horse.id, directory: directory
        )
    }

    private func note(_ setup: Setup, title: String = "Kuleje") -> NoteInput {
        var input = NoteInput()
        input.horseId = setup.horseId
        input.noteDate = today
        input.title = title
        return input
    }

    private func createNote(_ setup: Setup) async throws -> any LocalRecord {
        let input = note(setup)
        let result = try await setup.entries.perform { $0.createNote(input) }
        guard let record = result.saved?.record else { throw ProblemMismatch() }
        return record
    }

    @Test func seedingAddsTheDefaultDictionariesOnce() async throws {
        let setup = try await makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let kinds = try await setup.entries.dictionary(.vetVisitType)
        #expect(!kinds.isEmpty)
        let before = try await setup.store.count(.dictionary)
        try await setup.entries.seedDictionariesIfNeeded()
        #expect(try await setup.store.count(.dictionary) == before)
    }

    @Test func aNoteIsSavedAsLocalAndUndoRemovesIt() async throws {
        let setup = try await makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let input = note(setup)
        let result = try await setup.entries.perform { $0.createNote(input) }
        let saved = try #require(result.saved)
        let id = try #require(saved.record?.id)
        #expect(try await setup.store.get(.note, id: id)?.syncState == .local)
        try await setup.entries.undo(saved.undo)
        #expect(try await setup.store.get(.note, id: id) == nil)
    }

    @Test func undoOfAnEditRestoresThePreviousVersion() async throws {
        let setup = try await makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let created = try await createNote(setup)
        let changed = note(setup, title: "Po zmianie")
        let id = created.id
        let result = try await setup.entries.perform { $0.updateNote(id: id, changed, expectedVersion: 1) }
        let edited = try #require(result.saved)
        #expect((edited.record as? LocalNote)?.version == 2)
        try await setup.entries.undo(edited.undo)
        let back = try #require(try await setup.entries.record(.note, id: created.id) as? LocalNote)
        #expect(back.title == "Kuleje" && back.version == 1)
    }

    @Test func aRejectedEntryWritesNothingAndKeepsTheChangeCounter() async throws {
        let setup = try await makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let counter = try await setup.store.changeCounter()
        var input = note(setup)
        input.title = "  "
        let result = try await setup.entries.perform { [input] in $0.createNote(input) }
        guard case let .validation(errors, _) = try #require(result.problem) else { throw ProblemMismatch() }
        #expect(errors["title"] == [Messages.required])
        #expect(try await setup.store.changeCounter() == counter)
    }

    private struct ProblemMismatch: Error {}

    @Test func deletingMovesTheEntryToTheTrashAndUndoBringsItBack() async throws {
        let setup = try await makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let created = try await createNote(setup)
        let result = try await setup.entries.delete(.note, id: created.id)
        let removed = try #require(result.saved)
        #expect(try await setup.entries.record(.note, id: created.id) == nil)
        #expect(try await setup.store.get(.note, id: created.id)?.isDeleted == true)
        try await setup.entries.undo(removed.undo)
        #expect(try await setup.entries.record(.note, id: created.id) != nil)
    }

    @Test func aVisitWithANextDateCreatesAReminderInTheSameTransaction() async throws {
        let setup = try await makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let service = try #require(try await setup.entries.dictionary(.farrierService).first)
        var input = FarrierVisitInput()
        input.horseId = setup.horseId
        input.visitDate = today
        input.serviceId = service.id
        input.nextVisitDate = today.adding(days: 42)
        let visit = input
        let result = try await setup.entries.perform { $0.createFarrierVisit(visit) }
        let saved = try #require(result.saved)
        #expect(saved.effects.contains { $0.type == .reminder && $0.kind == .created })
        let open = try await setup.reminders.reminders(ReminderFilter(horseId: setup.horseId))
        #expect(open.count == 1 && open[0].dueDate == today.adding(days: 42))
        try await setup.entries.undo(saved.undo)
        #expect(try await setup.reminders.reminders(ReminderFilter(horseId: setup.horseId)).isEmpty)
    }

    @Test func theDashboardAndTimelineReadTheStore() async throws {
        let setup = try await makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        _ = try await createNote(setup)
        let dashboard = try await setup.entries.dashboard()
        #expect(dashboard.horses.map(\.name) == ["Grom"])
        #expect(dashboard.recentEntries.count == 1)
        let page = try await setup.entries.timeline(TimelineFilter(horseId: setup.horseId))
        #expect(page.totalCount == 1)
        #expect(try await setup.entries.recentHorseIds() == [setup.horseId])
    }

    @Test func postponingAReminderChangesItsDate() async throws {
        let setup = try await makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        var input = ReminderInput()
        input.horseId = setup.horseId
        input.kind = .other
        input.dueDate = today.adding(days: 3)
        input.title = "Wizyta"
        let createdResult = try await setup.reminders.create(input)
        let created = try #require(createdResult.saved?.record as? LocalReminder)
        let item = try #require(try await setup.reminders.reminder(id: created.id))
        _ = try await setup.reminders.postpone(item, to: today.adding(days: 10))
        #expect(try await setup.reminders.reminder(id: created.id)?.dueDate == today.adding(days: 10))
        _ = try #require(try await setup.reminders.complete(id: created.id).saved)
        #expect(try await setup.reminders.reminders(ReminderFilter(horseId: setup.horseId)).isEmpty)
        #expect(try await setup.reminders.reminders(ReminderFilter(horseId: setup.horseId, status: .completed)).count == 1)
    }

    @Test func aNewTrainingSuggestsTheCostOfThePreviousOne() async throws {
        let setup = try await makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.directory) }
        let type = try #require(try await setup.entries.dictionary(.trainingType).first)
        var input = TrainingInput()
        input.horseId = setup.horseId
        input.trainingDate = today
        input.trainingTypeId = type.id
        input.coaching = TrainingCoachingInput(cost: Money(80))
        _ = try #require(try await setup.trainings.create(input).saved)
        #expect(try await setup.trainings.defaults(horseId: setup.horseId).cost == Money(80))
        let list = try await setup.trainings.trainings(horseId: setup.horseId)
        #expect(list.trainings.count == 1 && list.totalCost == Money(80))
    }
}
