import CryptoKit
import Foundation
import GRDB
import HorselyCore
import Synchronization

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
    /// Chwila i miejsce wykonania odczytane z pliku z galerii PRZED jego przygotowaniem (zmniejszenie zdjęcia usuwa EXIF).
    public let metadata: MediaMetadata

    public init(url: URL, fileName: String, contentType: String, sizeBytes: Int64, sha256: String, metadata: MediaMetadata = .none) {
        self.url = url
        self.fileName = fileName
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.metadata = metadata
    }
}

/// Plik wybrany przez użytkownika z opisem (≤ 500 znaków). Od 3.0 także chwila i miejsce wykonania (`capturedAt`, `latitude`,
/// `longitude` — WGS84) oraz miniatura filmu JPEG ≤ 1 MB (`thumbnail`; plik przechodzi na własność operacji albo rekordu).
/// Czas domyślnie pochodzi z metadanych pliku z galerii (`ImportedFile.metadata`); współrzędne NIE są domyślane — dostaje je tylko
/// załącznik treningu (`forOwner`: konstytucja II, lokalizacja dotyczy wyłącznie jazdy), a nagranie jazdy podaje własne jawnie.
public struct PendingAttachment: Hashable, Sendable {
    public let file: ImportedFile
    public let description: String?
    public let capturedAt: Date?
    public let latitude: Decimal?
    public let longitude: Decimal?
    public let thumbnail: URL?
    /// „Wyślij oryginał” (tylko film poniżej 100 MB): bez zmniejszania do 720p (decyzja A10, `VideoPolicy.canSendOriginal`).
    public let sendOriginal: Bool

    public init(
        file: ImportedFile, description: String? = nil, capturedAt: Date? = nil, latitude: Decimal? = nil, longitude: Decimal? = nil, thumbnail: URL? = nil,
        sendOriginal: Bool = false
    ) {
        self.sendOriginal = sendOriginal
        self.file = file
        self.description = description
        self.capturedAt = capturedAt ?? file.metadata.capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.thumbnail = thumbnail
    }

    /// Załącznik gotowy dla właściciela `type`: współrzędne (konstytucja 3.0.0, zasada II; ZAT-05 dotyczy tylko pinezki trasy treningu)
    /// zostają wyłącznie przy załączniku treningu — jawne z nagrania jazdy albo, gdy ich brak, położenie z metadanych pliku z galerii
    /// (zdjęcia: tylko gdy przy imporcie zostało zachowane zgodnie z „Zachowuj lokalizację”). Dla pozostałych właścicieli zawsze `nil`;
    /// czas wykonania zostaje wszędzie.
    func forOwner(_ type: AttachmentOwnerType) -> PendingAttachment {
        let place: (latitude: Decimal?, longitude: Decimal?)
        if type != .training {
            place = (nil, nil)
        } else if latitude != nil || longitude != nil {
            place = (latitude, longitude)
        } else {
            place = (Self.decimal(file.metadata.latitude), Self.decimal(file.metadata.longitude))
        }
        guard place.latitude != latitude || place.longitude != longitude else { return self }
        return PendingAttachment(
            file: file, description: description, capturedAt: capturedAt, latitude: place.latitude, longitude: place.longitude, thumbnail: thumbnail,
            sendOriginal: sendOriginal
        )
    }

