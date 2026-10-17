import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Źródło miniatur zdjęć koni (poprawka 2.0.2, FR-006…FR-011, SC-002): lokalna miniatura → miniatura z lokalnego oryginału →
/// program (`GET attachments/{id}/thumbnail`), zapis przypięty; „Pokaż zdjęcie” pobiera oryginał; pobieranie równoległe z limitem.
struct HorsePhotoSourceTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 5, hour: 9)!

    private struct Setup {
        let store: RecordStore
        let files: LocalFileStore
        let program: FakeProgram
        let attachments: AttachmentStore
        let root: URL
    }

    private func makeSetup(mode: WorkMode = .online) throws -> Setup {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-photo-\(UUID().uuidString)", isDirectory: true)
        let files = try LocalFileStore(root: root.appendingPathComponent("Files", isDirectory: true))
        let program = FakeProgram()
        let (client, _) = program.client()
        let attachments = AttachmentStore(store: store, files: files, client: client, mode: { mode }, settings: { AttachmentSettings() })
        return Setup(store: store, files: files, program: program, attachments: attachments, root: root)
    }

    private func photo(_ id: String) -> LocalAttachment {
        LocalAttachment(
            id: id, createdAt: stamp, updatedAt: stamp, version: 1, ownerType: .horse, ownerId: "h1", horseId: "h1", fileName: "\(id).jpg",
            contentType: "image/jpeg", sizeBytes: 1024, sha256: String(repeating: "a", count: 64)
        )
    }

    private func jpeg(_ left: TestImages.Color = .red) -> Data {
        TestImages.jpeg(width: 600, height: 400, leftColor: left, rightColor: .blue)
    }

    private func store(_ data: Data, _ setup: Setup, id: String, kind: FileKind, pinned: Bool = false) async throws {
        let info = try setup.files.write(data, attachmentId: id, kind: kind, pinned: pinned)
        try await setup.store.write { try $0.upsertFile(info) }
    }

    // MARK: Kolejność źródeł

    @Test func aLocalThumbnailIsReturnedWithoutAnyRequest() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let small = try ImagePreparer.thumbnail(jpeg())
        try await store(small, setup, id: "a1", kind: .thumbnail, pinned: true)
        #expect(await setup.attachments.thumbnail(attachmentId: "a1") == .image(small))
        #expect(setup.program.requests.isEmpty)
    }

    @Test func aLocalOriginalProducesAPinnedThumbnailWithoutAnyRequest() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        try await store(jpeg(), setup, id: "a1", kind: .original, pinned: true)
        guard case let .image(data) = await setup.attachments.thumbnail(attachmentId: "a1") else { throw SourceFailure("brak miniatury") }
        #expect(!data.isEmpty)
        let saved = try #require(try await setup.store.read { try $0.file(attachmentId: "a1", kind: .thumbnail) })
        #expect(saved.pinned)
        #expect(setup.program.requests.isEmpty)
    }

    @Test func onlineWithoutFilesTheThumbnailComesFromTheProgramIsPinnedAndNotRequestedTwice() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let small = try ImagePreparer.thumbnail(jpeg())
        setup.program.on("GET", "attachments/a1/thumbnail", .bytes(200, small))
        #expect(await setup.attachments.thumbnail(attachmentId: "a1") == .image(small))
        let saved = try #require(try await setup.store.read { try $0.file(attachmentId: "a1", kind: .thumbnail) })
        #expect(saved.pinned)
        #expect(await setup.attachments.thumbnail(attachmentId: "a1") == .image(small))
        #expect(setup.program.requests("GET", "attachments/a1/thumbnail").count == 1)
    }

    @Test func withoutTheNetworkTheResultIsFailedNotAnError() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        setup.program.on("GET", "attachments/a1/thumbnail", .fail(.cannotConnectToHost))
        #expect(await setup.attachments.thumbnail(attachmentId: "a1") == .failed)
        #expect(try await setup.store.read { try $0.file(attachmentId: "a1", kind: .thumbnail) } == nil)
    }

    @Test func aMissingPhotoInTheProgramIsUnavailable() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        setup.program.on("GET", "attachments/a1/thumbnail", .json(404, #"{"title":"Nie znaleziono"}"#))
        #expect(await setup.attachments.thumbnail(attachmentId: "a1") == .unavailable)
    }

    @Test func inStandaloneModeWithoutFilesNothingIsRequested() async throws {
        let setup = try makeSetup(mode: .standalone)
        defer { try? FileManager.default.removeItem(at: setup.root) }
        #expect(await setup.attachments.thumbnail(attachmentId: "a1") == .failed)
        #expect(setup.program.requests.isEmpty)
    }

    // MARK: Pełne zdjęcie

    @Test func showingThePhotoDownloadsTheOriginalWhenItIsNotInThePhone() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let original = jpeg(.green)
        try await setup.store.write { try $0.upsert([try StoredRecord.of(photo("a1"), syncState: .synced)]) }
        setup.program.on("GET", "attachments/a1/content", .bytes(200, original))
        let url = try await setup.attachments.content(attachmentId: "a1")
        #expect(try Data(contentsOf: url) == original)
        #expect(setup.program.requests("GET", "attachments/a1/content").count == 1)
        // Drugie otwarcie — z pamięci telefonu.
        _ = try await setup.attachments.content(attachmentId: "a1")
        #expect(setup.program.requests("GET", "attachments/a1/content").count == 1)
    }

    @Test func showingAPhotoWithoutARecordIsUnavailable() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        await #expect(throws: AttachmentError.fileUnavailable) {
            try await setup.attachments.content(attachmentId: "nie-ma")
        }
    }

    // MARK: Pobieranie wielu miniatur

    @Test func changingTheHorsesPhotoFetchesTheNewThumbnail() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let first = try ImagePreparer.thumbnail(jpeg(.red))
        let second = try ImagePreparer.thumbnail(jpeg(.green))
        setup.program.on("GET", "attachments/old/thumbnail", .bytes(200, first))
        setup.program.on("GET", "attachments/new/thumbnail", .bytes(200, second))
        let fetcher = ThumbnailFetcher(attachments: setup.attachments)
        let delivered = Delivered()

        await fetcher.fetch(["old"], deliver: { delivered.add($0, $1) })
        #expect(delivered.data["old"] == first)
        // Po synchronizacji koń wskazuje inne zdjęcie (nowy `photoAttachmentId`).
        await fetcher.fetch(["new"], deliver: { delivered.add($0, $1) })
        #expect(delivered.data["new"] == second)
        #expect(delivered.data["new"] != delivered.data["old"])
    }

    @Test func thirtyHorsesGetTheirThumbnailsWithinTenSecondsWithAtMostFourRequestsAtOnce() async throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let small = try ImagePreparer.thumbnail(jpeg())
        setup.program.on("GET", "attachments/p*", .bytes(200, small, delay: 0.3))
        let ids = (0..<30).map { "p\($0)" }
        let delivered = Delivered()
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await ThumbnailFetcher(attachments: setup.attachments).fetch(ids, deliver: { delivered.add($0, $1) })
        }
        #expect(delivered.data.count == 30)
        #expect(setup.program.requests.count == 30)
        #expect(elapsed < .seconds(10))
    }

    @Test func theFetcherNeverRunsMoreThanFourSourcesAtOnce() async {
        let gauge = Gauge()
        let fetcher = ThumbnailFetcher { _ in
            gauge.enter()
            try? await Task.sleep(for: .milliseconds(40))
            gauge.leave()
            return .image(Data([1]))
        }
        let delivered = Delivered()
        await fetcher.fetch((0..<30).map { "p\($0)" }, deliver: { delivered.add($0, $1) })
        #expect(delivered.data.count == 30)
        #expect(gauge.peak <= 4)
        #expect(gauge.peak >= 2)
    }

    @Test func failedFetchesAreNotRetriedUntilForgottenAndUnavailableOnesNever() async {
        let calls = Gauge()
        let fetcher = ThumbnailFetcher { id in
            calls.enter()
            calls.leave()
            return id == "gone" ? .unavailable : .failed
        }
        let delivered = Delivered()
        await fetcher.fetch(["gone", "later"], deliver: { delivered.add($0, $1) })
        await fetcher.fetch(["gone", "later"], deliver: { delivered.add($0, $1) })
        #expect(calls.entered == 2)
        await fetcher.forgetFailures()
        await fetcher.fetch(["gone", "later"], deliver: { delivered.add($0, $1) })
        #expect(calls.entered == 3)
        #expect(delivered.data.isEmpty)
    }

    // MARK: Pomocnicze

    private struct SourceFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private final class Delivered: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: Data] = [:]

        func add(_ id: String, _ data: Data) {
            lock.lock()
            storage[id] = data
            lock.unlock()
        }

        var data: [String: Data] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    /// Licznik równoczesnych wywołań.
    private final class Gauge: @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private(set) var peak = 0
        private(set) var entered = 0

        func enter() {
            lock.lock()
            running += 1
            entered += 1
            peak = max(peak, running)
            lock.unlock()
        }

        func leave() {
            lock.lock()
            running -= 1
            lock.unlock()
        }
    }
}
