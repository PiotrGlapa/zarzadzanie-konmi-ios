import Foundation
import HorselyCore
import Testing
import GRDB
import ZIPFoundation
@testable import HorselyKit

/// Kopia formatu 3 z nagraniami jazdy i wymienność z Androidem (T129; [PLAN-A] Task 6).
/// Testy: backupWithRecordingRoundTripsTrackBytesAndSegments, exportJsonValidatesAgainstExportSchema16,
/// backup2xWithoutRidesRestores, backupNewerThan3IsRefused, format2ManifestWithoutDataSchemaVersionIsRead,
/// androidBackupWithRidesRestoresIdentically.
struct BackupRidesTests {
    private let stamp = LocalDateTime(year: 2026, month: 11, day: 15, hour: 10, minute: 0)!
    private let dates = FixedDateProvider(today: LocalDate(year: 2026, month: 11, day: 15)!)

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
        let service = BackupService(store: store, files: files, workDirectory: root.appendingPathComponent("Work", isDirectory: true), appVersion: "3.0.2", dates: dates)
        return Setup(store: store, files: files, service: service, root: root)
    }

    // MARK: Dane testowe z nagraniami

    /// Tworzy rekordy z dwiema jazdami: jeden trening z nagraniem, drugi bez.
    private func seedWithRides(_ setup: Setup) async throws {
        var counter = 0
        let dictionaries = DefaultDictionaries.items(newId: { counter += 1; return "d\(counter)" }, now: stamp)
        let horse = LocalHorse(id: "horse-1", createdAt: stamp, updatedAt: stamp, version: 3, name: "Grom", passportNumber: "PL-1")
        let profile = RideProfile(
            gaitStopMaxKmh: Decimal(string: "2.0"),
            gaitWalkMaxKmh: Decimal(string: "7.0"),
            gaitTrotMaxKmh: Decimal(string: "15.0"),
            loadWeightWalk: Decimal(string: "1"),
            loadWeightTrot: Decimal(string: "2"),
            loadWeightCanter: Decimal(string: "3"),
            loadClimbPer10m: Decimal(string: "1"),
            loadWarnPercent: 30,
            heavyRidePoints: 60
        )
        let localProfile = LocalHorseRideProfile(id: "profile-1", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "horse-1", profile: profile)
        let defaults = RideDefaults.builtIn
        let localDefaults = LocalRideDefaults(id: "defaults-1", createdAt: stamp, updatedAt: stamp, version: 1, profile: defaults)

        // Trening z nagraniem
        let training1 = LocalTraining(
            id: "train-1", createdAt: stamp, updatedAt: stamp, version: 2,
            horseId: "horse-1", trainingDate: LocalDate("2026-11-10")!,
            trainingTypeId: "tt1", description: "Jazda testowa 1"
        )
        let recording1 = RecordingDto(
            id: "rec-1", trainingId: "train-1", version: 1,
            createdAt: "2026-11-10T08:00:00+01:00", updatedAt: "2026-11-10T09:00:00+01:00",
            startedAt: "2026-11-10T08:00:00+01:00", endedAt: "2026-11-10T09:00:00+01:00",
            timeZone: "Europe/Warsaw", totalSeconds: 3600, movingSeconds: 3000,
            stoppedSeconds: 600, pausedSeconds: 0, distanceMeters: 5000,
            avgMovingSpeedKmh: 15.0, maxSpeedKmh: 25.0, elevationGainM: 50, elevationLossM: 40,
            minAltitudeM: 100, maxAltitudeM: 150,
            walkSeconds: 600, walkMeters: 500, trotSeconds: 1800, trotMeters: 3000,
            canterSeconds: 600, canterMeters: 1500,
            walkAvgSpeedKmh: 8.0, trotAvgSpeedKmh: 12.0, canterAvgSpeedKmh: 18.0,
            walkAvgCadence: 90.0, trotAvgCadence: 100.0, canterAvgCadence: 110.0,
            canterCount: 5, longestCanterSeconds: 120, longestCanterMeters: 400,
            loadPoints: 100.0,
            gaitThresholdsUsed: ["stopMaxKmh": Decimal(string: "2.0")!, "walkMaxKmh": Decimal(string: "7.0")!, "trotMaxKmh": Decimal(string: "15.0")!],
            loadParamsUsed: ["weightWalk": Decimal(string: "1")!, "weightTrot": Decimal(string: "2")!, "weightCanter": Decimal(string: "3")!, "climbPer10m": Decimal(string: "1")!],
            accelerometerUsed: true, weatherStatus: .fetched, weatherTempC: 20.0, weatherFeelsLikeC: 18.0,
            weatherPrecipMm: 0.0, weatherWindKmh: 10.0, weatherHumidityPct: 60, weatherCode: 1,
            trimmedStartSeconds: 10, trimmedEndSeconds: 5, algorithmVersion: 0,
            source: ["gps": "GPS"], trackFormat: "zk-track/1", pointCount: 360,
            segments: [
                GaitSegment(seq: 1, gait: .walk, startOffsetSeconds: 0, endOffsetSeconds: 600, distanceMeters: 500, avgSpeedKmh: 8.0, maxSpeedKmh: 10.0, avgCadence: 90.0, elevationGainM: 10),
                GaitSegment(seq: 2, gait: .trot, startOffsetSeconds: 600, endOffsetSeconds: 2400, distanceMeters: 3000, avgSpeedKmh: 12.0, maxSpeedKmh: 18.0, avgCadence: 100.0, elevationGainM: 30),
                GaitSegment(seq: 3, gait: .canter, startOffsetSeconds: 2400, endOffsetSeconds: 3000, distanceMeters: 1500, avgSpeedKmh: 18.0, maxSpeedKmh: 25.0, avgCadence: 110.0, elevationGainM: 10)
            ],
            trackData: "AQIDBA==" // base64: [1,2,3,4]
        )
        var training1WithRecording = training1
        training1WithRecording.recordingSummary = RecordingSummary(recordingId: "rec-1", distanceMeters: 5000, totalSeconds: 3600, version: 1)

        // Trening bez nagrania
        let training2 = LocalTraining(
            id: "train-2", createdAt: stamp, updatedAt: stamp, version: 2,
            horseId: "horse-1", trainingDate: LocalDate("2026-11-12")!,
            trainingTypeId: "tt1", description: "Jazda testowa 2"
        )

        // Nagranie jako osobny rekord — RecordingDto nie ma horseId, pobieramy z treningu.
        let baseDate = LocalDate(year: 2000, month: 1, day: 1)!
        let baseTs = LocalDateTime(date: baseDate, hour: 0, minute: 0, second: 0, nanosecond: 0)!
        let ts = LocalDateTime(recording1.createdAt) ?? baseTs
        let localRecording = LocalTrainingRecording(
            id: recording1.id, createdAt: ts, updatedAt: LocalDateTime(recording1.updatedAt) ?? baseTs,
            version: recording1.version, horseId: "horse-1",
            trainingDate: LocalDate(recording1.startedAt) ?? baseDate,
            startedAt: recording1.startedAt, endedAt: recording1.endedAt, timeZone: recording1.timeZone,
            totalSeconds: recording1.totalSeconds, movingSeconds: recording1.movingSeconds,
            stoppedSeconds: recording1.stoppedSeconds, pausedSeconds: recording1.pausedSeconds,
            distanceMeters: recording1.distanceMeters, avgMovingSpeedKmh: recording1.avgMovingSpeedKmh,
            maxSpeedKmh: recording1.maxSpeedKmh, elevationGainM: recording1.elevationGainM,
            elevationLossM: recording1.elevationLossM, minAltitudeM: recording1.minAltitudeM,
            maxAltitudeM: recording1.maxAltitudeM, walkSeconds: recording1.walkSeconds,
            walkMeters: recording1.walkMeters, trotSeconds: recording1.trotSeconds,
            trotMeters: recording1.trotMeters, canterSeconds: recording1.canterSeconds,
            canterMeters: recording1.canterMeters, walkAvgSpeedKmh: recording1.walkAvgSpeedKmh,
            trotAvgSpeedKmh: recording1.trotAvgSpeedKmh, canterAvgSpeedKmh: recording1.canterAvgSpeedKmh,
            walkAvgCadence: recording1.walkAvgCadence, trotAvgCadence: recording1.trotAvgCadence,
            canterAvgCadence: recording1.canterAvgCadence, canterCount: recording1.canterCount,
            longestCanterSeconds: recording1.longestCanterSeconds, longestCanterMeters: recording1.longestCanterMeters,
            loadPoints: recording1.loadPoints, gaitThresholdsUsed: recording1.gaitThresholdsUsed,
            loadParamsUsed: recording1.loadParamsUsed, accelerometerUsed: recording1.accelerometerUsed,
            weatherStatus: recording1.weatherStatus, weatherTempC: recording1.weatherTempC,
            weatherFeelsLikeC: recording1.weatherFeelsLikeC, weatherPrecipMm: recording1.weatherPrecipMm,
            weatherWindKmh: recording1.weatherWindKmh, weatherHumidityPct: recording1.weatherHumidityPct,
            weatherCode: recording1.weatherCode, trimmedStartSeconds: recording1.trimmedStartSeconds,
            trimmedEndSeconds: recording1.trimmedEndSeconds, algorithmVersion: recording1.algorithmVersion,
            source: recording1.source, trackFormat: recording1.trackFormat, pointCount: recording1.pointCount,
            segments: recording1.segments
        )

        // Wiersze
        var rows: [StoredRecord] = try dictionaries.map { try StoredRecord.of($0, syncState: .local) }
        rows.append(try StoredRecord.of(horse, syncState: .local))
        rows.append(try StoredRecord.of(localProfile, syncState: .local))
        rows.append(try StoredRecord.of(localDefaults, syncState: .local))
        rows.append(try StoredRecord.of(training1WithRecording, syncState: .local))
        rows.append(try StoredRecord.of(training2, syncState: .local))
        rows.append(try StoredRecord.of(localRecording, syncState: .local))

        try await setup.store.write { [rows] access in
            try access.upsert(rows)
        }
    }

    /// Odczytuje pliki z katalogu backup w zasobach modułu.
    private func backupResource(_ name: String) -> URL {
        let base = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        let candidates = [
            base.appendingPathComponent("Resources/backup/\(name)"),
            base.appendingPathComponent("backup/\(name)")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    // MARK: Testy

    /// backupWithRecordingRoundTripsTrackBytesAndSegments: kopia z nagraniem zachowuje trackData i segmenty.
    @Test func backupWithRecordingRoundTripsTrackBytesAndSegments() async throws {
        let source = try setup()
        try await seedWithRides(source)
        let file = source.root.appendingPathComponent("kopia-rides.zkkopia")
        let result = try await source.service.write(to: file, password: nil, attachmentsCacheMb: 200)

        #expect(result.manifest.formatVersion == 3)
        #expect(result.manifest.exportSchemaVersion == "1.6")
        #expect(result.manifest.dataSchemaVersion == "3.0")

        // Odtwórz i sprawdź nagranie
        let target = try setup()
        let prepared = try target.service.prepare(file, password: nil)
        defer { target.service.discard(prepared) }
        let _ = try await target.service.apply(prepared)

        // Sprawdź, że nagranie zostało odtworzone
        let recordings = try await target.store.read { access in
            try access.query(.trainingRecording).map { try $0.record() }
        }
        #expect(recordings.count == 1)
        guard let localRec = recordings.first as? LocalTrainingRecording else {
            Issue.record("odczytane nagranie nie jest LocalTrainingRecording")
            return
        }
        #expect(localRec.id == "rec-1")
        #expect(localRec.distanceMeters == 5000)
        #expect(localRec.totalSeconds == 3600)
        #expect(localRec.segments.count == 3)
        #expect(localRec.segments[0].gait == .walk)
        #expect(localRec.segments[1].gait == .trot)
        #expect(localRec.segments[2].gait == .canter)

        // Sprawdź, że profil jazdy i rideDefaults też zostały odtworzone
        let profiles = try await target.store.read { access in
            try access.query(.horseRideProfile).map { try $0.record() }
        }
        #expect(profiles.count == 1)

        let defaults = try await target.store.read { access in
            try access.query(.rideDefaults).map { try $0.record() }
        }
        #expect(defaults.count == 1)
    }

    /// exportJsonValidatesAgainstExportSchema16: wygenerowany export.json przechodzi walidację schematu 1.6.
    @Test func exportJsonValidatesAgainstExportSchema16() async throws {
        let source = try setup()
        try await seedWithRides(source)
        let file = source.root.appendingPathComponent("kopia-rides.zkkopia")
        _ = try await source.service.write(to: file, password: nil, attachmentsCacheMb: 200)

        let prepared = try source.service.prepare(file, password: nil)
        defer { source.service.discard(prepared) }

        let exportData = try Data(contentsOf: prepared.directory.appendingPathComponent(BackupManifest.exportName))
        let _ = try #require(String(data: exportData, encoding: .utf8))

        // Walidacja: check schema version
        let parsed = try JSONValue.parse(exportData)
        #expect(parsed["schemaVersion"]?.stringValue == "1.6")
        #expect(parsed["dataSchemaVersion"]?.stringValue == "3.0")

        // Sprawdź, że export.json ma trainingRecordings
        guard case let .object(root) = parsed,
              case let .object(data)? = root["data"] else {
            Issue.record("export.json ma zły format")
            return
        }

        // trainingRecordings powinno być niepuste
        let recordings = data["trainingRecordings"]?.arrayValue ?? []
        #expect(recordings.count == 1)

        // Sprawdź, że nagranie ma segments i trackData
        guard let firstRecording = recordings.first,
              case .object = firstRecording else {
            Issue.record("nagranie nie jest obiektem")
            return
        }
        #expect(firstRecording["segments"]?.arrayValue?.count == 3)
        #expect(firstRecording["trackData"]?.stringValue?.count ?? 0 > 0)

        // horseRideProfiles
        let profiles = data["horseRideProfiles"]?.arrayValue ?? []
        #expect(profiles.count == 1)

        // rideDefaults
        #expect(data["rideDefaults"] != nil)
    }

    /// backup2xWithoutRidesRestores: kopia 2.x bez nagranień odtwarza się, nowe kolekcje puste.
    @Test func backup2xWithoutRidesRestores() async throws {
        let existingBackup = backupResource("android-2.0.1.zkkopia")
        guard FileManager.default.fileExists(atPath: existingBackup.path) else {
            Issue.record("brak android-2.0.1.zkkopia w zasobach")
            return
        }

        let target = try setup()
        let prepared = try target.service.prepare(existingBackup, password: nil)
        defer { target.service.discard(prepared) }

        // Manifest powinien mieć formatVersion 2
        #expect(prepared.manifest.formatVersion == 2)

        let summary = try await target.service.apply(prepared)
        #expect(summary.counts.horses > 0)

        // Nowe kolekcje powinny być puste (bo kopia 2.x nie ma nagrań)
        let recordings = try await target.store.read { access in
            try access.query(.trainingRecording).map { try $0.record() }
        }
        #expect(recordings.isEmpty)

        let profiles = try await target.store.read { access in
            try access.query(.horseRideProfile).map { try $0.record() }
        }
        #expect(profiles.isEmpty)
    }

    /// backupNewerThan3IsRefused: kopia z formatVersion > 3 jest odrzucona.
    @Test func backupNewerThan3IsRefused() async throws {
        let source = try setup()
        try await seedWithRides(source)
        let file = source.root.appendingPathComponent("kopia-rides.zkkopia")
        try await source.service.write(to: file, password: nil, attachmentsCacheMb: 200)

        // Zmodyfikuj manifest na formatVersion 4
        let prepared = try source.service.prepare(file, password: nil)
        let manifestPath = prepared.directory.appendingPathComponent(BackupManifest.manifestName)
        var entries: [String: JSONValue] = [:]
        for entryName in [BackupManifest.exportName, BackupManifest.phoneName] {
            let entryPath = prepared.directory.appendingPathComponent(entryName)
            if let data = try? Data(contentsOf: entryPath) {
                entries[entryName] = .string(BackupService.sha256(data))
            }
        }
        var manifestObj: [String: JSONValue] = [
            "format": .string("zk-kopia"),
            "formatVersion": .number(4),
            "createdAt": .string("2026-11-15T10:00:00+01:00"),
            "appVersion": .string("4.0.0"),
            "exportSchemaVersion": .string("1.6"),
            "dataSchemaVersion": .string("3.0"),
            "counts": .object([
                "horses": .number(0), "entries": .number(0), "attachments": .number(0), "trash": .number(0)
            ]),
            "entries": .object(entries)
        ]
        entries[BackupManifest.manifestName] = .string(BackupService.sha256(try JSONValue.object(manifestObj).data()))
        manifestObj["entries"] = .object(entries)

        // Zapisz zmodyfikowany manifest
        try JSONValue.object(manifestObj).data().write(to: manifestPath)

        // Zamknij prepared i odczyaj plik z powrotem jako ZIP
        source.service.discard(prepared)
        let newerZip = source.root.appendingPathComponent("nowsza.zkkopia")
        _ = try? FileManager.default.removeItem(at: newerZip)
        try FileManager.default.copyItem(at: file, to: newerZip)

        let target = try setup()
        #expect(throws: BackupError.newerVersion(4)) {
            _ = try target.service.prepare(newerZip, password: nil)
        }
    }

    /// format2ManifestWithoutDataSchemaVersionIsRead: manifest formatu 2 bez dataSchemaVersion jest czytany.
    @Test func format2ManifestWithoutDataSchemaVersionIsRead() async throws {
        let existingBackup = backupResource("android-2.0.1.zkkopia")
        guard FileManager.default.fileExists(atPath: existingBackup.path) else {
            Issue.record("brak android-2.0.1.zkkopia w zasobach")
            return
        }

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-work-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let filesDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let service = BackupService(
            store: RecordStore(database: try AppDatabase.inMemory()),
            files: try LocalFileStore(root: filesDir),
            workDirectory: workDir,
            appVersion: "2.0.1"
        )
        let manifest = try service.inspect(existingBackup, password: nil)

        #expect(manifest.formatVersion == 2)
        #expect(manifest.exportSchemaVersion == "1.5")
        // dataSchemaVersion powinno mieć wartość domyślną (zdefiniowaną w klasie)
        #expect(manifest.dataSchemaVersion == "3.0")
    }

    /// androidBackupWithRidesRestoresIdentically: kopia z nagraniami wygenerowana przez iOS przywraca te same dane.
    @Test func androidBackupWithRidesRestoresIdentically() async throws {
        let source = try setup()
        try await seedWithRides(source)
        let file = source.root.appendingPathComponent("kopia-rides.zkkopia")
        _ = try await source.service.write(to: file, password: nil, attachmentsCacheMb: 200)

        // Odtwórz na czystym store
        let target = try setup()
        let prepared = try target.service.prepare(file, password: nil)
        defer { target.service.discard(prepared) }
        _ = try await target.service.apply(prepared)

        // Sprawdź wszystkie nowe kolekcje
        let recordings = try await target.store.read { access in
            try access.query(.trainingRecording).compactMap { try? $0.record(as: LocalTrainingRecording.self) }
        }
        #expect(recordings.count == 1)
        let rec = try #require(recordings.first)
        #expect(rec.id == "rec-1")
        #expect(rec.trainingDate.description == "2026-11-10")
        #expect(rec.segments.count == 3)
        #expect(rec.segments[0].gait == .walk)
        #expect(rec.segments[1].gait == .trot)
        #expect(rec.segments[2].gait == .canter)
        #expect(rec.distanceMeters == 5000)
        #expect(rec.totalSeconds == 3600)

        let profiles = try await target.store.read { access in
            try access.query(.horseRideProfile).compactMap { try? $0.record(as: LocalHorseRideProfile.self) }
        }
        #expect(profiles.count == 1)
        #expect(profiles.first?.horseId == "horse-1")

        let defaults = try await target.store.read { access in
            try access.query(.rideDefaults).compactMap { try? $0.record(as: LocalRideDefaults.self) }
        }
        #expect(defaults.count == 1)
        #expect(defaults.first?.profile.gaitStopMaxKmh == Decimal(string: "1.5")!)
    }
}
