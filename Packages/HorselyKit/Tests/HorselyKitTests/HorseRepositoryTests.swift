import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Repozytorium koni w trybie samodzielnym (T044): zapis z regułami, lista, zdjęcie konia z plikiem i miniaturą.
struct HorseRepositoryTests {
    private let today = LocalDate(year: 2026, month: 10, day: 5)!

    private func makeRepository() throws -> (HorseRepository, RecordStore, URL) {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-files-\(UUID().uuidString)")
        let repository = HorseRepository(store: store, files: try LocalFileStore(root: directory), dates: FixedDateProvider(today: today))
        return (repository, store, directory)
    }

    /// Źródło miniatur i oryginałów nad tym samym magazynem co repozytorium (bez programu: tryb samodzielny).
    private func makeAttachments(_ store: RecordStore, _ directory: URL) throws -> AttachmentStore {
        AttachmentStore(store: store, files: try LocalFileStore(root: directory), client: nil, mode: { .standalone }, settings: { AttachmentSettings() })
    }

    private func draft(_ name: String, passport: String? = nil) -> HorseDraft {
        var draft = HorseDraft()
        draft.name = name
        draft.passportNumber = passport ?? "PL-\(name)"
        return draft
    }

    private func savedHorse(_ outcome: HorseRules.SaveOutcome) throws -> LocalHorse {
        guard case let .saved(horse, _) = outcome else { throw TestFailure("oczekiwano zapisu, jest \(outcome)") }
        return horse
    }

    private struct TestFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    @Test func savingANewHorseStoresItAsLocalWithVersionOne() async throws {
        let (repository, store, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let horse = try savedHorse(try await repository.save(draft("Grom")))
        #expect(horse.version == 1)
        let stored = try #require(try await store.get(.horse, id: horse.id))
        #expect(stored.syncState == .local)
        #expect(try await repository.horses().map(\.name) == ["Grom"])
        #expect(try await repository.horse(id: horse.id)?.name == "Grom")
    }

