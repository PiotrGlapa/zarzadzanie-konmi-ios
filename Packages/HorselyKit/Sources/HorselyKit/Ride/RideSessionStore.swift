import Foundation
import GRDB
import HorselyCore

// MARK: - RideSessionRow

/// Wiersz tabeli `ride_session`.
struct RideSessionRow: Sendable {
    let id: String
    let horseId: String
    let horseName: String
    let state: String // Recording | Paused | Interrupted | Finished
    let startedAtMillis: Int64
    let endedAtMillis: Int64?
    let timeZone: String
    let pausesJson: String?
    let thresholdsJson: String?
    let loadJson: String?
    let accelerometerUsed: Int
    let lastFlushMillis: Int64
    let distanceMeters: Int
    let activeSeconds: Int

    init(
        id: String,
        horseId: String,
        horseName: String,
        state: String,
        startedAtMillis: Int64,
        endedAtMillis: Int64?,
        timeZone: String,
        pausesJson: String?,
        thresholdsJson: String?,
        loadJson: String?,
        accelerometerUsed: Int,
        lastFlushMillis: Int64,
        distanceMeters: Int,
        activeSeconds: Int
    ) {
        self.id = id
        self.horseId = horseId
        self.horseName = horseName
        self.state = state
        self.startedAtMillis = startedAtMillis
        self.endedAtMillis = endedAtMillis
        self.timeZone = timeZone
        self.pausesJson = pausesJson
        self.thresholdsJson = thresholdsJson
        self.loadJson = loadJson
        self.accelerometerUsed = accelerometerUsed
        self.lastFlushMillis = lastFlushMillis
        self.distanceMeters = distanceMeters
        self.activeSeconds = activeSeconds
    }

    /// Dekoduje wiersz z GRDB.
    init(row: Row) {
        self.id = row["id"] as String
        self.horseId = row["horseId"] as String
        self.horseName = row["horseName"] as String
        self.state = row["state"] as String
        self.startedAtMillis = row["startedAtMillis"] as Int64
        self.endedAtMillis = row["endedAtMillis"] as Int64?
        self.timeZone = row["timeZone"] as String
        self.pausesJson = row["pausesJson"] as String?
        self.thresholdsJson = row["thresholdsJson"] as String?
        self.loadJson = row["loadJson"] as String?
        self.accelerometerUsed = row["accelerometerUsed"] as Int
        self.lastFlushMillis = row["lastFlushMillis"] as Int64
        self.distanceMeters = row["distanceMeters"] as Int
        self.activeSeconds = row["activeSeconds"] as Int
    }
}

// MARK: - RidePointRow

/// Wiersz tabeli `ride_point`.
struct RidePointRow: Sendable {
    let sessionId: String
    let seq: Int
    let tMillis: Int
    let lat: Double
    let lon: Double
    let altM: Double?
    let speedMs: Double?
    let hAccM: Double?
    let vAccM: Double?
    let cadence: Double?
    let intensity: Double?

    init(
        sessionId: String,
        seq: Int,
        tMillis: Int,
        lat: Double,
        lon: Double,
        altM: Double?,
        speedMs: Double?,
        hAccM: Double?,
        vAccM: Double?,
        cadence: Double?,
        intensity: Double?
    ) {
        self.sessionId = sessionId
        self.seq = seq
        self.tMillis = tMillis
        self.lat = lat
        self.lon = lon
        self.altM = altM
        self.speedMs = speedMs
        self.hAccM = hAccM
        self.vAccM = vAccM
        self.cadence = cadence
        self.intensity = intensity
    }

    init(row: Row) {
        self.sessionId = row["sessionId"] as String
        self.seq = row["seq"] as Int
        self.tMillis = row["tMillis"] as Int
        self.lat = row["lat"] as Double
        self.lon = row["lon"] as Double
        self.altM = row["altM"] as Double?
        self.speedMs = row["speedMs"] as Double?
        self.hAccM = row["hAccM"] as Double?
        self.vAccM = row["vAccM"] as Double?
        self.cadence = row["cadence"] as Double?
        self.intensity = row["intensity"] as Double?
    }
}

// MARK: - RideMediaRow

/// Wiersz tabeli `ride_media`.
struct RideMediaRow: Sendable {
    let sessionId: String
    let uri: String
    let contentType: String
    let capturedAtMillis: Int
    let lat: Double?
    let lon: Double?

    init(
        sessionId: String,
        uri: String,
        contentType: String,
        capturedAtMillis: Int,
        lat: Double?,
        lon: Double?
    ) {
        self.sessionId = sessionId
        self.uri = uri
        self.contentType = contentType
        self.capturedAtMillis = capturedAtMillis
        self.lat = lat
        self.lon = lon
    }

