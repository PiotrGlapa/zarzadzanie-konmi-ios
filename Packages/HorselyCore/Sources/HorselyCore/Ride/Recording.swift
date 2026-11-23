// Modele nagrań jazdy — kopia z Androida 3.0.2 (Task 4).
// Odpowiadają kontraktowi `/api/v3` recordings (kontrakt: `specs/012-treningi-nagrania/contracts/api-v3-recordings.md`).

import Foundation

// MARK: - Gait

/// Rodzaj chodu konia w odcinku nagrania.
public enum Gait: String, Codable, Sendable, CaseIterable {
    case stop = "Stop"
    case walk = "Walk"
    case trot = "Trot"
    case canter = "Canter"
}

// MARK: - WeatherStatus

/// Stan pozyskania pogody dla nagrania.
public enum WeatherStatus: String, Codable, Sendable, CaseIterable {
    case none = "None"
    case pending = "Pending"
    case fetched = "Fetched"
    case disabled = "Disabled"
    case failed = "Failed"
}

// MARK: - GaitSegment

/// Odcinek chodu w nagraniu jazdy.
public struct GaitSegment: Codable, Hashable, Sendable {
    /// Numer sekwencyjny, od 1 bez przerw.
    public var seq: Int
    /// Rodzaj chodu.
    public var gait: Gait
    /// Sekunda od startu nagrania (bez pauz).
    public var startOffsetSeconds: Int
    /// Sekunda końca odcinka (bez pauz).
    public var endOffsetSeconds: Int
    /// Dystans w metrach.
    public var distanceMeters: Int
    /// Średnia prędkość km/h.
    public var avgSpeedKmh: Decimal
    /// Maksymalna prędkość km/h.
    public var maxSpeedKmh: Decimal
    /// Średnie tempo km/h; `nil` bez akcelerometru.
    public var avgCadence: Decimal?
    /// Przewyższenie w metrach; `nil` bez danych wysokości.
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

/// Podsumowanie nagrania — pole `recordingSummary` w treningu z [K] 3.1.
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

// MARK: - RecordingDto (odpowiedź API)

/// Pełny kształt nagrania z odpowiedzi API (`RecordingDto` z [K] 4.1).
public struct RecordingDto: Codable, Hashable, Sendable {
    public var id: String
    public var trainingId: String
    public var version: Int
    public var createdAt: String
    public var updatedAt: String
    public var startedAt: String
    public var endedAt: String
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
    public var gaitThresholdsUsed: [String: Decimal]
    public var loadParamsUsed: [String: Decimal]
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
    public var source: [String: String]
    public var trackFormat: String
    public var pointCount: Int
    public var segments: [GaitSegment]
    /// `trackData` base64 — tylko w pełnym `GET` i w `RecordingInput`; pomijane w odpowiedzi `PUT`.
    public var trackData: String?

    public init(
        id: String,
        trainingId: String,
        version: Int,
        createdAt: String,
        updatedAt: String,
        startedAt: String,
        endedAt: String,
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
        walkSeconds: Int = 0,
        walkMeters: Int = 0,
        trotSeconds: Int = 0,
        trotMeters: Int = 0,
        canterSeconds: Int = 0,
        canterMeters: Int = 0,
        walkAvgSpeedKmh: Decimal? = nil,
        trotAvgSpeedKmh: Decimal? = nil,
        canterAvgSpeedKmh: Decimal? = nil,
        walkAvgCadence: Decimal? = nil,
        trotAvgCadence: Decimal? = nil,
        canterAvgCadence: Decimal? = nil,
        canterCount: Int = 0,
        longestCanterSeconds: Int = 0,
        longestCanterMeters: Int = 0,
        loadPoints: Decimal = 0,
        gaitThresholdsUsed: [String: Decimal] = [:],
        loadParamsUsed: [String: Decimal] = [:],
        accelerometerUsed: Bool = false,
        weatherStatus: WeatherStatus = .none,
        weatherTempC: Decimal? = nil,
        weatherFeelsLikeC: Decimal? = nil,
        weatherPrecipMm: Decimal? = nil,
        weatherWindKmh: Decimal? = nil,
        weatherHumidityPct: Int? = nil,
        weatherCode: Int? = nil,
        trimmedStartSeconds: Int = 0,
        trimmedEndSeconds: Int = 0,
        algorithmVersion: Int = 0,
        source: [String: String] = [:],
        trackFormat: String = "",
        pointCount: Int = 0,
        segments: [GaitSegment] = [],
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
}

// MARK: - RecordingInput (żądanie PUT)

/// Żądanie `PUT /trainings/{trainingId}/recording` — `RecordingInput`.
/// Pola „tylko odpowiedź" z `RecordingDto` są pomijane.
public struct RecordingInput: Codable, Hashable, Sendable {
    public var startedAt: String
    public var endedAt: String
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
    public var gaitThresholdsUsed: [String: Decimal]
    public var loadParamsUsed: [String: Decimal]
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
    public var source: [String: String]
    public var trackFormat: String
    public var pointCount: Int
    public var segments: [GaitSegment]
    /// Wymagane w `RecordingInput`.
    public var trackData: String

