import Foundation
import GRDB
import HorselyCore

/// Konie w magazynie lokalnym (tryb samodzielny — telefon jest źródłem prawdy): lista, zapis z regułami programu w jednej transakcji,
/// zdjęcie konia z plikiem w załącznikach i miniaturą. Zapis w trybie online (rekord `Pending` + operacja w kolejce) dochodzi
/// w zadaniu T085.
public final class HorseRepository: Sendable {
    private let store: RecordStore
    private let files: LocalFileStore
    private let dates: any DateProvider

    public init(store: RecordStore, files: LocalFileStore, dates: any DateProvider = SystemDateProvider()) {
        self.store = store
        self.files = files
        self.dates = dates
    }

    // MARK: Odczyt

    /// Konie poza koszem (bez sortowania — filtruje i sortuje `HorseSearch`).
    public func horses() async throws -> [LocalHorse] {
        try await store.read { access in try Self.horses(in: access) }
    }

    public func horse(id: String) async throws -> LocalHorse? {
        try await store.read { access in
            guard let stored = try access.get(.horse, id: id), !stored.isDeleted else { return nil }
            return try stored.record(as: LocalHorse.self)
        }
    }

    /// Lista koni jako strumień — emituje po każdej zmianie magazynu.
    public func observeHorses() -> AsyncThrowingStream<[LocalHorse], Error> {
        let store = self.store
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await rows in store.observe(.horse) {
                        continuation.yield(try rows.compactMap { try $0.record(as: LocalHorse.self) })
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Zapis

    /// Zapisuje konia (`id` = `nil` — nowy). Reguły: walidacja pól, unikalność, zmiana statusu; wynik niesie ostrzeżenia albo powód odmowy.
    @discardableResult
    public func save(_ draft: HorseDraft, id: String? = nil) async throws -> HorseRules.SaveOutcome {
        let dates = self.dates
        return try await store.write { access in
            let existing = try Self.horses(in: access)
            let old: LocalHorse?
            if let id {
                guard let found = existing.first(where: { $0.id == id }) else { throw StoreError.notFound(id) }
                old = found
            } else {
                old = nil
            }
            let outcome = HorseRules.prepareSave(
                draft, id: id ?? Self.newId(), old: old, existing: existing, today: dates.today(), now: dates.now()
            )
            if case let .saved(horse, _) = outcome {
                try access.upsert([try StoredRecord.of(horse, syncState: .local)])
            }
            return outcome
        }
    }

    // MARK: Zdjęcie konia (FR-ZDK)

    /// Ustawia zdjęcie: plik i miniatura trafiają do załączników konia (poprzednie zdjęcie zostaje w załącznikach), koń dostaje
    /// `photoAttachmentId`. Wszystko w jednej transakcji; plik jest usuwany, gdy zapis się nie uda.
    public func setPhoto(horseId: String, image: PreparedImage, fileName: String = "zdjecie.jpg") async throws {
        let attachmentId = Self.newId()
        let thumbnail = try ImagePreparer.thumbnail(image.jpeg)
        let original = try files.write(image.jpeg, attachmentId: attachmentId, kind: .original, pinned: true)
        let small = try files.write(thumbnail, attachmentId: attachmentId, kind: .thumbnail, pinned: true)
        let now = dates.now()
        do {
            try await store.write { access in
                guard let stored = try access.get(.horse, id: horseId), !stored.isDeleted, var horse = try stored.record(as: LocalHorse.self) else {
                    throw StoreError.notFound(horseId)
                }
                let attachment = LocalAttachment(
                    id: attachmentId, createdAt: now, updatedAt: now, version: 1, ownerType: .horse, ownerId: horseId, horseId: horseId,
                    fileName: fileName, contentType: "image/jpeg", sizeBytes: Int64(original.sizeBytes), sha256: original.sha256
                )
                horse.photoAttachmentId = attachmentId
                horse = horse.withAudit(version: horse.version + 1, updatedAt: now)
                try access.upsert([try StoredRecord.of(attachment, syncState: .local), try StoredRecord.of(horse, syncState: .local)])
                try access.upsertFile(original)
                try access.upsertFile(small)
            }
        } catch {
            files.delete(attachmentId: attachmentId)
            throw error
        }
    }

    /// „Wybierz z załączników konia”: zdjęciem może być tylko obraz z jego własnych załączników.
    public func choosePhoto(horseId: String, attachmentId: String) async throws {
        let now = dates.now()
        try await store.write { access in
            guard let stored = try access.get(.horse, id: horseId), !stored.isDeleted, var horse = try stored.record(as: LocalHorse.self) else {
                throw StoreError.notFound(horseId)
            }
            guard let attachmentRow = try access.get(.attachment, id: attachmentId), !attachmentRow.isDeleted,
                  let attachment = try attachmentRow.record(as: LocalAttachment.self),
                  attachment.horseId == horseId, attachment.contentType.lowercased().hasPrefix("image/") else {
                throw HorsePhotoError.notAnImageOfTheHorse
            }
            horse.photoAttachmentId = attachmentId
            horse = horse.withAudit(version: horse.version + 1, updatedAt: now)
            try access.upsert([try StoredRecord.of(horse, syncState: .local)])
        }
    }

    /// „Usuń zdjęcie”: tylko odpina — plik zostaje w załącznikach konia.
    public func clearPhoto(horseId: String) async throws {
        let now = dates.now()
        try await store.write { access in
            guard let stored = try access.get(.horse, id: horseId), !stored.isDeleted, var horse = try stored.record(as: LocalHorse.self) else {
                throw StoreError.notFound(horseId)
            }
            guard horse.photoAttachmentId != nil else { return }
            horse.photoAttachmentId = nil
            horse = horse.withAudit(version: horse.version + 1, updatedAt: now)
            try access.upsert([try StoredRecord.of(horse, syncState: .local)])
        }
    }

    /// Załączniki konia będące obrazami (do wyboru zdjęcia).
    public func imageAttachments(horseId: String) async throws -> [LocalAttachment] {
        try await store.read { access in
            try access.byOwner(.attachment, ownerId: horseId)
                .compactMap { try $0.record(as: LocalAttachment.self) }
                .filter { $0.contentType.lowercased().hasPrefix("image/") }
        }
    }

    /// Dane miniatury załącznika (lub `nil`, gdy pliku nie ma w telefonie).
    public func thumbnailData(attachmentId: String) async -> Data? {
        guard let info = try? await store.read({ access in try access.file(attachmentId: attachmentId, kind: .thumbnail) }) else { return nil }
        return files.read(info)
    }

    /// Dane oryginału załącznika (podgląd zdjęcia „Pokaż zdjęcie”).
    public func originalData(attachmentId: String) async -> Data? {
        guard let info = try? await store.read({ access in try access.file(attachmentId: attachmentId, kind: .original) }) else { return nil }
        return files.read(info)
    }

    // MARK: Pomocnicze

    private static func horses(in access: RecordAccess) throws -> [LocalHorse] {
        try access.query(.horse).compactMap { try $0.record(as: LocalHorse.self) }
    }

    private static func newId() -> String {
        UUID().uuidString.lowercased()
    }
}

public enum HorsePhotoError: Error, Equatable {
    case notAnImageOfTheHorse

    public var message: String { Messages.horsePhotoInvalid }
}
