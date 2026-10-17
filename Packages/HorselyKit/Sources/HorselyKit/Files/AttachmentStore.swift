import CryptoKit
import Foundation
import GRDB
import HorselyCore

/// Wpis albo koń, do którego należą załączniki; `horseId` — koń wpisu (opis operacji w kolejce, zakładka „Załączniki” konia).
public struct AttachmentOwner: Hashable, Sendable {
    public let type: AttachmentOwnerType
    public let id: String
    public let horseId: String?

    public init(type: AttachmentOwnerType, id: String, horseId: String?) {
        self.type = type
        self.id = id
        self.horseId = horseId
    }
}

/// Plik przygotowany do dodania: sprawdzony (`FilePolicy`), zdjęcie zmniejszone i bez lokalizacji (wg ustawień), skopiowany do
/// katalogu importu w kontenerze App Group.
public struct ImportedFile: Hashable, Sendable {
    public let url: URL
    public let fileName: String
    public let contentType: String
    public let sizeBytes: Int64
    public let sha256: String

    public init(url: URL, fileName: String, contentType: String, sizeBytes: Int64, sha256: String) {
        self.url = url
        self.fileName = fileName
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
    }
}

/// Plik wybrany przez użytkownika z opisem (≤ 500 znaków).
public struct PendingAttachment: Hashable, Sendable {
    public let file: ImportedFile
    public let description: String?

    public init(file: ImportedFile, description: String? = nil) {
        self.file = file
        self.description = description
    }
}

public enum AttachmentError: Error, Equatable, Sendable {
    /// Plik niedozwolony albo za duży (FR-M-ZAL-02) — komunikat dla użytkownika.
    case rejected(String)
    /// Plik nie jest dostępny ani w telefonie, ani w programie.
    case fileUnavailable
    /// Pobranie z programu nie powiodło się (brak połączenia).
    case downloadFailed
    case unreadable
}

/// Ustawienia plików (Ustawienia → Dane, data-model.md §5).
public struct AttachmentSettings: Sendable {
    public var sendOriginals: Bool
    public var keepPhotoLocation: Bool
    public var limitMB: Int
    public var downloadAll: Bool

    public init(sendOriginals: Bool = false, keepPhotoLocation: Bool = false, limitMB: Int = 200, downloadAll: Bool = false) {
        self.sendOriginals = sendOriginals
        self.keepPhotoLocation = keepPhotoLocation
        self.limitMB = limitMB
        self.downloadAll = downloadAll
    }

    public init(_ settings: SettingsStore) {
        self.init(
            sendOriginals: settings.sendOriginals, keepPhotoLocation: settings.keepPhotoLocation, limitMB: settings.attachmentLimitMB,
            downloadAll: settings.downloadAllAttachments
        )
    }
}

/// Załączniki (T114, FR-M-ZAL-*): przygotowanie plików, dodawanie (online — operacja `CreateAttachment` w kolejce, zależna od
/// niewysłanego wpisu, z rekordem `Pending`; samodzielny — rekord `Local` z plikiem przypiętym w magazynie), miniatury i pliki
/// z programu w pamięci z limitem LRU (domyślnie 200 MB, przypięte poza limitem), ostrzeżenie o małej ilości miejsca.
public final class AttachmentStore: Sendable {
    public static let lowStorageBytes: Int64 = 500 * 1024 * 1024
    public static let descriptionLimit = 500

    private let store: RecordStore
    private let files: LocalFileStore
    private let client: ApiClient?
    private let mode: @Sendable () -> WorkMode
    private let settings: @Sendable () -> AttachmentSettings
    private let dates: any DateProvider
    /// Katalog plików przygotowanych do dodania (kopie z galerii, aparatu, udostępniania).
    public let importDirectory: URL
    /// Katalog plików operacji `CreateAttachment` — nigdy nie czyszczony przez LRU, plik znika po wysłaniu.
    public let outboxDirectory: URL

