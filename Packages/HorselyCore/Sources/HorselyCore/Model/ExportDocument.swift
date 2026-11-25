import Foundation

/// Zakres eksportu (`scope`): pełny albo jednego konia; `includesAttachmentFiles` — czy plik zawiera treść załączników.
public struct ExportScope: Codable, Hashable, Sendable {
    public var type: String
    public var horseId: String?
    public var from: LocalDate?
    public var to: LocalDate?
    public var includesAttachmentFiles: Bool
    /// Eksport przyrostowy programu 2.0.0 (schemat 1.5): chwila, od której liczone są zmiany; brak — eksport pełny.
    public var updatedSince: String?
    /// `true`: chwila graniczna jest starsza niż linia bazowa programu — `data` zawiera komplet, klient zastępuje całą kopię.
    public var fullRequired: Bool?
    /// Wartość `updatedSince` do następnego żądania (napis programu, przekazywany bez zmian).
    public var nextUpdatedSince: String?

    public init(
        type: String = "full", horseId: String? = nil, from: LocalDate? = nil, to: LocalDate? = nil, includesAttachmentFiles: Bool = false,
        updatedSince: String? = nil, fullRequired: Bool? = nil, nextUpdatedSince: String? = nil
    ) {
        self.type = type
        self.horseId = horseId
        self.from = from
        self.to = to
        self.includesAttachmentFiles = includesAttachmentFiles
        self.updatedSince = updatedSince
        self.fullRequired = fullRequired
        self.nextUpdatedSince = nextUpdatedSince
    }

    private enum CodingKeys: String, CodingKey {
        case type, horseId, from, to, includesAttachmentFiles, updatedSince, fullRequired, nextUpdatedSince
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "full"
        horseId = try c.decodeIfPresent(String.self, forKey: .horseId)
        from = try c.decodeIfPresent(LocalDate.self, forKey: .from)
        to = try c.decodeIfPresent(LocalDate.self, forKey: .to)
        includesAttachmentFiles = try c.decodeIfPresent(Bool.self, forKey: .includesAttachmentFiles) ?? false
        updatedSince = try c.decodeIfPresent(String.self, forKey: .updatedSince)
        fullRequired = try c.decodeIfPresent(Bool.self, forKey: .fullRequired)
        nextUpdatedSince = try c.decodeIfPresent(String.self, forKey: .nextUpdatedSince)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(horseId, forKey: .horseId)
        try c.encodeIfPresent(from, forKey: .from)
        try c.encodeIfPresent(to, forKey: .to)
        try c.encode(includesAttachmentFiles, forKey: .includesAttachmentFiles)
        try c.encodeIfPresent(updatedSince, forKey: .updatedSince)
        try c.encodeIfPresent(fullRequired, forKey: .fullRequired)
        try c.encodeIfPresent(nextUpdatedSince, forKey: .nextUpdatedSince)
    }
}

/// Nagłówek pliku eksportu (wszystko poza `data`).
public struct ExportHeader: Hashable, Sendable {
    public var schemaVersion: String
    public var exportedAt: String?
    public var appVersion: String?
    public var scope: ExportScope

    public init(schemaVersion: String, exportedAt: String? = nil, appVersion: String? = nil, scope: ExportScope = ExportScope()) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.scope = scope
    }
}

/// Rekord, który w eksporcie przyrostowym opuścił dane (schemat 1.5): przeniesiony do kosza (`trashed[]`) albo usunięty na stałe
/// (`purged[]`). Dla telefonu oba znaczą to samo co nieobecność w pełnym eksporcie.
public struct ExportRemoval: Hashable, Sendable {
    public let type: RecordType
    public let id: String
    public let purged: Bool

    public init(type: RecordType, id: String, purged: Bool) {
        self.type = type
        self.id = id
        self.purged = purged
    }
}

/// Rekord z pliku z datą porządkującą (start bez daty dziedziczy datę zawodów).
public struct ExportedRecord: Sendable {
    public let record: any LocalRecord
    public let dateKey: LocalDate?

    public init(record: any LocalRecord, dateKey: LocalDate?) {
        self.record = record
        self.dateKey = dateKey
    }
}

