import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Operacje załączników (T113): załącznik czeka na swój wpis (także z kolejki) i dostaje jego `id` z programu; wynik nieznany
/// ustala licznik przed i po porównujący `sha256`; tryb samodzielny — plik w magazynie, przypięty; wycofanie z kolejki; limit LRU.
struct AttachmentOperationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Setup {
        let store: RecordStore
        let files: LocalFileStore
        let program: FakeProgram
        let processor: OutboxProcessor
        let attachments: AttachmentStore
    }

    private func makeSetup(mode: WorkMode = .online, capabilities: ProgramCapabilities = .none, limitMB: Int = 200) throws -> Setup {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-att-\(UUID().uuidString)", isDirectory: true)
        let files = try LocalFileStore(root: root.appendingPathComponent("Files", isDirectory: true))
        let program = FakeProgram()
        let (client, _) = program.client(capabilities: capabilities)
        let processor = OutboxProcessor(store: store, client: client, capabilities: { capabilities }, now: { Date() })
        let attachments = AttachmentStore(store: store, files: files, client: client, mode: { mode }, settings: { AttachmentSettings(limitMB: limitMB) })
        return Setup(store: store, files: files, program: program, processor: processor, attachments: attachments)
    }

    private func enqueueNote(_ setup: Setup, operationId: String, noteId: String) async throws {
        let operation = OutboxOperation(
            id: operationId, kind: .createNote, localRef: noteId,
            payload: .object(["horseId": .string("h1"), "noteDate": .string("2026-10-05"), "title": .string("Faktura")]),
            horseRefs: [HorseRef(id: "h1", name: "Grom", passportNumber: nil)], summary: "Notatka · Grom", createdAt: now, updatedAt: now,
            recordType: .note, recordId: noteId
        )
        try await setup.store.writeQuietly { try $0.enqueue(operation) }
    }

    private func invoice(_ setup: Setup) throws -> PendingAttachment {
        PendingAttachment(file: try setup.attachments.prepare(data: Data("faktura za siano".utf8), fileName: "faktura.txt", mimeType: "text/plain"), description: "  Siano  ")
    }

    @Test func anAttachmentWaitsForItsQueuedEntryAndFollowsItsProgramId() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "notes", .json(201, #"{"id":"srv-n1"}"#))
        setup.program.on("POST", "attachments", .json(201, #"{"id":"srv-a1"}"#))
        try await enqueueNote(setup, operationId: "op-n", noteId: "n1")

        let ids = try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try invoice(setup)])
        let localId = try #require(ids.first)
        let operation = try #require(try await setup.store.read { try $0.operations().first { $0.kind == .createAttachment } })
        #expect(operation.dependsOn == ["op-n"])
        #expect(operation.payload["ownerId"] == .string("n1"))
        let file = try #require(try await setup.store.read { try $0.outboxFile(operation.id) })
        #expect(FileManager.default.fileExists(atPath: file.path))
        let pending = try #require(try await setup.store.get(.attachment, id: localId))
        #expect(pending.syncState == .pending)
        #expect(try pending.record(as: LocalAttachment.self)?.description == "Siano")

        let summary = await setup.processor.processAll()
        #expect(summary.sent == 2)
        let order = setup.program.requests.filter { $0.method == "POST" }.map(\.path)
        #expect(order == ["notes", "attachments"])
        #expect(try await setup.store.get(.attachment, id: localId) == nil)
        #expect(try await setup.store.get(.attachment, id: "srv-a1")?.syncState == .synced)
        #expect(!FileManager.default.fileExists(atPath: file.path), "plik operacji znika po wysłaniu")
    }

    @Test func aLostUploadIsSettledByCountingTheSha256BeforeAndAfter() async throws {
        let setup = try makeSetup()
        let pending = try invoice(setup)
        let sha = pending.file.sha256
        setup.program.on("GET", "attachments", .json(200, "[]"), .json(200, #"[{"id":"srv-a1","sha256":"\#(sha)"}]"#))
        setup.program.on("POST", "attachments", .fail(.networkConnectionLost))

        try await setup.attachments.add(AttachmentOwner(type: .note, id: "srv-n1", horseId: "h1"), [pending])
        _ = await setup.processor.processAll()

        #expect(setup.program.requests("POST", "attachments").count == 1, "bez duplikatu w programie")
        #expect(setup.program.requests("GET", "attachments").count == 2)
        let history = try await setup.store.read { try $0.history() }
        #expect(history.first?.outcome == .sent)
    }

    @Test func standaloneKeepsTheFileInTheStoreAndPinned() async throws {
        let setup = try makeSetup(mode: .standalone)
        let pending = try invoice(setup)
        let ids = try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [pending])
        let id = try #require(ids.first)

        let row = try #require(try await setup.store.get(.attachment, id: id))
        #expect(row.syncState == .local)
        let original = try #require(try await setup.store.read { try $0.file(attachmentId: id, kind: .original) })
        #expect(original.pinned)
        #expect(original.sha256 == pending.file.sha256)
        #expect(try await setup.store.read { try $0.operations() }.isEmpty)

        let attachment = try #require(try row.record(as: LocalAttachment.self))
        let url = try await setup.attachments.content(attachment)
        #expect(try Data(contentsOf: url) == Data("faktura za siano".utf8))
        #expect(try await setup.attachments.attachments(ownerId: "n1").map(\.id) == [id])
        #expect(try await setup.attachments.attachments(horseId: "h1").map(\.id) == [id])
    }

    @Test func withdrawingAQueuedAttachmentRemovesTheOperationRecordAndFile() async throws {
        let setup = try makeSetup()
        let ids = try await setup.attachments.add(AttachmentOwner(type: .horse, id: "h1", horseId: "h1"), [try invoice(setup)])
        let id = try #require(ids.first)
        let operation = try #require(try await setup.store.read { try $0.operations().first })
        let file = try #require(try await setup.store.read { try $0.outboxFile(operation.id) })
        #expect(await setup.attachments.isQueued(id))

        #expect(try await setup.attachments.withdraw(id))
        #expect(try await setup.store.read { try $0.operations() }.isEmpty)
        #expect(try await setup.store.get(.attachment, id: id) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func rejectedFilesNeverReachTheQueue() async throws {
        let setup = try makeSetup()
        #expect(throws: AttachmentError.self) {
            _ = try setup.attachments.prepare(data: Data("MZ".utf8), fileName: "program.exe", mimeType: "application/x-msdownload")
        }
        #expect(try await setup.store.read { try $0.operations() }.isEmpty)
    }

    @Test func theLeastRecentlyOpenedUnpinnedFilesGoFirstAndPinnedOnesStay() async throws {
        let setup = try makeSetup(limitMB: 0)
        let old = try setup.files.write(Data(repeating: 1, count: 2048), attachmentId: "old", kind: .original, pinned: false)
        let recent = try setup.files.write(Data(repeating: 2, count: 2048), attachmentId: "recent", kind: .original, pinned: false)
        let pinned = try setup.files.write(Data(repeating: 3, count: 2048), attachmentId: "pinned", kind: .thumbnail, pinned: true)
        try await setup.store.write { access in
            var first = old
            first.lastOpenedAt = LocalDateTime(year: 2026, month: 9, day: 1, hour: 8)
            var second = recent
            second.lastOpenedAt = LocalDateTime(year: 2026, month: 10, day: 1, hour: 8)
            try access.upsertFile(first)
            try access.upsertFile(second)
            try access.upsertFile(pinned)
        }
        await setup.attachments.evict()
        #expect(try await setup.store.read { try $0.file(attachmentId: "old", kind: .original) } == nil)
        #expect(try await setup.store.read { try $0.file(attachmentId: "recent", kind: .original) } == nil)
        #expect(try await setup.store.read { try $0.file(attachmentId: "pinned", kind: .thumbnail) } != nil)
        #expect(!FileManager.default.fileExists(atPath: setup.files.url(for: old).path))
        #expect(FileManager.default.fileExists(atPath: setup.files.url(for: pinned).path))
    }

    @Test func theSharedInboxShowsOnlyCommittedEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-inbox-\(UUID().uuidString)", isDirectory: true)
        let inbox = SharedInbox.inGroup(root)
        let abandoned = try inbox.newFolder()
        try Data("x".utf8).write(to: abandoned.appendingPathComponent("a.txt"))
        let folder = try inbox.newFolder()
        try Data("faktura".utf8).write(to: folder.appendingPathComponent("faktura.pdf"))
        let entry = SharedInboxEntry(createdAt: now, horseId: "h1", target: .entry(ownerType: .vetVisit, ownerId: "v1"), files: [.init(name: "faktura.pdf", contentType: "application/pdf")])
        try inbox.commit(entry, folder: folder)

        let entries = inbox.entries()
        #expect(entries.map(\.entry) == [entry])
        #expect(FileManager.default.fileExists(atPath: entries[0].folder.appendingPathComponent("faktura.pdf").path))
        inbox.remove(entries[0].folder)
        #expect(inbox.entries().isEmpty)
        inbox.removeAbandoned(now: Date().addingTimeInterval(2 * 24 * 60 * 60))
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
    }
}
