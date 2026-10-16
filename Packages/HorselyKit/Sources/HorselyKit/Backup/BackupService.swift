import CryptoKit
import Foundation
import GRDB
import HorselyCore
import ZIPFoundation

/// Wynik zapisu kopii: rozmiar pliku, manifest, licznik zmian danych w chwili migawki i załączniki bez pliku w telefonie.
public struct BackupResult: Sendable {
    public let bytes: Int64
    public let manifest: BackupManifest
    public let changeCounter: Int64
    public let missingFiles: [String]
}

/// Kopia wczytana i zweryfikowana: manifest i rozpakowane wpisy w `directory` (usuwane przez `BackupService.discard`).
public struct PreparedBackup: Sendable {
    public let manifest: BackupManifest
    public let directory: URL

    public func attachmentFile(_ id: String) -> URL? {
        let url = directory.appendingPathComponent(BackupManifest.attachmentEntry(id))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// Wynik odtworzenia: liczby z kopii i załączniki, które mają plik w telefonie.
public struct RestoreSummary: Sendable {
    public let counts: BackupCounts
    public let attachmentsWithFiles: Set<String>
}

/// Kopia zapasowa (T125, FR-KOP-01…09, contracts/android/backup-format.md; `BackupWriter.kt`/`BackupReader.kt` Androida 2.0.1):
/// ZIP z `manifest.json` (pierwszy), `export.json` (schemat 1.5, aktywne rekordy), `phone.json` (kosz, ustawienia danych) i
/// `attachments/<id>` (oryginały, także rekordów z kosza); z hasłem — całość szyfrowana `BackupCrypto`. Plik jest wymienny z Androidem
/// w obie strony. Odtwarzanie: najpierw weryfikacja i rozpakowanie do katalogu tymczasowego, dopiero potem jedna transakcja.
public final class BackupService: Sendable {
    private let store: RecordStore
    private let files: LocalFileStore
    private let workDirectory: URL
    private let appVersion: String
    private let dates: any DateProvider
    private let newId: @Sendable () -> String

    public init(
        store: RecordStore, files: LocalFileStore, workDirectory: URL, appVersion: String, dates: any DateProvider = SystemDateProvider(),
        newId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.store = store
        self.files = files
        self.workDirectory = workDirectory
        self.appVersion = appVersion
        self.dates = dates
        self.newId = newId
    }

    // MARK: Zapis

    private struct Snapshot: Sendable {
        let export: Data
        let phone: Data
        let attachments: [LocalAttachment]
        let originals: [String: LocalFileInfo]
        let counts: BackupCounts
        let changeCounter: Int64
    }

    /// Zapisuje kopię do `target` (nadpisuje). `password` puste albo `nil` — plik bez hasła.
    /// - Throws: `BackupError.sourceCorrupted`, gdy plik załącznika w telefonie nie zgadza się ze swoją sumą kontrolną.
    @discardableResult
    public func write(to target: URL, password: String?, attachmentsCacheMb: Int, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> BackupResult {
        let now = dates.now()
        let appVersion = self.appVersion
        let snapshot = try await store.read { access in try Self.snapshot(access, now: now, appVersion: appVersion, attachmentsCacheMb: attachmentsCacheMb) }
        let work = try newWorkFolder()
        defer { try? FileManager.default.removeItem(at: work) }

        var present: [(LocalAttachment, URL)] = []
        var missing: [String] = []
        for attachment in snapshot.attachments {
            if let info = snapshot.originals[attachment.id], FileManager.default.fileExists(atPath: files.url(for: info).path) {
                present.append((attachment, files.url(for: info)))
            } else {
                missing.append(attachment.id)
            }
        }
        var entries: [String: String] = [
            BackupManifest.exportName: Self.sha256(snapshot.export), BackupManifest.phoneName: Self.sha256(snapshot.phone),
        ]
        for (attachment, _) in present { entries[BackupManifest.attachmentEntry(attachment.id)] = attachment.sha256 }
        let manifest = BackupManifest(createdAt: now.description, appVersion: appVersion, counts: snapshot.counts, entries: entries)

        let zipURL = work.appendingPathComponent("kopia.zip")
        let archive = try Archive(url: zipURL, accessMode: .create)
        let total = 3 + present.count
        var done = 0
        func addData(_ name: String, _ data: Data) throws {
            let file = work.appendingPathComponent("entry-\(done)")
            try data.write(to: file)
            try archive.addEntry(with: name, fileURL: file, compressionMethod: .deflate)
            try FileManager.default.removeItem(at: file)
            done += 1
            progress?(done, total)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        try addData(BackupManifest.manifestName, try encoder.encode(manifest))
        try addData(BackupManifest.exportName, snapshot.export)
        try addData(BackupManifest.phoneName, snapshot.phone)
        for (attachment, url) in present {
            try Task.checkCancellation()
            let (_, digest) = try FileDigest.sha256(of: url)
            guard digest.caseInsensitiveCompare(attachment.sha256) == .orderedSame else { throw BackupError.sourceCorrupted(attachment.id) }
            try archive.addEntry(with: BackupManifest.attachmentEntry(attachment.id), fileURL: url, compressionMethod: Self.isCompressed(attachment) ? .none : .deflate)
            done += 1
            progress?(done, total)
        }

        try? FileManager.default.removeItem(at: target)
        if let password, !password.isEmpty {
            try BackupCrypto.encrypt(source: zipURL, target: target, password: password)
        } else {
            try FileManager.default.moveItem(at: zipURL, to: target)
        }
        let bytes = Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return BackupResult(bytes: bytes, manifest: manifest, changeCounter: snapshot.changeCounter, missingFiles: missing)
    }

    private static func snapshot(_ access: RecordAccess, now: LocalDateTime, appVersion: String, attachmentsCacheMb: Int) throws -> Snapshot {
        var records: [ExportedRecord] = []
        var horses = 0
        var entries = 0
        for type in RecordType.allCases {
            for row in try access.query(type) {
                records.append(ExportedRecord(record: try row.record(), dateKey: row.dateKey))
                switch type {
                case .horse: horses += 1
                case .vetVisit, .farrierVisit, .physioVisit, .specialistVisit, .note, .training, .purchase, .competition, .competitionStart: entries += 1
                default: break
                }
            }
        }
        let header = ExportHeader(
            schemaVersion: BackupManifest.exportSchemaVersion, exportedAt: now.description, appVersion: appVersion,
            scope: ExportScope(type: "full", includesAttachmentFiles: true)
        )
        let export = try ExportDocument(header: header, records: records).toJSON()

        var trash: [JSONValue] = []
        for row in try access.trashed() {
            guard case var .object(fields) = try JSONValue.parse(row.body), let deletedAt = row.deletedAt else { continue }
            fields["recordType"] = .string(row.type.rawValue)
            fields["deletedAt"] = .string(deletedAt.description)
            fields["deletionBatchId"] = row.deletionBatchId.map(JSONValue.string) ?? .null
            trash.append(.object(fields))
        }
        let phone = try JSONValue.object([
            "trash": .array(trash), "dataSettings": .object(["attachmentsCacheMb": .number(Decimal(attachmentsCacheMb))]),
        ]).data()
        let attachments = try access.query(.attachment, includeDeleted: true).compactMap { try $0.record(as: LocalAttachment.self) }
        var originals: [String: LocalFileInfo] = [:]
        for attachment in attachments {
            if let info = try access.file(attachmentId: attachment.id, kind: .original) { originals[attachment.id] = info }
        }
        return Snapshot(
            export: export, phone: phone, attachments: attachments, originals: originals,
            counts: BackupCounts(horses: horses, entries: entries, attachments: attachments.count, trash: trash.count), changeCounter: try access.changeCounter()
        )
    }

    // MARK: Odczyt

    /// Sam manifest (data i liczby do ekranu przed odtworzeniem).
    public func inspect(_ source: URL, password: String?) throws -> BackupManifest {
        let work = try newWorkFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = try openArchive(source, password: password, work: work)
        return try Self.readManifest(archive)
    }

    /// Rozpakowuje i weryfikuje całą kopię (sumy `sha256` każdego wpisu); wynik usuwa `discard`.
    public func prepare(_ source: URL, password: String?) throws -> PreparedBackup {
        let work = try newWorkFolder()
        let directory = work.appendingPathComponent("restore-tmp", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let archive = try openArchive(source, password: password, work: work)
            let manifest = try Self.readManifest(archive)
            var seen = Set<String>()
            for entry in archive where entry.path != BackupManifest.manifestName {
                let name = entry.path
                guard BackupManifest.isValidEntryName(name), let expected = manifest.entries[name] else { throw BackupError.corrupted("nieoczekiwany wpis") }
                guard seen.insert(name).inserted else { throw BackupError.corrupted("powtórzony wpis") }
                let target = directory.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let actual = try Self.extract(entry, from: archive, to: target)
                guard actual.caseInsensitiveCompare(expected) == .orderedSame else { throw BackupError.corrupted("suma kontrolna \(name)") }
            }
            if let missing = Set(manifest.entries.keys).subtracting(seen).sorted().first { throw BackupError.corrupted("brak wpisu \(missing)") }
            guard seen.contains(BackupManifest.exportName), seen.contains(BackupManifest.phoneName) else { throw BackupError.corrupted("brak danych") }
            return PreparedBackup(manifest: manifest, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw Self.mapped(error)
        }
    }

    public func discard(_ prepared: PreparedBackup) {
        try? FileManager.default.removeItem(at: prepared.directory.deletingLastPathComponent())
    }

    /// Zastępuje dane telefonu zawartością kopii w jednej transakcji (rekordy, kosz, pliki załączników jako przypięte z miniaturami).
    /// Błąd przed zatwierdzeniem zostawia dotychczasowe dane.
    @discardableResult
    public func apply(_ prepared: PreparedBackup) async throws -> RestoreSummary {
        let exportData = try Data(contentsOf: prepared.directory.appendingPathComponent(BackupManifest.exportName))
        let document: ExportDocument
        do {
            document = try ExportDocument.parse(exportData)
        } catch {
            throw BackupError.corrupted("export.json")
        }
        let trash = try Self.readTrash(prepared.directory.appendingPathComponent(BackupManifest.phoneName))
        let upgrade = DictionaryUpgrades.isBeforeTrainingTypes200(prepared.manifest.exportSchemaVersion)
        let now = dates.now()
        let newId = self.newId
        let files = self.files

        // Pliki najpierw do folderu przejściowego w magazynie: przeniesienie na miejsce i wiersze `local_file` idą razem z transakcją.
        let staging = files.root.appendingPathComponent(".restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var placed: [String: (original: URL, thumbnail: Data?)] = [:]
        for case let attachment as LocalAttachment in document.records(of: .attachment) + trash.map(\.record) {
            guard let source = prepared.attachmentFile(attachment.id) else { continue }
            let copy = staging.appendingPathComponent(attachment.id)
            try FileManager.default.copyItem(at: source, to: copy)
            let thumbnail = FilePolicy.isImage(attachment.contentType) ? try? ImagePreparer.thumbnail(Data(contentsOf: copy)) : nil
            placed[attachment.id] = (copy, thumbnail)
        }
        let staged = placed
        let summary = try await store.write { access -> Set<String> in
            try access.clear()
            try access.clearFiles()
            var rows: [StoredRecord] = []
            for exported in document.records { rows.append(try StoredRecord.of(exported.record, syncState: .local, dateKey: exported.dateKey)) }
            for item in trash {
                rows.append(try StoredRecord.of(item.record, syncState: .local, deletedAt: item.deletedAt, deletionBatchId: item.batchId))
            }
            try access.upsert(rows)
            if upgrade {
                let dictionaries = rows.filter { $0.type == .dictionary }.compactMap { try? $0.record(as: LocalDictionaryItem.self) }
                let added = DictionaryUpgrades.missingTrainingTypes(existing: dictionaries, newId: newId, now: now)
                try access.upsert(try added.map { try StoredRecord.of($0, syncState: .local) })
            }
            var withFiles = Set<String>()
            for (id, file) in staged {
                let original = try files.move(file.original, attachmentId: id, kind: .original, pinned: true)
                try access.upsertFile(original)
                if let thumbnail = file.thumbnail, let small = try? files.write(thumbnail, attachmentId: id, kind: .thumbnail, pinned: true) {
                    try access.upsertFile(small)
                }
                withFiles.insert(id)
            }
            return withFiles
        }
        // Po zatwierdzeniu: pliki załączników, których nie ma w kopii, znikają z telefonu.
        files.retain(summary)
        return RestoreSummary(counts: prepared.manifest.counts, attachmentsWithFiles: summary)
    }

    // MARK: Pomocnicze

    private func newWorkFolder() throws -> URL {
        let folder = workDirectory.appendingPathComponent("backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Archiwum ZIP kopii; plik z hasłem jest najpierw odszyfrowywany do `work`.
    private func openArchive(_ source: URL, password: String?, work: URL) throws -> Archive {
        let handle = try FileHandle(forReadingFrom: source)
        let prefix = try handle.read(upToCount: 8) ?? Data()
        try handle.close()
        var zipURL = source
        if BackupCrypto.isEncrypted(prefix) {
            guard let password, !password.isEmpty else { throw BackupError.needsPassword }
            zipURL = work.appendingPathComponent("kopia.zip")
            try BackupCrypto.decrypt(source: source, target: zipURL, password: password)
        } else if prefix.count < 4 || prefix[prefix.startIndex] != 0x50 || prefix[prefix.startIndex + 1] != 0x4B {
            throw BackupError.corrupted("to nie jest plik kopii")
        }
        do {
            return try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw BackupError.corrupted("archiwum")
        }
    }

    static func readManifest(_ archive: Archive) throws -> BackupManifest {
        guard let first = archive.makeIterator().next() else { throw BackupError.corrupted("pusty plik") }
        guard first.path == BackupManifest.manifestName else { throw BackupError.corrupted("brak manifestu") }
        guard first.uncompressedSize <= 4 * 1024 * 1024 else { throw BackupError.corrupted("manifest") }
        var data = Data()
        do {
            _ = try archive.extract(first) { data.append($0) }
        } catch {
            throw BackupError.corrupted("manifest")
        }
        guard let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data) else { throw BackupError.corrupted("manifest") }
        guard manifest.format == BackupManifest.format else { throw BackupError.corrupted("to nie jest kopia aplikacji") }
        if manifest.formatVersion > BackupManifest.formatVersion { throw BackupError.newerVersion(manifest.formatVersion) }
        return manifest
    }

    static func extract(_ entry: Entry, from archive: Archive, to target: URL) throws -> String {
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        var hasher = SHA256Stream()
        do {
            _ = try archive.extract(entry) { chunk in
                hasher.update(chunk)
                try handle.write(contentsOf: chunk)
            }
        } catch {
            throw BackupError.corrupted("archiwum")
        }
        return hasher.hex
    }

    struct TrashItem: Sendable {
        let record: any LocalRecord
        let deletedAt: LocalDateTime
        let batchId: String?
    }

    static func readTrash(_ url: URL) throws -> [TrashItem] {
        guard let root = try? JSONValue.parse(Data(contentsOf: url)), case .object = root else { throw BackupError.corrupted("phone.json") }
        guard let items = root["trash"]?.arrayValue else { return [] }
        return try items.map { item in
            guard case var .object(body) = item, let rawType = item["recordType"]?.stringValue, let type = RecordType(rawValue: rawType),
                  let deletedText = item["deletedAt"]?.stringValue, let deletedAt = LocalDateTime(deletedText) else { throw BackupError.corrupted("phone.json") }
            body.removeValue(forKey: "recordType")
            body.removeValue(forKey: "deletedAt")
            body.removeValue(forKey: "deletionBatchId")
            do {
                let record = try RecordCodec.decode(type, from: try JSONValue.object(body).data())
                return TrashItem(record: record, deletedAt: deletedAt, batchId: item["deletionBatchId"]?.stringValue)
            } catch {
                throw BackupError.corrupted("phone.json")
            }
        }
    }

    static func isCompressed(_ attachment: LocalAttachment) -> Bool {
        ["image/jpeg", "image/png", "video/mp4", "application/pdf"].contains(attachment.contentType.lowercased())
    }

    static func sha256(_ data: Data) -> String {
        var hasher = SHA256Stream()
        hasher.update(data)
        return hasher.hex
    }

    static func mapped(_ error: Error) -> Error {
        if error is BackupError { return error }
        return BackupError.corrupted("odczyt")
    }
}

/// SHA-256 liczony porcjami.
struct SHA256Stream {
    private var hasher = SHA256()

    mutating func update(_ data: Data) { hasher.update(data: data) }

    var hex: String { hasher.finalize().map { String(format: "%02x", $0) }.joined() }
}

extension RecordAccess {
    /// Usuwa wszystkie wiersze `local_file` (odtworzenie kopii).
    func clearFiles() throws {
        try db.execute(sql: "DELETE FROM local_file")
    }
}

extension LocalFileStore {
    /// Usuwa katalogi plików załączników spoza `keep` (po odtworzeniu kopii).
    public func retain(_ keep: Set<String>) {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders where !folder.lastPathComponent.hasPrefix(".") && !keep.contains(folder.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