/// Dokument eksportu w pamięci — testy, kopia zapasowa i małe pliki. Duże pobranie (50 000 rekordów) czyta strumień
/// w zadaniu T083, bez budowania całości.
public struct ExportDocument: Sendable {
    public var header: ExportHeader
    public var records: [ExportedRecord]
    public var removals: [ExportRemoval]
    /// Nazwy typów z `trashed[]` i `purged[]`, których telefon nie zna — pominięte.
    public var unknownRemovalTypes: [String]

    public init(header: ExportHeader, records: [ExportedRecord], removals: [ExportRemoval] = [], unknownRemovalTypes: [String] = []) {
        self.header = header
        self.records = records
        self.removals = removals
        self.unknownRemovalTypes = unknownRemovalTypes
    }

    public var schemaVersion: String { header.schemaVersion }

    public func records(of type: RecordType) -> [any LocalRecord] {
        records.map(\.record).filter { $0.recordType == type }
    }

    // MARK: Odczyt

    public static func parse(_ data: Data) throws -> ExportDocument {
        let file = try JSONDecoder().decode(ReadFile.self, from: data)
        var records: [ExportedRecord] = []
        func add<R: LocalRecord>(_ items: [R]) {
            for item in items { records.append(ExportedRecord(record: item, dateKey: item.dateKey)) }
        }
        let content = file.data
        add(content.dictionaries)
        add(content.contacts)
        add(content.horses)
        add(content.vetVisits)
        add(content.farrierVisits)
        add(content.physioVisits)
        add(content.specialistVisits)
        for envelope in content.competitions {
            records.append(ExportedRecord(record: envelope.competition, dateKey: envelope.competition.dateKey))
            for var start in envelope.starts {
                start.competitionId = envelope.competition.id
                records.append(ExportedRecord(record: start, dateKey: start.startDate ?? envelope.competition.dateFrom))
            }
        }
        add(content.purchases)
        add(content.notes)
        add(content.trainings)
        add(content.reminders)
        add(content.attachments)

        // Zbuduj mapę treningów po trainingId, żeby pobrać horseId i datę dla nagrań.
        var trainingMap: [String: LocalTraining] = [:]
        for t in content.trainings { trainingMap[t.id] = t }

        // Dekoduj nagrania ręcznie z surowego JSON, uzupełniając horseId z treningu.
        let baseDate = LocalDate(year: 2000, month: 1, day: 1)!
        let baseTs = LocalDateTime(date: baseDate, hour: 0, minute: 0, second: 0, nanosecond: 0)
        for rawEnv in content.trainingRecordings {
            guard let training = trainingMap[rawEnv.trainingId] else { continue }
            let recording = LocalTrainingRecording(
                id: rawEnv.recording.id,
                createdAt: rawEnv.recording.createdAt,
                updatedAt: rawEnv.recording.updatedAt,
                version: rawEnv.recording.version,
                horseId: training.horseId,
                trainingDate: LocalDate(rawEnv.trainingDate) ?? training.trainingDate,
                startedAt: rawEnv.recording.startedAt,
                endedAt: rawEnv.recording.endedAt,
                timeZone: rawEnv.recording.timeZone,
                totalSeconds: rawEnv.recording.totalSeconds,
                movingSeconds: rawEnv.recording.movingSeconds,
                stoppedSeconds: rawEnv.recording.stoppedSeconds,
                pausedSeconds: rawEnv.recording.pausedSeconds,
                distanceMeters: rawEnv.recording.distanceMeters,
                avgMovingSpeedKmh: rawEnv.recording.avgMovingSpeedKmh,
                maxSpeedKmh: rawEnv.recording.maxSpeedKmh,
                elevationGainM: rawEnv.recording.elevationGainM,
                elevationLossM: rawEnv.recording.elevationLossM,
                minAltitudeM: rawEnv.recording.minAltitudeM,
                maxAltitudeM: rawEnv.recording.maxAltitudeM,
                walkSeconds: rawEnv.recording.walkSeconds,
                walkMeters: rawEnv.recording.walkMeters,
                trotSeconds: rawEnv.recording.trotSeconds,
                trotMeters: rawEnv.recording.trotMeters,
                canterSeconds: rawEnv.recording.canterSeconds,
                canterMeters: rawEnv.recording.canterMeters,
                walkAvgSpeedKmh: rawEnv.recording.walkAvgSpeedKmh,
                trotAvgSpeedKmh: rawEnv.recording.trotAvgSpeedKmh,
                canterAvgSpeedKmh: rawEnv.recording.canterAvgSpeedKmh,
                walkAvgCadence: rawEnv.recording.walkAvgCadence,
                trotAvgCadence: rawEnv.recording.trotAvgCadence,
                canterAvgCadence: rawEnv.recording.canterAvgCadence,
                canterCount: rawEnv.recording.canterCount,
                longestCanterSeconds: rawEnv.recording.longestCanterSeconds,
                longestCanterMeters: rawEnv.recording.longestCanterMeters,
                loadPoints: rawEnv.recording.loadPoints,
                gaitThresholdsUsed: rawEnv.recording.gaitThresholdsUsed,
                loadParamsUsed: rawEnv.recording.loadParamsUsed,
                accelerometerUsed: rawEnv.recording.accelerometerUsed,
                weatherStatus: rawEnv.recording.weatherStatus,
                weatherTempC: rawEnv.recording.weatherTempC,
                weatherFeelsLikeC: rawEnv.recording.weatherFeelsLikeC,
                weatherPrecipMm: rawEnv.recording.weatherPrecipMm,
                weatherWindKmh: rawEnv.recording.weatherWindKmh,
                weatherHumidityPct: rawEnv.recording.weatherHumidityPct,
                weatherCode: rawEnv.recording.weatherCode,
                trimmedStartSeconds: rawEnv.recording.trimmedStartSeconds,
                trimmedEndSeconds: rawEnv.recording.trimmedEndSeconds,
                algorithmVersion: rawEnv.recording.algorithmVersion,
                source: rawEnv.recording.source,
                trackFormat: rawEnv.recording.trackFormat,
                pointCount: rawEnv.recording.pointCount,
                segments: rawEnv.recording.segments
            )
            let trainingDate = LocalDate(rawEnv.trainingDate) ?? training.trainingDate
            records.append(ExportedRecord(record: recording, dateKey: trainingDate))
        }

        for env in content.horseRideProfiles {
            records.append(ExportedRecord(record: LocalHorseRideProfile(id: env.horseId, createdAt: baseTs, updatedAt: baseTs, version: 0, horseId: env.horseId, profile: env.profile), dateKey: nil))
        }
        if let env = content.rideDefaults {
            records.append(ExportedRecord(record: LocalRideDefaults(id: "rideDefaults", createdAt: baseTs, updatedAt: baseTs, version: 0, profile: env.defaults), dateKey: nil))
        }

        var removals: [ExportRemoval] = []
        var unknown: [String] = []
        for (items, purged) in [(file.trashed, false), (file.purged, true)] {
            for item in items {
                guard let name = item.type, let id = item.id else { continue }
                if let type = RecordType.fromRemovalType(name) {
                    removals.append(ExportRemoval(type: type, id: id, purged: purged))
                } else {
                    unknown.append(name)
                }
            }
        }
        let header = ExportHeader(schemaVersion: file.schemaVersion ?? "1.0", exportedAt: file.exportedAt, appVersion: file.appVersion, scope: file.scope ?? ExportScope())
        return ExportDocument(header: header, records: records, removals: removals, unknownRemovalTypes: unknown)
    }

