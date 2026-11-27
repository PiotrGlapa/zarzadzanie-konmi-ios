import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Miniatury kafli załączników (US3.0-1 p. 2; `the detail asks for the thumbnail only of attachments that have one` Androida): zdjęcie —
/// jak dotąd; film — z pamięci telefonu, z pliku operacji w kolejce albo (tylko z programem) z `GET attachments/{id}/thumbnail`;
/// inne pliki i film w trybie samodzielnym nie wysyłają żadnego żądania.
struct AttachmentThumbnailTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 5, hour: 9)!
    private let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])

    private struct Setup {
        let store: RecordStore
        let files: LocalFileStore
        let program: FakeProgram
        let attachments: AttachmentStore
        let root: URL
    }

    private func makeSetup(mode: WorkMode = .online) throws -> Setup {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-tile-\(UUID().uuidString)", isDirectory: true)
        let files = try LocalFileStore(root: root.appendingPathComponent("Files", isDirectory: true))
        let program = FakeProgram()
        let (client, _) = program.client()
        let attachments = AttachmentStore(store: store, files: files, client: client, mode: { mode }, settings: { AttachmentSettings() })
        return Setup(store: store, files: files, program: program, attachments: attachments, root: root)
    }

    private func attachment(_ id: String, _ contentType: String) -> LocalAttachment {
        LocalAttachment(
            id: id, createdAt: stamp, updatedAt: stamp, version: 1, ownerType: .training, ownerId: "t1", horseId: "h1", fileName: "\(id).bin",
            contentType: contentType, sizeBytes: 1024, sha256: String(repeating: "a", count: 64)
        )
    }

    @Test func aThumbnailIsOfferedForPhotosAlwaysForVideosOnlyWithTheProgramAndNeverForOtherFiles() {
        #expect(AttachmentStore.mayHaveRemoteThumbnail(contentType: "image/jpeg", online: true))
        #expect(AttachmentStore.mayHaveRemoteThumbnail(contentType: "image/png", online: false))
        #expect(AttachmentStore.mayHaveRemoteThumbnail(contentType: "video/mp4", online: true))
        #expect(!AttachmentStore.mayHaveRemoteThumbnail(contentType: "video/mp4", online: false), "w trybie samodzielnym miniatura leży tylko w telefonie")
        #expect(!AttachmentStore.mayHaveRemoteThumbnail(contentType: "application/pdf", online: true))
        #expect(!AttachmentStore.mayHaveRemoteThumbnail(contentType: "text/plain", online: true))
    }

    @Test func aVideoFromTheProgramAsksForItsThumbnailOnceAndKeepsItUnpinned() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        setup.program.on("GET", "attachments/v1/thumbnail", .bytes(200, jpegBytes))

        #expect(await setup.attachments.thumbnail(attachment("v1", "video/mp4")) == jpegBytes)
        #expect(await setup.attachments.thumbnail(attachment("v1", "video/mp4")) == jpegBytes)

        #expect(setup.program.requests("GET", "attachments/v1/thumbnail").count == 1, "drugi raz z pamięci telefonu")
        let saved = try #require(try await setup.store.read { try $0.file(attachmentId: "v1", kind: .thumbnail) })
        #expect(!saved.pinned, "miniatura filmu z programu podlega czyszczeniu LRU")
    }

    @Test func aVideoWithoutAThumbnailInTheProgramKeepsTheIcon() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        setup.program.on("GET", "attachments/v1/thumbnail", .json(404, #"{"title":"Nie znaleziono"}"#))

        #expect(await setup.attachments.thumbnail(attachment("v1", "video/mp4")) == nil)
        #expect(try await setup.store.read { try $0.file(attachmentId: "v1", kind: .thumbnail) } == nil)
    }

    @Test func inStandaloneModeAVideoUsesOnlyItsLocalThumbnailAndNeverAsksTheProgram() async throws {
        let setup = try makeSetup(mode: .standalone)
        defer { try? FileManager.default.removeItem(at: setup.root) }
        #expect(await setup.attachments.thumbnail(attachment("v1", "video/mp4")) == nil)

        let info = try setup.files.write(jpegBytes, attachmentId: "v2", kind: .thumbnail, pinned: true)
        try await setup.store.write { try $0.upsertFile(info) }
        #expect(await setup.attachments.thumbnail(attachment("v2", "video/mp4")) == jpegBytes)
        #expect(setup.program.requests.isEmpty)
    }

    @Test func otherFilesNeverAskTheProgramForAThumbnail() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }

        #expect(await setup.attachments.thumbnail(attachment("d1", "application/pdf")) == nil)
        #expect(await setup.attachments.thumbnail(attachment("d2", "text/plain")) == nil)
        #expect(setup.program.requests.isEmpty)
    }

    @Test func aPhotoStillComesFromTheProgramAndIsPinned() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        setup.program.on("GET", "attachments/p1/thumbnail", .bytes(200, jpegBytes))

        #expect(await setup.attachments.thumbnail(attachment("p1", "image/jpeg")) == jpegBytes)

        #expect(setup.program.requests("GET", "attachments/p1/thumbnail").count == 1)
        #expect(try #require(try await setup.store.read { try $0.file(attachmentId: "p1", kind: .thumbnail) }).pinned)
    }

    @Test func aQueuedVideoShowsTheThumbnailOfItsOperationWithoutAnyRequest() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let folder = setup.root.appendingPathComponent("zrodlo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let thumbnail = folder.appendingPathComponent("miniatura.jpg")
        try jpegBytes.write(to: thumbnail)
        let video = try await setup.attachments.prepare(
            data: Data((0 ..< 2048).map { UInt8(truncatingIfNeeded: $0 % 200) }), fileName: "jazda.mp4", mimeType: "video/mp4"
        )

        let id = try #require(try await setup.attachments.add(
            AttachmentOwner(type: .training, id: "t1", horseId: "h1"), [PendingAttachment(file: video, thumbnail: thumbnail)]
        ).first)

        let record = try #require(try await setup.store.get(.attachment, id: id)?.record(as: LocalAttachment.self))
        #expect(await setup.attachments.thumbnail(record) == jpegBytes)
        #expect(setup.program.requests.isEmpty)
    }
}
