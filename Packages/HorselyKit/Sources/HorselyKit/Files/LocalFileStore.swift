import CryptoKit
import Foundation
import GRDB
import HorselyCore

/// Rodzaj pliku załącznika w magazynie.
public enum FileKind: String, Sendable, CaseIterable {
    case original = "Original"
    case thumbnail = "Thumbnail"
}

/// Wiersz `local_file`: gdzie leży plik załącznika, jaki ma rozmiar i skrót. `pinned` — poza limitem LRU (tryb samodzielny i
/// miniatury koni, data-model.md §2).
public struct LocalFileInfo: Sendable, Equatable {
    public let attachmentId: String
    public let kind: FileKind
    public let relativePath: String
    public let sizeBytes: Int
    public let sha256: String
    public var lastOpenedAt: LocalDateTime?
    public var pinned: Bool

    public init(attachmentId: String, kind: FileKind, relativePath: String, sizeBytes: Int, sha256: String, lastOpenedAt: LocalDateTime? = nil, pinned: Bool) {
        self.attachmentId = attachmentId
        self.kind = kind
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.lastOpenedAt = lastOpenedAt
        self.pinned = pinned
    }
}

extension RecordAccess {
    public func upsertFile(_ info: LocalFileInfo) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO local_file (attachmentId, kind, relativePath, sizeBytes, sha256, lastOpenedAt, pinned) VALUES (?, ?, ?, ?, ?, ?, ?)",
            arguments: [info.attachmentId, info.kind.rawValue, info.relativePath, info.sizeBytes, info.sha256, info.lastOpenedAt?.description, info.pinned]
        )
    }

    public func file(attachmentId: String, kind: FileKind) throws -> LocalFileInfo? {
        try Row.fetchOne(db, sql: "SELECT * FROM local_file WHERE attachmentId = ? AND kind = ?", arguments: [attachmentId, kind.rawValue]).map(Self.fileInfo)
    }

    public func files(attachmentId: String) throws -> [LocalFileInfo] {
        try Row.fetchAll(db, sql: "SELECT * FROM local_file WHERE attachmentId = ?", arguments: [attachmentId]).map(Self.fileInfo)
    }

    public func deleteFiles(attachmentId: String) throws {
        try db.execute(sql: "DELETE FROM local_file WHERE attachmentId = ?", arguments: [attachmentId])
    }

    private static func fileInfo(_ row: Row) throws -> LocalFileInfo {
        let rawKind: String = row["kind"]
        guard let kind = FileKind(rawValue: rawKind) else { throw StoreError.corruptRow("local_file.kind=\(rawKind)") }
        let opened: String? = row["lastOpenedAt"]
        return LocalFileInfo(
            attachmentId: row["attachmentId"], kind: kind, relativePath: row["relativePath"], sizeBytes: row["sizeBytes"], sha256: row["sha256"],
            lastOpenedAt: opened.flatMap { LocalDateTime($0) }, pinned: row["pinned"]
        )
    }
}

/// Pliki załączników na dysku (kontener App Group, wyłączony z kopii iCloud): `Files/<id załącznika>/original.jpg|thumbnail.jpg`.
/// Rozbudowa o limit LRU, wysyłkę w tle i pobieranie z programu — w zadaniu T114.
public final class LocalFileStore: Sendable {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Zapisuje plik i zwraca opis wiersza `local_file`.
    public func write(_ data: Data, attachmentId: String, kind: FileKind, fileExtension: String = "jpg", pinned: Bool) throws -> LocalFileInfo {
        let relative = "\(attachmentId)/\(kind == .original ? "original" : "thumbnail").\(fileExtension)"
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return LocalFileInfo(attachmentId: attachmentId, kind: kind, relativePath: relative, sizeBytes: data.count, sha256: digest, pinned: pinned)
    }

    public func read(_ info: LocalFileInfo) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent(info.relativePath))
    }

    public func url(for info: LocalFileInfo) -> URL {
        root.appendingPathComponent(info.relativePath)
    }

    public func delete(attachmentId: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(attachmentId, isDirectory: true))
    }
}