    public init(
        store: RecordStore, files: LocalFileStore, client: ApiClient?, mode: @escaping @Sendable () -> WorkMode,
        settings: @escaping @Sendable () -> AttachmentSettings, dates: any DateProvider = SystemDateProvider()
    ) {
        self.store = store
        self.files = files
        self.client = client
        self.mode = mode
        self.settings = settings
        self.dates = dates
        let base = files.root.deletingLastPathComponent()
        importDirectory = base.appendingPathComponent("Import", isDirectory: true)
        outboxDirectory = base.appendingPathComponent("Outbox", isDirectory: true)
    }

    // MARK: Przygotowanie

    /// Plik z urządzenia (aplikacja Pliki, udostępnianie): sprawdzenie typu i rozmiaru, kopia strumieniowa, obróbka zdjęć.
    public func prepare(fileAt source: URL, fileName: String? = nil, mimeType: String? = nil) throws -> ImportedFile {
        let name = fileName ?? source.lastPathComponent
        let size = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let (safeName, contentType) = try Self.verdict(name, mimeType, size)
        let target = try newImportURL(safeName)
        try FileManager.default.copyItem(at: source, to: target)
        return try finish(target, fileName: safeName, contentType: contentType)
    }

    /// Zdjęcie z aparatu albo galerii (dane w pamięci).
    public func prepare(data: Data, fileName: String, mimeType: String?) throws -> ImportedFile {
        let (safeName, contentType) = try Self.verdict(fileName, mimeType, Int64(data.count))
        let target = try newImportURL(safeName)
        try data.write(to: target, options: .atomic)
        return try finish(target, fileName: safeName, contentType: contentType)
    }