    public static func parse(_ json: String) throws -> ExportDocument {
        try parse(Data(json.utf8))
    }

    // MARK: Zapis

    /// Tekst w formacie eksportu programu (zawody ze startami zagnieżdżonymi) — wejście kopii zapasowej.
    public func toJSON(pretty: Bool = false) throws -> Data {
        func list<R: LocalRecord>(_ type: RecordType, as _: R.Type) -> [R] {
            records(of: type).compactMap { $0 as? R }
        }
        let starts = Dictionary(grouping: list(.competitionStart, as: LocalCompetitionStart.self), by: \.competitionId)
        let competitions = list(.competition, as: LocalCompetition.self).map { CompetitionEnvelope(competition: $0, starts: starts[$0.id] ?? []) }
        let trainingRecordings = list(.trainingRecording, as: LocalTrainingRecording.self).map { envelope in
            TrainingRecordingEnvelope(recording: envelope, trainingDate: envelope.trainingDate.description)
        }
        let horseRideProfiles = list(.horseRideProfile, as: LocalHorseRideProfile.self).map { envelope in
            HorseRideProfileEnvelope(horseId: envelope.horseId, profile: envelope.profile)
        }
        let rideDefaults = list(.rideDefaults, as: LocalRideDefaults.self).first.map { RideDefaultsEnvelope(defaults: $0.profile) }
        let content = WriteData(
            dictionaries: list(.dictionary, as: LocalDictionaryItem.self),
            contacts: list(.contact, as: LocalContact.self),
            horses: list(.horse, as: LocalHorse.self),
            vetVisits: list(.vetVisit, as: LocalVetVisit.self),
            farrierVisits: list(.farrierVisit, as: LocalFarrierVisit.self),
            physioVisits: list(.physioVisit, as: LocalPhysioVisit.self),
            specialistVisits: list(.specialistVisit, as: LocalSpecialistVisit.self),
            competitions: competitions,
            purchases: list(.purchase, as: LocalPurchase.self),
            notes: list(.note, as: LocalNote.self),
            trainings: list(.training, as: LocalTraining.self),
            reminders: list(.reminder, as: LocalReminder.self),
            attachments: list(.attachment, as: LocalAttachment.self),
            trainingRecordings: trainingRecordings.isEmpty ? nil : trainingRecordings,
            horseRideProfiles: horseRideProfiles.isEmpty ? nil : horseRideProfiles,
            rideDefaults: rideDefaults
        )
        let file = WriteFile(schemaVersion: header.schemaVersion, dataSchemaVersion: BackupManifest.dataSchemaVersion, exportedAt: header.exportedAt, appVersion: header.appVersion, scope: header.scope, data: content)
        return try RecordCodec.makeEncoder(pretty: pretty).encode(file)
    }
}

