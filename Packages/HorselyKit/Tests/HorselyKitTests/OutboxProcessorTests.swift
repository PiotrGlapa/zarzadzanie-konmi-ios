import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Kolejka wysyłki z zaślepką programu (T076; scenariusze `OfflineScenarioTest`, `OutboxIdempotencyTest`, `BeforeAfterCountTest`,
/// `DeleteIfMatchTest`, `SendNowTest`, `ConflictFlowTest`).
struct OutboxProcessorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 5, hour: 10)!

    private struct Setup {
        let store: RecordStore
        let program: FakeProgram
        let processor: OutboxProcessor
    }

    private func makeSetup(capabilities: ProgramCapabilities = .none) throws -> Setup {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let program = FakeProgram()
        let (client, _) = program.client(capabilities: capabilities)
        let processor = OutboxProcessor(store: store, client: client, capabilities: { capabilities }, now: { Date() })
        return Setup(store: store, program: program, processor: processor)
    }

    private func note(_ id: String, title: String = "Kuleje", horse: String = "h1") -> JSONValue {
        .object(["horseId": .string(horse), "noteDate": .string("2026-10-05"), "title": .string(title)])
    }

    @discardableResult
    private func enqueue(
        _ setup: Setup, id: String, kind: OperationKind, payload: JSONValue, type: RecordType? = .note, record: String? = nil, dependsOn: [String] = [],
        base: Int? = nil
    ) async throws -> OutboxOperation {
        let operation = OutboxOperation(
            id: id, kind: kind, localRef: record ?? id, payload: payload, dependsOn: dependsOn, horseRefs: [HorseRef(id: "h1", name: "Grom", passportNumber: "PL-1")],
            summary: "\(kind.label) · Grom", createdAt: now, updatedAt: now, recordType: type, recordId: record ?? id, baseVersion: base
        )
        return try await setup.store.writeQuietly { try $0.enqueue(operation) }
    }

    private func state(_ setup: Setup, _ id: String) async throws -> OutboxState? {
        try await setup.store.read { try $0.operation(id)?.state }
    }

    private func history(_ setup: Setup) async throws -> [QueueHistoryEntry] {
        try await setup.store.read { try $0.history() }
    }

    // MARK: Kolejność i zależności

    @Test func dependentOperationsWaitForTheirPredecessorAndGetItsProgramId() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "contacts", .json(201, #"{"id":"srv-c1","createdAt":"2026-10-05T10:00:00","updatedAt":"2026-10-05T10:00:00","version":1,"name":"Anna","types":["Trainer"]}"#))
        setup.program.on("POST", "trainings", .json(201, #"{"id":"srv-t1"}"#))
        try await enqueue(setup, id: "op-c", kind: .createContact, payload: .object(["name": .string("Anna"), "types": .array([.string("Trainer")])]), type: .contact, record: "c1")
        try await enqueue(setup, id: "op-t", kind: .createTraining, payload: .object(["horseId": .string("h1"), "coaching": .object(["trainerContactId": .string("c1")])]),
                          type: .training, record: "t1", dependsOn: ["op-c"])
        let summary = await setup.processor.processAll()
        #expect(summary.sent == 2)
        let training = try #require(setup.program.requests("POST", "trainings").first?.json)
        #expect(training["coaching"]?["trainerContactId"] == .string("srv-c1"))
        #expect(try await history(setup).map(\.outcome) == [.sent, .sent])
    }

    @Test func needsFixBlocksDependentsButNotIndependentOperations() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "contacts", .json(400, #"{"title":"Błąd","errors":{"name":["Nazwa jest wymagana"]}}"#))
        setup.program.on("POST", "notes", .json(201, #"{"id":"srv-n1"}"#))
        try await enqueue(setup, id: "op-c", kind: .createContact, payload: .object(["name": .string("")]), type: .contact, record: "c1")
        try await enqueue(setup, id: "op-t", kind: .createTraining, payload: .object(["riderContactId": .string("c1")]), type: .training, record: "t1", dependsOn: ["op-c"])
        try await enqueue(setup, id: "op-n", kind: .createNote, payload: note("n1"), record: "n1")
        let summary = await setup.processor.processAll()
        #expect(try await state(setup, "op-c") == .needsFix)
        #expect(try await state(setup, "op-t") == .pending)
        #expect(summary.sent == 1)
        #expect(setup.program.requests("POST", "trainings").isEmpty)
        let problem = try await setup.store.read { try $0.operation("op-c")?.problem }
        #expect(problem?.errors["name"] == ["Nazwa jest wymagana"])
    }

    @Test func a401InAQueueOfThreeMakesExactlyOneRequest() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "notes", .json(401, "{}"))
        for index in 1...3 { try await enqueue(setup, id: "op-\(index)", kind: .createNote, payload: note("n\(index)"), record: "n\(index)") }
        let summary = await setup.processor.processAll()
        #expect(summary.stopped == .addressSuspended)
        #expect(setup.program.requests.count == 1)
        #expect(summary.pending == 3)
    }

    // MARK: Licznik przed i po (program bez `idempotencyKey`)

    @Test func aLostAnswerWithAGrownCountIsSentWithoutADuplicate() async throws {
        let setup = try makeSetup()
        let empty = #"{"items":[],"totalCount":0}"#
        let found = #"{"items":[{"id":"srv-n1","createdAt":"2026-10-05T10:00:01","noteDate":"2026-10-05","title":"Kuleje"}],"totalCount":1}"#
        setup.program.on("GET", "notes", .json(200, empty), .json(200, found))
        setup.program.on("POST", "notes", .fail(.networkConnectionLost))
        try await enqueue(setup, id: "op-n", kind: .createNote, payload: note("n1"), record: "n1")
        _ = await setup.processor.processAll()
        #expect(setup.program.requests("POST", "notes").count == 1)
        #expect(try await state(setup, "op-n") == nil, "wysłana operacja trafia do historii")
        #expect(try await history(setup).first?.outcome == .sent)
        #expect(setup.program.requests("POST", "notes").first?.header("Idempotency-Key") == nil)
    }

    @Test func aLostAnswerWithTheSameCountIsSentAgainLater() async throws {
        let setup = try makeSetup()
        setup.program.on("GET", "notes", .json(200, #"{"items":[],"totalCount":0}"#))
        setup.program.on("POST", "notes", .fail(.networkConnectionLost))
        try await enqueue(setup, id: "op-n", kind: .createNote, payload: note("n1"), record: "n1")
        _ = await setup.processor.processAll()
        let operation = try #require(try await setup.store.read { try $0.operation("op-n") })
        #expect(operation.state == .pending)
        #expect(operation.attempts == 1)
        #expect(operation.nextAttemptAt != nil)
    }

    @Test func twoIdenticalEntriesAreBothSentAndNoThirdAppears() async throws {
        let setup = try makeSetup()
        let one = #"{"items":[{"id":"s1","createdAt":"2026-10-05T10:00:01","noteDate":"2026-10-05","title":"Kuleje"}],"totalCount":1}"#
        setup.program.on("GET", "notes", .json(200, #"{"items":[],"totalCount":0}"#), .json(200, one))
        setup.program.on("POST", "notes", .json(201, #"{"id":"s1"}"#), .json(201, #"{"id":"s2"}"#))
        try await enqueue(setup, id: "op-1", kind: .createNote, payload: note("n1"), record: "n1")
        try await enqueue(setup, id: "op-2", kind: .createNote, payload: note("n2"), record: "n2")
        let summary = await setup.processor.processAll()
        #expect(summary.sent == 2)
        #expect(setup.program.requests("POST", "notes").count == 2)
    }

    // MARK: `Idempotency-Key`

    @Test func withIdempotencyKeyTheRetryUsesTheSameKeyAndNoCount() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "notes", .fail(.networkConnectionLost), .json(201, #"{"id":"srv-n1"}"#, headers: ["Idempotent-Replayed": "true"]))
        try await enqueue(setup, id: "op-n", kind: .createNote, payload: note("n1"), record: "n1")
        _ = await setup.processor.processAll()
        #expect(setup.program.requests("GET", "notes").isEmpty)
        try await setup.store.writeQuietly { access in
            try access.updateOperation("op-n", expected: [.pending]) { current in
                var next = current
                next.nextAttemptAt = nil
                return next
            }
        }
        _ = await setup.processor.processAll()
        let posts = setup.program.requests("POST", "notes")
        #expect(posts.count == 2)
        #expect(posts.allSatisfy { $0.header("Idempotency-Key") == "op-n" })
        #expect(try await history(setup).first?.outcome == .sent)
    }

    @Test func aKeyInProgressWaitsAndAReusedKeyNeedsAFix() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "notes", .json(409, #"{"type":"https://zk/errors/idempotency-key-in-progress"}"#), .json(422, #"{"type":"https://zk/errors/idempotency-key-reused","title":"Klucz z inną treścią"}"#))
        try await enqueue(setup, id: "op-n", kind: .createNote, payload: note("n1"), record: "n1")
        _ = await setup.processor.processAll()
        let waiting = try #require(try await setup.store.read { try $0.operation("op-n") })
        #expect(waiting.state == .pending)
        #expect(waiting.problem == nil)
        try await setup.store.writeQuietly { access in
            try access.updateOperation("op-n", expected: [.pending]) { current in
                var next = current
                next.nextAttemptAt = nil
                return next
            }
        }
        _ = await setup.processor.processAll()
        let fixed = try #require(try await setup.store.read { try $0.operation("op-n") })
        #expect(fixed.state == .needsFix)
        #expect(fixed.problem?.message == "Klucz z inną treścią")
    }

    // MARK: Zapis z połączeniem (≤ 1 s)

    @Test func aQuickAnswerIsSavedAndASlowOneIsQueued() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "notes", .json(201, #"{"id":"srv-n1"}"#))
        try await enqueue(setup, id: "op-1", kind: .createNote, payload: note("n1"), record: "n1")
        guard case .sent = await setup.processor.sendNow("op-1") else { Issue.record("brak „Zapisano”"); return }

        let slow = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        slow.program.on("POST", "notes", .delayed(2, 201, #"{"id":"srv-n2"}"#))
        try await enqueue(slow, id: "op-2", kind: .createNote, payload: note("n2"), record: "n2")
        #expect(await slow.processor.sendNow("op-2", timeout: 0.3) == .queued)
    }

    @Test func a400WithinTheLimitGoesBackToTheFormForOperationsWithoutARecord() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "notes", .json(400, #"{"title":"Błąd","errors":{"title":["Tytuł jest wymagany"]}}"#))
        try await enqueue(setup, id: "op-1", kind: .createNote, payload: note("n1", title: ""), type: nil, record: nil)
        guard case let .rejected(problem) = await setup.processor.sendNow("op-1") else { Issue.record("brak odrzucenia"); return }
        #expect(problem.errors["title"] == ["Tytuł jest wymagany"])
        #expect(try await state(setup, "op-1") == nil)
    }

    // MARK: Zmiany i usunięcia

    @Test func aDeleteWithIfMatchSkipsTheControlRead() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["ifMatchDelete"]))
        setup.program.on("DELETE", "notes/n1", .empty(204))
        try await enqueue(setup, id: "op-d", kind: .deleteRecord, payload: .object([:]), record: "n1", base: 3)
        _ = await setup.processor.processAll()
        #expect(setup.program.requests("GET", "notes/n1").isEmpty)
        #expect(setup.program.requests("DELETE", "notes/n1").first?.header("If-Match") == "\"3\"")
        #expect(try await history(setup).first?.outcome == .sent)
    }

    @Test func aDeleteOfARecordChangedInTheProgramIsADeleteEditConflict() async throws {
        let setup = try makeSetup()
        setup.program.on("GET", "notes/n1", .json(200, #"{"id":"n1","version":5,"createdAt":"2026-10-05T10:00:00","updatedAt":"2026-10-05T11:00:00","horseId":"h1","noteDate":"2026-10-05","title":"Zmieniona"}"#))
        try await enqueue(setup, id: "op-d", kind: .deleteRecord, payload: .object([:]), record: "n1", base: 3)
        _ = await setup.processor.processAll()
        #expect(setup.program.requests("DELETE", "notes/n1").isEmpty)
        #expect(try await state(setup, "op-d") == .conflict)
        let conflict = try #require(try await setup.store.read { try $0.openConflicts() }.first)
        #expect(conflict.kind == .deleteEdit)
        #expect(conflict.theirsVersion == 5)
    }

    @Test func a409OnAnUpdateIsAnEditEditConflictThatMarksTheRecord() async throws {
        let setup = try makeSetup()
        let horseNote = LocalNote(id: "n1", createdAt: stamp, updatedAt: stamp, version: 3, horseId: "h1", noteDate: LocalDate(year: 2026, month: 10, day: 5)!, title: "Moja")
        try await setup.store.upsert([try StoredRecord.of(horseNote, syncState: .pending, baseVersion: 3)])
        setup.program.on("PUT", "notes/n1", .json(409, #"{"reason":"VersionMismatch","current":{"id":"n1","version":4,"createdAt":"2026-10-05T10:00:00","updatedAt":"2026-10-05T11:00:00","horseId":"h1","noteDate":"2026-10-05","title":"Ich"}}"#))
        try await enqueue(setup, id: "op-u", kind: .updateRecord, payload: .object(["title": .string("Moja")]), record: "n1", base: 3)
        _ = await setup.processor.processAll()
        #expect(try await state(setup, "op-u") == .conflict)
        #expect(try await setup.store.get(.note, id: "n1")?.syncState == .conflict)
        let conflict = try #require(try await setup.store.read { try $0.openConflicts() }.first)
        #expect(conflict.kind == .editEdit)
        #expect(conflict.theirsVersion == 4)

        // „Przyjmij z programu”: rekord z programu jako `Synced`, operacja znika.
        let (client, _) = setup.program.client()
        let resolver = ConflictResolver(store: setup.store, client: client)
        #expect(await resolver.resolve(conflict.id, .acceptTheirs) == .done)
        let row = try #require(try await setup.store.get(.note, id: "n1"))
        #expect(row.syncState == .synced)
        #expect(try row.record(as: LocalNote.self)?.title == "Ich")
        #expect(try await state(setup, "op-u") == nil)
    }

    @Test func anUpdateTheProgramAlreadyHasIsNotAConflict() async throws {
        let setup = try makeSetup()
        setup.program.on("PUT", "notes/n1", .json(409, #"{"reason":"VersionMismatch","current":{"id":"n1","version":4,"createdAt":"2026-10-05T10:00:00","updatedAt":"2026-10-05T11:00:00","horseId":"h1","noteDate":"2026-10-05","title":"Moja"}}"#))
        try await enqueue(setup, id: "op-u", kind: .updateRecord, payload: .object(["title": .string("Moja")]), record: "n1", base: 3)
        _ = await setup.processor.processAll()
        #expect(try await history(setup).first?.outcome == .sent)
        #expect(try await setup.store.read { try $0.openConflicts() }.isEmpty)
    }

    @Test func aReminderActionOnAClosedReminderIsAlreadyHandled() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "reminders/r1/complete", .json(409, #"{"reason":"InvalidState"}"#))
        try await enqueue(setup, id: "op-r", kind: .completeReminder, payload: .object(["id": .string("r1")]), type: .reminder, record: "r1")
        _ = await setup.processor.processAll()
        #expect(try await history(setup).first?.outcome == .alreadyHandled)
    }

    @Test func aRestartInSendingBecomesUnknownAndIsCounted() async throws {
        let setup = try makeSetup()
        let found = #"{"items":[{"id":"srv-n1","createdAt":"2026-10-05T10:00:01","noteDate":"2026-10-05","title":"Kuleje"}],"totalCount":1}"#
        setup.program.on("GET", "notes", .json(200, found))
        try await enqueue(setup, id: "op-n", kind: .createNote, payload: note("n1"), record: "n1")
        try await setup.store.writeQuietly { access in
            try access.updateOperation("op-n", expected: [.pending]) { current in
                var next = current
                next.state = .sending
                next.countBefore = 0
                return next
            }
        }
        await setup.processor.recover()
        _ = await setup.processor.processAll()
        #expect(setup.program.requests("POST", "notes").isEmpty)
        #expect(try await history(setup).first?.outcome == .sent)
    }
}
