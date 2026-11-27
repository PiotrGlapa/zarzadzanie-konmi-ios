// Nagranie jazdy treningu (API 3.0, kontrakt serwera `api-v3-recordings.md` 4.1) — port 1:1 z Androida 3.0.2
// (`core/.../ride/TrainingRecording.kt`, rekordy magazynu z `core/.../local/ExportRecords.kt`, mapowanie z `ApiMapping.kt`).
// Nazwy pól są wiążące — to ten sam JSON co `RecordingDto` serwera. Czasy to chwile (UTC, `Z`), liczby dziesiętne zachowują
// skalę z serwera (`24.60`), gdy nagranie czytane jest przez `JSONValue.parseKeepingScale`.

import Foundation

// MARK: - Gait

/// Chód rozpoznany na odcinku jazdy; nazwy jak w kontrakcie (`segments[].gait`).
public enum Gait: String, Codable, Sendable, CaseIterable {
    case stop = "Stop"
    case walk = "Walk"
    case trot = "Trot"
    case canter = "Canter"
}

// MARK: - WeatherStatus

/// Stan pobierania pogody dla jazdy (POG-*); nazwy jak w kontrakcie (`weatherStatus`).
public enum WeatherStatus: String, Codable, Sendable, CaseIterable {
    case none = "None"
    case pending = "Pending"
    case fetched = "Fetched"
    case disabled = "Disabled"
    case failed = "Failed"
}

// MARK: - GaitSegment

/// Odcinek jazdy jednym chodem. `startOffsetSeconds` i `endOffsetSeconds` liczone od startu nagrania, bez pauz; `avgCadence` to `nil`
/// bez akcelerometru. Odcinki są zastępowane w całości przy każdym zapisie nagrania.
public struct GaitSegment: Codable, Hashable, Sendable {
    public var seq: Int
    public var gait: Gait
    public var startOffsetSeconds: Int
    public var endOffsetSeconds: Int
    public var distanceMeters: Int
    public var avgSpeedKmh: Decimal
    public var maxSpeedKmh: Decimal
    public var avgCadence: Decimal?
    public var elevationGainM: Int?

    public init(
        seq: Int,
        gait: Gait,
        startOffsetSeconds: Int,
        endOffsetSeconds: Int,
        distanceMeters: Int,
        avgSpeedKmh: Decimal,
        maxSpeedKmh: Decimal,
        avgCadence: Decimal? = nil,
        elevationGainM: Int? = nil
    ) {
        self.seq = seq
        self.gait = gait
        self.startOffsetSeconds = startOffsetSeconds
        self.endOffsetSeconds = endOffsetSeconds
        self.distanceMeters = distanceMeters
        self.avgSpeedKmh = avgSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.avgCadence = avgCadence
        self.elevationGainM = elevationGainM
    }
}

// MARK: - RecordingSummary

/// Co trening z nagraniem mówi o nim w liście (`recordingSummary` w treningu pod `/api/v3`): dość, by pokazać jazdę i pobrać ją.
public struct RecordingSummary: Codable, Hashable, Sendable {
    public var recordingId: String
    public var distanceMeters: Int
    public var totalSeconds: Int
    public var version: Int

    public init(recordingId: String, distanceMeters: Int, totalSeconds: Int, version: Int) {
        self.recordingId = recordingId
        self.distanceMeters = distanceMeters
        self.totalSeconds = totalSeconds
        self.version = version
    }
}

// MARK: - Recording