    init(row: Row) {
        self.sessionId = row["sessionId"] as String
        self.uri = row["uri"] as String
        self.contentType = row["contentType"] as String
        self.capturedAtMillis = row["capturedAtMillis"] as Int
        self.lat = row["lat"] as Double?
        self.lon = row["lon"] as Double?
    }
}

// MARK: - StoredTrack

/// Przechowana trasa nagrania (kopia Androida `StoredTrack`).
struct StoredTrack: Sendable {
    let recordingId: String
    let version: Int
    let format: String
    let data: Data
}

// MARK: - RideSessionStore

/// Interfejs do sesji nagrywania i tras — typy wierszy i zapytania (logika w Task 14).
struct RideSessionStore {
    private let db: any DatabaseWriter

    init(db: any DatabaseWriter) {
        self.db = db
    }

    // MARK: - Session

    /// Aktywna sesja nagrywania — zwraca `nil`, gdy nie ma sesji.
    func activeSession() async throws -> RideSessionRow? {
        try await db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM ride_session WHERE state != 'Finished' LIMIT 1") else {
                return nil
            }
            return RideSessionRow(row: row)
        }
    }

    /// Sesja o podanym id.
    func session(id: String) async throws -> RideSessionRow? {
        try await db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM ride_session WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return RideSessionRow(row: row)
        }
    }

    /// Zapisz lub zaktualizuj sesję.
    func saveSession(_ session: RideSessionRow) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO ride_session
                        (id, horseId, horseName, state, startedAtMillis, endedAtMillis, timeZone, pausesJson, thresholdsJson, loadJson, accelerometerUsed, lastFlushMillis, distanceMeters, activeSeconds)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    session.id, session.horseId, session.horseName, session.state,
                    session.startedAtMillis, session.endedAtMillis, session.timeZone,
                    session.pausesJson, session.thresholdsJson, session.loadJson,
                    session.accelerometerUsed, session.lastFlushMillis, session.distanceMeters, session.activeSeconds
                ]
            )
        }
    }

    /// Usuń sesję i kaskadowo punkty/media.
    func deleteSession(id: String) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM ride_point WHERE sessionId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM ride_media WHERE sessionId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM ride_session WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Points

    /// Punkty dla sesji, posortowane po seq.
    func points(sessionId: String) async throws -> [RidePointRow] {
        try await db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM ride_point WHERE sessionId = ? ORDER BY seq ASC", arguments: [sessionId])
            return rows.map { RidePointRow(row: $0) }
        }
    }

    /// Wstaw punkty (batch).
    func insertPoints(_ points: [RidePointRow]) async throws {
        try await db.write { db in
            for point in points {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO ride_point
                            (sessionId, seq, tMillis, lat, lon, altM, speedMs, hAccM, vAccM, cadence, intensity)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        point.sessionId, point.seq, point.tMillis, point.lat, point.lon,
                        point.altM, point.speedMs, point.hAccM, point.vAccM, point.cadence, point.intensity
                    ]
                )
            }
        }
    }

    // MARK: - Media

    /// Pliki multimediów dla sesji.
    func media(sessionId: String) async throws -> [RideMediaRow] {
        try await db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM ride_media WHERE sessionId = ?", arguments: [sessionId])
            return rows.map { RideMediaRow(row: $0) }
        }
    }

    /// Dodaj wpis media.
    func insertMedia(_ media: RideMediaRow) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO ride_media
                        (sessionId, uri, contentType, capturedAtMillis, lat, lon)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [media.sessionId, media.uri, media.contentType, media.capturedAtMillis, media.lat, media.lon]
            )
        }
    }

    // MARK: - Track

    /// Pobierz trasę dla nagrania.
    func track(recordingId: String) async throws -> StoredTrack? {
        try await db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM local_track WHERE recordingId = ?", arguments: [recordingId]) else {
                return nil
            }
            return StoredTrack(
                recordingId: row["recordingId"] as String,
                version: row["version"] as Int,
                format: row["format"] as String,
                data: row["data"] as Data
            )
        }
    }

    /// Zapisz trasę.
    func putTrack(_ track: StoredTrack) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO local_track
                        (recordingId, version, format, data)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [track.recordingId, track.version, track.format, track.data]
            )
        }
    }

    /// Usuń trasę.
    func deleteTrack(recordingId: String) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM local_track WHERE recordingId = ?", arguments: [recordingId])
        }
    }

    // MARK: - Clear

    /// Czyszczenie magazynu — usuwa trasy i sesje.
    func clearRideData() async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM ride_point")
            try db.execute(sql: "DELETE FROM ride_media")
            try db.execute(sql: "DELETE FROM ride_session")
            try db.execute(sql: "DELETE FROM local_track")
        }
    }
}
