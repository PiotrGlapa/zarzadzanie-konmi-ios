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
        let client: ApiClient
    }

    private func makeSetup(mode: WorkMode = .online, capabilities: ProgramCapabilities = .none, limitMB: Int = 200) throws -> Setup {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-att-\(UUID().uuidString)", isDirectory: true)
        let files = try LocalFileStore(root: root.appendingPathComponent("Files", isDirectory: true))
        let program = FakeProgram()
        let (client, _) = program.client(capabilities: capabilities)
        let processor = OutboxProcessor(store: store, client: client, capabilities: { capabilities }, now: { Date() })
        let attachments = AttachmentStore(store: store, files: files, client: client, mode: { mode }, settings: { AttachmentSettings(limitMB: limitMB) })
        return Setup(store: store, files: files, program: program, processor: processor, attachments: attachments, client: client)
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

    // MARK: Załączniki treningu (3.0): miejsce, czas i miniatura filmu (`AttachmentOperationTest.kt` Androida 3.0.2)

    /// Program 3.0 ogłasza `trainingAttachments`; `idempotencyKey` — wysyłka bez licznika przed i po.
    private static let withTrainingAttachments = ProgramCapabilities(names: ["idempotencyKey", "trainingAttachments"])

    private static let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4])

    private func thumbnailFile(_ setup: Setup, _ bytes: Data, name: String = "miniatura.jpg") throws -> URL {
        let folder = setup.files.root.deletingLastPathComponent().appendingPathComponent("thumbs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    private func video(_ setup: Setup, thumbnail: URL? = nil, latitude: String = "52.2297", longitude: String = "21.0122") throws -> PendingAttachment {
        let file = try setup.attachments.prepare(data: Data((0 ..< 2048).map { UInt8(truncatingIfNeeded: $0 % 200) }), fileName: "jazda.mp4", mimeType: "video/mp4")
        return PendingAttachment(
            file: file, capturedAt: InstantText.parse("2026-09-01T08:15:00Z"), latitude: DecimalText.parse(latitude), longitude: DecimalText.parse(longitude),
            thumbnail: thumbnail
        )
    }

    private struct Part {
        let name: String
        let contentType: String?
        let body: Data
        var text: String { String(decoding: body, as: UTF8.self) }
    }

    /// Części `multipart/form-data` zapisanego żądania, w kolejności wysłania.
    private func parts(of request: FakeProgram.Recorded) throws -> [Part] {
        let body = try #require(request.body)
        let delimiter = Data("--\(MultipartBody.boundary)".utf8)
        var found: [Range<Data.Index>] = []
        var cursor = body.startIndex
        while let range = body.range(of: delimiter, in: cursor ..< body.endIndex) {
            found.append(range)
            cursor = range.upperBound
        }
        var result: [Part] = []
        for (index, range) in found.enumerated() {
            let end = index + 1 < found.count ? found[index + 1].lowerBound : body.endIndex
            let chunk = Data(body[range.upperBound ..< end])
            if chunk.starts(with: Data("--".utf8)) { continue }
            let content = Data(chunk.dropFirst(2).dropLast(2))
            let split = try #require(content.range(of: Data("\r\n\r\n".utf8)))
            let header = String(decoding: content[content.startIndex ..< split.lowerBound], as: UTF8.self)
            let name = try #require(header.components(separatedBy: #"name=""#).dropFirst().first?.components(separatedBy: "\"").first)
            let type = header.components(separatedBy: "\r\n").first { $0.hasPrefix("Content-Type: ") }.map { String($0.dropFirst("Content-Type: ".count)) }
            result.append(Part(name: name, contentType: type, body: Data(content[split.upperBound...])))
        }
        return result
    }

    @Test func trainingAttachmentMultipartCarriesMetadataAndThumbnail() async throws {
        let setup = try makeSetup(capabilities: Self.withTrainingAttachments)
        let pending = try video(setup, thumbnail: try thumbnailFile(setup, Self.jpegBytes))
        let sha = pending.file.sha256
        setup.program.on("POST", "attachments", .json(201, #"""
        [{"id":"srv-a1","ownerType":"Training","ownerId":"t1","horseId":"h1","fileName":"jazda.mp4","contentType":"video/mp4","sizeBytes":2048,
          "sha256":"\#(sha)","hasThumbnail":true,"fileAvailable":true,"createdAt":"2026-09-01T08:20:41","updatedAt":"2026-09-01T08:20:41",
          "capturedAt":"2026-09-01T08:15:00Z","latitude":52.2297000,"longitude":21.0122000}]
        """#))

        let localId = try #require(try await setup.attachments.add(AttachmentOwner(type: .training, id: "t1", horseId: "h1"), [pending]).first)
        let operation = try #require(try await setup.store.read { try $0.operations().first { $0.kind == .createAttachment } })
        let queued = try #require(try await setup.store.read { try $0.outboxFile(operation.id) })
        let thumbnailPath = try #require(queued.thumbnailPath)
        #expect(queued.capturedAt == InstantText.parse("2026-09-01T08:15:00Z"))
        #expect(queued.latitude.map(DecimalText.text) == "52.2297000", "miejsce w kolejce ze skalą 7 miejsc")
        #expect(FileManager.default.fileExists(atPath: thumbnailPath))
        #expect(operation.payload["ownerType"] == .string("Training"))

        #expect(await setup.processor.processAll().sent == 1)

        let request = try #require(setup.program.requests("POST", "attachments").first)
        let sent = try parts(of: request)
        #expect(sent.map(\.name) == ["ownerType", "ownerId", "capturedAt", "latitude", "longitude", "file", "thumbnail"])
        let byName = Dictionary(uniqueKeysWithValues: sent.map { ($0.name, $0) })
        #expect(byName["ownerType"]?.text == "Training")
        #expect(byName["ownerId"]?.text == "t1")
        #expect(byName["capturedAt"]?.text == "2026-09-01T08:15:00Z")
        #expect(byName["latitude"]?.text == "52.2297000", "współrzędne z 7 miejscami po przecinku")
        #expect(byName["longitude"]?.text == "21.0122000")
        #expect(byName["file"]?.contentType == "video/mp4")
        #expect(byName["thumbnail"]?.contentType == "image/jpeg")
        #expect(byName["thumbnail"]?.body == Self.jpegBytes)

        // Po wysyłce: rekord z odpowiedzi programu zachowuje skalę współrzędnych (bez `Double`), a plik i miniatura znikają.
        let stored = try #require(try await setup.store.get(.attachment, id: "srv-a1")?.record(as: LocalAttachment.self))
        #expect(stored.ownerType == .training)
        #expect(stored.version == 1, "odpowiedź programu bez `version` — rekord dostaje wersję 1 (eksport 1.6 wymaga >= 1)")
        #expect(stored.capturedAt == InstantText.parse("2026-09-01T08:15:00Z"))
        #expect(stored.latitude.map(DecimalText.text) == "52.2297000")
        #expect(stored.longitude.map(DecimalText.text) == "21.0122000")
        #expect(try await setup.store.get(.attachment, id: localId) == nil)
        #expect(!FileManager.default.fileExists(atPath: queued.path))
        #expect(!FileManager.default.fileExists(atPath: thumbnailPath))
    }

    @Test func coordinatesAreRoundedHalfUpToSevenDecimalPlaces() {
        #expect(DecimalText.coordinateText(DecimalText.parse("52.229700051")!) == "52.2297001")
        #expect(DecimalText.coordinateText(DecimalText.parse("-0.00000005")!) == "-0.0000001", "HALF_UP zaokrągla od zera")
        #expect(DecimalText.coordinateText(DecimalText.parse("21.01220004")!) == "21.0122000")
        #expect(DecimalText.coordinateText(DecimalText.parse("-52")!) == "-52.0000000")
        #expect(DecimalText.coordinateText(DecimalText.parse("0.00000004")!) == "0.0000000")
    }

    @Test func aMissingOversizedOrNonJpegThumbnailIsLeftOutAndTheFileIsStillSent() async throws {
        let setup = try makeSetup(capabilities: Self.withTrainingAttachments)
        setup.program.on("POST", "attachments", .json(201, #"{"id":"srv-a1"}"#), .json(201, #"{"id":"srv-a2"}"#), .json(201, #"{"id":"srv-a3"}"#))
        let tooBig = try thumbnailFile(setup, Self.jpegBytes + Data(count: Int(OutboxFile.maxThumbnailBytes)), name: "duza.jpg")
        let notJpeg = try thumbnailFile(setup, Data([0x89, 0x50, 0x4E, 0x47]), name: "nie-jpeg.jpg")
        let owner = AttachmentOwner(type: .training, id: "t1", horseId: "h1")
        try await setup.attachments.add(owner, [try video(setup, thumbnail: tooBig), try video(setup, thumbnail: notJpeg), try video(setup)])

        #expect(await setup.processor.processAll().sent == 3)

        let requests = setup.program.requests("POST", "attachments")
        #expect(requests.count == 3)
        for request in requests {
            #expect(try parts(of: request).map(\.name) == ["ownerType", "ownerId", "capturedAt", "latitude", "longitude", "file"])
        }
    }

    @Test func anAttachmentWithoutMetadataSendsNoMetadataParts() async throws {
        let setup = try makeSetup(capabilities: Self.withTrainingAttachments)
        setup.program.on("POST", "attachments", .json(201, #"{"id":"srv-a1"}"#))
        try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try invoice(setup)])

        #expect(await setup.processor.processAll().sent == 1)

        let sent = try parts(of: try #require(setup.program.requests("POST", "attachments").first))
        #expect(sent.map(\.name) == ["ownerType", "ownerId", "description", "file"])
    }

    @Test func trainingAttachmentWaitsWithoutTrainingAttachments() async throws {
        let setup = try makeSetup(capabilities: ProgramCapabilities(names: ["idempotencyKey"]))
        setup.program.on("POST", "attachments", .json(201, #"{"id":"srv-a1"}"#))
        let trainingId = try #require(try await setup.attachments.add(AttachmentOwner(type: .training, id: "t1", horseId: "h1"), [try video(setup)]).first)
        let noteId = try #require(try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try invoice(setup)]).first)
        let operations = try await setup.store.read { try $0.operations().filter { $0.kind == .createAttachment } }
        let training = try #require(operations.first { $0.recordId == trainingId })
        let note = try #require(operations.first { $0.recordId == noteId })
        let queued = try #require(try await setup.store.read { try $0.outboxFile(training.id) })

        #expect(training.waitsForProgramUpdate(.none), "kolejka pokazuje „Czeka na aktualizację programu”")
        #expect(!note.waitsForProgramUpdate(.none), "załącznik innego wpisu nie czeka")
        #expect(!training.waitsForProgramUpdate(Self.withTrainingAttachments))

        let first = await setup.processor.processAll()

        #expect(first.sent == 1)
        #expect(first.pending == 1)
        #expect(first.stopped == nil)
        #expect(try await setup.store.read { try $0.operation(training.id) }?.state == .pending)
        #expect(try await setup.store.read { try $0.operation(note.id) } == nil, "załącznik notatki wysłany i usunięty z kolejki")
        #expect(setup.program.requests("POST", "attachments").count == 1, "załącznik treningu nie jest wysyłany")
        #expect(FileManager.default.fileExists(atPath: queued.path), "plik czeka razem z operacją")

        // Program zaktualizowany: operacja rusza sama.
        let upgraded = OutboxProcessor(store: setup.store, client: setup.client, capabilities: { Self.withTrainingAttachments })
        let second = await upgraded.processAll()

        #expect(second.sent == 1)
        #expect(try await setup.store.read { try $0.operation(training.id) } == nil)
        #expect(setup.program.requests("POST", "attachments").count == 2)
        #expect(!FileManager.default.fileExists(atPath: queued.path))
    }

    @Test func attachmentDtoWithMetadataParses() throws {
        let json = #"""
        {"id":"c41d6e0a-3f27-4b9e-8a15-2d7c9e5f0b64","version":1,"ownerType":"Training","ownerId":"7b2f3a1c-5d0e-4c8a-9f21-0a6e8d4b1c33",
         "horseId":"0e9a4b72-81c3-4d6f-b2a8-53f1c7d90e14","fileName":"IMG_0412.mp4","contentType":"video/mp4","sizeBytes":8421377,
         "sha256":"\#(String(repeating: "3b", count: 32))","description":"Po jeździe","hasThumbnail":true,"fileAvailable":true,
         "createdAt":"2026-09-01T08:20:41.123456Z","isImage":false,
         "capturedAt":"2026-09-01T08:15:00Z","latitude":52.2297000,"longitude":21.0122000}
        """#

        let attachment = try #require(ApiRecordMapping.record(.attachment, from: try JSONValue.parseKeepingScale(json)) as? LocalAttachment)

        #expect(attachment.ownerType == .training)
        #expect(attachment.capturedAt == InstantText.parse("2026-09-01T08:15:00Z"))
        #expect(attachment.latitude.map(DecimalText.text) == "52.2297000", "skala zapisu z programu zostaje (bez `Double`)")
        #expect(attachment.longitude.map(DecimalText.text) == "21.0122000")
        #expect(attachment.sizeBytes == 8_421_377)
        #expect(attachment.description == "Po jeździe")
        let again = try #require(try RecordCodec.decode(.attachment, from: try RecordCodec.encode(attachment)) as? LocalAttachment)
        #expect(again == attachment)
    }

    @Test func attachmentDtoWithoutMetadataOrWithNullsParsesToNils() throws {
        let base = #""id":"a1","ownerType":"Note","ownerId":"n1","fileName":"a.jpg","contentType":"image/jpeg","sizeBytes":1,"sha256":"\#(String(repeating: "0", count: 64))","createdAt":"2026-09-01T08:20:41""#
        let nulls = #","capturedAt":null,"latitude":null,"longitude":null"#
        for json in ["{" + base + "}", "{" + base + nulls + "}"] {
            let attachment = try #require(ApiRecordMapping.record(.attachment, from: try JSONValue.parseKeepingScale(json)) as? LocalAttachment)
            #expect(attachment.capturedAt == nil)
            #expect(attachment.latitude == nil)
            #expect(attachment.longitude == nil)
            #expect(attachment.version == 1, "DTO bez `version` — wersja 1 jak `Attachment.toRecord` Androida")
            #expect(attachment.updatedAt == attachment.createdAt)
        }
    }

    @Test func coordinatesOutsideTheWgs84RangeAreDroppedAndTheBoundsAreKept() async throws {
        let setup = try makeSetup(capabilities: Self.withTrainingAttachments)
        setup.program.on("POST", "attachments", .json(201, #"{"id":"srv-a1"}"#), .json(201, #"{"id":"srv-a2"}"#), .json(201, #"{"id":"srv-a3"}"#))
        let owner = AttachmentOwner(type: .training, id: "t1", horseId: "h1")
        let ids = try await setup.attachments.add(owner, [
            try video(setup, latitude: "91", longitude: "21.0122"),
            try video(setup, latitude: "52.2297", longitude: "181"),
            try video(setup, latitude: "90", longitude: "-180"),
        ])

        var records: [LocalAttachment] = []
        for id in ids { records.append(try #require(try await setup.store.get(.attachment, id: id)?.record(as: LocalAttachment.self))) }
        for dropped in records.prefix(2) {
            #expect(dropped.latitude == nil && dropped.longitude == nil, "miejsce spoza zakresu odrzucone w całości")
            #expect(dropped.capturedAt == InstantText.parse("2026-09-01T08:15:00Z"), "chwila zostaje")
        }
        #expect(records[2].latitude.map(DecimalText.text) == "90.0000000")
        #expect(records[2].longitude.map(DecimalText.text) == "-180.0000000")
        let queued = try await setup.store.read { access in try access.operations().compactMap { try access.outboxFile($0.id) } }
        #expect(queued.map { $0.latitude == nil && $0.longitude == nil } == [true, true, false])

        #expect(await setup.processor.processAll().sent == 3)

        let requests = setup.program.requests("POST", "attachments")
        #expect(requests.count == 3)
        for request in requests.prefix(2) {
            #expect(try parts(of: request).map(\.name) == ["ownerType", "ownerId", "capturedAt", "file"])
        }
        let bounds = Dictionary(uniqueKeysWithValues: try parts(of: requests[2]).map { ($0.name, $0.text) })
        #expect(bounds["latitude"] == "90.0000000")
        #expect(bounds["longitude"] == "-180.0000000")
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