/// Nagranie jazdy (`RecordingDto`): wszystkie pola w kolejności z kontraktu, `segments` i na końcu `trackData`.
/// `trackData` (base64 skompresowanych punktów `zk-track/1`) niesie tylko pełny `GET`; w treści rekordu magazynu jest `nil`,
/// bo punkty leżą osobno (magazyn tras, decyzja A4), a zapis na serwer składa je przez `toInput(trackData:)`.
///
/// Nowe, jeszcze niewysłane nagranie ma `version` 0 i czasy `InstantText.epoch` (serwer nadaje je przy utworzeniu).
/// `gaitThresholdsUsed` i `loadParamsUsed` to progi i wagi, z którymi policzono statystyki (kopia z chwili zapisu —
/// zmiana ustawień konia ich nie przelicza); `source` to dowolny obiekt (platforma, urządzenie, wersja aplikacji).
public struct Recording: Codable, Hashable, Sendable {
    public var id: String
    public var trainingId: String
    public var version: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date
    public var endedAt: Date
    public var timeZone: String
    public var totalSeconds: Int
    public var movingSeconds: Int
    public var stoppedSeconds: Int
    public var pausedSeconds: Int
    public var distanceMeters: Int
    public var avgMovingSpeedKmh: Decimal?
    public var maxSpeedKmh: Decimal?
    public var elevationGainM: Int?
    public var elevationLossM: Int?
    public var minAltitudeM: Int?
    public var maxAltitudeM: Int?
    public var walkSeconds: Int
    public var walkMeters: Int
    public var trotSeconds: Int
    public var trotMeters: Int
    public var canterSeconds: Int
    public var canterMeters: Int
    public var walkAvgSpeedKmh: Decimal?
    public var trotAvgSpeedKmh: Decimal?
    public var canterAvgSpeedKmh: Decimal?
    public var walkAvgCadence: Decimal?
    public var trotAvgCadence: Decimal?
    public var canterAvgCadence: Decimal?
    public var canterCount: Int
    public var longestCanterSeconds: Int
    public var longestCanterMeters: Int
    public var loadPoints: Decimal
    public var gaitThresholdsUsed: GaitThresholds
    public var loadParamsUsed: LoadParams
    public var accelerometerUsed: Bool
    public var weatherStatus: WeatherStatus
    public var weatherTempC: Decimal?
    public var weatherFeelsLikeC: Decimal?
    public var weatherPrecipMm: Decimal?
    public var weatherWindKmh: Decimal?
    public var weatherHumidityPct: Int?
    public var weatherCode: Int?
    public var trimmedStartSeconds: Int
    public var trimmedEndSeconds: Int
    public var algorithmVersion: Int
    public var source: [String: JSONValue]
    public var trackFormat: String
    public var pointCount: Int
    public var segments: [GaitSegment]
    public var trackData: String?

    public init(
        id: String,
        trainingId: String,
        version: Int = 0,
        createdAt: Date = InstantText.epoch,
        updatedAt: Date = InstantText.epoch,
        startedAt: Date,
        endedAt: Date,
        timeZone: String,
        totalSeconds: Int,
        movingSeconds: Int,
        stoppedSeconds: Int,
        pausedSeconds: Int,
        distanceMeters: Int,
        avgMovingSpeedKmh: Decimal? = nil,
        maxSpeedKmh: Decimal? = nil,
        elevationGainM: Int? = nil,
        elevationLossM: Int? = nil,
        minAltitudeM: Int? = nil,
        maxAltitudeM: Int? = nil,
        walkSeconds: Int,
        walkMeters: Int,
        trotSeconds: Int,
        trotMeters: Int,
        canterSeconds: Int,
        canterMeters: Int,
        walkAvgSpeedKmh: Decimal? = nil,
        trotAvgSpeedKmh: Decimal? = nil,
        canterAvgSpeedKmh: Decimal? = nil,
        walkAvgCadence: Decimal? = nil,
        trotAvgCadence: Decimal? = nil,
        canterAvgCadence: Decimal? = nil,
        canterCount: Int,
        longestCanterSeconds: Int,
        longestCanterMeters: Int,
        loadPoints: Decimal,
        gaitThresholdsUsed: GaitThresholds,
        loadParamsUsed: LoadParams,
        accelerometerUsed: Bool,
        weatherStatus: WeatherStatus,
        weatherTempC: Decimal? = nil,
        weatherFeelsLikeC: Decimal? = nil,
        weatherPrecipMm: Decimal? = nil,
        weatherWindKmh: Decimal? = nil,
        weatherHumidityPct: Int? = nil,
        weatherCode: Int? = nil,
        trimmedStartSeconds: Int,
        trimmedEndSeconds: Int,
        algorithmVersion: Int,
        source: [String: JSONValue],
        trackFormat: String,
        pointCount: Int,
        segments: [GaitSegment],
        trackData: String? = nil
    ) {
        self.id = id
        self.trainingId = trainingId
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timeZone = timeZone
        self.totalSeconds = totalSeconds
        self.movingSeconds = movingSeconds
        self.stoppedSeconds = stoppedSeconds
        self.pausedSeconds = pausedSeconds
        self.distanceMeters = distanceMeters
        self.avgMovingSpeedKmh = avgMovingSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.elevationGainM = elevationGainM
        self.elevationLossM = elevationLossM
        self.minAltitudeM = minAltitudeM
        self.maxAltitudeM = maxAltitudeM
        self.walkSeconds = walkSeconds
        self.walkMeters = walkMeters
        self.trotSeconds = trotSeconds
        self.trotMeters = trotMeters
        self.canterSeconds = canterSeconds
        self.canterMeters = canterMeters
        self.walkAvgSpeedKmh = walkAvgSpeedKmh
        self.trotAvgSpeedKmh = trotAvgSpeedKmh
        self.canterAvgSpeedKmh = canterAvgSpeedKmh
        self.walkAvgCadence = walkAvgCadence
        self.trotAvgCadence = trotAvgCadence
        self.canterAvgCadence = canterAvgCadence
        self.canterCount = canterCount
        self.longestCanterSeconds = longestCanterSeconds
        self.longestCanterMeters = longestCanterMeters
        self.loadPoints = loadPoints
        self.gaitThresholdsUsed = gaitThresholdsUsed
        self.loadParamsUsed = loadParamsUsed
        self.accelerometerUsed = accelerometerUsed
        self.weatherStatus = weatherStatus
        self.weatherTempC = weatherTempC
        self.weatherFeelsLikeC = weatherFeelsLikeC
        self.weatherPrecipMm = weatherPrecipMm
        self.weatherWindKmh = weatherWindKmh
        self.weatherHumidityPct = weatherHumidityPct
        self.weatherCode = weatherCode
        self.trimmedStartSeconds = trimmedStartSeconds
        self.trimmedEndSeconds = trimmedEndSeconds
        self.algorithmVersion = algorithmVersion
        self.source = source
        self.trackFormat = trackFormat
        self.pointCount = pointCount
        self.segments = segments
        self.trackData = trackData
    }

