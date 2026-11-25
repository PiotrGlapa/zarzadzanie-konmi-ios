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

/// Rekord z pliku z datą porządkującą (start bez daty dziedziczy datę zawodów). `track` — punkty trasy nagrania jazdy z `trackData`
/// pliku 1.6 (poza rekordem, decyzja A4); `nil` dla pozostałych rekordów i nagrań bez trasy.
public struct ExportedRecord: Sendable {
    public let record: any LocalRecord
    public let dateKey: LocalDate?
    public let track: StoredTrack?

    public init(record: any LocalRecord, dateKey: LocalDate?, track: StoredTrack? = nil) {
        self.record = record
        self.dateKey = dateKey
        self.track = track
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

    /// Dokument z pliku eksportu. Schemat 1.6 niesie też jazdy: nagranie bez konia i daty (biorą się z treningu o `trainingId`
    /// z tego samego pliku), profil bez wersji (wersja i czasy konia) i `rideDefaults` (obiekt albo `null` = brak). Nagranie bez
    /// treningu i profil konia spoza pliku są pomijane (jak `ExportCursor.kt`).
    /// Plik 1.6 jest dodatkowo czytany raz przez `JSONValue.parseKeepingScale`: nagrania, profile, ustawienia jazd i załączniki
    /// (współrzędne) zachowują skalę liczb jak `BigDecimal` w Androidzie (`18.00`, `52.2297000`).
    /// - Parameter lenientTracks: `true` (pobieranie z programu) — trasa, której nie da się odczytać (zły base64), nie psuje pobrania:
    ///   nagranie wchodzi bez trasy. `false` (odtwarzanie kopii) — uszkodzona trasa to uszkodzony plik (`DecodingError`).
    public static func parse(_ data: Data, lenientTracks: Bool = false) throws -> ExportDocument {
        let file = try JSONDecoder().decode(ReadFile.self, from: data)
        var scaledData: JSONValue?
        if RideExport.supportsRides(file.schemaVersion ?? "1.0") { scaledData = try JSONValue.parseKeepingScale(data)["data"] }
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
        if let scaledData {
            // Załączniki 1.6 ze skalą współrzędnych (ten sam rekord, czytany z tekstu z zachowaną skalą).
            add(try (scaledData["attachments"]?.arrayValue ?? []).map { try LocalAttachment(scaledJSON: $0) })
            records += try RideExport.read(scaledData, trainings: content.trainings, horses: content.horses, lenientTracks: lenientTracks)
        } else {
            add(content.attachments)
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

    public static func parse(_ json: String, lenientTracks: Bool = false) throws -> ExportDocument {
        try parse(Data(json.utf8), lenientTracks: lenientTracks)
    }

    // MARK: Zapis

    /// Tekst w formacie eksportu programu (zawody ze startami zagnieżdżonymi) — wejście kopii zapasowej. Dokument schematu 1.6 niesie
    /// też jazdy: `trainingRecordings[]` (z `trackData` w base64 z `ExportedRecord.track`), `horseRideProfiles[]` i `rideDefaults`
    /// (obiekt albo `null`); schemat 1.5 ich nie zna (`additionalProperties: false`), więc ich nie dostaje. Liczby jazd i współrzędne
    /// załączników zachowują skalę: plik jest składany jako `JSONValue` i zapisywany `textKeepingScale()` (klucze w porządku
    /// alfabetycznym, jak dotąd `sortedKeys`).
    public func toJSON() throws -> Data {
        func list<R: LocalRecord>(_ type: RecordType, as _: R.Type) -> [R] {
            records(of: type).compactMap { $0 as? R }
        }
        let starts = Dictionary(grouping: list(.competitionStart, as: LocalCompetitionStart.self), by: \.competitionId)
        let competitions = list(.competition, as: LocalCompetition.self).map { CompetitionEnvelope(competition: $0, starts: starts[$0.id] ?? []) }
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
            attachments: list(.attachment, as: LocalAttachment.self)
        )
        let file = WriteFile(schemaVersion: header.schemaVersion, exportedAt: header.exportedAt, appVersion: header.appVersion, scope: header.scope, data: content)
        guard case var .object(root) = try JSONValue.parseKeepingScale(RecordCodec.makeEncoder().encode(file)), case var .object(data)? = root["data"] else {
            throw EncodingError.invalidValue(file.schemaVersion, .init(codingPath: [], debugDescription: "Plik eksportu bez obiektu data"))
        }
        data["attachments"] = .array(list(.attachment, as: LocalAttachment.self).map { $0.scaledJSON() })
        if RideExport.supportsRides(header.schemaVersion) {
            data[RideExport.recordingsKey] = .array(records.compactMap { exported in
                (exported.record as? LocalTrainingRecording).map { RideExport.recording($0, track: exported.track) }
            })
            data[RideExport.profilesKey] = .array(list(.horseRideProfile, as: LocalHorseRideProfile.self).compactMap(RideExport.profile))
            data[RideExport.defaultsKey] = RideExport.defaults(list(.rideDefaults, as: LocalRideDefaults.self).first)
        }
        root["data"] = .object(data)
        return Data(JSONValue.object(root).textKeepingScale().utf8)
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
    /// Plik 1.6 czyta załączniki i jazdy (`trainingRecordings`, `horseRideProfiles`, `rideDefaults`) ze skalą liczb — `ExportDocument.parse`.
    var attachments: [LocalAttachment] = []

    private enum CodingKeys: String, CodingKey {
        case dictionaries, contacts, horses, vetVisits, farrierVisits, physioVisits, specialistVisits, competitions, purchases, notes, trainings, reminders, attachments
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
    }
}

private struct RemovalItem: Decodable {
    let type: String?
    let id: String?
}

private struct ReadFile: Decodable {
    let schemaVersion: String?
    let exportedAt: String?
    let appVersion: String?
    let scope: ExportScope?
    let data: ReadData
    let trashed: [RemovalItem]
    let purged: [RemovalItem]

    private enum CodingKeys: String, CodingKey { case schemaVersion, exportedAt, appVersion, scope, data, trashed, purged }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(String.self, forKey: .schemaVersion)
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
    /// Zastępowane w `toJSON` treścią ze skalą współrzędnych (`LocalAttachment.scaledJSON`).
    let attachments: [LocalAttachment]
}

private struct WriteFile: Encodable {
    let schemaVersion: String
    let exportedAt: String?
    let appVersion: String?
    let scope: ExportScope
    let data: WriteData
}

// MARK: - Jazdy w pliku 1.6

/// Kształt jazd w pliku eksportu 1.6 (kontrakt serwera [K] 9, `export-schema-1.6.json`; `RideExport.kt` Androida 3.0.2). W pliku nagranie
/// jest jak `RecordingDto` z `trackData` w base64 (bez konia i daty — wynikają z treningu), profil konia to `{horseId, <9 pól>}`
/// z jawnymi `null`, a `rideDefaults` to obiekt albo `null`.
enum RideExport {
    static let trackDataKey = "trackData"
    static let recordingsKey = "trainingRecordings"
    static let profilesKey = "horseRideProfiles"
    static let defaultsKey = "rideDefaults"

    /// Czy plik o tym schemacie niesie jazdy (od 1.6).
    static func supportsRides(_ schemaVersion: String) -> Bool {
        let parts = schemaVersion.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return false }
        let numbers = parts.compactMap { $0 }
        let major = numbers[0]
        let minor = numbers.count > 1 ? numbers[1] : 0
        return major > 1 || (major == 1 && minor >= 6)
    }

    // MARK: Zapis

    /// Nagranie do pliku: treść rekordu i `trackData` z `track` w base64. Brak trasy w telefonie daje pusty `trackData` — pole jest
    /// w schemacie wymagane, a odczyt traktuje pusty napis jako „bez trasy”.
    static func recording(_ record: LocalTrainingRecording, track: StoredTrack?) -> JSONValue {
        record.toApi(trackData: track?.data.base64EncodedString() ?? "").toJSON()
    }

    /// Profil konia do pliku (dziewięć pól, wszystkie wymagane w schemacie; `null` = dziedziczy z ustawień domyślnych); `nil`, gdy koń
    /// nie ma żadnej własnej wartości (taki profil nie jest zapisywany).
    static func profile(_ record: LocalHorseRideProfile) -> JSONValue? {
        let profile = record.profile
        guard !profile.isEmpty else { return nil }
        let decimals: [(String, Decimal?)] = [
            ("gaitStopMaxKmh", profile.gaitStopMaxKmh), ("gaitWalkMaxKmh", profile.gaitWalkMaxKmh), ("gaitTrotMaxKmh", profile.gaitTrotMaxKmh),
            ("loadWeightWalk", profile.loadWeightWalk), ("loadWeightTrot", profile.loadWeightTrot), ("loadWeightCanter", profile.loadWeightCanter),
            ("loadClimbPer10m", profile.loadClimbPer10m),
        ]
        let ints: [(String, Int?)] = [("loadWarnPercent", profile.loadWarnPercent), ("heavyRidePoints", profile.heavyRidePoints)]
        var fields: [String: JSONValue] = ["horseId": .string(record.horseId)]
        for (name, value) in decimals {
            if let value { fields[name] = .number(value) } else { fields[name] = .null }
        }
        for (name, value) in ints {
            if let value { fields[name] = .number(Decimal(value)) } else { fields[name] = .null }
        }
        return .object(fields)
    }

    /// Ustawienia domyślne do pliku (ze skalą liczb); `.null`, gdy ich brak albo jeszcze nie zapisane (wersja 0 — wartości wbudowane).
    static func defaults(_ record: LocalRideDefaults?) -> JSONValue {
        guard let record, record.defaults.version > 0 else { return .null }
        return record.defaults.toJSON()
    }

    // MARK: Odczyt

    /// Nagrania, profile i ustawienia jazd z `data` pliku (czytanego ze skalą liczb): koń i data nagrania z treningu o `trainingId`,
    /// wersja i czasy profilu z konia.
    static func read(_ data: JSONValue, trainings trainingList: [LocalTraining], horses horseList: [LocalHorse], lenientTracks: Bool) throws -> [ExportedRecord] {
        var trainings: [String: LocalTraining] = [:]
        for training in trainingList { trainings[training.id] = training }
        var horses: [String: LocalHorse] = [:]
        for horse in horseList { horses[horse.id] = horse }

        var records: [ExportedRecord] = []
        for json in data[recordingsKey]?.arrayValue ?? [] {
            guard case var .object(fields) = json, let trainingId = fields["trainingId"]?.stringValue, let training = trainings[trainingId] else { continue }
            let text = fields.removeValue(forKey: trackDataKey)?.stringValue ?? ""
            var bytes: Data?
            if !text.isEmpty {
                bytes = Data(base64Encoded: text)
                if bytes == nil, !lenientTracks {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Nagranie treningu \(trainingId): trackData nie jest w base64"))
                }
            }
            guard let local = ApiRecordMapping.decodeRecording(.object(fields), horseId: training.horseId, trainingDate: training.trainingDate) else { continue }
            let track = bytes.map { StoredTrack(recordingId: local.id, version: local.version, format: local.recording.trackFormat, data: $0) }
            records.append(ExportedRecord(record: local, dateKey: local.dateKey, track: track))
        }
        for json in data[profilesKey]?.arrayValue ?? [] {
            guard case var .object(fields) = json, let horseId = fields.removeValue(forKey: "horseId")?.stringValue, let horse = horses[horseId] else { continue }
            let profile = try RideProfile(json: .object(fields))
            guard !profile.isEmpty else { continue }
            let record = LocalHorseRideProfile(horseId: horseId, profile: profile, createdAt: horse.createdAt, updatedAt: horse.updatedAt, version: horse.version)
            records.append(ExportedRecord(record: record, dateKey: nil))
        }
        // `rideDefaults`: obiekt ustawień; `null` (albo nieprawidłowa treść) — „brak w pliku”.
        if let json = data[defaultsKey], case .object = json, let defaults = try? RideDefaults(json: json) {
            records.append(ExportedRecord(record: defaults.toRecord(), dateKey: nil))
        }
        return records
    }
}