    /// Najkrótszy zapis dziesiętny (`52.2297`, nie `52.22970000000001`), żeby zaokrąglenie do 7 miejsc było dokładne.
    private static func decimal(_ value: Double?) -> Decimal? {
        guard let value, value.isFinite else { return nil }
        return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
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
    /// Przygotowanie filmów (zmniejszenie do 720p, miniatura — decyzja A10); `nil` — film idzie jak każdy plik.
    private let videos: VideoPreparation?
    /// Postęp przygotowania filmu z kolejki według `id` załącznika (0–100; `nil` — koniec), do napisu „Przygotowuję film… 45%”.
    private let videoProgress: @Sendable (String, Int?) -> Void
    /// Operacje, których film właśnie jest przygotowywany — drugie wywołanie (start, zadanie w tle, dodanie) go nie zdubluje.
    private let preparingNow = Mutex<Set<String>>([])
    /// Katalog plików przygotowanych do dodania (kopie z galerii, aparatu, udostępniania).
    public let importDirectory: URL
    /// Katalog plików operacji `CreateAttachment` — nigdy nie czyszczony przez LRU, plik znika po wysłaniu.
    public let outboxDirectory: URL

    public init(
        store: RecordStore, files: LocalFileStore, client: ApiClient?, mode: @escaping @Sendable () -> WorkMode,
        settings: @escaping @Sendable () -> AttachmentSettings, dates: any DateProvider = SystemDateProvider(), videos: VideoPreparation? = nil,
        videoProgress: @escaping @Sendable (String, Int?) -> Void = { _, _ in }
    ) {
        self.videos = videos
        self.videoProgress = videoProgress
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

    /// Plik z urządzenia (aplikacja Pliki, udostępnianie): sprawdzenie typu i rozmiaru, kopia strumieniowa, odczyt metadanych (czas,
    /// miejsce) z kopii, obróbka zdjęć.
    public func prepare(fileAt source: URL, fileName: String? = nil, mimeType: String? = nil) async throws -> ImportedFile {
        let name = fileName ?? source.lastPathComponent
        let size = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let (safeName, contentType) = try Self.verdict(name, mimeType, size)
        let target = try newImportURL(safeName)
        try FileManager.default.copyItem(at: source, to: target)
        return try await finish(target, fileName: safeName, contentType: contentType)
    }

    /// Zdjęcie z aparatu albo galerii (dane w pamięci).
    public func prepare(data: Data, fileName: String, mimeType: String?) async throws -> ImportedFile {
        let (safeName, contentType) = try Self.verdict(fileName, mimeType, Int64(data.count))
        let target = try newImportURL(safeName)
        try data.write(to: target, options: .atomic)
        return try await finish(target, fileName: safeName, contentType: contentType)
    }

    /// Usuwa przygotowany plik, którego użytkownik jednak nie dodał.
    public func discard(_ file: ImportedFile) {
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    static func verdict(_ name: String, _ mime: String?, _ size: Int64) throws -> (String, String) {
        // Film > 100 MB jest przyjmowany: przed wysłaniem zostanie zmniejszony do 720p, a limit sprawdzi wynik (decyzja A10).
        switch FilePolicy.checkImport(fileName: name, mimeType: mime, sizeBytes: size) {
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
    private func finish(_ url: URL, fileName: String, contentType: String) async throws -> ImportedFile {
        // Metadane z surowej kopii: zdjęcie po zmniejszeniu nie ma już EXIF, film po przekodowaniu — metadanych kontenera.
        let read = await MediaMetadataReader.read(file: url, contentType: contentType)
        let metadata = locationAllowed(read, contentType)
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
                        return try Self.describe(renamed, fileName: name, contentType: type, metadata: metadata)
                    }
                }
            } else if !options.keepPhotoLocation, let cleaned = try? ImagePreparer.removingLocation(data), cleaned != data {
                try cleaned.write(to: url, options: .atomic)
            }
        }
        return try Self.describe(url, fileName: name, contentType: type, metadata: metadata)
    }

    /// Ustawienie „Zachowuj lokalizację” obejmuje też współrzędne zapisywane jako pola załącznika: bez niego zdjęcie nie niesie położenia
    /// (zostaje czas). Film nie ma tego ustawienia — o współrzędnych decyduje właściciel załącznika (`PendingAttachment.forOwner`).
    private func locationAllowed(_ metadata: MediaMetadata, _ contentType: String) -> MediaMetadata {
        FilePolicy.isImage(contentType) && !settings().keepPhotoLocation ? metadata.withoutLocation : metadata
    }

    static func describe(_ url: URL, fileName: String, contentType: String, metadata: MediaMetadata = .none) throws -> ImportedFile {
        let (size, digest) = try FileDigest.sha256(of: url)
        guard size <= FilePolicy.maxBytes || FilePolicy.isVideo(contentType) else { throw AttachmentError.rejected("Plik jest za duży (najwyżej 100 MB).") }
        return ImportedFile(url: url, fileName: fileName, contentType: contentType, sizeBytes: size, sha256: digest, metadata: metadata)
    }

    // MARK: Dodawanie

    /// Dodaje załączniki wpisu `owner`. Online: operacja `CreateAttachment` (zależna od niewysłanego wpisu) i rekord `Pending`;
    /// samodzielny: rekord `Local`, plik i miniatura przypięte w magazynie. Zwraca identyfikatory załączników.
    ///
    /// Film (decyzja A10): online, gdy trzeba go zmniejszyć do 720p, operacja czeka w stanie `held` z plikiem źródłowym
    /// (`needsPreparation`) — przygotowanie robi `resumePreparation()`; samodzielnie film jest zmniejszany przed zapisem pliku,
    /// a `progress` dostaje postęp (0–100).
    @discardableResult
    public func add(_ owner: AttachmentOwner, _ attachments: [PendingAttachment], progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> [String] {
        var ids: [String] = []
        for pending in attachments.map({ $0.forOwner(owner.type) }) {
            ids.append(mode() == .online ? try await addQueued(owner, pending) : try await addLocal(owner, pending, progress: progress))
        }
        return ids
    }

    /// Czy dodanie zostawiło filmy do przygotowania w kolejce (wtedy aplikacja planuje zadanie w tle „przygotowanie filmów”).
    public func hasPreparingVideos() async -> Bool {
        ((try? await store.read { try $0.preparingOperationIds() }) ?? []).isEmpty == false
    }

    private func record(_ id: String, _ owner: AttachmentOwner, _ pending: PendingAttachment, now: LocalDateTime) -> LocalAttachment {
        let text = pending.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = Self.place(latitude: pending.latitude, longitude: pending.longitude)
        return LocalAttachment(
            id: id, createdAt: now, updatedAt: now, version: 1, ownerType: owner.type, ownerId: owner.id, horseId: owner.horseId,
            fileName: pending.file.fileName, contentType: pending.file.contentType, sizeBytes: pending.file.sizeBytes, sha256: pending.file.sha256,
            description: (text?.isEmpty ?? true) ? nil : String(text!.prefix(Self.descriptionLimit)),
            // Metadane jak w programie 3.0: chwila wykonania i współrzędne z 7 miejscami po przecinku (HALF_UP).
            capturedAt: pending.capturedAt, latitude: place.latitude, longitude: place.longitude
        )
    }

    /// Miejsce wykonania pliku: współrzędne z 7 miejscami po przecinku (HALF_UP) w zakresie WGS84 (szerokość -90…90, długość -180…180).
    /// Wartość spoza zakresu (albo `NaN`) odrzuca całe miejsce — jak `MediaMetadataReader` Androida, który traktuje taką parę jako „brak
    /// położenia”; plik jest dodawany bez miejsca. Rekord spoza zakresu psułby kopię i eksport (schemat 1.6 ma `minimum`/`maximum`).
    static func place(latitude: Decimal?, longitude: Decimal?) -> (latitude: Decimal?, longitude: Decimal?) {
        func rounded(_ value: Decimal?, limit: Decimal) -> (value: Decimal?, valid: Bool) {
            guard let value else { return (nil, true) }
            guard !value.isNaN else { return (nil, false) }
            let result = DecimalText.coordinate(value)
            return (result, result >= -limit && result <= limit)
        }
        let lat = rounded(latitude, limit: 90)
        let lon = rounded(longitude, limit: 180)
        return lat.valid && lon.valid ? (lat.value, lon.value) : (nil, nil)
    }

    /// Miniatura filmu (JPEG ≤ 1 MB) w magazynie plików, przypięta; `nil`, gdy jej nie ma albo jest za duża.
    private func storeVideoThumbnail(_ source: URL?, attachmentId: String) -> LocalFileInfo? {
        guard let source, let data = FileManager.default.contents(atPath: source.path), !data.isEmpty, Int64(data.count) <= OutboxFile.maxThumbnailBytes else {
            return nil
        }
        return try? files.write(data, attachmentId: attachmentId, kind: .thumbnail, pinned: true)
    }

    /// Tryb samodzielny: film przechodzi to samo przygotowanie co w kolejce, ale przed zapisem pliku. Nic nie jest tu wysyłane, więc limit
    /// 100 MB nie obowiązuje — film, którego nie udało się zmniejszyć, zapisuje się w oryginale (`lenient`).
    private func preparedLocally(_ pending: PendingAttachment, progress: @escaping @Sendable (Int) -> Void) async throws -> PendingAttachment {
        guard let videos, FilePolicy.isVideo(pending.file.contentType) else { return pending }
        let result = try await videos.prepare(
            source: pending.file.url, fileName: pending.file.fileName, contentType: pending.file.contentType, sendOriginal: pending.sendOriginal,
            existingThumbnail: pending.thumbnail, lenient: true, progress: progress
        )
        guard case let .ready(ready) = result else { return pending }
        // Źródło zastąpione wersją 720p leży w tym samym katalogu importu i znika razem z nim po zapisie rekordu.
        return PendingAttachment(
            file: ImportedFile(
                url: ready.file, fileName: ready.fileName, contentType: ready.contentType, sizeBytes: ready.sizeBytes, sha256: ready.sha256,
                metadata: pending.file.metadata
            ),
            description: pending.description, capturedAt: pending.capturedAt, latitude: pending.latitude, longitude: pending.longitude,
            thumbnail: ready.thumbnail, sendOriginal: pending.sendOriginal
        )
    }

    private func addLocal(_ owner: AttachmentOwner, _ picked: PendingAttachment, progress: @escaping @Sendable (Int) -> Void) async throws -> String {
        let pending = try await preparedLocally(picked, progress: progress)
        let id = UUID().uuidString.lowercased()
        // Najpierw plik, potem rekord: przerwanie zostawia najwyżej osierocony plik, a nie rekord bez pliku.
        let original = try files.move(pending.file.url, attachmentId: id, kind: .original, pinned: true)
        // Film z jazdy: miniaturę (JPEG ≤ 1 MB) przygotował telefon przy nagrywaniu — zapisujemy ją jak miniaturę zdjęcia.
        let thumbnail = FilePolicy.isImage(pending.file.contentType)
            ? (try? ImagePreparer.thumbnail(try Data(contentsOf: files.url(for: original)))).flatMap { try? files.write($0, attachmentId: id, kind: .thumbnail, pinned: true) }
            : storeVideoThumbnail(pending.thumbnail, attachmentId: id)
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
        if let source = pending.thumbnail { try? FileManager.default.removeItem(at: source) }
        if let source = picked.thumbnail { try? FileManager.default.removeItem(at: source) }
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
        // Miniatura filmu to druga kopia w katalogu operacji — znika razem z plikiem.
        var thumbnailPath: String?
        let thumbnailCopy = folder.appendingPathComponent("thumbnail.jpg")
        if let source = pending.thumbnail {
            try? FileManager.default.removeItem(at: thumbnailCopy)
            if (try? FileManager.default.moveItem(at: source, to: thumbnailCopy)) != nil { thumbnailPath = thumbnailCopy.path }
        }
        // Film (A10): do zmniejszenia — operacja `held` z plikiem źródłowym do końca przygotowania; bez zmniejszania — tylko miniatura.
        var held = false
        if let videos, FilePolicy.isVideo(pending.file.contentType) {
            if await videos.needsTranscoding(target, sendOriginal: pending.sendOriginal) {
                held = true
            } else if thumbnailPath == nil, let jpeg = await videos.thumbnail(of: target), (try? jpeg.write(to: thumbnailCopy, options: .atomic)) != nil {
                thumbnailPath = thumbnailCopy.path
            }
        }
        let thumbnail = FilePolicy.isImage(pending.file.contentType)
            ? (try? ImagePreparer.thumbnail(try Data(contentsOf: target))).flatMap { try? files.write($0, attachmentId: id, kind: .thumbnail, pinned: true) }
            : nil
        let attachment = record(id, owner, pending, now: dates.now())
        let moment = Date()
        let initialState: OutboxState = held ? .held : .pending
        let file = OutboxFile(
            operationId: operationId, path: target.path, fileName: pending.file.fileName, contentType: pending.file.contentType,
            sizeBytes: pending.file.sizeBytes, sha256: pending.file.sha256, description: attachment.description,
            capturedAt: attachment.capturedAt, latitude: attachment.latitude, longitude: attachment.longitude, thumbnailPath: thumbnailPath,
            needsPreparation: held
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
                    state: initialState, createdAt: moment, updatedAt: moment, recordType: .attachment, recordId: id
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

    // MARK: Przygotowanie filmów (decyzja A10)

    static let missingVideo = "Brak pliku filmu na telefonie."
    static let preparationFailed = "Nie udało się przygotować filmu. Spróbuj ponownie albo wybierz inny film."

    /// Przygotowuje każdy film, który stoi w kolejce w stanie `held` z `needsPreparation` (w kolejności kolejki) — po dodaniu, przy starcie
    /// aplikacji i w zadaniu w tle `pl.glapa.horsely.video`. Przerwane przygotowanie (zabity proces, koniec czasu zadania) zostawia operację
    /// `held` z plikiem źródłowym, więc następne wywołanie zaczyna je od nowa. Zwraca liczbę operacji zwolnionych do wysyłki (`pending`).
    @discardableResult
    public func resumePreparation() async -> Int {
        guard videos != nil else { return 0 }
        let ids = (try? await store.read { access -> [String] in
            let preparing = try access.preparingOperationIds()
            return try access.operations().map(\.id).filter { preparing.contains($0) }
        }) ?? []
        var released = 0
        for id in ids {
            if Task.isCancelled { break }
            if await prepareHeldVideo(id) { released += 1 }
        }
        return released
    }

    /// Przygotowanie filmu jednej operacji (`VideoPrepareJob` Androida): po zmniejszeniu do 720p i miniaturze plik jest podmieniany,
    /// a operacja wraca do kolejki jako `pending` (jedna transakcja). Film, którego nie da się przygotować, kończy jako `needsFix`
    /// z komunikatem, a jego pliki są usuwane, więc „Wyślij ponownie” nie wypuści nieprzygotowanego filmu. `true` — operacja zwolniona.
    func prepareHeldVideo(_ operationId: String) async -> Bool {
        guard let videos else { return false }
        guard preparingNow.withLock({ $0.insert(operationId).inserted }) else { return false }
        defer { _ = preparingNow.withLock { $0.remove(operationId) } }
        let found = try? await store.read { access -> HeldVideo? in
            guard let operation = try access.operation(operationId), operation.state == .held,
                  let file = try access.outboxFile(operationId), file.needsPreparation else { return nil }
            return HeldVideo(file: file, attachmentId: operation.recordId ?? operation.localRef)
        }
        guard let held = found else { return false }
        let file = held.file
        let attachmentId = held.attachmentId
        let source = URL(fileURLWithPath: file.path)
        guard FileManager.default.fileExists(atPath: source.path) else {
            await rejectPreparation(operationId, file, Self.missingVideo)
            return false
        }
        let progress = videoProgress
        progress(attachmentId, 0)
        defer { progress(attachmentId, nil) }
        do {
            let result = try await videos.prepare(
                source: source, fileName: file.fileName, contentType: file.contentType, sendOriginal: false,
                existingThumbnail: file.thumbnailPath.map { URL(fileURLWithPath: $0) }
            ) { progress(attachmentId, $0) }
            switch result {
            case let .rejected(message):
                try? FileManager.default.removeItem(at: source)
                await rejectPreparation(operationId, file, message)
                return false
            case let .ready(ready):
                let prepared = OutboxFile(
                    operationId: operationId, path: ready.file.path, fileName: ready.fileName, contentType: ready.contentType, sizeBytes: ready.sizeBytes,
                    sha256: ready.sha256, description: file.description, capturedAt: file.capturedAt, latitude: file.latitude, longitude: file.longitude,
                    thumbnailPath: ready.thumbnail?.path, needsPreparation: false
                )
                let now = Date()
                let stored = (try? await store.write { access -> Bool in
                    guard try access.replaceFile(operationId, expected: [.held], with: prepared) else { return false }
                    try access.updateOperation(operationId, expected: [.held]) { current in
                        var next = current
                        next.state = .pending
                        next.updatedAt = now
                        return next
                    }
                    return true
                }) ?? false
                if !stored {
                    // Operację usunięto (albo zmieniono) w trakcie kodowania — wyniku nikt już nie potrzebuje.
                    prepared.deleteFiles()
                    if let replaced = ready.replacedSource { try? FileManager.default.removeItem(at: replaced) }
                    return false
                }
                // Źródło znika dopiero po utrwaleniu wyniku: przerwanie wcześniej zostawia operację ze źródłem, które istnieje.
                if let replaced = ready.replacedSource { try? FileManager.default.removeItem(at: replaced) }
                return true
            }
        } catch is CancellationError {
            // Przerwane: operacja zostaje `held` ze źródłem — wznowi ją następne `resumePreparation()`.
            return false
        } catch where VideoPreparation.isInterruption(error) || Task.isCancelled {
            // Przerwanie zgłoszone inaczej niż `CancellationError` (np. `AVError.operationInterrupted`) — też zostaje `held`.
            return false
        } catch {
            // Nieoczekiwany błąd (zapis miniatury, brak miejsca): operacja nie może zostać w `held` z napisem „Przygotowuję film…”.
            let stem = source.deletingPathExtension().lastPathComponent
            for name in ["\(stem)-720p.mp4", "\(stem)-720p-miniatura.jpg", "\(stem)-miniatura.jpg"] {
                try? FileManager.default.removeItem(at: source.deletingLastPathComponent().appendingPathComponent(name))
            }
            try? FileManager.default.removeItem(at: source)
            await rejectPreparation(operationId, file, Self.preparationFailed)
            return false
        }
    }

    private struct HeldVideo: Sendable {
        let file: OutboxFile
        let attachmentId: String
    }

    private func rejectPreparation(_ operationId: String, _ file: OutboxFile, _ message: String) async {
        if let path = file.thumbnailPath { try? FileManager.default.removeItem(atPath: path) }
        let now = Date()
        _ = try? await store.write { access in
            try access.updateOperation(operationId, expected: [.held]) { current in
                var next = current
                next.state = .needsFix
                next.problem = ApiProblem(title: message)
                next.updatedAt = now
                return next
            }
        }
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

    /// Miniatura kafla: z pamięci telefonu, dla filmu w kolejce — z pliku operacji (pierwsza klatka zrobiona przy przygotowaniu),
    /// inaczej z programu, ale tylko tam, gdzie może ona być (`mayHaveRemoteThumbnail`); `nil`, gdy jej nie ma.
    public func thumbnail(_ attachment: LocalAttachment) async -> Data? {
        if let data = await localThumbnail(attachment.id) { return data }
        if FilePolicy.isVideo(attachment.contentType) {
            if let data = await queuedThumbnail(attachment.id) { return data }
            guard Self.mayHaveRemoteThumbnail(contentType: attachment.contentType, online: mode() == .online) else { return nil }
            // Film z programu: miniatura nie jest przypięta (jak `download(pinned = false)` Androida), 404 — zostaje ikona.
            if case let .image(data) = await programThumbnail(attachment.id, pinned: false) { return data }
            return nil
        }
        guard FilePolicy.isImage(attachment.contentType) else { return nil }
        if case let .image(data) = await thumbnail(attachmentId: attachment.id) { return data }
        return nil
    }

    /// Czy telefon ma szukać miniatury załącznika w programie (`AttachmentRepository.savedOf` Androida; eksport programu nie niesie
    /// `hasThumbnail`): zdjęcie zawsze, film tylko w trybie z programem (w samodzielnym miniatura leży wyłącznie w telefonie), inne
    /// pliki — nigdy (żądanie nie jest wysyłane).
    static func mayHaveRemoteThumbnail(contentType: String, online: Bool) -> Bool {
        FilePolicy.isImage(contentType) || (FilePolicy.isVideo(contentType) && online)
    }

    /// Miniatura filmu czekającego w kolejce: plik w katalogu jego operacji `CreateAttachment` (`OutboxFile.thumbnailPath`).
    private func queuedThumbnail(_ attachmentId: String) async -> Data? {
        let path = try? await store.read { access -> String? in
            guard let operation = try access.operations().first(where: { $0.kind == .createAttachment && ($0.recordId ?? $0.localRef) == attachmentId }) else { return nil }
            return try access.outboxFile(operation.id)?.thumbnailPath
        }
        guard let path else { return nil }
        let data = FileManager.default.contents(atPath: path)
        return data?.isEmpty == false ? data : nil
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
        return await programThumbnail(id, pinned: true)
    }

    /// `GET attachments/{id}/thumbnail` (tylko online) z zapisem w pamięci telefonu.
    private func programThumbnail(_ id: String, pinned: Bool) async -> ThumbnailResult {
        guard mode() == .online, let client else { return .failed }
        switch await client.execute(ApiRequest(.get, "attachments/\(id)/thumbnail", forFile: true)) {
        case let .success(response):
            guard !response.body.isEmpty else { return .failed }
            if let saved = try? files.write(response.body, attachmentId: id, kind: .thumbnail, pinned: pinned) {
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

    /// Czy załącznik czeka jeszcze w kolejce (niewysłany, także film w przygotowaniu) — wtedy „Usuń” tylko wycofuje go z kolejki.
    public func isQueued(_ attachmentId: String) async -> Bool {
        (try? await store.read { access -> Bool in
            let preparing = try access.preparingOperationIds()
            return try access.operations().contains {
                $0.kind == .createAttachment && $0.recordId == attachmentId && ($0.state == .pending || preparing.contains($0.id))
            }
        }) ?? false
    }

    /// Wycofuje niewysłany załącznik: operacja, rekord `Pending` i pliki znikają. `false` — wysyłka już się zaczęła.
    @discardableResult
    public func withdraw(_ attachmentId: String) async throws -> Bool {
        let released = try await store.write { access -> [OutboxFile]? in
            guard let operation = try access.operations().first(where: { $0.kind == .createAttachment && $0.recordId == attachmentId && $0.state.isUnsent }) else {
                return []
            }
            // Film w przygotowaniu (`held`, A10) też można wycofać — przygotowanie zauważy brak operacji i usunie swój wynik.
            let preparing = try access.preparingOperationIds().contains(operation.id)
            guard operation.state == .pending || preparing else { return nil }
            let files = try access.deleteOperation(operation.id, allowed: [.pending, .held]).files
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