    /// Nazwy pól w kolejności kontraktu ([K] 4.1) — kolejność zapisu nagrania (`RecordingDto`).
    public static let fieldNames: [String] = [
        "id", "trainingId", "version", "createdAt", "updatedAt", "startedAt", "endedAt", "timeZone", "totalSeconds", "movingSeconds",
        "stoppedSeconds", "pausedSeconds", "distanceMeters", "avgMovingSpeedKmh", "maxSpeedKmh", "elevationGainM", "elevationLossM",
        "minAltitudeM", "maxAltitudeM", "walkSeconds", "walkMeters", "trotSeconds", "trotMeters", "canterSeconds", "canterMeters",
        "walkAvgSpeedKmh", "trotAvgSpeedKmh", "canterAvgSpeedKmh", "walkAvgCadence", "trotAvgCadence", "canterAvgCadence", "canterCount",
        "longestCanterSeconds", "longestCanterMeters", "loadPoints", "gaitThresholdsUsed", "loadParamsUsed", "accelerometerUsed",
        "weatherStatus", "weatherTempC", "weatherFeelsLikeC", "weatherPrecipMm", "weatherWindKmh", "weatherHumidityPct", "weatherCode",
        "trimmedStartSeconds", "trimmedEndSeconds", "algorithmVersion", "source", "trackFormat", "pointCount", "segments", "trackData",
    ]

    /// Pola tylko w odpowiedzi serwera — `RecordingInput` ich nie ma ([K] 4.1).
    public static let responseOnlyFields: [String] = ["id", "trainingId", "version", "createdAt", "updatedAt"]

    // MARK: JSON

