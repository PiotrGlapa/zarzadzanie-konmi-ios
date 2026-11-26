import Foundation

// SZKIELET fazy czerwonej (TDD): typy i sygnatury bez działania — implementacja w następnym commicie.

public struct TrackPoint: Sendable, Hashable {
    public var tMillis: Int64
    public var lat: Double
    public var lon: Double
    public var altM: Double?
    public var speedMs: Double?
    public var hAccM: Double?
    public var cadence: Double?
    public var intensity: Double?

    public init(tMillis: Int64, lat: Double, lon: Double, altM: Double?, speedMs: Double?, hAccM: Double?, cadence: Double?, intensity: Double?) {
        self.tMillis = tMillis
        self.lat = lat
        self.lon = lon
        self.altM = altM
        self.speedMs = speedMs
        self.hAccM = hAccM
        self.cadence = cadence
        self.intensity = intensity
    }
}

public struct Pause: Sendable, Hashable {
    public var startMillis: Int64
    public var endMillis: Int64

    public init(startMillis: Int64, endMillis: Int64) {
        self.startMillis = startMillis
        self.endMillis = endMillis
    }
}

public struct Track: Sendable, Hashable {
    public var startedAtMillis: Int64
    public var points: [TrackPoint]
    public var pauses: [Pause]

    public init(startedAtMillis: Int64, points: [TrackPoint], pauses: [Pause]) {
        self.startedAtMillis = startedAtMillis
        self.points = points
        self.pauses = pauses
    }
}

public struct ZkTrackError: Error, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

enum Gzip {
    static func compress(_ data: Data) throws -> Data {
        throw ZkTrackError("Nie zaimplementowano.")
    }

    static func decompress(_ data: Data, limit: Int) throws -> Data {
        throw ZkTrackError("Nie zaimplementowano.")
    }
}

public enum ZkTrack {
    public static let format = "zk-track/1"

    public static func encode(_ track: Track) throws -> Data {
        throw ZkTrackError("Nie zaimplementowano.")
    }

    public static func decode(_ data: Data) throws -> Track {
        throw ZkTrackError("Nie zaimplementowano.")
    }
}
