import Foundation
import Testing
@testable import HorselyCore

/// Scalanie eksportu i plan odświeżenia (T073; przypadki z `SyncMergerTest`, `ExportCursorIncrementalTest`, `ProgramSyncTest`,
/// `ConflictFlowTest`).
struct SyncMergerTests {
    private func meta(_ state: SyncState, version: Int = 1, base: Int? = nil, deleted: Bool = false) -> RecordMeta {
        RecordMeta(version: version, syncState: state, baseVersion: base, deleted: deleted)
    }

    // MARK: Rekord z programu

    @Test func aRecordMissingLocallyIsInsertedAsSynced() {
        #expect(SyncMerger.incoming(version: 1, local: nil, hasOperation: nil) == .insert)
    }

    @Test func aSyncedRecordWithAnotherVersionIsReplacedAndTheSameVersionIsNotRewritten() {
        #expect(SyncMerger.incoming(version: 2, local: meta(.synced, version: 1), hasOperation: false) == .replace)
        #expect(SyncMerger.incoming(version: 1, local: meta(.synced, version: 1), hasOperation: false) == .unchanged)
        // Program bez wersji rekordów (tryb zgodności) — zawsze zastąpienie.
        #expect(SyncMerger.incoming(version: 0, local: meta(.synced, version: 0), hasOperation: false) == .replace)
    }

    @Test func aPendingChangeIsKeptWhetherTheProgramMovedOnOrNot() {
        #expect(SyncMerger.incoming(version: 3, local: meta(.pending, version: 3, base: 3), hasOperation: true) == .keepPending)
        #expect(SyncMerger.incoming(version: 4, local: meta(.pending, version: 3, base: 3), hasOperation: true) == .keepPending)
        #expect(SyncMerger.incoming(version: 4, local: meta(.conflict, version: 3, base: 3), hasOperation: nil) == .keepPending)
    }

    @Test func anOrphanedPendingRecordWithoutAnOperationTakesTheProgramVersion() {
        #expect(SyncMerger.incoming(version: 4, local: meta(.pending, version: 3, base: 3), hasOperation: false) == .replace)
    }

    // MARK: Rekord nieobecny w programie

    @Test func aSyncedRecordMissingInTheExportIsRemoved() {
        #expect(SyncMerger.absent(local: meta(.synced), hasOperation: false) == .remove)
        #expect(SyncMerger.absent(local: meta(.local), hasOperation: nil) == .remove)
    }

    @Test func anEditOfARecordDeletedInTheProgramBecomesAConflictCandidateAndStays() {
        #expect(SyncMerger.absent(local: meta(.pending, base: 2), hasOperation: true) == .editDeleteConflict)
    }

    @Test func aNewRecordWaitingToBeSentIsUntouchedWhenAbsent() {
        #expect(SyncMerger.absent(local: meta(.pending, base: nil), hasOperation: true) == .keep)
    }

    @Test func anUnsentRecordWithoutAnOperationIsRemoved() {
        #expect(SyncMerger.absent(local: meta(.pending, base: 2), hasOperation: false) == .remove)
    }

    // MARK: Eksport przyrostowy (schemat 1.5)

    private let incremental = """
    {"schemaVersion":"1.5","exportedAt":"2026-10-05T10:00:00Z","appVersion":"2.0.0",
     "scope":{"type":"full","includesAttachmentFiles":false,"updatedSince":"2026-10-04T10:00:00Z","nextUpdatedSince":"2026-10-05T09:59:00Z"},
     "data":{"notes":[{"id":"n1","createdAt":"2026-10-05T09:00:00","updatedAt":"2026-10-05T09:30:00","version":2,"horseId":"h1","noteDate":"2026-10-05","title":"Kuleje"}]},
     "trashed":[{"type":"Note","id":"n2"},{"type":"DictionaryItem","id":"d1"},{"type":"Przyszly","id":"x"}],
     "purged":[{"type":"Horse","id":"h9"}]}
    """