    /// Nagranie z obiektu JSON (`RecordingDto`); liczby zachowują skalę, jeśli `json` przeczytano przez `JSONValue.parseKeepingScale`.
    /// Brak wymaganego pola albo zła wartość — `DecodingError.dataCorrupted`. Pola nieznane są pomijane.
    public init(json: JSONValue) throws {
        let reader = try JSONFields(json)
        id = try reader.string("id")
        trainingId = try reader.string("trainingId")
        version = try reader.optionalInt("version") ?? 0
        createdAt = try reader.optionalInstant("createdAt") ?? InstantText.epoch
        updatedAt = try reader.optionalInstant("updatedAt") ?? InstantText.epoch
        startedAt = try reader.instant("startedAt")
        endedAt = try reader.instant("endedAt")
        timeZone = try reader.string("timeZone")
        totalSeconds = try reader.int("totalSeconds")
        movingSeconds = try reader.int("movingSeconds")
        stoppedSeconds = try reader.int("stoppedSeconds")
        pausedSeconds = try reader.int("pausedSeconds")
        distanceMeters = try reader.int("distanceMeters")
        avgMovingSpeedKmh = try reader.optionalDecimal("avgMovingSpeedKmh")
        maxSpeedKmh = try reader.optionalDecimal("maxSpeedKmh")
        elevationGainM = try reader.optionalInt("elevationGainM")
        elevationLossM = try reader.optionalInt("elevationLossM")
        minAltitudeM = try reader.optionalInt("minAltitudeM")
        maxAltitudeM = try reader.optionalInt("maxAltitudeM")
        walkSeconds = try reader.int("walkSeconds")
        walkMeters = try reader.int("walkMeters")
        trotSeconds = try reader.int("trotSeconds")
        trotMeters = try reader.int("trotMeters")
        canterSeconds = try reader.int("canterSeconds")
        canterMeters = try reader.int("canterMeters")
        walkAvgSpeedKmh = try reader.optionalDecimal("walkAvgSpeedKmh")
        trotAvgSpeedKmh = try reader.optionalDecimal("trotAvgSpeedKmh")
        canterAvgSpeedKmh = try reader.optionalDecimal("canterAvgSpeedKmh")
        walkAvgCadence = try reader.optionalDecimal("walkAvgCadence")
        trotAvgCadence = try reader.optionalDecimal("trotAvgCadence")
        canterAvgCadence = try reader.optionalDecimal("canterAvgCadence")
        canterCount = try reader.int("canterCount")
        longestCanterSeconds = try reader.int("longestCanterSeconds")
        longestCanterMeters = try reader.int("longestCanterMeters")
        loadPoints = try reader.decimal("loadPoints")
        let thresholds = try JSONFields(reader.value("gaitThresholdsUsed"), path: "gaitThresholdsUsed")
        gaitThresholdsUsed = GaitThresholds(
            stopMaxKmh: try thresholds.decimal("stopMaxKmh"),
            walkMaxKmh: try thresholds.decimal("walkMaxKmh"),
            trotMaxKmh: try thresholds.decimal("trotMaxKmh")
        )
        let load = try JSONFields(reader.value("loadParamsUsed"), path: "loadParamsUsed")
        loadParamsUsed = LoadParams(
            weightWalk: try load.decimal("weightWalk"),
            weightTrot: try load.decimal("weightTrot"),
            weightCanter: try load.decimal("weightCanter"),
            climbPer10m: try load.decimal("climbPer10m")
        )
        accelerometerUsed = try reader.bool("accelerometerUsed")
        weatherStatus = try reader.enumValue("weatherStatus", WeatherStatus.self)
        weatherTempC = try reader.optionalDecimal("weatherTempC")
        weatherFeelsLikeC = try reader.optionalDecimal("weatherFeelsLikeC")
        weatherPrecipMm = try reader.optionalDecimal("weatherPrecipMm")
        weatherWindKmh = try reader.optionalDecimal("weatherWindKmh")
        weatherHumidityPct = try reader.optionalInt("weatherHumidityPct")
        weatherCode = try reader.optionalInt("weatherCode")
        trimmedStartSeconds = try reader.int("trimmedStartSeconds")
        trimmedEndSeconds = try reader.int("trimmedEndSeconds")
        algorithmVersion = try reader.int("algorithmVersion")
        guard case let .object(sourceFields) = try reader.value("source") else { throw reader.invalid("source") }
        source = sourceFields
        trackFormat = try reader.string("trackFormat")
        pointCount = try reader.int("pointCount")
        guard case let .array(items) = try reader.value("segments") else { throw reader.invalid("segments") }
        segments = try items.enumerated().map { index, item in try GaitSegment(json: item, path: "segments[\(index)]") }
        trackData = try reader.optionalString("trackData")
    }