    public init(
        startedAt: String,
        endedAt: String,
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
        walkSeconds: Int = 0,
        walkMeters: Int = 0,
        trotSeconds: Int = 0,
        trotMeters: Int = 0,
        canterSeconds: Int = 0,
        canterMeters: Int = 0,
        walkAvgSpeedKmh: Decimal? = nil,
        trotAvgSpeedKmh: Decimal? = nil,
        canterAvgSpeedKmh: Decimal? = nil,
        walkAvgCadence: Decimal? = nil,
        trotAvgCadence: Decimal? = nil,
        canterAvgCadence: Decimal? = nil,
        canterCount: Int = 0,
        longestCanterSeconds: Int = 0,
        longestCanterMeters: Int = 0,
        loadPoints: Decimal = 0,
        gaitThresholdsUsed: [String: Decimal] = [:],
        loadParamsUsed: [String: Decimal] = [:],
        accelerometerUsed: Bool = false,
        weatherStatus: WeatherStatus = .none,
        weatherTempC: Decimal? = nil,
        weatherFeelsLikeC: Decimal? = nil,
        weatherPrecipMm: Decimal? = nil,
        weatherWindKmh: Decimal? = nil,
        weatherHumidityPct: Int? = nil,
        weatherCode: Int? = nil,
        trimmedStartSeconds: Int = 0,
        trimmedEndSeconds: Int = 0,
        algorithmVersion: Int = 0,
        source: [String: String] = [:],
        trackFormat: String = "",
        pointCount: Int = 0,
        segments: [GaitSegment] = [],
        trackData: String
    ) {
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
}

// MARK: - LocalTrainingRecording

/// Lokalny rekord treningu z nagraniem — treść to `RecordingDto` bez `trackData` + `horseId`, `trainingDate`.
public struct LocalTrainingRecording: Codable, Hashable, Sendable, LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var horseId: String
    public var trainingDate: LocalDate
    public var startedAt: String
    public var endedAt: String
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
    public var gaitThresholdsUsed: [String: Decimal]
    public var loadParamsUsed: [String: Decimal]
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
    public var source: [String: String]
    public var trackFormat: String
    public var pointCount: Int
    public var segments: [GaitSegment]

    public init(
        id: String,
        createdAt: LocalDateTime,
        updatedAt: LocalDateTime,
        version: Int = 0,
        horseId: String,
        trainingDate: LocalDate,
        startedAt: String,
        endedAt: String,
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
        walkSeconds: Int = 0,
        walkMeters: Int = 0,
        trotSeconds: Int = 0,
        trotMeters: Int = 0,
        canterSeconds: Int = 0,
        canterMeters: Int = 0,
        walkAvgSpeedKmh: Decimal? = nil,
        trotAvgSpeedKmh: Decimal? = nil,
        canterAvgSpeedKmh: Decimal? = nil,
        walkAvgCadence: Decimal? = nil,
        trotAvgCadence: Decimal? = nil,
        canterAvgCadence: Decimal? = nil,
        canterCount: Int = 0,
        longestCanterSeconds: Int = 0,
        longestCanterMeters: Int = 0,
        loadPoints: Decimal = 0,
        gaitThresholdsUsed: [String: Decimal] = [:],
        loadParamsUsed: [String: Decimal] = [:],
        accelerometerUsed: Bool = false,
        weatherStatus: WeatherStatus = .none,
        weatherTempC: Decimal? = nil,
        weatherFeelsLikeC: Decimal? = nil,
        weatherPrecipMm: Decimal? = nil,
        weatherWindKmh: Decimal? = nil,
        weatherHumidityPct: Int? = nil,
        weatherCode: Int? = nil,
        trimmedStartSeconds: Int = 0,
        trimmedEndSeconds: Int = 0,
        algorithmVersion: Int = 0,
        source: [String: String] = [:],
        trackFormat: String = "",
        pointCount: Int = 0,
        segments: [GaitSegment] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.horseId = horseId
        self.trainingDate = trainingDate
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
    }

