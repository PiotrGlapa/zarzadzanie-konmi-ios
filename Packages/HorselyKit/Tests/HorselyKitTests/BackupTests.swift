import Foundation
import HorselyCore
import Testing
import ZIPFoundation
@testable import HorselyKit

/// Kopia zapasowa (T123; przypadki `BackupRoundTripTest`, `BackupCorruptionTest`, `BackupInjuredTest`): z hasłem i bez, błędne
/// hasło, obcięty plik, zmieniony bajt, zła suma `sha256`, nowszy format, format 1 ze schematem 1.4 (dopisanie rodzajów treningów)
/// i pliki utworzone przez Androida 2.0.1.
struct BackupTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 9, hour: 18, minute: 30)!
    private let dates = FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 9)!)

    private struct Setup {
        let store: RecordStore
        let files: LocalFileStore
        let service: BackupService
        let root: URL
    }

    private func setup() throws -> Setup {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-backup-\(UUID().uuidString)", isDirectory: true)
        let store = RecordStore(database: try AppDatabase.inMemory())
        let files = try LocalFileStore(root: root.appendingPathComponent("Files", isDirectory: true))
        let service = BackupService(store: store, files: files, workDirectory: root.appendingPathComponent("Work", isDirectory: true), appVersion: "2.0.1", dates: dates)
        return Setup(store: store, files: files, service: service, root: root)
    }

    private func resource(_ name: String) -> URL {
        let base = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        let candidates = [base.appendingPathComponent("Resources/backup/\(name)"), base.appendingPathComponent("backup/\(name)")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    /// Dane do kopii: koń aktywny i kontuzjowany, słowniki, notatki, notatka w koszu, załącznik ze zdjęciem.
    private func seed(_ setup: Setup) async throws -> Data {
        var counter = 0
        let dictionaries = DefaultDictionaries.items(newId: { counter += 1; return "d\(counter)" }, now: stamp)
        var injured = LocalHorse(id: "h2", createdAt: stamp, updatedAt: stamp, version: 4, name: "Iskra", passportNumber: "PL-2")
        injured.status = .injured
        injured.statusDate = LocalDate("2026-10-01")
        let horse = LocalHorse(id: "h1", createdAt: stamp, updatedAt: stamp, version: 3, name: "Grom", passportNumber: "PL-1")
        let note = LocalNote(id: "n1", createdAt: stamp, updatedAt: stamp, version: 2, horseId: "h1", noteDate: LocalDate("2026-10-01")!, title: "Zażółć gęślą", content: "Treść")
        let trashed = LocalNote(id: "n2", createdAt: stamp, updatedAt: stamp, version: 2, horseId: "h1", noteDate: LocalDate("2026-10-02")!, title: "W koszu")
        let photo = Data((0 ..< 5000).map { UInt8($0 % 251) })
        let info = try setup.files.write(photo, attachmentId: "a1", kind: .original, pinned: true)
        let attachment = LocalAttachment(
            id: "a1", createdAt: stamp, updatedAt: stamp, version: 1, ownerType: .note, ownerId: "n1", horseId: "h1", fileName: "rana.bin",
            contentType: "application/pdf", sizeBytes: Int64(photo.count), sha256: info.sha256, description: "Opis"
        )
        var rows = try dictionaries.map { try StoredRecord.of($0, syncState: .local) }
        rows += [try StoredRecord.of(horse, syncState: .local), try StoredRecord.of(injured, syncState: .local), try StoredRecord.of(note, syncState: .local)]
        rows.append(try StoredRecord.of(attachment, syncState: .local))
        rows.append(try StoredRecord.of(trashed, syncState: .local, deletedAt: LocalDateTime(year: 2026, month: 10, day: 8, hour: 12), deletionBatchId: "n2"))
        let finalRows = rows
        try await setup.store.write { access in
            try access.upsert(finalRows)
            try access.upsertFile(info)
        }
        return photo
    }

    /// Pełny obraz magazynu: rodzaj, id, wersja, kosz i treść rekordu (porównywana po zdekodowaniu).
    private func image(_ store: RecordStore) async throws -> [String] {
        try await store.read { access in
            try RecordType.allCases.flatMap { type in
                try access.query(type, includeDeleted: true).map { row in
                    "\(row.type.rawValue)|\(row.id)|v\(row.version)|\(row.deletedAt?.description ?? "")|\(row.deletionBatchId ?? "")|\(try RecordCodec.encodeString(try row.record()))"
                }
            }.sorted()
        }
    }

    private func restore(_ setup: Setup, _ file: URL, password: String? = nil) async throws -> RestoreSummary {
        let prepared = try setup.service.prepare(file, password: password)
        defer { setup.service.discard(prepared) }
        return try await setup.service.apply(prepared)
    }

    // MARK: Zapis i odczyt

    @Test(arguments: [nil, "Siano-2026"])
    func aBackupRestoresTheSameRecordsAndFiles(password: String?) async throws {
        let source = try setup()
        let photo = try await seed(source)
        let file = source.root.appendingPathComponent("kopia.zkkopia")
        let result = try await source.service.write(to: file, password: password, attachmentsCacheMb: 200)
        #expect(result.manifest.counts == BackupCounts(horses: 2, entries: 1, attachments: 1, trash: 1))
        #expect(result.missingFiles.isEmpty)
        #expect(result.bytes > 0)

        let manifest = try source.service.inspect(file, password: password)
        #expect(manifest.formatVersion == 2 && manifest.exportSchemaVersion == "1.5")

        let target = try setup()
        let summary = try await restore(target, file, password: password)
        #expect(summary.attachmentsWithFiles == ["a1"])
        #expect(try await image(target.store) == image(source.store))
        let original = try #require(try await target.store.read { try $0.file(attachmentId: "a1", kind: .original) })
        #expect(original.pinned)
        #expect(try Data(contentsOf: target.files.url(for: original)) == photo)
    }

    @Test func theFirstEntryIsTheManifestAndTrashGoesToPhoneJson() async throws {
        let source = try setup()
        _ = try await seed(source)
        let file = source.root.appendingPathComponent("kopia.zkkopia")
        try await source.service.write(to: file, password: nil, attachmentsCacheMb: 150)
        let archive = try Archive(url: file, accessMode: .read)
        #expect(archive.makeIterator().next()?.path == BackupManifest.manifestName)
        let phone = try #require(archive[BackupManifest.phoneName])
        var data = Data()
        _ = try archive.extract(phone) { data.append($0) }
        let json = try JSONValue.parse(data)
        #expect(json["trash"]?.arrayValue?.first?["recordType"] == .string("Note"))
        #expect(json["dataSettings"]?["attachmentsCacheMb"] == .number(150))
    }

    // MARK: Błędy

    @Test func aPasswordProtectedBackupNeedsTheRightPassword() async throws {
        let source = try setup()
        _ = try await seed(source)
        let file = source.root.appendingPathComponent("kopia.zkkopia")
        try await source.service.write(to: file, password: "Siano-2026", attachmentsCacheMb: 200)
        #expect(throws: BackupError.needsPassword) { try source.service.inspect(file, password: nil) }
        #expect(throws: BackupError.wrongPassword) { try source.service.inspect(file, password: "zle") }
    }

    @Test(arguments: [nil, "Siano-2026"])
    func aTruncatedOrChangedFileIsCorruptedAndLeavesTheDataUntouched(password: String?) async throws {
        let source = try setup()
        _ = try await seed(source)
        let file = source.root.appendingPathComponent("kopia.zkkopia")
        try await source.service.write(to: file, password: password, attachmentsCacheMb: 200)
        let bytes = try Data(contentsOf: file)

        let truncated = source.root.appendingPathComponent("obciety.zkkopia")
        try bytes.prefix(bytes.count - 40).write(to: truncated)
        var changedBytes = bytes
        changedBytes[changedBytes.count / 2] ^= 0xFF
        let changed = source.root.appendingPathComponent("zmieniony.zkkopia")
        try changedBytes.write(to: changed)

        let target = try setup()
        _ = try await seed(target)
        let before = try await image(target.store)
        for broken in [truncated, changed] {
            #expect(throws: BackupError.self) { _ = try target.service.prepare(broken, password: password) }
            do {
                _ = try target.service.prepare(broken, password: password)
            } catch let error as BackupError {
                // Mała kopia z hasłem to jedna porcja: zmieniony bajt w niej jest nie do odróżnienia od złego hasła (jak w Androidzie).
                let acceptable = if case .corrupted = error { true } else { password != nil && broken == changed && error == .wrongPassword }
                if !acceptable { Issue.record("oczekiwano uszkodzenia, jest \(error)") }
            }
        }
        #expect(try await image(target.store) == before)
    }

    @Test func aWrongChecksumOrNewerFormatIsRejected() async throws {
        let source = try setup()
        _ = try await seed(source)
        let file = source.root.appendingPathComponent("kopia.zkkopia")
        try await source.service.write(to: file, password: nil, attachmentsCacheMb: 200)
        var entries = try read(file)

        var badSum = entries
        badSum[BackupManifest.attachmentEntry("a1")] = Data("inna treść".utf8)
        let bad = try zip(badSum, at: source.root.appendingPathComponent("suma.zkkopia"))
        #expect(throws: BackupError.corrupted("suma kontrolna attachments/a1")) { _ = try source.service.prepare(bad, password: nil) }

        var manifest = try JSONValue.parse(try #require(entries[BackupManifest.manifestName]))
        if case var .object(fields) = manifest {
            fields["formatVersion"] = .number(3)
            manifest = .object(fields)
        }
        entries[BackupManifest.manifestName] = try manifest.data()
        let newer = try zip(entries, at: source.root.appendingPathComponent("nowsza.zkkopia"))
        #expect(throws: BackupError.newerVersion(3)) { _ = try source.service.inspect(newer, password: nil) }
    }

    @Test func aFormat1BackupWithSchema14GetsThe200TrainingTypes() async throws {
        let source = try setup()
        _ = try await seed(source)
        let file = source.root.appendingPathComponent("kopia.zkkopia")
        try await source.service.write(to: file, password: nil, attachmentsCacheMb: 200)
        var entries = try read(file)
        // Kopia sprzed 2.0.0: bez Zajeżdżania, Gimnastyki i Wszechstronnego, format 1, schemat 1.4.
        var export = try JSONValue.parse(try #require(entries[BackupManifest.exportName]))
        if case var .object(root) = export, case var .object(data)? = root["data"], case let .array(items)? = data["dictionaries"] {
            data["dictionaries"] = .array(items.filter { !["Zajeżdżanie", "Gimnastyka", "Wszechstronny"].contains($0["value"]?.stringValue ?? "") })
            root["data"] = .object(data)
            root["schemaVersion"] = .string("1.4")
            export = .object(root)
        }
        entries[BackupManifest.exportName] = try export.data()
        var manifest = try JSONValue.parse(try #require(entries[BackupManifest.manifestName]))
        if case var .object(fields) = manifest, case var .object(sums)? = fields["entries"] {
            sums[BackupManifest.exportName] = .string(BackupService.sha256(try #require(entries[BackupManifest.exportName])))
            fields["entries"] = .object(sums)
            fields["formatVersion"] = .number(1)
            fields["exportSchemaVersion"] = .string("1.4")
            manifest = .object(fields)
        }
        entries[BackupManifest.manifestName] = try manifest.data()
        let old = try zip(entries, at: source.root.appendingPathComponent("stara.zkkopia"))

        let target = try setup()
        _ = try await restore(target, old)
        let types = try await target.store.read { access in
            try access.query(.dictionary).compactMap { try $0.record(as: LocalDictionaryItem.self) }.filter { $0.dictionaryType == .trainingType }
        }
        for name in DefaultDictionaries.trainingTypesAddedIn200 { #expect(types.contains { $0.value == name }) }
        #expect(types.count == DefaultDictionaries.values(of: .trainingType).count)
    }

    // MARK: Pliki z Androida

    @Test(arguments: [("android-2.0.1.zkkopia", nil), ("android-2.0.1-haslo.zkkopia", "Siano-2026")] as [(String, String?)])
    func aBackupMadeByAndroid201RestoresWithTheSameRecordsAndChecksums(name: String, password: String?) async throws {
        let expectedText = try String(contentsOf: resource("android-2.0.1-expected.txt"), encoding: .utf8)
        let lines = expectedText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let target = try setup()
        let manifest = try target.service.inspect(resource(name), password: password)
        #expect(manifest.appVersion == "2.0.1" && manifest.formatVersion == 2)
        #expect(manifest.counts == BackupCounts(horses: 2, entries: 3, attachments: 2, trash: 1))
        let summary = try await restore(target, resource(name), password: password)
        #expect(summary.attachmentsWithFiles == ["a1", "a2"])

        let restored = try await target.store.read { access in
            try RecordType.allCases.flatMap { type in
                try access.query(type, includeDeleted: true).map { row in
                    "\(row.type.rawValue)|\(row.id)|v\(row.version)|\(row.deletedAt?.description ?? "")|\(row.deletionBatchId ?? "")"
                }
            }
        }
        let expectedRecords = lines.filter { !$0.hasPrefix("sha:") }.map { line -> String in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let deleted = parts[3].isEmpty ? "" : (LocalDateTime(parts[3])?.description ?? parts[3])
            return "\(parts[0])|\(parts[1])|\(parts[2])|\(deleted)|\(parts[4])"
        }
        #expect(restored.sorted() == expectedRecords.sorted())

        for line in lines where line.hasPrefix("sha:") {
            let pair = line.dropFirst(4).split(separator: "=").map(String.init)
            let info = try #require(try await target.store.read { try $0.file(attachmentId: pair[0], kind: .original) })
            #expect(try FileDigest.sha256(of: target.files.url(for: info)).hex == pair[1])
        }
        let injured = try #require(try await target.store.get(.horse, id: "h2")?.record(as: LocalHorse.self))
        #expect(injured.status == .injured)
        let note = try #require(try await target.store.get(.note, id: "n1")?.record(as: LocalNote.self))
        #expect(note.title == "Notatka zażółć 1")
    }

    // MARK: Pomocnicze

    private func read(_ file: URL) throws -> [String: Data] {
        let archive = try Archive(url: file, accessMode: .read)
        var result: [String: Data] = [:]
        for entry in archive {
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            result[entry.path] = data
        }
        return result
    }

    /// Archiwum z wpisami — manifest pierwszy, reszta w kolejności nazw.
    private func zip(_ entries: [String: Data], at url: URL) throws -> URL {
        let archive = try Archive(url: url, accessMode: .create)
        let names = [BackupManifest.manifestName] + entries.keys.filter { $0 != BackupManifest.manifestName }.sorted()
        let folder = url.deletingLastPathComponent().appendingPathComponent("zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, name) in names.enumerated() {
            guard let data = entries[name] else { continue }
            let file = folder.appendingPathComponent("e\(index)")
            try data.write(to: file)
            try archive.addEntry(with: name, fileURL: file, compressionMethod: .deflate)
        }
        return url
    }
}
