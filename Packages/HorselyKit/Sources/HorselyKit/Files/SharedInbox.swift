import Foundation
import GRDB
import HorselyCore

/// Pozycja skrzynki udostępniania: pliki przekazane przez rozszerzenie „Udostępnij → Horsely” i wybrany cel (wpis konia albo
/// nowa notatka). Aplikacja zamienia ją w załączniki przy otwarciu i w zadaniu w tle (T116/T117).
public struct SharedInboxEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Target: Codable, Hashable, Sendable {
        case entry(ownerType: AttachmentOwnerType, ownerId: String)
        case newNote(title: String)
    }

    public struct File: Codable, Hashable, Sendable {
        /// Nazwa pliku w folderze pozycji (bezpieczna, jak w `FilePolicy`).
        public let name: String
        public let contentType: String?

        public init(name: String, contentType: String?) {
            self.name = name
            self.contentType = contentType
        }
    }

    public let id: String
    public let createdAt: Date
    public let horseId: String
    public let target: Target
    public let files: [File]
    public let description: String?

    public init(id: String = UUID().uuidString.lowercased(), createdAt: Date = Date(), horseId: String, target: Target, files: [File], description: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.horseId = horseId
        self.target = target
        self.files = files
        self.description = description
    }
}

/// Skrzynka udostępniania w kontenerze App Group (`Inbox/`): rozszerzenie kopiuje pliki strumieniowo do folderu roboczego
/// (`.incoming-<id>`), zapisuje `manifest.json` i dopiero wtedy nadaje folderowi nazwę `<id>` — aplikacja widzi tylko pełne pozycje.
/// Rozszerzenie nie pisze do bazy i nie łączy się z siecią (contracts/app-entry-points-ios.md).
public struct SharedInbox: Sendable {
    public static let manifestName = "manifest.json"
    static let incomingPrefix = ".incoming-"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Skrzynka w katalogu grupy (`<App Group>/Inbox`).
    public static func inGroup(_ groupDirectory: URL) -> SharedInbox {
        SharedInbox(directory: groupDirectory.appendingPathComponent("Inbox", isDirectory: true))
    }

    /// Folder roboczy nowej pozycji.
    public func newFolder() throws -> URL {
        let folder = directory.appendingPathComponent(Self.incomingPrefix + UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Zatwierdza pozycję: manifest, potem zmiana nazwy folderu (operacja atomowa).
    public func commit(_ entry: SharedInboxEntry, folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(to: folder.appendingPathComponent(Self.manifestName), options: .atomic)
        try FileManager.default.moveItem(at: folder, to: directory.appendingPathComponent(entry.id, isDirectory: true))
    }

    /// Zatwierdzone pozycje od najstarszej.
    public func entries() -> [(entry: SharedInboxEntry, folder: URL)] {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { folder in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.manifestName)),
                      let entry = try? decoder.decode(SharedInboxEntry.self, from: data) else { return nil }
                return (entry, folder)
            }
            .sorted { $0.entry.createdAt < $1.entry.createdAt }
    }

    public func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Porzucone foldery robocze (rozszerzenie przerwane w trakcie kopiowania) starsze niż doba.
    public func removeAbandoned(now: Date = Date()) {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for folder in folders where folder.lastPathComponent.hasPrefix(Self.incomingPrefix) {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if now.timeIntervalSince(created) > 24 * 60 * 60 { remove(folder) }
        }
    }
}

extension AppDatabase {
    /// Baza tylko do odczytu (rozszerzenie udostępniania): bez migracji i bez zapisu — zapisuje wyłącznie aplikacja.
    public static func openReadOnly(in directory: URL) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.busyMode = .timeout(5)
        let path = directory.appendingPathComponent("Horsely", isDirectory: true).appendingPathComponent("horsely.sqlite").path
        return AppDatabase(readOnly: try DatabasePool(path: path, configuration: configuration))
    }
}