    /// Nagranie jako obiekt JSON (`RecordingDto`); pola `nil` są pomijane, liczby zachowują skalę `Decimal`.
    public func toJSON() -> JSONValue {
        var fields: [String: JSONValue] = [:]
        fields["id"] = .string(id)
        fields["trainingId"] = .string(trainingId)
        fields["createdAt"] = .string(InstantText.format(createdAt))
        fields["updatedAt"] = .string(InstantText.format(updatedAt))
        fields["startedAt"] = .string(InstantText.format(startedAt))
        fields["endedAt"] = .string(InstantText.format(endedAt))
        fields["timeZone"] = .string(timeZone)
        let ints: [(String, Int)] = [
            ("version", version), ("totalSeconds", totalSeconds), ("movingSeconds", movingSeconds), ("stoppedSeconds", stoppedSeconds),
            ("pausedSeconds", pausedSeconds), ("distanceMeters", distanceMeters), ("walkSeconds", walkSeconds), ("walkMeters", walkMeters),
            ("trotSeconds", trotSeconds), ("trotMeters", trotMeters), ("canterSeconds", canterSeconds), ("canterMeters", canterMeters),
            ("canterCount", canterCount), ("longestCanterSeconds", longestCanterSeconds), ("longestCanterMeters", longestCanterMeters),
            ("trimmedStartSeconds", trimmedStartSeconds), ("trimmedEndSeconds", trimmedEndSeconds), ("algorithmVersion", algorithmVersion),
            ("pointCount", pointCount),
        ]
        for (name, value) in ints { fields[name] = .number(Decimal(value)) }
        fields["loadPoints"] = .number(loadPoints)
        var thresholds: [String: JSONValue] = [:]
        thresholds["stopMaxKmh"] = .number(gaitThresholdsUsed.stopMaxKmh)
        thresholds["walkMaxKmh"] = .number(gaitThresholdsUsed.walkMaxKmh)
        thresholds["trotMaxKmh"] = .number(gaitThresholdsUsed.trotMaxKmh)
        fields["gaitThresholdsUsed"] = .object(thresholds)
        var load: [String: JSONValue] = [:]
        load["weightWalk"] = .number(loadParamsUsed.weightWalk)
        load["weightTrot"] = .number(loadParamsUsed.weightTrot)
        load["weightCanter"] = .number(loadParamsUsed.weightCanter)
        load["climbPer10m"] = .number(loadParamsUsed.climbPer10m)
        fields["loadParamsUsed"] = .object(load)
        fields["accelerometerUsed"] = .bool(accelerometerUsed)
        fields["weatherStatus"] = .string(weatherStatus.rawValue)
        fields["source"] = .object(source)
        fields["trackFormat"] = .string(trackFormat)
        fields["segments"] = .array(segments.map { $0.toJSON() })
        let optionalDecimals: [(String, Decimal?)] = [
            ("avgMovingSpeedKmh", avgMovingSpeedKmh), ("maxSpeedKmh", maxSpeedKmh), ("walkAvgSpeedKmh", walkAvgSpeedKmh),
            ("trotAvgSpeedKmh", trotAvgSpeedKmh), ("canterAvgSpeedKmh", canterAvgSpeedKmh), ("walkAvgCadence", walkAvgCadence),
            ("trotAvgCadence", trotAvgCadence), ("canterAvgCadence", canterAvgCadence), ("weatherTempC", weatherTempC),
            ("weatherFeelsLikeC", weatherFeelsLikeC), ("weatherPrecipMm", weatherPrecipMm), ("weatherWindKmh", weatherWindKmh),
        ]
        for (name, value) in optionalDecimals {
            if let value { fields[name] = .number(value) }
        }
        let optionalInts: [(String, Int?)] = [
            ("elevationGainM", elevationGainM), ("elevationLossM", elevationLossM), ("minAltitudeM", minAltitudeM),
            ("maxAltitudeM", maxAltitudeM), ("weatherHumidityPct", weatherHumidityPct), ("weatherCode", weatherCode),
        ]
        for (name, value) in optionalInts {
            if let value { fields[name] = .number(Decimal(value)) }
        }
        if let trackData { fields["trackData"] = .string(trackData) }
        return .object(fields)
    }

    /// Treść `PUT /trainings/{trainingId}/recording` ([K] 4.2): pola nagrania bez `id`, `trainingId`, `version`, `createdAt` i `updatedAt`,
    /// z wymaganym `trackData` (base64 punktów z magazynu tras). Pola `nil` są pomijane, liczby zachowują skalę.
    public func toInput(trackData: String) -> JSONValue {
        guard case var .object(fields) = toJSON() else { return .object([:]) }
        for name in Self.responseOnlyFields { fields.removeValue(forKey: name) }
        fields["trackData"] = .string(trackData)
        return .object(fields)
    }