    @Test func editingBumpsTheVersionAndKeepsTheCreationTime() async throws {
        let (repository, _, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let created = try savedHorse(try await repository.save(draft("Grom")))
        var edit = HorseDraft(horse: created)
        edit.breed = "Śląski"
        let updated = try savedHorse(try await repository.save(edit, id: created.id))
        #expect(updated.version == 2)
        #expect(updated.createdAt == created.createdAt)
        #expect(updated.breed == "Śląski")
        #expect(try await repository.horses().count == 1)
    }

    @Test func rulesRejectInvalidAndDuplicatedHorsesWithoutSavingAnything() async throws {
        let (repository, store, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try savedHorse(try await repository.save(draft("Grom", passport: "PL-1")))

        var invalid = draft("Iskra")
        invalid.passportNumber = ""
        guard case let .invalid(report) = try await repository.save(invalid) else { throw TestFailure("oczekiwano odmowy") }
        #expect(report.errors["passportNumber"] == [Messages.required])

        let outcome = try await repository.save(draft("Iskra", passport: "pl-1"))
        #expect(outcome == .conflict(.passportTaken))
        #expect(try await store.count(.horse) == 1)
    }

    @Test func editingAnUnknownHorseFails() async throws {
        let (repository, _, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: StoreError.notFound("brak")) {
            try await repository.save(draft("X"), id: "brak")
        }
    }

    @Test func statusChangesFollowTheProgramRules() async throws {
        let (repository, _, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let horse = try savedHorse(try await repository.save(draft("Gaj")))
        var edit = HorseDraft(horse: horse)
        edit.status = .deceased
        edit.statusDate = today
        edit.finance = HorseFinanceDraft(salePrice: Money(string: "7777"))
        let dead = try savedHorse(try await repository.save(edit, id: horse.id))
        #expect(dead.status == .deceased)
        #expect(dead.salePrice == .zero)
        #expect(dead.saleDate == today)
    }

    @Test func observationEmitsHorsesAfterEachSave() async throws {
        let (repository, _, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        var iterator = repository.observeHorses().makeAsyncIterator()
        #expect(try await iterator.next()?.count == 0)
        _ = try await repository.save(draft("Grom"))
        #expect(try await iterator.next()?.map(\.name) == ["Grom"])
    }

    // MARK: Zdjęcie

    private func sampleImage() throws -> PreparedImage {
        try ImagePreparer.prepare(TestImages.jpeg(width: 600, height: 400, leftColor: .red, rightColor: .blue, withGPS: true))
    }

    @Test func settingAPhotoAddsAnAttachmentWithFilesAndPointsTheHorseAtIt() async throws {
        let (repository, store, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let horse = try savedHorse(try await repository.save(draft("Grom")))
        try await repository.setPhoto(horseId: horse.id, image: try sampleImage())

        let updated = try #require(try await repository.horse(id: horse.id))
        let photoId = try #require(updated.photoAttachmentId)
        #expect(updated.version == 2)

        let attachment = try #require(try await store.get(.attachment, id: photoId)?.record(as: LocalAttachment.self))
        #expect(attachment.ownerType == .horse)
        #expect(attachment.horseId == horse.id)
        #expect(attachment.contentType == "image/jpeg")
        #expect(try await repository.imageAttachments(horseId: horse.id).map(\.id) == [photoId])

        let attachments = try makeAttachments(store, directory)
        guard case let .image(thumbnail) = await attachments.thumbnail(attachmentId: photoId) else { throw TestFailure("brak miniatury") }
        let original = try Data(contentsOf: try await attachments.content(attachmentId: photoId))
        #expect(!thumbnail.isEmpty && thumbnail.count < original.count)
        #expect(!ImagePreparer.hasGPS(original))

        let file = try #require(try await store.read { try $0.file(attachmentId: photoId, kind: .original) })
        #expect(file.pinned)
        #expect(file.sizeBytes == Int(attachment.sizeBytes))
        #expect(file.sha256 == attachment.sha256)
    }

    @Test func replacingThePhotoKeepsThePreviousOneInTheAttachments() async throws {
        let (repository, _, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let horse = try savedHorse(try await repository.save(draft("Grom")))
        try await repository.setPhoto(horseId: horse.id, image: try sampleImage())
        let first = try #require(try await repository.horse(id: horse.id)?.photoAttachmentId)
        try await repository.setPhoto(horseId: horse.id, image: try sampleImage())
        let second = try #require(try await repository.horse(id: horse.id)?.photoAttachmentId)
        #expect(first != second)
        #expect(Set(try await repository.imageAttachments(horseId: horse.id).map(\.id)) == [first, second])
    }

    @Test func removingThePhotoOnlyUnlinksIt() async throws {
        let (repository, store, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let horse = try savedHorse(try await repository.save(draft("Grom")))
        try await repository.setPhoto(horseId: horse.id, image: try sampleImage())
        let photoId = try #require(try await repository.horse(id: horse.id)?.photoAttachmentId)
        try await repository.clearPhoto(horseId: horse.id)
        #expect(try await repository.horse(id: horse.id)?.photoAttachmentId == nil)
        #expect(try await repository.imageAttachments(horseId: horse.id).map(\.id) == [photoId])
        guard case .image = await (try makeAttachments(store, directory)).thumbnail(attachmentId: photoId) else { throw TestFailure("brak miniatury") }
    }

    /// FR-011: po przejściu na tryb samodzielny (pobrany oryginał zdjęcia konia, bez miniatury) awatar działa bez programu.
    @Test func afterSwitchingToStandaloneAHorsePhotoGetsItsThumbnailFromTheDownloadedOriginal() async throws {
        let (repository, store, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let horse = try savedHorse(try await repository.save(draft("Grom")))
        try await repository.setPhoto(horseId: horse.id, image: try sampleImage())
        let photoId = try #require(try await repository.horse(id: horse.id)?.photoAttachmentId)
        // Stan po pobraniu oryginałów z programu: jest oryginał, nie ma miniatury.
        let original = try #require(try await store.read { try $0.file(attachmentId: photoId, kind: .original) })
        try await store.write { access in
            try access.deleteFiles(attachmentId: photoId)
            try access.upsertFile(original)
        }
        try FileManager.default.removeItem(at: directory.appendingPathComponent("\(photoId)/thumbnail.jpg"))
        let attachments = try makeAttachments(store, directory)
        #expect(try await store.read { try $0.file(attachmentId: photoId, kind: .thumbnail) } == nil)

        guard case let .image(data) = await attachments.thumbnail(attachmentId: photoId) else { throw TestFailure("brak miniatury") }
        #expect(!data.isEmpty)
        let saved = try #require(try await store.read { try $0.file(attachmentId: photoId, kind: .thumbnail) })
        #expect(saved.pinned)
    }

    @Test func aPhotoCanBeChosenOnlyFromTheHorsesOwnImages() async throws {
        let (repository, _, directory) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let grom = try savedHorse(try await repository.save(draft("Grom")))
        let iskra = try savedHorse(try await repository.save(draft("Iskra")))
        try await repository.setPhoto(horseId: grom.id, image: try sampleImage())
        try await repository.clearPhoto(horseId: grom.id)
        let attachment = try #require(try await repository.imageAttachments(horseId: grom.id).first)

        try await repository.choosePhoto(horseId: grom.id, attachmentId: attachment.id)
        #expect(try await repository.horse(id: grom.id)?.photoAttachmentId == attachment.id)

        await #expect(throws: HorsePhotoError.notAnImageOfTheHorse) {
            try await repository.choosePhoto(horseId: iskra.id, attachmentId: attachment.id)
        }
    }
}