// MARK: - Kształty pliku

private struct CompetitionEnvelope: Codable {
    let competition: LocalCompetition
    let starts: [LocalCompetitionStart]

    private enum StartsKey: String, CodingKey { case starts }

    init(competition: LocalCompetition, starts: [LocalCompetitionStart]) {
        self.competition = competition
        self.starts = starts
    }

    init(from decoder: Decoder) throws {
        competition = try LocalCompetition(from: decoder)
        let c = try decoder.container(keyedBy: StartsKey.self)
        starts = try c.decodeIfPresent([LocalCompetitionStart].self, forKey: .starts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        try competition.encode(to: encoder)
        var c = encoder.container(keyedBy: StartsKey.self)
        try c.encode(starts, forKey: .starts)
    }
}

private struct ReadData: Decodable {
    var dictionaries: [LocalDictionaryItem] = []
    var contacts: [LocalContact] = []
    var horses: [LocalHorse] = []
    var vetVisits: [LocalVetVisit] = []
    var farrierVisits: [LocalFarrierVisit] = []
    var physioVisits: [LocalPhysioVisit] = []
    var specialistVisits: [LocalSpecialistVisit] = []
    var competitions: [CompetitionEnvelope] = []
    var purchases: [LocalPurchase] = []
    var notes: [LocalNote] = []
    var trainings: [LocalTraining] = []
    var reminders: [LocalReminder] = []
    var attachments: [LocalAttachment] = []
    /// Nagrania jazdy — tylko eksport pełny schematu 1.6.
    var trainingRecordings: [TrainingRecordingEnvelope] = []
    /// Profile jazdy koni — tylko eksport pełny schematu 1.6.
    var horseRideProfiles: [HorseRideProfileEnvelope] = []
    /// Ustawienia domyślne jazd — tylko eksport pełny schematu 1.6.
    var rideDefaults: RideDefaultsEnvelope?