    // MARK: Codable (treść rekordu magazynu, plik eksportu)

    public init(from decoder: Decoder) throws {
        try self.init(json: JSONValue(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try toJSON().encode(to: encoder)
    }
}

extension GaitSegment {
    init(json: JSONValue, path: String) throws {
        let reader = try JSONFields(json, path: path)
        self.init(
            seq: try reader.int("seq"),
            gait: try reader.enumValue("gait", Gait.self),
            startOffsetSeconds: try reader.int("startOffsetSeconds"),
            endOffsetSeconds: try reader.int("endOffsetSeconds"),
            distanceMeters: try reader.int("distanceMeters"),
            avgSpeedKmh: try reader.decimal("avgSpeedKmh"),
            maxSpeedKmh: try reader.decimal("maxSpeedKmh"),
            avgCadence: try reader.optionalDecimal("avgCadence"),
            elevationGainM: try reader.optionalInt("elevationGainM")
        )
    }

    func toJSON() -> JSONValue {
        var fields: [String: JSONValue] = [:]
        fields["seq"] = .number(Decimal(seq))
        fields["gait"] = .string(gait.rawValue)
        fields["startOffsetSeconds"] = .number(Decimal(startOffsetSeconds))
        fields["endOffsetSeconds"] = .number(Decimal(endOffsetSeconds))
        fields["distanceMeters"] = .number(Decimal(distanceMeters))
        fields["avgSpeedKmh"] = .number(avgSpeedKmh)
        fields["maxSpeedKmh"] = .number(maxSpeedKmh)
        if let avgCadence { fields["avgCadence"] = .number(avgCadence) }
        if let elevationGainM { fields["elevationGainM"] = .number(Decimal(elevationGainM)) }
        return .object(fields)
    }
}

/// Odczyt pól obiektu JSON z błędem `DecodingError` wskazującym pole.
private struct JSONFields {
    let fields: [String: JSONValue]
    let path: String

    init(_ json: JSONValue, path: String = "") throws {
        guard case let .object(fields) = json else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Nagranie: \(path.isEmpty ? "treść" : path) nie jest obiektem"))
        }
        self.fields = fields
        self.path = path
    }

    func invalid(_ name: String) -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Nagranie: brak albo zła wartość pola \(path.isEmpty ? name : path + "." + name)"))
    }

    /// Wartość pola; `nil` dla braku i `null`.
    private func present(_ name: String) -> JSONValue? {
        guard let value = fields[name], value != .null else { return nil }
        return value
    }

    func value(_ name: String) throws -> JSONValue {
        guard let value = present(name) else { throw invalid(name) }
        return value
    }

    func string(_ name: String) throws -> String {
        guard let text = try optionalString(name) else { throw invalid(name) }
        return text
    }

    func optionalString(_ name: String) throws -> String? {
        guard let value = present(name) else { return nil }
        guard case let .string(text) = value else { throw invalid(name) }
        return text
    }

    func int(_ name: String) throws -> Int {
        guard let number = try optionalInt(name) else { throw invalid(name) }
        return number
    }

    func optionalInt(_ name: String) throws -> Int? {
        guard let value = present(name) else { return nil }
        guard case let .number(number) = value, number == number.rounded(scale: 0) else { throw invalid(name) }
        return NSDecimalNumber(decimal: number).intValue
    }

    func decimal(_ name: String) throws -> Decimal {
        guard let number = try optionalDecimal(name) else { throw invalid(name) }
        return number
    }

    func optionalDecimal(_ name: String) throws -> Decimal? {
        guard let value = present(name) else { return nil }
        guard case let .number(number) = value else { throw invalid(name) }
        return number
    }

    func bool(_ name: String) throws -> Bool {
        guard case let .bool(flag)? = present(name) else { throw invalid(name) }
        return flag
    }

    func instant(_ name: String) throws -> Date {
        guard let date = try optionalInstant(name) else { throw invalid(name) }
        return date
    }

    func optionalInstant(_ name: String) throws -> Date? {
        guard let text = try optionalString(name) else { return nil }
        guard let date = InstantText.parse(text) else { throw invalid(name) }
        return date
    }

    func enumValue<E: RawRepresentable>(_ name: String, _: E.Type) throws -> E where E.RawValue == String {
        let raw = try string(name)
        guard let value = E(rawValue: raw) else { throw invalid(name) }
        return value
    }
}

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }
}