    @Test func trashedAndPurgedRecordsAreRemovalsAndUnknownTypesAreSkipped() throws {
        let document = try ExportDocument.parse(incremental)
        #expect(document.records.count == 1)
        #expect(document.removals == [
            ExportRemoval(type: .note, id: "n2", purged: false), ExportRemoval(type: .dictionary, id: "d1", purged: false), ExportRemoval(type: .horse, id: "h9", purged: true),
        ])
        #expect(document.unknownRemovalTypes == ["Przyszly"])
        #expect(RefreshPlan.isIncremental(requested: true, header: document.header))
        #expect(RefreshPlan.nextPoint(header: document.header) == "2026-10-05T09:59:00Z")
    }

    @Test func fullRequiredMakesAnIncrementalAnswerAFullDownload() throws {
        let document = try ExportDocument.parse(incremental.replacingOccurrences(of: #""includesAttachmentFiles":false,"#, with: #""includesAttachmentFiles":false,"fullRequired":true,"#))
        #expect(!RefreshPlan.isIncremental(requested: true, header: document.header))
        #expect(!RefreshPlan.isIncremental(requested: false, header: document.header))
    }

    @Test func aFullExportWithoutAPointUsesExportedAtMinusAMinute() {
        let header = ExportHeader(schemaVersion: "1.5", exportedAt: "2026-10-05T10:00:00Z")
        #expect(RefreshPlan.nextPoint(header: header) == "2026-10-05T09:59:00Z")
        #expect(RefreshPlan.nextPoint(header: ExportHeader(schemaVersion: "1.4")) == nil)
    }

    // MARK: Plan odświeżenia

    private let all = ProgramCapabilities(names: ["dataStamp", "updatedSince"])
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theFirstDownloadIsFull() {
        #expect(RefreshPlan.plan(capabilities: all, stamp: "a", state: SyncMetaState(), background: false, queueEmpty: true, now: now) == .full)
    }

    @Test func theSameStampAndAnEmptyQueueEndTheRefreshWithTheInfoOnly() {
        let state = SyncMetaState(dataStamp: "a", nextUpdatedSince: "p", lastFullAt: now)
        #expect(RefreshPlan.plan(capabilities: all, stamp: "a", state: state, background: false, queueEmpty: true, now: now) == .upToDate)
        #expect(RefreshPlan.plan(capabilities: all, stamp: "a", state: state, background: false, queueEmpty: false, now: now) == .incremental(since: "p"))
        #expect(RefreshPlan.plan(capabilities: all, stamp: "b", state: state, background: false, queueEmpty: true, now: now) == .incremental(since: "p"))
    }

    @Test func theBackgroundDoesAFullDownloadOnceADay() {
        let fresh = SyncMetaState(dataStamp: "a", nextUpdatedSince: "p", lastFullAt: now.addingTimeInterval(-3600))
        #expect(RefreshPlan.plan(capabilities: all, stamp: "b", state: fresh, background: true, queueEmpty: true, now: now) == .incremental(since: "p"))
        let old = SyncMetaState(dataStamp: "a", nextUpdatedSince: "p", lastFullAt: now.addingTimeInterval(-25 * 3600))
        #expect(RefreshPlan.plan(capabilities: all, stamp: "a", state: old, background: true, queueEmpty: true, now: now) == .full)
        #expect(RefreshPlan.plan(capabilities: all, stamp: "a", state: old, background: false, queueEmpty: true, now: now) == .upToDate)
    }

    @Test func aForcedFullDownloadAndLosingTheCapabilityMakeItFull() {
        let forced = SyncMetaState(dataStamp: "a", nextUpdatedSince: "p", lastFullAt: now, forceFull: true)
        #expect(RefreshPlan.plan(capabilities: all, stamp: "a", state: forced, background: false, queueEmpty: true, now: now) == .full)
        let state = SyncMetaState(dataStamp: "a", nextUpdatedSince: "p", lastFullAt: now)
        #expect(RefreshPlan.plan(capabilities: ProgramCapabilities(names: ["dataStamp"]), stamp: "b", state: state, background: false, queueEmpty: true, now: now) == .full)
    }

    @Test func aProgramWithoutCapabilitiesGetsTheFullExportEveryTime() {
        let state = SyncMetaState(dataStamp: "a", nextUpdatedSince: "p", lastFullAt: now)
        #expect(RefreshPlan.plan(capabilities: .none, stamp: "a", state: state, background: false, queueEmpty: true, now: now) == .full)
    }

    // MARK: Mapowanie rekordów API

    @Test func anApiHorseWithFinanceAndAnApiTrainingWithCoachingBecomeRecords() throws {
        let horse = try JSONValue.parse("""
        {"id":"h1","version":3,"createdAt":"2026-10-01T10:00:00Z","updatedAt":"2026-10-02T10:00:00Z","name":"Grom","passportNumber":"PL-1",
         "status":"Injured","finance":{"purchasePrice":12500.5,"purchaseDate":"2020-05-01","salePrice":null},"nextReminder":null,"monthsWithoutPassport":null}
        """)
        let record = try #require(ApiRecordMapping.record(.horse, from: horse) as? LocalHorse)
        #expect(record.version == 3)
        #expect(record.status == .injured)
        #expect(record.purchasePrice == Money(string: "12500.5"))
        let input = ApiRecordMapping.input(record)
        #expect(input["id"] == nil)
        #expect(input["finance"]?["purchasePrice"]?.decimalValue == Decimal(string: "12500.5"))
        #expect(input["photoAttachmentId"] == nil)
        #expect(ApiRecordMapping.input(record, includeFinance: false)["finance"] == nil)

        let training = try JSONValue.parse("""
        {"id":"t1","version":1,"createdAt":"2026-10-01T10:00:00","updatedAt":"2026-10-01T10:00:00","horseId":"h1","trainingDate":"2026-10-01",
         "trainingTypeId":"d1","coaching":{"trainerContactId":"c1","cost":80},"horseName":"Grom"}
        """)
        let trainingRecord = try #require(ApiRecordMapping.record(.training, from: training) as? LocalTraining)
        #expect(trainingRecord.trainerContactId == "c1")
        #expect(trainingRecord.cost == Money(80))
        #expect(ApiRecordMapping.input(trainingRecord)["coaching"]?["trainerContactId"] == .string("c1"))
    }

    @Test func vetMedicationsWithoutAuditFieldsAreAccepted() throws {
        let visit = try JSONValue.parse("""
        {"id":"v1","version":1,"createdAt":"2026-10-01T10:00:00","updatedAt":"2026-10-01T10:00:00","horseId":"h1","visitDateTime":"2026-10-01T09:00:00",
         "visitTypeId":"d1","medications":[{"id":"m1","name":"Lek","administration":"Prescribed"}]}
        """)
        let record = try #require(ApiRecordMapping.record(.vetVisit, from: visit) as? LocalVetVisit)
        #expect(record.medications.first?.name == "Lek")
        let medication = try #require(ApiRecordMapping.input(record)["medications"]?.arrayValue?.first)
        #expect(medication["createdAt"] == nil)
        #expect(medication["name"] == .string("Lek"))
    }
}