    private enum CodingKeys: String, CodingKey {
        case dictionaries, contacts, horses, vetVisits, farrierVisits, physioVisits, specialistVisits, competitions, purchases, notes, trainings, reminders, attachments, trainingRecordings, horseRideProfiles, rideDefaults
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dictionaries = try c.decodeIfPresent([LocalDictionaryItem].self, forKey: .dictionaries) ?? []
        contacts = try c.decodeIfPresent([LocalContact].self, forKey: .contacts) ?? []
        horses = try c.decodeIfPresent([LocalHorse].self, forKey: .horses) ?? []
        vetVisits = try c.decodeIfPresent([LocalVetVisit].self, forKey: .vetVisits) ?? []
        farrierVisits = try c.decodeIfPresent([LocalFarrierVisit].self, forKey: .farrierVisits) ?? []
        physioVisits = try c.decodeIfPresent([LocalPhysioVisit].self, forKey: .physioVisits) ?? []
        specialistVisits = try c.decodeIfPresent([LocalSpecialistVisit].self, forKey: .specialistVisits) ?? []
        competitions = try c.decodeIfPresent([CompetitionEnvelope].self, forKey: .competitions) ?? []
        purchases = try c.decodeIfPresent([LocalPurchase].self, forKey: .purchases) ?? []
        notes = try c.decodeIfPresent([LocalNote].self, forKey: .notes) ?? []
        trainings = try c.decodeIfPresent([LocalTraining].self, forKey: .trainings) ?? []
        reminders = try c.decodeIfPresent([LocalReminder].self, forKey: .reminders) ?? []
        attachments = try c.decodeIfPresent([LocalAttachment].self, forKey: .attachments) ?? []
        trainingRecordings = try c.decodeIfPresent([TrainingRecordingEnvelope].self, forKey: .trainingRecordings) ?? []
        horseRideProfiles = try c.decodeIfPresent([HorseRideProfileEnvelope].self, forKey: .horseRideProfiles) ?? []
        rideDefaults = try c.decodeIfPresent(RideDefaultsEnvelope.self, forKey: .rideDefaults)
    }
}

private struct RemovalItem: Decodable {
    let type: String?
    let id: String?
}

private struct ReadFile: Decodable {
    let schemaVersion: String?
    let dataSchemaVersion: String?
    let exportedAt: String?
    let appVersion: String?
    let scope: ExportScope?
    let data: ReadData
    let trashed: [RemovalItem]
    let purged: [RemovalItem]

    private enum CodingKeys: String, CodingKey { case schemaVersion, dataSchemaVersion, exportedAt, appVersion, scope, data, trashed, purged }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(String.self, forKey: .schemaVersion)
        dataSchemaVersion = try c.decodeIfPresent(String.self, forKey: .dataSchemaVersion)
        exportedAt = try c.decodeIfPresent(String.self, forKey: .exportedAt)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        scope = try c.decodeIfPresent(ExportScope.self, forKey: .scope)
        data = try c.decode(ReadData.self, forKey: .data)
        trashed = try c.decodeIfPresent([RemovalItem].self, forKey: .trashed) ?? []
        purged = try c.decodeIfPresent([RemovalItem].self, forKey: .purged) ?? []
    }
}

private struct WriteData: Encodable {
    let dictionaries: [LocalDictionaryItem]
    let contacts: [LocalContact]
    let horses: [LocalHorse]
    let vetVisits: [LocalVetVisit]
    let farrierVisits: [LocalFarrierVisit]
    let physioVisits: [LocalPhysioVisit]
    let specialistVisits: [LocalSpecialistVisit]
    let competitions: [CompetitionEnvelope]
    let purchases: [LocalPurchase]
    let notes: [LocalNote]
    let trainings: [LocalTraining]
    let reminders: [LocalReminder]
    let attachments: [LocalAttachment]
    /// Nagrania jazdy — tylko eksport pełny schematu 1.6.
    let trainingRecordings: [TrainingRecordingEnvelope]?
    /// Profile jazdy koni — tylko eksport pełny schematu 1.6.
    let horseRideProfiles: [HorseRideProfileEnvelope]?
    /// Ustawienia domyślne jazd — tylko eksport pełny schematu 1.6.
    let rideDefaults: RideDefaultsEnvelope?
}

private struct WriteFile: Encodable {
    let schemaVersion: String
    let dataSchemaVersion: String
    let exportedAt: String?
    let appVersion: String?
    let scope: ExportScope
    let data: WriteData
}

// MARK: - Obiekty-wrappery dla nowych kolekcji eksportu 1.6

/// Obiekt-wraper dla nagrania w eksporcie — zawiera `LocalTrainingRecording` (bez `trackData`) i `trainingDate`.
private struct TrainingRecordingEnvelope: Codable {
    let recording: LocalTrainingRecording
    let trainingDate: String
    let trainingId: String

    private enum CodingKeys: String, CodingKey {
        case recording, trainingDate, trainingId
    }