    /// Usuwa przygotowany plik, którego użytkownik jednak nie dodał.
    public func discard(_ file: ImportedFile) {
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    static func verdict(_ name: String, _ mime: String?, _ size: Int64) throws -> (String, String) {
        switch FilePolicy.check(fileName: name, mimeType: mime, sizeBytes: size) {
        case let .allowed(fileName, contentType): return (fileName, contentType)
        case let .rejected(reason): throw AttachmentError.rejected(reason)
        }
    }

    private func newImportURL(_ fileName: String) throws -> URL {
        let folder = importDirectory.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    /// Zdjęcia: domyślnie zmniejszone do 2560 px (JPEG ~85 %) bez metadanych; „Wysyłaj oryginały” — bez zmian, ale bez GPS,
    /// chyba że włączono „Zachowuj lokalizację” (FR-M-ZAL-03).
    private func finish(_ url: URL, fileName: String, contentType: String) throws -> ImportedFile {
        var name = fileName
        var type = contentType
        if FilePolicy.isImage(contentType) {
            let options = settings()
            let data = try Data(contentsOf: url)
            if !options.sendOriginals {
                if let prepared = try? ImagePreparer.prepare(data) {
                    try prepared.jpeg.write(to: url, options: .atomic)
                    if contentType != "image/jpeg" {
                        name = (name as NSString).deletingPathExtension + ".jpg"
                        type = "image/jpeg"
                        let renamed = url.deletingLastPathComponent().appendingPathComponent(name)
                        try FileManager.default.moveItem(at: url, to: renamed)
                        return try Self.describe(renamed, fileName: name, contentType: type)
                    }
                }
            } else if !options.keepPhotoLocation, let cleaned = try? ImagePreparer.removingLocation(data), cleaned != data {
                try cleaned.write(to: url, options: .atomic)
            }
        }
        return try Self.describe(url, fileName: name, contentType: type)
    }

    static func describe(_ url: URL, fileName: String, contentType: String) throws -> ImportedFile {
        let (size, digest) = try FileDigest.sha256(of: url)
        guard size <= FilePolicy.maxBytes else { throw AttachmentError.rejected("Plik jest za duży (najwyżej 100 MB).") }
        return ImportedFile(url: url, fileName: fileName, contentType: contentType, sizeBytes: size, sha256: digest)
    }

    // MARK: Dodawanie

    /// Dodaje załączniki wpisu `owner`. Online: operacja `CreateAttachment` (zależna od niewysłanego wpisu) i rekord `Pending`;
    /// samodzielny: rekord `Local`, plik i miniatura przypięte w magazynie. Zwraca identyfikatory załączników.
    @discardableResult
    public func add(_ owner: AttachmentOwner, _ attachments: [PendingAttachment]) async throws -> [String] {
        var ids: [String] = []
        for pending in attachments {
            ids.append(mode() == .online ? try await addQueued(owner, pending) : try await addLocal(owner, pending))
        }
        return ids
    }

    private func record(_ id: String, _ owner: AttachmentOwner, _ pending: PendingAttachment, now: LocalDateTime) -> LocalAttachment {
        let text = pending.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalAttachment(
            id: id, createdAt: now, updatedAt: now, version: 1, ownerType: owner.type, ownerId: owner.id, horseId: owner.horseId,
            fileName: pending.file.fileName, contentType: pending.file.contentType, sizeBytes: pending.file.sizeBytes, sha256: pending.file.sha256,
            description: (text?.isEmpty ?? true) ? nil : String(text!.prefix(Self.descriptionLimit))
        )
    }

    private func addLocal(_ owner: AttachmentOwner, _ pending: PendingAttachment) async throws -> String {
        let id = UUID().uuidString.lowercased()
        // Najpierw plik, potem rekord: przerwanie zostawia najwyżej osierocony plik, a nie rekord bez pliku.
        let original = try files.move(pending.file.url, attachmentId: id, kind: .original, pinned: true)
        let thumbnail = FilePolicy.isImage(pending.file.contentType)
            ? (try? ImagePreparer.thumbnail(try Data(contentsOf: files.url(for: original)))).flatMap { try? files.write($0, attachmentId: id, kind: .thumbnail, pinned: true) }
            : nil
        let attachment = record(id, owner, pending, now: dates.now())
        do {
            try await store.write { access in
                try access.upsert([try StoredRecord.of(attachment, syncState: .local)])
                try access.upsertFile(original)
                if let thumbnail { try access.upsertFile(thumbnail) }
            }
        } catch {
            files.delete(attachmentId: id)
            throw error
        }
        try? FileManager.default.removeItem(at: pending.file.url.deletingLastPathComponent())
        return id
    }

    private func addQueued(_ owner: AttachmentOwner, _ pending: PendingAttachment) async throws -> String {
        let id = UUID().uuidString.lowercased()
        let operationId = UUID().uuidString.lowercased()
        let folder = outboxDirectory.appendingPathComponent(operationId, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(pending.file.fileName)
        try FileManager.default.moveItem(at: pending.file.url, to: target)
        try? FileManager.default.removeItem(at: pending.file.url.deletingLastPathComponent())
        let thumbnail = FilePolicy.isImage(pending.file.contentType)
            ? (try? ImagePreparer.thumbnail(try Data(contentsOf: target))).flatMap { try? files.write($0, attachmentId: id, kind: .thumbnail, pinned: true) }
            : nil
        let attachment = record(id, owner, pending, now: dates.now())
        let moment = Date()
        let file = OutboxFile(
            operationId: operationId, path: target.path, fileName: pending.file.fileName, contentType: pending.file.contentType,
            sizeBytes: pending.file.sizeBytes, sha256: pending.file.sha256, description: attachment.description
        )
        do {
            try await store.write { access in
                // Wpis, który sam jeszcze czeka na wysłanie — załącznik wyjdzie dopiero po nim.
                let dependsOn = try access.operations()
                    .filter { $0.kind.isCreate && $0.state.isUnsent && ($0.recordId == owner.id || $0.localRef == owner.id) }
                    .map(\.id)
                let horse = try owner.horseId.flatMap { try access.get(.horse, id: $0)?.record(as: LocalHorse.self) }
                let operation = OutboxOperation(
                    id: operationId, kind: .createAttachment, localRef: id,
                    payload: .object(["ownerType": .string(owner.type.rawValue), "ownerId": .string(owner.id)]), dependsOn: dependsOn,
                    horseRefs: horse.map { [HorseRef($0)] } ?? [], summary: "\(OperationKind.createAttachment.label) · \(horse?.name ?? "stajnia")",
                    createdAt: moment, updatedAt: moment, recordType: .attachment, recordId: id
                )
                try access.upsert([try StoredRecord.of(attachment, syncState: .pending)])
                try access.enqueue(operation, file: file)
                if let thumbnail { try access.upsertFile(thumbnail) }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            files.delete(attachmentId: id)
            throw error
        }
        return id
    }

    // MARK: Lista

    /// Załączniki wpisu (bez kosza) od najstarszego.
    public func attachments(ownerId: String) async throws -> [LocalAttachment] {
        try await store.read { access in
            try access.byOwner(.attachment, ownerId: ownerId).compactMap { try $0.record(as: LocalAttachment.self) }
                .sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : Self.byName($0, $1) }
        }
    }

    /// Wszystkie załączniki konia — jego własne i wpisów (zakładka „Załączniki” karty konia), od najnowszego.
    public func attachments(horseId: String) async throws -> [LocalAttachment] {
        try await store.read { access in
            try access.query(.attachment, horseId: horseId).compactMap { try $0.record(as: LocalAttachment.self) }
                .sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : Self.byName($0, $1) }
        }
    }

    /// Ten sam czas dodania (kilka plików naraz) — alfabetycznie po nazwie, potem po `id`.
    static func byName(_ lhs: LocalAttachment, _ rhs: LocalAttachment) -> Bool {
        lhs.fileName != rhs.fileName ? PolishNames.isOrdered(lhs.fileName, before: rhs.fileName) : lhs.id < rhs.id
    }

    // MARK: Pliki

    /// Miniatura z pamięci albo z programu (tylko obrazy); `nil`, gdy jej nie ma.
    public func thumbnail(_ attachment: LocalAttachment) async -> Data? {
        if let data = await localThumbnail(attachment.id) { return data }
        guard FilePolicy.isImage(attachment.contentType) else { return nil }
        if case let .image(data) = await thumbnail(attachmentId: attachment.id) { return data }
        return nil
    }

    /// Miniatura załącznika-obrazu po identyfikatorze (zdjęcie konia, FR-006…FR-011), w kolejności: plik miniatury →
    /// miniatura z lokalnego oryginału (zapis przypięty) → w trybie online `GET attachments/{id}/thumbnail` (zapis przypięty).
    /// Odpowiedź `404` to `.unavailable` (zdjęcia już nie ma w programie); brak źródła albo sieci to `.failed` — do ponowienia.
    public func thumbnail(attachmentId id: String) async -> ThumbnailResult {
        if let data = await localThumbnail(id) { return .image(data) }
        if let info = try? await store.read({ try $0.file(attachmentId: id, kind: .original) }), let original = files.read(info) {
            guard let small = try? ImagePreparer.thumbnail(original) else { return .unavailable }
            if let saved = try? files.write(small, attachmentId: id, kind: .thumbnail, pinned: true) {
                try? await store.write { try $0.upsertFile(saved) }
            }
            return .image(small)
        }
        guard mode() == .online, let client else { return .failed }
        switch await client.execute(ApiRequest(.get, "attachments/\(id)/thumbnail", forFile: true)) {
        case let .success(response):
            guard !response.body.isEmpty else { return .failed }
            if let saved = try? files.write(response.body, attachmentId: id, kind: .thumbnail, pinned: true) {
                try? await store.write { try $0.upsertFile(saved) }
            }
            return .image(response.body)
        case .failure(.notFound):
            return .unavailable
        case .failure:
            return .failed
        }
    }

    private func localThumbnail(_ id: String) async -> Data? {
        guard let info = try? await store.read({ try $0.file(attachmentId: id, kind: .thumbnail) }) else { return nil }
        return files.read(info)
    }

    /// Cały plik załącznika po identyfikatorze (podgląd „Pokaż zdjęcie” konia): jak `content(_:)`, rekord czytany z magazynu.
    public func content(attachmentId id: String) async throws -> URL {
        guard let attachment = try await store.read({ try $0.get(.attachment, id: id)?.record(as: LocalAttachment.self) }) else {
            throw AttachmentError.fileUnavailable
        }
        return try await content(attachment)
    }

    /// Cały plik: z pamięci (zapamiętuje otwarcie), z kolejki (jeszcze niewysłany) albo z programu (do pamięci LRU, przypięty przy
    /// „Pobieraj wszystkie załączniki” i w trybie samodzielnym).
    public func content(_ attachment: LocalAttachment) async throws -> URL {
        let id = attachment.id
        let opened = dates.now()
        if let info = try await store.write({ access -> LocalFileInfo? in
            guard let info = try access.file(attachmentId: id, kind: .original) else { return nil }
            try access.touchFile(attachmentId: id, kind: .original, at: opened)
            return info
        }), FileManager.default.fileExists(atPath: files.url(for: info).path) {
            return files.url(for: info)
        }
        if let queued = try await store.read({ access in
            try access.operations().first { $0.kind == .createAttachment && $0.recordId == id && $0.state.isUnsent }.flatMap { try access.outboxFile($0.id) }
        }), FileManager.default.fileExists(atPath: queued.path) {
            return URL(fileURLWithPath: queued.path)
        }
        guard mode() == .online, let client else { throw AttachmentError.fileUnavailable }
        switch await client.execute(ApiRequest(.get, "attachments/\(id)/content", forFile: true, downloadToFile: true)) {
        case let .success(response):
            let pinned = settings().downloadAll
            let info: LocalFileInfo
            if let downloaded = response.file {
                info = try files.move(downloaded, attachmentId: id, kind: .original, fileExtension: FilePolicy.fileExtension(attachment.fileName), pinned: pinned)
            } else {
                info = try files.write(response.body, attachmentId: id, kind: .original, fileExtension: FilePolicy.fileExtension(attachment.fileName), pinned: pinned)
            }
            var touched = info
            touched.lastOpenedAt = opened
            let row = touched
            try await store.write { try $0.upsertFile(row) }
            await evict()
            return files.url(for: info)
        case .failure(.notFound):
            throw AttachmentError.fileUnavailable
        case .failure:
            throw AttachmentError.downloadFailed
        }
    }

    /// Limit miejsca (LRU): nieprzypięte pliki od najdawniej otwieranych, aż suma zmieści się w limicie z ustawień.
    public func evict() async {
        let limit = Int64(max(settings().limitMB, 0)) * 1024 * 1024
        guard let removed = try? await store.write({ access in try access.evictFiles(over: limit) }) else { return }
        for info in removed { try? FileManager.default.removeItem(at: files.url(for: info)) }
    }

    /// Mniej niż 500 MB wolnego miejsca w telefonie (ostrzeżenie `attachments_low_storage`).
    public func isLowOnStorage() -> Bool {
        let values = try? files.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return false }
        return available < Self.lowStorageBytes
    }

    // MARK: Usuwanie

    /// Czy załącznik czeka jeszcze w kolejce (niewysłany) — wtedy „Usuń” tylko wycofuje go z kolejki.
    public func isQueued(_ attachmentId: String) async -> Bool {
        (try? await store.read { access in
            try access.operations().contains { $0.kind == .createAttachment && $0.recordId == attachmentId && $0.state == .pending }
        }) ?? false
    }

    /// Wycofuje niewysłany załącznik: operacja, rekord `Pending` i pliki znikają. `false` — wysyłka już się zaczęła.
    @discardableResult
    public func withdraw(_ attachmentId: String) async throws -> Bool {
        let released = try await store.write { access -> [OutboxFile]? in
            guard let operation = try access.operations().first(where: { $0.kind == .createAttachment && $0.recordId == attachmentId && $0.state.isUnsent }) else {
                return []
            }
            guard operation.state == .pending else { return nil }
            let files = try access.deleteOperation(operation.id, allowed: [.pending]).files
            try access.deleteHard(.attachment, id: attachmentId)
            try access.deleteFiles(attachmentId: attachmentId)
            return files
        }
        guard let released else { return false }
        for file in released { try? FileManager.default.removeItem(at: URL(fileURLWithPath: file.path).deletingLastPathComponent()) }
        files.delete(attachmentId: attachmentId)
        return true
    }
}

// MARK: Magazyn plików

extension LocalFileStore {
    /// Przenosi gotowy plik (pobrany, przygotowany) do magazynu i liczy jego skrót strumieniowo.
    public func move(_ source: URL, attachmentId: String, kind: FileKind, fileExtension: String? = nil, pinned: Bool) throws -> LocalFileInfo {
        let suffix = fileExtension.flatMap { $0.isEmpty ? nil : $0 } ?? (source.pathExtension.isEmpty ? "bin" : source.pathExtension.lowercased())
        let relative = "\(attachmentId)/\(kind == .original ? "original" : "thumbnail").\(suffix)"
        let target = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: source, to: target)
        let (size, digest) = try FileDigest.sha256(of: target)
        return LocalFileInfo(attachmentId: attachmentId, kind: kind, relativePath: relative, sizeBytes: Int(size), sha256: digest, pinned: pinned)
    }
}