    public var recordType: RecordType { .trainingRecording }
    public var primaryHorseId: String? { horseId }
    public var dateKey: LocalDate? { trainingDate }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalTrainingRecording {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalTrainingRecording {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

// MARK: - LocalHorseRideProfile

/// Lokalny rekord profilu jazdy konia.
public struct LocalHorseRideProfile: Codable, Hashable, Sendable, LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var horseId: String
    public var profile: RideProfile

    public init(id: String, createdAt: LocalDateTime, updatedAt: LocalDateTime, version: Int, horseId: String, profile: RideProfile) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.horseId = horseId
        self.profile = profile
    }

    public var recordType: RecordType { .horseRideProfile }

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

/// Lokalny rekord ustawień domyślnych jazd.
public struct LocalRideDefaults: Codable, Hashable, Sendable, LocalRecord {
    public var id: String
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var version: Int
    public var profile: RideDefaults

    public init(id: String, createdAt: LocalDateTime, updatedAt: LocalDateTime, version: Int, profile: RideDefaults) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.profile = profile
    }

    public var recordType: RecordType { .rideDefaults }

    public func withAudit(version: Int, updatedAt: LocalDateTime) -> LocalRideDefaults {
        var copy = self
        copy.version = version
        copy.updatedAt = updatedAt
        return copy
    }

    public func withCreated(at time: LocalDateTime) -> LocalRideDefaults {
        var copy = self
        copy.createdAt = time
        return copy
    }
}

// MARK: - RecordingDto → RecordingInput (rozszerzenie)

/// Rozszerzenie `RecordingDto` z metodą konwersji na `RecordingInput`.
/// `toInput(trackData:)` tworzy obiekt wejściowy `RecordingInput` z bieżących pól `RecordingDto`,
/// pomijając pola „tylko odpowiedź" (`id`, `trainingId`, `version`, `createdAt`, `updatedAt`)
/// i dołączając `trackData` jako wymagane pole.
public extension RecordingDto {
    /// Konwertuje `RecordingDto` na `RecordingInput` z podanym `trackData`.
    /// Pomija pola tylko do odczytu z odpowiedzi API; dołącza `trackData` jako wymagane.
    func toInput(trackData: String) -> RecordingInput {
        RecordingInput(
            startedAt: startedAt,
            endedAt: endedAt,
            timeZone: timeZone,
            totalSeconds: totalSeconds,
            movingSeconds: movingSeconds,
            stoppedSeconds: stoppedSeconds,
            pausedSeconds: pausedSeconds,
            distanceMeters: distanceMeters,
            avgMovingSpeedKmh: avgMovingSpeedKmh,
            maxSpeedKmh: maxSpeedKmh,
            elevationGainM: elevationGainM,
            elevationLossM: elevationLossM,
            minAltitudeM: minAltitudeM,
            maxAltitudeM: maxAltitudeM,
            walkSeconds: walkSeconds,
            walkMeters: walkMeters,
            trotSeconds: trotSeconds,
            trotMeters: trotMeters,
            canterSeconds: canterSeconds,
            canterMeters: canterMeters,
            walkAvgSpeedKmh: walkAvgSpeedKmh,
            trotAvgSpeedKmh: trotAvgSpeedKmh,
            canterAvgSpeedKmh: canterAvgSpeedKmh,
            walkAvgCadence: walkAvgCadence,
            trotAvgCadence: trotAvgCadence,
            canterAvgCadence: canterAvgCadence,
            canterCount: canterCount,
            longestCanterSeconds: longestCanterSeconds,
            longestCanterMeters: longestCanterMeters,
            loadPoints: loadPoints,
            gaitThresholdsUsed: gaitThresholdsUsed,
            loadParamsUsed: loadParamsUsed,
            accelerometerUsed: accelerometerUsed,
            weatherStatus: weatherStatus,
            weatherTempC: weatherTempC,
            weatherFeelsLikeC: weatherFeelsLikeC,
            weatherPrecipMm: weatherPrecipMm,
            weatherWindKmh: weatherWindKmh,
            weatherHumidityPct: weatherHumidityPct,
            weatherCode: weatherCode,
            trimmedStartSeconds: trimmedStartSeconds,
            trimmedEndSeconds: trimmedEndSeconds,
            algorithmVersion: algorithmVersion,
            source: source,
            trackFormat: trackFormat,
            pointCount: pointCount,
            segments: segments,
            trackData: trackData
        )
    }
}