    init(recording: LocalTrainingRecording, trainingDate: String) {
        self.recording = recording
        self.trainingDate = trainingDate
        self.trainingId = "placeholder"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let trainingDateStr = try c.decode(String.self, forKey: .trainingDate)
        let dto = try c.decode(RecordingDto.self, forKey: .recording)
        self.trainingId = dto.trainingId
        // Uwaga: RecordingDto nie zawiera horseId — to pochodzi z treningu (ExportDocument.parse uzupełnia).
        // Tutaj używamy placeholdera dla horseId; nadpiszemy go w parse().
        let placeholderHorseId = "placeholder"
        let baseDate = LocalDate(year: 2000, month: 1, day: 1)!
        let baseTs = LocalDateTime(date: baseDate, hour: 0, minute: 0, second: 0, nanosecond: 0)
        let ts = LocalDateTime(dto.createdAt) ?? baseTs
        let trainingDate = LocalDate(trainingDateStr) ?? baseDate
        self.recording = LocalTrainingRecording(
            id: dto.id, createdAt: ts, updatedAt: LocalDateTime(dto.updatedAt) ?? baseTs,
            version: dto.version, horseId: placeholderHorseId, trainingDate: trainingDate,
            startedAt: dto.startedAt, endedAt: dto.endedAt, timeZone: dto.timeZone, totalSeconds: dto.totalSeconds,
            movingSeconds: dto.movingSeconds, stoppedSeconds: dto.stoppedSeconds, pausedSeconds: dto.pausedSeconds,
            distanceMeters: dto.distanceMeters, avgMovingSpeedKmh: dto.avgMovingSpeedKmh, maxSpeedKmh: dto.maxSpeedKmh,
            elevationGainM: dto.elevationGainM, elevationLossM: dto.elevationLossM, minAltitudeM: dto.minAltitudeM,
            maxAltitudeM: dto.maxAltitudeM, walkSeconds: dto.walkSeconds, walkMeters: dto.walkMeters, trotSeconds: dto.trotSeconds,
            trotMeters: dto.trotMeters, canterSeconds: dto.canterSeconds, canterMeters: dto.canterMeters,
            walkAvgSpeedKmh: dto.walkAvgSpeedKmh, trotAvgSpeedKmh: dto.trotAvgSpeedKmh, canterAvgSpeedKmh: dto.canterAvgSpeedKmh,
            walkAvgCadence: dto.walkAvgCadence, trotAvgCadence: dto.trotAvgCadence, canterAvgCadence: dto.canterAvgCadence,
            canterCount: dto.canterCount, longestCanterSeconds: dto.longestCanterSeconds, longestCanterMeters: dto.longestCanterMeters,
            loadPoints: dto.loadPoints, gaitThresholdsUsed: dto.gaitThresholdsUsed, loadParamsUsed: dto.loadParamsUsed,
            accelerometerUsed: dto.accelerometerUsed, weatherStatus: dto.weatherStatus, weatherTempC: dto.weatherTempC,
            weatherFeelsLikeC: dto.weatherFeelsLikeC, weatherPrecipMm: dto.weatherPrecipMm, weatherWindKmh: dto.weatherWindKmh,
            weatherHumidityPct: dto.weatherHumidityPct, weatherCode: dto.weatherCode, trimmedStartSeconds: dto.trimmedStartSeconds,
            trimmedEndSeconds: dto.trimmedEndSeconds, algorithmVersion: dto.algorithmVersion, source: dto.source,
            trackFormat: dto.trackFormat, pointCount: dto.pointCount, segments: dto.segments
        )
        self.trainingDate = trainingDateStr
    }
}

/// Obiekt-wraper dla profilu jazdy konia w eksporcie.
private struct HorseRideProfileEnvelope: Codable {
    let horseId: String
    let profile: RideProfile

    private enum CodingKeys: String, CodingKey {
        case horseId, profile
    }

    init(horseId: String, profile: RideProfile) {
        self.horseId = horseId
        self.profile = profile
    }
}

/// Obiekt-wraper dla ustawień domyślnych jazd w eksporcie.
private struct RideDefaultsEnvelope: Codable {
    let defaults: RideDefaults

    private enum CodingKeys: String, CodingKey {
        case defaults
    }

    init(defaults: RideDefaults) {
        self.defaults = defaults
    }
}