// MARK: - LocalTrainingRecording

/// Nagranie jazdy treningu w magazynie (decyzja A4): treść to `recording` **bez** `trackData` (punkty leżą osobno, magazyn tras)
/// oraz koń i data treningu, po których filtrują listy i raporty (serwer ich w nagraniu nie niesie).
/// `id`, wersja i czasy wynikają z `recording`; czasy nagrania są chwilami UTC, a rekord magazynu liczy je jako `LocalDateTime` w UTC.
public struct LocalTrainingRecording: LocalRecord {
    public var recording: Recording
    public var horseId: String
    public var trainingDate: LocalDate

    public init(recording: Recording, horseId: String, trainingDate: LocalDate) {
        self.recording = recording
        self.horseId = horseId
        self.trainingDate = trainingDate
    }

    public var id: String { recording.id }
    public var createdAt: LocalDateTime { InstantText.localDateTime(recording.createdAt) }
    public var updatedAt: LocalDateTime { InstantText.localDateTime(recording.updatedAt) }
    public var version: Int { recording.version }
    public var recordType: RecordType { .trainingRecording }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { trainingDate }
    /// Trening nagrania (kolumna `ownerId` magazynu).
    public var parentId: String? { recording.trainingId }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalTrainingRecording {
        var copy = self
        copy.recording.version = version
        copy.recording.updatedAt = InstantText.date(updatedAt)
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalTrainingRecording {
        var copy = self
        copy.recording.createdAt = InstantText.date(time)
        return copy
    }
}

// MARK: - LocalHorseRideProfile

/// Własne parametry jazd konia ([K] 6) jako osobny rekord o `id` = `horseId` (decyzja A4). Profil nie ma własnej wersji na serwerze —
/// `version` i czasy to wersja i czasy konia z ostatniej odpowiedzi (`If-Match` operacji `PutHorseRideProfile` to wersja konia).
public struct LocalHorseRideProfile: LocalRecord {
    public var horseId: String
    public var profile: RideProfile
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int

    public init(
        horseId: String,
        profile: RideProfile,
        createdAt: LocalDateTime = .unknownTime,
        updatedAt: LocalDateTime = .unknownTime,
        version: Int = 0
    ) {
        self.horseId = horseId
        self.profile = profile
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }

    public var id: String { horseId }
    public var recordType: RecordType { .horseRideProfile }
    public var primaryHorseId: String? { horseId }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalHorseRideProfile {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalHorseRideProfile {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

// MARK: - LocalRideDefaults

/// Ustawienia domyślne jazd ([K] 7): jeden rekord o stałym `ID`; `version` to wersja zapisanych ustawień (`0` — wartości wbudowane).
public struct LocalRideDefaults: LocalRecord {
    /// Stałe `id` jedynego rekordu ustawień jazd.
    public static let ID = "ride-defaults"

    public var defaults: RideDefaults
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime

    public init(defaults: RideDefaults, createdAt: LocalDateTime = .unknownTime, updatedAt: LocalDateTime = .unknownTime) {
        self.defaults = defaults
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var id: String { Self.ID }
    public var version: Int { defaults.version }
    public var recordType: RecordType { .rideDefaults }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalRideDefaults {
        var copy = self
        copy.defaults.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalRideDefaults {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

// MARK: - API ↔ rekord (`ApiMapping.kt`)

public extension Recording {
    /// Rekord magazynu z nagrania z serwera: bez `trackData`, z koniem i datą treningu.
    func toRecord(horseId: String, trainingDate: LocalDate) -> LocalTrainingRecording {
        var stripped = self
        stripped.trackData = nil
        return LocalTrainingRecording(recording: stripped, horseId: horseId, trainingDate: trainingDate)
    }
}

public extension LocalTrainingRecording {
    /// Nagranie w kształcie API; `trackData` z magazynu tras, gdy potrzebne (eksport, pełny `GET`).
    func toApi(trackData: String? = nil) -> Recording {
        var api = recording
        api.trackData = trackData
        return api
    }
}

public extension RideDefaults {
    func toRecord() -> LocalRideDefaults { LocalRideDefaults(defaults: self) }
}

public extension LocalRideDefaults {
    func toApi() -> RideDefaults { defaults }
}
