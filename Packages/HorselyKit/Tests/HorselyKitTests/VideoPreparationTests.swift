import Foundation
import HorselyCore
import Synchronization
import Testing
@testable import HorselyKit

/// Przygotowanie filmów w kolejce i w trybie samodzielnym (decyzja A10; `VideoPrepareJobTest.kt`, `VideoPrepareSweepTest.kt` Androida):
/// operacja `held` do końca przygotowania, potem `pending`; wznowienie przerwanego przy starcie; odrzucenie z komunikatem. Kodek jest
/// podmieniony (`FakeTranscoder`) — sama decyzja, podmiana pliku i stany kolejki działają naprawdę (baza w pamięci, pliki na dysku).
struct VideoPreparationTests {
    private static let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9, 9])
    private static let transcodedBytes = Data("film 720p".utf8)

    /// Zachowanie kodeka zastępczego: zapis wyniku, błąd albo „sukces” bez pliku wynikowego (nieoczekiwany błąd dalej w przygotowaniu).
    enum Behaviour: Sendable {
        case writes
        case failing(NSError)
        case writesNothing
    }

    /// Błąd `AVAssetExportSession` po zawieszeniu aplikacji w trakcie eksportu (`AVError.operationInterrupted`).
    static let interrupted = NSError(domain: "AVFoundationErrorDomain", code: -11847)

    /// Kodek zastępczy: zapisuje `transcodedBytes` w `target` (albo zgłasza błąd) i liczy wywołania.
    private final class FakeTranscoder: VideoTranscoding {
        let behaviour: Mutex<Behaviour>
        let calls = Mutex(0)

        init(_ behaviour: Behaviour) {
            self.behaviour = Mutex(behaviour)
        }

        func prepare(source: URL, target: URL, progress: @escaping @Sendable (Int) -> Void) async throws -> URL {
            calls.withLock { $0 += 1 }
            progress(45)
            switch behaviour.withLock({ $0 }) {
            case let .failing(error): throw error
            case .writesNothing: return target
            case .writes: break
            }
            try VideoPreparationTests.transcodedBytes.write(to: target)
            progress(100)
            return target
        }
    }

    private final class Recorded: Sendable {
        let values = Mutex<[Int?]>([])
        func append(_ value: Int?) { values.withLock { $0.append(value) } }
        var all: [Int?] { values.withLock { $0 } }
    }

    private struct Setup {
        let store: RecordStore
        let files: LocalFileStore
        let processor: OutboxProcessor
        let attachments: AttachmentStore
        let transcoder: FakeTranscoder
        let progress: Recorded
        let make: @Sendable () -> AttachmentStore
    }

    private func makeSetup(mode: WorkMode = .online, shortSide: Int = 2160, fails: Bool = false, behaviour: Behaviour? = nil) throws -> Setup {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-video-\(UUID().uuidString)", isDirectory: true)
        let files = try LocalFileStore(root: root.appendingPathComponent("Files", isDirectory: true))
        let program = FakeProgram()
        let capabilities = ProgramCapabilities(names: ["idempotencyKey"])
        let (client, _) = program.client(capabilities: capabilities)
        let processor = OutboxProcessor(store: store, client: client, capabilities: { capabilities }, now: { Date() })
        let transcoder = FakeTranscoder(behaviour ?? (fails ? .failing(VideoPreparerError.unsupported as NSError) : .writes))
        let progress = Recorded()
        let videos = VideoPreparation(transcoder: transcoder, inspect: { _ in VideoInfo(shortSidePx: shortSide, durationSeconds: 60) }, thumbnail: { _ in Self.jpegBytes })
        let make: @Sendable () -> AttachmentStore = {
            AttachmentStore(
                store: store, files: files, client: client, mode: { mode }, settings: { AttachmentSettings() }, videos: videos,
                videoProgress: { _, percent in progress.append(percent) }
            )
        }
        return Setup(store: store, files: files, processor: processor, attachments: make(), transcoder: transcoder, progress: progress, make: make)
    }

    private func video(_ setup: Setup, sendOriginal: Bool = false) throws -> PendingAttachment {
        let file = try setup.attachments.prepare(data: Data((0 ..< 4096).map { UInt8(truncatingIfNeeded: $0 % 251) }), fileName: "jazda.mov", mimeType: "video/quicktime")
        return PendingAttachment(file: file, sendOriginal: sendOriginal)
    }

    private func attachmentOperation(_ setup: Setup) async throws -> (OutboxOperation, OutboxFile) {
        let operation = try #require(try await setup.store.read { try $0.operations().first { $0.kind == .createAttachment } })
        let file = try #require(try await setup.store.read { try $0.outboxFile(operation.id) })
        return (operation, file)
    }

    @Test func aLargeVideoWaitsHeldAndIsNotSentUntilPrepared() async throws {
        let setup = try makeSetup()
        let id = try #require(try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)]).first)

        let (operation, file) = try await attachmentOperation(setup)
        #expect(operation.state == .held)
        #expect(file.needsPreparation)
        #expect(file.fileName == "jazda.mov")
        #expect(setup.transcoder.calls.withLock { $0 } == 0, "dodanie nie czeka na kodowanie")
        let snapshot = try await setup.store.queueSnapshot()
        #expect(snapshot.preparing == [operation.id])
        #expect(snapshot.preparingOperation(attachmentId: id)?.id == operation.id)
        #expect(snapshot.marker(.attachment, id: id) == .pending, "film w przygotowaniu nie „wymaga poprawy”")
        #expect(await setup.attachments.hasPreparingVideos())
        #expect(await setup.processor.processAll().sent == 0, "plik źródłowy nie wychodzi do programu")
    }

    @Test func interruptedPreparationResumesOnLaunch() async throws {
        let setup = try makeSetup()
        try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)])
        let (operation, held) = try await attachmentOperation(setup)
        // Przerwane kodowanie (zabity proces): operacja `held` ze źródłem, bez pliku wynikowego w kolejce, z resztką pliku częściowego.
        let source = URL(fileURLWithPath: held.path)
        let partial = source.deletingLastPathComponent().appendingPathComponent("jazda-720p.mp4")
        try Data("urwane".utf8).write(to: partial)

        // Start aplikacji: nowy magazyn załączników nad tą samą bazą wznawia przygotowanie.
        let released = await setup.make().resumePreparation()

        #expect(released == 1)
        let (after, file) = try await attachmentOperation(setup)
        #expect(after.id == operation.id)
        #expect(after.state == .pending)
        #expect(!file.needsPreparation)
        #expect(file.path == partial.path)
        #expect(file.fileName == "jazda.mp4")
        #expect(file.contentType == "video/mp4")
        #expect(try Data(contentsOf: partial) == Self.transcodedBytes, "plik częściowy zastąpiony pełnym wynikiem")
        #expect(file.sizeBytes == Int64(Self.transcodedBytes.count))
        #expect(file.sha256 == (try FileDigest.sha256(of: partial)).hex)
        let thumbnail = try #require(file.thumbnailPath)
        #expect(FileManager.default.contents(atPath: thumbnail) == Self.jpegBytes)
        #expect(!FileManager.default.fileExists(atPath: source.path), "źródło usunięte po utrwaleniu wyniku")
        #expect(setup.progress.all.contains(45) && setup.progress.all.last == .some(nil), "postęp „Przygotowuję film… 45%”, potem koniec")
        #expect(try await setup.store.queueSnapshot().preparing.isEmpty)
        #expect(await setup.make().resumePreparation() == 0, "drugi przebieg nie ma nic do zrobienia")
    }

    @Test func aVideoNotNeedingTranscodingGoesStraightToTheQueueWithAThumbnail() async throws {
        let setup = try makeSetup(shortSide: 480)
        try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)])

        let (operation, file) = try await attachmentOperation(setup)
        #expect(operation.state == .pending)
        #expect(!file.needsPreparation)
        #expect(file.fileName == "jazda.mov")
        #expect(file.thumbnailPath.flatMap { FileManager.default.contents(atPath: $0) } == Self.jpegBytes)
        #expect(setup.transcoder.calls.withLock { $0 } == 0)
    }

    @Test func sendOriginalKeeps4KBelow100MB() async throws {
        let setup = try makeSetup()
        try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup, sendOriginal: true)])

        let (operation, file) = try await attachmentOperation(setup)
        #expect(operation.state == .pending)
        #expect(!file.needsPreparation)
    }

    @Test func aFailedTranscodeNeedsFixAndDropsTheSource() async throws {
        let setup = try makeSetup(fails: true)
        try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)])
        let (_, held) = try await attachmentOperation(setup)

        #expect(await setup.attachments.resumePreparation() == 0)

        let (operation, _) = try await attachmentOperation(setup)
        #expect(operation.state == .needsFix)
        #expect(operation.problem?.firstMessage == VideoPreparation.transcodeFailed)
        #expect(!FileManager.default.fileExists(atPath: held.path), "nieprzygotowany film nie wyjdzie po „Wyślij ponownie”")
        #expect(try await setup.store.queueSnapshot().preparing.isEmpty)
    }

    @Test func anInterruptedExportKeepsTheVideoHeldAndResumesLater() async throws {
        let setup = try makeSetup(behaviour: .failing(Self.interrupted))
        try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)])
        let (operation, held) = try await attachmentOperation(setup)

        // Aplikacja zawieszona w trakcie eksportu: błąd przejściowy, nie odrzucenie.
        #expect(await setup.attachments.resumePreparation() == 0)

        let (after, file) = try await attachmentOperation(setup)
        #expect(after.state == .held)
        #expect(after.problem == nil)
        #expect(file == held, "wpis kolejki nietknięty")
        #expect(FileManager.default.fileExists(atPath: held.path), "plik źródłowy zostaje")
        #expect(try await setup.store.queueSnapshot().preparing == [operation.id])
        #expect(setup.progress.all.last == .some(nil))

        // Następny start albo zadanie w tle kończy przygotowanie.
        setup.transcoder.behaviour.withLock { $0 = .writes }
        #expect(await setup.make().resumePreparation() == 1)
        #expect(try await attachmentOperation(setup).0.state == .pending)
    }

    @Test func interruptionErrorsAreTransientAndOthersAreNot() {
        #expect(VideoPreparation.isInterruption(Self.interrupted))
        #expect(VideoPreparation.isInterruption(NSError(domain: "AVFoundationErrorDomain", code: -11818)))
        #expect(VideoPreparation.isInterruption(NSError(domain: "AVFoundationErrorDomain", code: -11819)))
        #expect(VideoPreparation.isInterruption(CancellationError()))
        #expect(VideoPreparation.isInterruption(NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: Self.interrupted])))
        #expect(!VideoPreparation.isInterruption(NSError(domain: "AVFoundationErrorDomain", code: -11800)))
        #expect(!VideoPreparation.isInterruption(VideoPreparerError.unsupported))
    }

    @Test func standaloneKeepsTheOriginalWhenTheExportIsInterrupted() async throws {
        let setup = try makeSetup(mode: .standalone, behaviour: .failing(Self.interrupted))
        let id = try #require(try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)]).first)

        let record = try #require(try await setup.store.get(.attachment, id: id)?.record(as: LocalAttachment.self))
        #expect(record.fileName == "jazda.mov", "film zapisany w oryginale — nic nie ginie")
    }

    @Test func anUnexpectedErrorNeedsFixAndCleansUp() async throws {
        // Kodek „kończy” bez pliku wynikowego — skrót SHA-256 wyniku się nie udaje: ścieżka `preparationFailed`.
        let setup = try makeSetup(behaviour: .writesNothing)
        try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)])
        let (_, held) = try await attachmentOperation(setup)
        let folder = URL(fileURLWithPath: held.path).deletingLastPathComponent()

        #expect(await setup.attachments.resumePreparation() == 0)

        let (operation, _) = try await attachmentOperation(setup)
        #expect(operation.state == .needsFix)
        #expect(operation.problem?.firstMessage == AttachmentStore.preparationFailed)
        #expect(!FileManager.default.fileExists(atPath: held.path), "źródło usunięte")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        #expect(!leftovers.contains { $0.hasSuffix("-miniatura.jpg") || $0.hasSuffix("-720p.mp4") }, "wyniki przygotowania usunięte: \(leftovers)")
        #expect(try await setup.store.queueSnapshot().preparing.isEmpty)
    }

    @Test func aMissingSourceNeedsFix() async throws {
        let setup = try makeSetup()
        try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)])
        let (_, held) = try await attachmentOperation(setup)
        try FileManager.default.removeItem(atPath: held.path)

        await setup.attachments.resumePreparation()

        let (operation, _) = try await attachmentOperation(setup)
        #expect(operation.state == .needsFix)
        #expect(operation.problem?.firstMessage == AttachmentStore.missingVideo)
    }

    @Test func aVideoBeingPreparedCanBeWithdrawn() async throws {
        let setup = try makeSetup()
        let id = try #require(try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)]).first)

        #expect(await setup.attachments.isQueued(id))
        #expect(try await setup.attachments.withdraw(id))
        #expect(try await setup.store.read { try $0.operations() }.isEmpty)
        #expect(await setup.attachments.resumePreparation() == 0)
    }

    @Test func standaloneTranscodesBeforeSavingTheFile() async throws {
        let setup = try makeSetup(mode: .standalone)
        let percents = Recorded()
        let id = try #require(try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)]) { percents.append($0) }.first)

        let record = try #require(try await setup.store.get(.attachment, id: id)?.record(as: LocalAttachment.self))
        #expect(record.fileName == "jazda.mp4")
        #expect(record.contentType == "video/mp4")
        #expect(record.sizeBytes == Int64(Self.transcodedBytes.count))
        #expect(percents.all.contains(45))
        let original = try #require(try await setup.store.read { try $0.file(attachmentId: id, kind: .original) })
        #expect(setup.files.read(original) == Self.transcodedBytes)
        let thumbnail = try #require(try await setup.store.read { try $0.file(attachmentId: id, kind: .thumbnail) })
        #expect(setup.files.read(thumbnail) == Self.jpegBytes)
        #expect(try await setup.store.read { try $0.operations() }.isEmpty, "tryb samodzielny nie używa kolejki")
    }

    @Test func standaloneKeepsTheOriginalWhenTranscodingFails() async throws {
        let setup = try makeSetup(mode: .standalone, fails: true)
        let id = try #require(try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [try video(setup)]).first)

        let record = try #require(try await setup.store.get(.attachment, id: id)?.record(as: LocalAttachment.self))
        #expect(record.fileName == "jazda.mov", "nic nie jest wysyłane, więc film zapisuje się w oryginale (lenient)")
    }

    @Test func aLargeVideoIsAcceptedWhenAddedButOtherLargeFilesAreNot() async throws {
        let setup = try makeSetup()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-big-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let big = folder.appendingPathComponent("jazda.mov")
        #expect(FileManager.default.createFile(atPath: big.path, contents: nil))
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(FilePolicy.maxBytes) + 1)
        try handle.close()

        let imported = try setup.attachments.prepare(fileAt: big, mimeType: "video/quicktime")
        #expect(imported.sizeBytes == FilePolicy.maxBytes + 1)
        // Tak jak z udostępniania (skrzynka → `prepare(fileAt:)` → `add`): film ≥ 100 MB czeka w kolejce na zmniejszenie.
        try await setup.attachments.add(AttachmentOwner(type: .note, id: "n1", horseId: "h1"), [PendingAttachment(file: imported)])
        let (operation, file) = try await attachmentOperation(setup)
        #expect(operation.state == .held)
        #expect(file.needsPreparation)
        let pdf = folder.appendingPathComponent("skan.pdf")
        try FileManager.default.copyItem(at: big, to: pdf)
        #expect(throws: AttachmentError.self) { try setup.attachments.prepare(fileAt: pdf, mimeType: "application/pdf") }
    }
}