extension RecordAccess {
    public func touchFile(attachmentId: String, kind: FileKind, at moment: LocalDateTime) throws {
        try db.execute(sql: "UPDATE local_file SET lastOpenedAt = ? WHERE attachmentId = ? AND kind = ?", arguments: [moment.description, attachmentId, kind.rawValue])
    }

    /// Pliki nieprzypięte do usunięcia, by suma nieprzypiętych zmieściła się w `limit` (od najdawniej otwieranych); usuwa ich wiersze.
    func evictFiles(over limit: Int64) throws -> [LocalFileInfo] {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM local_file WHERE pinned = 0 ORDER BY lastOpenedAt IS NOT NULL, lastOpenedAt")
        var total = rows.reduce(Int64(0)) { $0 + Int64($1["sizeBytes"] as Int) }
        var removed: [LocalFileInfo] = []
        for row in rows where total > limit {
            let attachmentId: String = row["attachmentId"]
            let rawKind: String = row["kind"]
            guard let kind = FileKind(rawValue: rawKind), let info = try file(attachmentId: attachmentId, kind: kind) else { continue }
            try db.execute(sql: "DELETE FROM local_file WHERE attachmentId = ? AND kind = ?", arguments: [attachmentId, rawKind])
            total -= Int64(info.sizeBytes)
            removed.append(info)
        }
        return removed
    }

    /// Po wysłaniu załącznika z `id` nadanym w programie pliki w telefonie należą do nowego `id` (ścieżka na dysku bez zmian).
    func remapFiles(from oldId: String, to newId: String) throws {
        try db.execute(sql: "UPDATE OR REPLACE local_file SET attachmentId = ? WHERE attachmentId = ?", arguments: [newId, oldId])
    }
}

/// Skrót SHA-256 i rozmiar pliku liczone strumieniowo (pliki do 100 MB bez wczytywania w całości).
public enum FileDigest {
    public static func sha256(of url: URL) throws -> (size: Int64, hex: String) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            size += Int64(chunk.count)
        }
        return (size, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
