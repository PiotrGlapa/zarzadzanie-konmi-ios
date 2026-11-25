import Foundation
import HorselyCore
import Testing
import ZIPFoundation
@testable import HorselyKit

/// Kopia formatu 3 ze schematem eksportu 1.6 (Task 7 = [PLAN-A] Task 6; `BackupRidesTest.kt` Androida 3.0.2): nagrania jazd z trasami,
/// profile jazd koni, ustawienia jazd, metadane załączników, zgodność wstecz z kopią 2.x i kopia z dwiema jazdami zapisana przez Androida.
struct BackupRidesTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 9, hour: 18, minute: 30)!
    private let dates = FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 9)!)
    private let horseId = "0b6c1f0e-3a49-4f1b-8d5a-7c2e9a1d4b10"
    private let trainingDate = LocalDate(year: 2026, month: 9, day: 1)!

    private struct Setup {
        let store: RecordStore
        let files: LocalFileStore
        let service: BackupService
        let root: URL
    }

    private func setup() throws -> Setup {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-backup-rides-\(UUID().uuidString)", isDirectory: true)
        let store = RecordStore(database: try AppDatabase.inMemory())
        let files = try LocalFileStore(root: root.appendingPathComponent("Files", isDirectory: true))
        let service = BackupService(store: store, files: files, workDirectory: root.appendingPathComponent("Work", isDirectory: true), appVersion: "3.0.0", dates: dates)
        return Setup(store: store, files: files, service: service, root: root)
    }

    private func resource(_ path: String) -> URL {
        let base = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        let candidates = [base.appendingPathComponent("Resources/\(path)"), base.appendingPathComponent(path)]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    // MARK: Dane

    /// Nagranie z kontraktu (`v3/recording.json`, kopia 1:1 z Androida) — liczby ze skalą zapisu.
    private func contractRecording() throws -> Recording {
        try Recording(json: JSONValue.parseKeepingScale(Data(contentsOf: resource("v3/recording.json"))))
    }

    private func makeTrack(_ recording: Recording) -> StoredTrack {
        StoredTrack(recordingId: recording.id, version: recording.version, format: "zk-track/1", data: Data((0 ..< 3000).map { UInt8(truncatingIfNeeded: $0 &* 7919 &+ 11) }))
    }

    private func training(_ recording: Recording) -> LocalTraining {
        LocalTraining(
            id: recording.trainingId, createdAt: stamp, updatedAt: stamp, version: 1, horseId: horseId, trainingDate: trainingDate,
            trainingTypeId: "5d1a7e20-9c3b-4a6f-b1d4-2e8f0a7c6b31"
        )
    }

    private func horse() -> LocalHorse {
        LocalHorse(id: horseId, createdAt: stamp, updatedAt: stamp, version: 3, name: "Grom", passportNumber: "PL-\(horseId)")
    }

    private func profile() -> LocalHorseRideProfile {
        LocalHorseRideProfile(
            horseId: horseId, profile: RideProfile(loadWeightTrot: Decimal(string: "2.5"), loadWarnPercent: 20), createdAt: stamp, updatedAt: stamp, version: 3
        )
    }

    private func defaults() -> LocalRideDefaults {
        var values = RideDefaults.builtIn
        values.loadWarnPercent = 25
        values.version = 2
        return LocalRideDefaults(defaults: values)
    }

    /// Magazyn z koniem, treningiem, nagraniem z trasą, profilem konia i (opcjonalnie) ustawieniami jazd.
    private func withRides(_ setup: Setup, rideDefaults: Bool = true) async throws {
        let recording = try contractRecording()
        var rows = [
            try StoredRecord.of(horse(), syncState: .local),
            try StoredRecord.of(training(recording), syncState: .local),
            try StoredRecord.of(recording.toRecord(horseId: horseId, trainingDate: trainingDate), syncState: .local),
            try StoredRecord.of(profile(), syncState: .local),
        ]
        if rideDefaults { rows.append(try StoredRecord.of(defaults(), syncState: .local)) }
        let finalRows = rows
        let track = makeTrack(recording)
        try await setup.store.write { access in
            try access.upsert(finalRows)
            try access.putTrack(track)
        }
    }

    private func backup(_ setup: Setup) async throws -> (URL, BackupResult) {
        let file = setup.root.appendingPathComponent("kopia-\(UUID().uuidString).zkkopia")
        let result = try await setup.service.write(to: file, password: nil, attachmentsCacheMb: 200)
        return (file, result)
    }

    private func restore(_ setup: Setup, _ file: URL) async throws -> RestoreSummary {
        let prepared = try setup.service.prepare(file, password: nil)
        defer { setup.service.discard(prepared) }
        return try await setup.service.apply(prepared)
    }

    /// Pełny obraz magazynu: rodzaj, id, wersja, stan, kosz, data porządkująca i treść rekordu (po zdekodowaniu).
    private func image(_ store: RecordStore) async throws -> [String] {
        try await store.read { access in
            try RecordType.allCases.flatMap { type in
                try access.query(type, includeDeleted: true).map { row in
                    let deleted = row.deletedAt?.description ?? ""
                    let batch = row.deletionBatchId ?? ""
                    let dateKey = row.dateKey?.description ?? ""
                    return "\(row.type.rawValue)|\(row.id)|v\(row.version)|\(row.syncState.rawValue)|\(deleted)|\(batch)|\(dateKey)|\(try RecordCodec.encodeString(try row.record()))"
                }
            }.sorted()
        }
    }

    private func entries(_ file: URL) throws -> [String: Data] {
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

    private func schemaErrors(_ export: Data) throws -> [String] {
        try JSONSchemaValidator(schema: Data(contentsOf: resource("contracts/export-schema-1.6.json"))).errors(export)
    }

    // MARK: Nagrania, profile i ustawienia jazd

    @Test func backupWithRecordingRoundTripsTrackBytesAndSegments() async throws {
        let source = try setup()
        try await withRides(source)
        let recording = try contractRecording()
        let track = makeTrack(recording)
        let (file, result) = try await backup(source)

        let target = try setup()
        _ = try await restore(target, file)

        #expect(try await image(target.store) == image(source.store))
        let read = try #require(try await target.store.get(.trainingRecording, id: recording.id)?.record(as: LocalTrainingRecording.self))
        #expect(read.recording.segments.count == 3)
        #expect(read.recording.segments == recording.segments)
        var stripped = recording
        stripped.trackData = nil
        #expect(read.recording.toJSON().textKeepingScale() == stripped.toJSON().textKeepingScale(), "nagranie wraca z tą samą skalą liczb (24.60, 7.00, 98.0)")
        let exportText = String(decoding: try #require(try entries(file)[BackupManifest.exportName]), as: UTF8.self)
        for fragment in [#""maxSpeedKmh":24.60"#, #""trotAvgSpeedKmh":12.00"#, #""walkAvgCadence":98.0"#, #""loadPoints":100.0"#, #""weatherPrecipMm":0.0"#, #""loadWeightTrot":2.5"#] {
            #expect(exportText.contains(fragment), "export.json zawiera \(fragment)")
        }
        #expect(read.horseId == horseId)
        #expect(read.trainingDate == trainingDate)
        #expect(read.recording.trackData == nil, "punkty leżą w magazynie tras, nie w rekordzie")
        let restoredTrack = try #require(try await target.store.track(recordingId: recording.id))
        #expect(restoredTrack.data == track.data)
        #expect(restoredTrack.format == track.format)
        #expect(restoredTrack.version == track.version)
        #expect(try await target.store.get(.horseRideProfile, id: horseId)?.record(as: LocalHorseRideProfile.self) == profile())
        #expect(try await target.store.get(.rideDefaults, id: LocalRideDefaults.ID)?.record(as: LocalRideDefaults.self) == defaults())
        #expect(result.manifest.formatVersion == 3)
        #expect(result.manifest.exportSchemaVersion == "1.6")
        #expect(result.manifest.dataSchemaVersion == "3.0")
    }

    @Test(arguments: [true, false])
    func exportJsonValidatesAgainstExportSchema16(rideDefaults: Bool) async throws {
        let source = try setup()
        try await withRides(source, rideDefaults: rideDefaults)
        let track = makeTrack(try contractRecording())
        let (file, _) = try await backup(source)
        let export = try #require(try entries(file)[BackupManifest.exportName])

        let errors = try schemaErrors(export)
        #expect(errors.isEmpty, "rideDefaults=\(rideDefaults): \(Array(errors.prefix(5)))")
        let data = try #require(try JSONValue.parseKeepingScale(export)["data"])
        #expect(data["trainingRecordings"]?.arrayValue?.count == 1)
        #expect(data["horseRideProfiles"]?.arrayValue?.count == 1)
        if rideDefaults {
            #expect(data["rideDefaults"]?["loadWarnPercent"] == .number(25))
        } else {
            #expect(data["rideDefaults"] == .null, "brak ustawień jazd to jawne null")
        }
        let exported = try #require(data["trainingRecordings"]?.arrayValue?.first)
        #expect(exported["trackData"] == .string(track.data.base64EncodedString()), "trackData to base64 punktów")
        #expect(exported["horseId"] == nil && exported["trainingDate"] == nil, "nagranie w pliku jak RecordingDto — bez konia i daty")
        let profile = try #require(data["horseRideProfiles"]?.arrayValue?.first)
        #expect(profile["gaitStopMaxKmh"] == .null, "profil niesie wszystkie 9 pól, brak = null")
    }

    @Test func exportJsonCarriesAttachmentMetadataAndValidatesAgainstExportSchema16() async throws {
        let source = try setup()
        try await withRides(source)
        let bytes = Data((0 ..< 500).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 21) })
        let filmInfo = try source.files.write(bytes, attachmentId: "9c1d2e3f-0000-4000-8000-000000000001", kind: .original, fileExtension: "mp4", pinned: true)
        let photoInfo = try source.files.write(bytes, attachmentId: "9c1d2e3f-0000-4000-8000-000000000002", kind: .original, fileExtension: "pdf", pinned: true)
        let withMetadata = LocalAttachment(
            id: "9c1d2e3f-0000-4000-8000-000000000001", createdAt: stamp, updatedAt: stamp, version: 1, ownerType: .horse, ownerId: horseId, horseId: horseId,
            fileName: "film.mp4", contentType: "video/mp4", sizeBytes: Int64(bytes.count), sha256: filmInfo.sha256, description: "Film",
            capturedAt: InstantText.parse("2026-09-01T08:15:00Z"), latitude: DecimalText.parse("52.2297000"), longitude: DecimalText.parse("21.0122000")
        )
        let plain = LocalAttachment(
            id: "9c1d2e3f-0000-4000-8000-000000000002", createdAt: stamp, updatedAt: stamp, version: 1, ownerType: .horse, ownerId: horseId, horseId: horseId,
            fileName: "plan.pdf", contentType: "application/pdf", sizeBytes: Int64(bytes.count), sha256: photoInfo.sha256
        )
        let rows = [try StoredRecord.of(withMetadata, syncState: .local), try StoredRecord.of(plain, syncState: .local)]
        try await source.store.write { access in
            try access.upsert(rows)
            try access.upsertFile(filmInfo)
            try access.upsertFile(photoInfo)
        }

        let (file, _) = try await backup(source)

        let export = try #require(try entries(file)[BackupManifest.exportName])
        let errors = try schemaErrors(export)
        #expect(errors.isEmpty, "\(Array(errors.prefix(5)))")
        let attachments = try #require(try JSONValue.parseKeepingScale(export)["data"]?["attachments"]?.arrayValue)
        let exported = try #require(attachments.first { $0["id"] == .string(withMetadata.id) })
        #expect(exported["capturedAt"] == .string("2026-09-01T08:15:00Z"))
        #expect(exported["latitude"]?.textKeepingScale() == "52.2297000", "szerokość jako liczba ze skalą zapisu")
        #expect(exported["longitude"]?.textKeepingScale() == "21.0122000", "długość jako liczba ze skalą zapisu")
        let exportText = String(decoding: export, as: UTF8.self)
        #expect(exportText.contains(#""latitude":52.2297000"#) && exportText.contains(#""longitude":21.0122000"#))
        let bare = try #require(attachments.first { $0["id"] == .string(plain.id) })
        #expect(bare["capturedAt"] == nil && bare["latitude"] == nil && bare["longitude"] == nil, "bez metadanych pól nie ma — schemat dopuszcza brak")

        let target = try setup()
        let summary = try await restore(target, file)
        let back = try #require(try await target.store.get(.attachment, id: withMetadata.id)?.record(as: LocalAttachment.self))
        #expect(back.capturedAt == withMetadata.capturedAt)
        #expect(back.latitude.map(DecimalText.text) == "52.2297000")
        #expect(back.longitude.map(DecimalText.text) == "21.0122000")
        #expect(try await target.store.get(.attachment, id: plain.id)?.record(as: LocalAttachment.self) == plain)
        #expect(summary.attachmentsWithFiles == [withMetadata.id, plain.id])
    }

    @Test func aRecordingInTheTrashKeepsItsTrackAndStaysInTheTrash() async throws {
        let source = try setup()
        try await withRides(source)
        let recording = try contractRecording()
        let trashed = try StoredRecord.of(
            recording.toRecord(horseId: horseId, trainingDate: trainingDate), syncState: .local, deletedAt: stamp, deletionBatchId: "kosz-treningu"
        )
        try await source.store.write { access in try access.upsert([trashed]) }
        let (file, result) = try await backup(source)

        let export = try ExportDocument.parse(try #require(try entries(file)[BackupManifest.exportName]))
        let target = try setup()
        _ = try await restore(target, file)

        #expect(export.records(of: .trainingRecording).isEmpty, "kosz nie jest w eksporcie")
        #expect(result.manifest.counts.trash == 1)
        #expect(try await image(target.store) == image(source.store))
        #expect(try await target.store.track(recordingId: recording.id)?.data == makeTrack(recording).data)
    }

    @Test func aRecordingWithoutALocalTrackIsWrittenWithAnEmptyTrackDataAndRestoredWithoutATrack() async throws {
        let source = try setup()
        try await withRides(source)
        let recording = try contractRecording()
        try await source.store.deleteTrack(recordingId: recording.id)
        let (file, _) = try await backup(source)

        let export = try #require(try entries(file)[BackupManifest.exportName])
        #expect(try JSONValue.parseKeepingScale(export)["data"]?["trainingRecordings"]?.arrayValue?.first?["trackData"] == .string(""))
        let target = try setup()
        _ = try await restore(target, file)

        #expect(try await target.store.get(.trainingRecording, id: recording.id) != nil)
        #expect(try await target.store.track(recordingId: recording.id) == nil)
    }

    // MARK: Zgodność wstecz i nowszy format

    /// Kopia 2.x z Androida 2.0.1: format 2, schemat 1.5, manifest bez `dataSchemaVersion`, bez jazd.
    private var backup2x: URL { resource("backup/android-2.0.1.zkkopia") }

    @Test func backup2xWithoutRidesRestores() async throws {
        let target = try setup()
        _ = try await restore(target, backup2x)

        #expect(try await target.store.count(.horse) > 0)
        #expect(try await target.store.count(.trainingRecording, includeDeleted: true) == 0)
        #expect(try await target.store.count(.horseRideProfile, includeDeleted: true) == 0)
        #expect(try await target.store.count(.rideDefaults, includeDeleted: true) == 0)
    }

    @Test func format2ManifestWithoutDataSchemaVersionIsRead() throws {
        let raw = try JSONValue.parse(try #require(try entries(backup2x)[BackupManifest.manifestName]))
        #expect(raw["dataSchemaVersion"] == nil, "kopia 2.x nie zna pola dataSchemaVersion")

        let manifest = try setup().service.inspect(backup2x, password: nil)

        #expect(manifest.formatVersion == 2)
        #expect(manifest.exportSchemaVersion == "1.5")
        #expect(manifest.dataSchemaVersion == "2.0", "brak pola = dane sprzed jazd")
    }

    @Test func backupNewerThan3IsRefused() async throws {
        let source = try setup()
        try await withRides(source)
        let (file, _) = try await backup(source)
        var parts = try entries(file)
        var manifest = try JSONValue.parse(try #require(parts[BackupManifest.manifestName]))
        if case var .object(fields) = manifest {
            fields["formatVersion"] = .number(4)
            manifest = .object(fields)
        }
        parts[BackupManifest.manifestName] = try manifest.data()
        let newer = try zip(parts, at: source.root.appendingPathComponent("nowsza.zkkopia"))

        let target = try setup()
        #expect(throws: BackupError.newerVersion(4)) { _ = try target.service.inspect(newer, password: nil) }
        #expect(throws: BackupError.newerVersion(4)) { _ = try target.service.prepare(newer, password: nil) }
        #expect(BackupError.newerVersion(4).errorDescription == "Kopia z nowszej wersji aplikacji (format 4) — zaktualizuj aplikację.")
    }

    // MARK: Kopia z Androida 3.0.2

    /// `backup-3/android-3.0.2.zkkopia` zapisał `BackupWriter` Androida 3.0.2 (dwie jazdy z trasami `zk-track/1`, statystyki policzone przez
    /// `RideStatsCalculator`, profil konia, ustawienia jazd, załącznik z miejscem i czasem); `expected-stats.json` to jego oczekiwane wartości.
    @Test func androidBackupWithRidesRestoresIdentically() async throws {
        let file = resource("backup-3/android-3.0.2.zkkopia")
        let expected = try JSONValue.parseKeepingScale(Data(contentsOf: resource("backup-3/expected-stats.json")))
        let target = try setup()

        let manifest = try target.service.inspect(file, password: nil)
        let wanted = try #require(expected["manifest"])
        #expect(manifest.formatVersion == wanted["formatVersion"]?.intValue)
        #expect(manifest.exportSchemaVersion == wanted["exportSchemaVersion"]?.stringValue)
        #expect(manifest.dataSchemaVersion == wanted["dataSchemaVersion"]?.stringValue)
        #expect(manifest.appVersion == wanted["appVersion"]?.stringValue)
        let counts = try #require(wanted["counts"])
        #expect(manifest.counts == BackupCounts(
            horses: counts["horses"]?.intValue ?? -1, entries: counts["entries"]?.intValue ?? -1,
            attachments: counts["attachments"]?.intValue ?? -1, trash: counts["trash"]?.intValue ?? -1
        ))

        let summary = try await restore(target, file)

        // Nagrania: rekord ze statystykami i odcinkami jak w Androidzie (liczby po wartości), koń i data z treningu, trasa bajt w bajt.
        let recordings = try #require(expected["recordings"]?.arrayValue)
        #expect(recordings.count == 2)
        #expect(try await target.store.count(.trainingRecording) == recordings.count)
        #expect(try await target.store.count(.training) == 2)
        for item in recordings {
            let want = try Recording(json: try #require(item["recording"]))
            let stored = try #require(try await target.store.get(.trainingRecording, id: want.id)?.record(as: LocalTrainingRecording.self))
            #expect(stored.recording == want, "nagranie \(want.id)")
            #expect(stored.recording.toJSON().textKeepingScale() == want.toJSON().textKeepingScale(), "nagranie \(want.id) ze skalą liczb")
            #expect(stored.recording.segments == want.segments)
            #expect(stored.horseId == item["horseId"]?.stringValue)
            #expect(stored.trainingDate.description == item["trainingDate"]?.stringValue)
            let track = try #require(try await target.store.track(recordingId: want.id))
            #expect(track.data.count == item["trackBytes"]?.intValue)
            #expect(BackupService.sha256(track.data) == item["trackSha256"]?.stringValue)
            #expect(track.format == want.trackFormat)
            #expect(track.version == want.version)
        }

        // Profil konia: wartości z pliku, wersja i czasy konia (profil nie ma własnej wersji).
        for item in try #require(expected["horseRideProfiles"]?.arrayValue) {
            guard case var .object(fields) = item, let owner = fields.removeValue(forKey: "horseId")?.stringValue else {
                Issue.record("profil bez konia w expected-stats.json")
                continue
            }
            let want = try RideProfile(json: .object(fields))
            let stored = try #require(try await target.store.get(.horseRideProfile, id: owner)?.record(as: LocalHorseRideProfile.self))
            #expect(stored.profile.toJSON().textKeepingScale() == want.toJSON().textKeepingScale())
            let horse = try #require(try await target.store.get(.horse, id: owner)?.record(as: LocalHorse.self))
            #expect(stored.version == horse.version)
        }

        // Ustawienia jazd.
        let wantDefaults = try RideDefaults(json: try #require(expected["rideDefaults"]))
        let storedDefaults = try #require(try await target.store.get(.rideDefaults, id: LocalRideDefaults.ID)?.record(as: LocalRideDefaults.self))
        #expect(storedDefaults.defaults.toJSON().textKeepingScale() == wantDefaults.toJSON().textKeepingScale())

        // Załącznik z czasem i miejscem wykonania oraz plikiem.
        for item in try #require(expected["attachments"]?.arrayValue) {
            let id = try #require(item["id"]?.stringValue)
            let stored = try #require(try await target.store.get(.attachment, id: id)?.record(as: LocalAttachment.self))
            let capturedText = item["capturedAt"]?.stringValue
            #expect(stored.sha256 == item["sha256"]?.stringValue)
            #expect(stored.capturedAt == capturedText.flatMap { InstantText.parse($0) })
            // `expected-stats.json` serializuje rekord Androida wprost (`52.2297000`), a `export.json` tego samego pliku niesie
            // `52.2297` — iOS przyjmuje skalę z `export.json` (porównanie ze skalą z plikiem Androida — niżej); tu wartość.
            #expect(stored.latitude == item["latitude"]?.decimalValue)
            #expect(stored.longitude == item["longitude"]?.decimalValue)
            #expect(summary.attachmentsWithFiles.contains(id))
            let info = try #require(try await target.store.read { try $0.file(attachmentId: id, kind: .original) })
            #expect(try FileDigest.sha256(of: target.files.url(for: info)).hex == item["sha256"]?.stringValue)
        }

        // W drugą stronę: kopia iOS z odtworzonych danych niesie te same jazdy i załączniki co plik Androida i spełnia schemat 1.6.
        let android = try JSONValue.parseKeepingScale(try #require(try entries(file)[BackupManifest.exportName]))
        let (again, _) = try await backup(target)
        let iosExport = try #require(try entries(again)[BackupManifest.exportName])
        let errors = try schemaErrors(iosExport)
        #expect(errors.isEmpty, "\(Array(errors.prefix(5)))")
        let ios = try JSONValue.parseKeepingScale(iosExport)
        for collection in ["trainingRecordings", "horseRideProfiles", "attachments"] {
            let mine = Self.byId(ios["data"]?[collection]?.arrayValue ?? [])
            let theirs = Self.byId(android["data"]?[collection]?.arrayValue ?? [])
            #expect(!theirs.isEmpty, "\(collection) w pliku Androida")
            #expect(mine.mapValues { $0.textKeepingScale() } == theirs.mapValues { $0.textKeepingScale() }, "\(collection): iOS zapisuje to samo co Android, ze skalą liczb")
        }
        #expect(ios["data"]?["rideDefaults"]?.textKeepingScale() == android["data"]?["rideDefaults"]?.textKeepingScale())
        let iosText = String(decoding: iosExport, as: UTF8.self)
        for fragment in [#""maxSpeedKmh":18.00"#, #""avgSpeedKmh":11.00"#, #""loadPoints":21.0"#, #""weatherPrecipMm":0.0"#, #""gaitWalkMaxKmh":6.5"#, #""latitude":52.2297"#] {
            #expect(iosText.contains(fragment), "kopia iOS zawiera \(fragment) jak plik Androida")
        }
    }

    /// Elementy kolekcji po `id` (profil konia — po `horseId`).
    private static func byId(_ items: [JSONValue]) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for item in items {
            if let key = item["id"]?.stringValue ?? item["horseId"]?.stringValue { result[key] = item }
        }
        return result
    }
}
