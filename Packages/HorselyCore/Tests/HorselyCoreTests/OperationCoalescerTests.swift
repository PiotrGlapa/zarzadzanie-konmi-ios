import Foundation
import Testing
@testable import HorselyCore

/// Łączenie operacji przed wysłaniem (T072, FR-SYN2-04; przypadki z `OperationCoalescerTest`).
struct OperationCoalescerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func op(
        _ id: String, _ kind: OperationKind, record: String = "n1", type: RecordType = .note, state: OutboxState = .pending,
        payload: String = "{}", base: Int? = nil, dependsOn: [String] = [], sequence: Int64 = 0
    ) -> OutboxOperation {
        OutboxOperation(
            id: id, sequence: sequence, kind: kind, localRef: record, payload: (try? JSONValue.parse(payload)) ?? .null, dependsOn: dependsOn,
            summary: "Notatka · Grom · 05.10.2026", state: state, createdAt: now, updatedAt: now, recordType: type, recordId: record, baseVersion: base
        )
    }

    @Test func createFollowedByUpdateBecomesOneCreateWithTheFinalBody() {
        let create = op("c", .createNote, payload: #"{"title":"A"}"#, sequence: 1)
        let update = op("u", .updateRecord, payload: #"{"title":"B"}"#, base: nil)
        guard case let .merge(merged) = OperationCoalescer.decide(update, queue: [create], now: now) else { Issue.record("brak połączenia"); return }
        #expect(merged.id == "c")
        #expect(merged.kind == .createNote)
        #expect(merged.payload["title"] == .string("B"))
        #expect(merged.baseVersion == nil)
    }

    @Test func createFollowedByDeleteRemovesBothAndTheAttachmentsOfTheNewEntry() {
        let create = op("c", .createNote, sequence: 1)
        let attachment = op("a", .createAttachment, record: "f1", type: .attachment, payload: #"{"ownerId":"n1"}"#, dependsOn: ["c"], sequence: 2)
        let other = op("o", .createNote, record: "n2", sequence: 3)
        let delete = op("d", .deleteRecord, base: nil)
        #expect(OperationCoalescer.decide(delete, queue: [create, attachment, other], now: now) == .cancel(removed: ["c", "a"]))
    }

    @Test func twoUpdatesBecomeOneUpdateWithTheFirstBaseVersion() {
        let first = op("u1", .updateRecord, payload: #"{"title":"A"}"#, base: 3, sequence: 1)
        let second = op("u2", .updateRecord, payload: #"{"title":"B"}"#, base: 4)
        guard case let .merge(merged) = OperationCoalescer.decide(second, queue: [first], now: now) else { Issue.record("brak połączenia"); return }
        #expect(merged.id == "u1")
        #expect(merged.baseVersion == 3)
        #expect(merged.payload["title"] == .string("B"))
    }

    @Test func updateFollowedByDeleteBecomesADeleteWithTheFirstBaseVersion() {
        let first = op("u1", .updateRecord, base: 3, sequence: 1)
        guard case let .merge(merged) = OperationCoalescer.decide(op("d", .deleteRecord, base: 4), queue: [first], now: now) else { Issue.record("brak połączenia"); return }
        #expect(merged.kind == .deleteRecord)
        #expect(merged.baseVersion == 3)
    }

    @Test func aRescheduleFollowedByAnEditIsOneUpdateAndTwoReschedulesStayAReschedule() {
        let reschedule = op("r1", .rescheduleReminder, type: .reminder, base: 2, sequence: 1)
        if case let .merge(merged) = OperationCoalescer.decide(op("r2", .rescheduleReminder, type: .reminder, base: 2), queue: [reschedule], now: now) {
            #expect(merged.kind == .rescheduleReminder)
        } else {
            Issue.record("brak połączenia")
        }
        if case let .merge(merged) = OperationCoalescer.decide(op("e", .updateRecord, type: .reminder, base: 2), queue: [reschedule], now: now) {
            #expect(merged.kind == .updateRecord)
        } else {
            Issue.record("brak połączenia")
        }
    }

    @Test func operationsThatAreSendingUnknownOrInConflictAreNotMerged() {
        for state in [OutboxState.sending, .unknown, .conflict] {
            let first = op("u1", .updateRecord, state: state, base: 3, sequence: 1)
            let second = op("u2", .updateRecord, base: 3)
            #expect(OperationCoalescer.decide(second, queue: [first], now: now) == .queue(second), "\(state)")
            let delete = op("d", .deleteRecord, base: 3)
            #expect(OperationCoalescer.decide(delete, queue: [first], now: now) == .queue(delete), "\(state)")
        }
    }

    @Test func anOperationThatNeedsAFixIsMergedAndGoesBackToPendingWithoutTheProblem() {
        var first = op("u1", .updateRecord, state: .needsFix, base: 3, sequence: 1)
        first.problem = ApiProblem(title: "Błąd", status: 400)
        first.attempts = 4
        guard case let .merge(merged) = OperationCoalescer.decide(op("u2", .updateRecord, base: 3), queue: [first], now: now) else { Issue.record("brak połączenia"); return }
        #expect(merged.state == .pending)
        #expect(merged.problem == nil)
        #expect(merged.attempts == 0)
    }

    @Test func changesOfOtherRecordsAndOperationsWithoutARecordAreNeverMerged() {
        let first = op("u1", .updateRecord, record: "n1", base: 3, sequence: 1)
        let other = op("u2", .updateRecord, record: "n2", base: 1)
        #expect(OperationCoalescer.decide(other, queue: [first], now: now) == .queue(other))
        let create = op("c2", .createNote, record: "n1")
        #expect(OperationCoalescer.decide(create, queue: [first], now: now) == .queue(create))
        let afterDelete = op("u3", .updateRecord, record: "n1", base: 3)
        let delete = op("d", .deleteRecord, record: "n1", base: 3, sequence: 2)
        #expect(OperationCoalescer.decide(afterDelete, queue: [first, delete], now: now) == .queue(afterDelete))
    }

    @Test func dependenciesOfTheNewBodyAreAddedToTheMergedCreate() {
        let contact = op("k", .createContact, record: "c1", type: .contact, sequence: 1)
        let create = op("c", .createNote, dependsOn: [], sequence: 2)
        let update = op("u", .updateRecord, dependsOn: ["k"])
        guard case let .merge(merged) = OperationCoalescer.decide(update, queue: [contact, create], now: now) else { Issue.record("brak połączenia"); return }
        #expect(merged.dependsOn == ["k"])
    }

    @Test func droppingARecordRemovesItsUnsentOperationsWithDependents() {
        let create = op("c", .createNote, sequence: 1)
        let attachment = op("a", .createAttachment, record: "f1", type: .attachment, payload: #"{"ownerId":"n1"}"#, dependsOn: ["c"], sequence: 2)
        let sending = op("s", .updateRecord, state: .sending, base: 1, sequence: 3)
        #expect(OperationCoalescer.drop(type: .note, recordId: "n1", queue: [create, attachment, sending]) == ["c", "a"])
        #expect(OperationCoalescer.dropAttachments(ownerId: "n1", queue: [create, attachment]) == ["a"])
    }

    @Test func retryDelaysGrowFrom15SecondsTo30Minutes() {
        #expect(RetryPolicy.delay(afterAttempts: 1) == 15)
        #expect(RetryPolicy.delay(afterAttempts: 2) == 30)
        #expect(RetryPolicy.delay(afterAttempts: 3) == 60)
        #expect(RetryPolicy.delay(afterAttempts: 20) == 1800)
    }
}
