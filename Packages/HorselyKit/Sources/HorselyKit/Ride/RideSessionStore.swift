import Foundation
import GRDB
import HorselyCore
import Synchronization

// MARK: - RideSessionRow

/// Wiersz tabeli `ride_session`.
struct RideSessionRow: Sendable, Equatable {
    let id: String
    let horseId: String
    let horseName: String
    let state: String // Recording | Paused | Interrupted | Finished
    let startedAtMillis: Int64
    let endedAtMillis: Int64?
    let timeZone: String
    let pausesJson: String
    let thresholdsJson: String
    let loadJson: String
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
        pausesJson: String,
        thresholdsJson: String,
        loadJson: String,
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
        self.pausesJson = row["pausesJson"] as String
        self.thresholdsJson = row["thresholdsJson"] as String
        self.loadJson = row["loadJson"] as String
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

// MARK: - Typy publiczne

/// Błędy repozytorium sesji nagrywania (Android: `IllegalStateException` i `IllegalArgumentException` z `RideSessionRepository`).
public enum RideSessionError: Error, Sendable, Equatable, LocalizedError {
    /// W tabeli jest już sesja (także zakończona, a jeszcze niezapisana jako nagranie) — `start` jej nie nadpisze.
    case onlyOneActiveSession

    /// Nie ma sesji o podanym id.
    case sessionNotFound(String)

    /// Punkt jest sprzed startu sesji albo poza zakresem czasu — maszyna nagrywania powstała z innym `startedAtMillis` niż podany w `start`.
    case pointOutsideSession(offsetMillis: Int64)

    /// Zapis sesji (czas startu, progi, obciążenie, pauzy) jest nieczytelny — sesję można tylko odrzucić.
    case corruptSession(String)

    public var errorDescription: String? {
        switch self {
        case .onlyOneActiveSession:
            "Poprzednia jazda czeka na zapisanie lub odrzucenie — najpierw ją zapisz albo odrzuć."
        case .sessionNotFound(let id):
            "Nie ma sesji nagrywania \(id)."
        case .pointOutsideSession(let offset):
            "Punkt trasy poza zakresem czasu sesji (przesunięcie \(offset) ms) — maszyna nagrywania musi startować z tym samym startedAtMillis, co RideSessionStore.start."
        case .corruptSession(let id):
            "Zapis sesji nagrywania \(id) jest uszkodzony."
        }
    }
}

/// Sesja nagrywania w postaci niezależnej od tabeli. `lastFlushMillis` to chwila ostatniego zapisu (epoka, ms).
public struct RideSessionInfo: Sendable, Hashable {
    public let id: String
    public let horse: HorseRef
    public let state: RideState
    public let startedAt: Date
    public let endedAt: Date?
    public let timeZone: String
    public let accelerometerUsed: Bool
    public let lastFlushMillis: Int64
    public let distanceMeters: Int
    public let activeSeconds: Int

    public init(
        id: String, horse: HorseRef, state: RideState, startedAt: Date, endedAt: Date?, timeZone: String, accelerometerUsed: Bool,
        lastFlushMillis: Int64, distanceMeters: Int, activeSeconds: Int
    ) {
        self.id = id
        self.horse = horse
        self.state = state
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timeZone = timeZone
        self.accelerometerUsed = accelerometerUsed
        self.lastFlushMillis = lastFlushMillis
        self.distanceMeters = distanceMeters
        self.activeSeconds = activeSeconds
    }
}

/// Zdjęcie lub film zrobione w trakcie jazdy; `uri` to adres pliku, miejsce tylko gdy było znane.
public struct RideMedia: Sendable, Hashable {
    public let uri: String
    public let contentType: String
    public let capturedAt: Date
    public let latitude: Double?
    public let longitude: Double?

    public init(uri: String, contentType: String, capturedAt: Date, latitude: Double?, longitude: Double?) {
        self.uri = uri
        self.contentType = contentType
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Jazda czekająca na zapisanie, do pokazania przy starcie aplikacji („Masz niezakończone nagranie (Grom, 14:05, 6,1 km)”). Dla `.finished`
/// interfejs otwiera ekran zakończenia, dla pozostałych pokazuje „Zapisz / Odrzuć”. `damaged` — zapis sesji jest uszkodzony i odzyskano go
/// tylko częściowo (dystans z ostatniego zapisu albo po pominięciu błędnych danych, stan `.interrupted` dla nieznanego); zapis i odrzucenie
/// nadal działają.
public struct UnfinishedRide: Sendable, Hashable {
    public let sessionId: String
    public let horseName: String
    public let startedAt: Date
    public let distanceMeters: Int
    public let state: RideState
    public let damaged: Bool

    public init(sessionId: String, horseName: String, startedAt: Date, distanceMeters: Int, state: RideState, damaged: Bool = false) {
        self.sessionId = sessionId
        self.horseName = horseName
        self.startedAt = startedAt
        self.distanceMeters = distanceMeters
        self.state = state
        self.damaged = damaged
    }
}

/// Trwająca (niezakończona) jazda dla paska NAG-01 i ekranu nagrywania: sesja, koń, początek i bieżąca migawka.
public struct ActiveRide: Sendable, Hashable {
    public let sessionId: String
    public let horseName: String
    public let startedAt: Date
    public let snapshot: RideSnapshot

    public init(sessionId: String, horseName: String, startedAt: Date, snapshot: RideSnapshot) {
        self.sessionId = sessionId
        self.horseName = horseName
        self.startedAt = startedAt
        self.snapshot = snapshot
    }
}

/// Sesja wczytana z bazy: `track` to zapisane punkty i pauzy (po oczyszczeniu błędnych wartości), `params` — parametry sprzed startu jazdy
/// (nie zmieniają się w trakcie).
public struct LoadedSession: Sendable {
    public let session: RideSessionInfo
    public let track: Track
    public let media: [RideMedia]
    public let params: EffectiveRideParameters

    public init(session: RideSessionInfo, track: Track, media: [RideMedia], params: EffectiveRideParameters) {
        self.session = session
        self.track = track
        self.media = media
        self.params = params
    }

    /// Maszyna nagrywania odtworzona z zapisanych danych (stan `.interrupted` wraca jako wstrzymana od ostatniego zapisu).
    public func restoreRecorder() -> RideRecorder {
        RideRecorder.restore(
            session: RideRestoreState(
                startedAtMillis: track.startedAtMillis, thresholds: params.thresholds, state: session.state, lastFlushMillis: session.lastFlushMillis
            ),
            points: track.points,
            pauses: track.pauses
        )
    }
}

// MARK: - Zapis JSON (progi, obciążenie, pauzy)

/// Liczba dziesiętna jako tekst: bez straty przy zapisie i odczycie (`JSONEncoder` zapisałby `Decimal` przez `Double`).
private struct DecimalText: Codable {
    let value: Decimal

    init(_ value: Decimal) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "To nie jest liczba: \(text)"))
        }
        self.value = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(value)")
    }
}

/// `ride_session.thresholdsJson`.
private struct StoredThresholds: Codable {
    let stopMaxKmh: DecimalText
    let walkMaxKmh: DecimalText
    let trotMaxKmh: DecimalText

    init(_ thresholds: GaitThresholds) {
        stopMaxKmh = DecimalText(thresholds.stopMaxKmh)
        walkMaxKmh = DecimalText(thresholds.walkMaxKmh)
        trotMaxKmh = DecimalText(thresholds.trotMaxKmh)
    }

    var thresholds: GaitThresholds {
        GaitThresholds(stopMaxKmh: stopMaxKmh.value, walkMaxKmh: walkMaxKmh.value, trotMaxKmh: trotMaxKmh.value)
    }
}

/// `ride_session.loadJson`: wszystko z `EffectiveRideParameters` poza progami (te mają własną kolumnę).
private struct StoredLoad: Codable {
    let weightWalk: DecimalText
    let weightTrot: DecimalText
    let weightCanter: DecimalText
    let climbPer10m: DecimalText
    let warnPercent: Int
    let heavyRidePoints: Int
    let ownFields: [String]

    init(_ params: EffectiveRideParameters) {
        weightWalk = DecimalText(params.load.weightWalk)
        weightTrot = DecimalText(params.load.weightTrot)
        weightCanter = DecimalText(params.load.weightCanter)
        climbPer10m = DecimalText(params.load.climbPer10m)
        warnPercent = params.warnPercent
        heavyRidePoints = params.heavyRidePoints
        ownFields = params.ownFields
    }

    var load: LoadParams {
        LoadParams(weightWalk: weightWalk.value, weightTrot: weightTrot.value, weightCanter: weightCanter.value, climbPer10m: climbPer10m.value)
    }
}

/// Pauza w `ride_session.pausesJson`: czasy bezwzględne (epoka, ms); koniec otwartej pauzy to czas ostatniego zdarzenia maszyny.
private struct StoredPause: Codable {
    let startMillis: Int64
    let endMillis: Int64
}

// MARK: - Migawka na żywo

/// Ostatnia migawka z `flush` — bogatsza niż kolumny sesji (prędkość, chód, słaby GPS), ważna dopóki stan sesji się zgadza.
struct LiveSnapshot: Sendable {
    let sessionId: String
    let snapshot: RideSnapshot
}

/// Bieżąca migawka na żywo z powiadamianiem obserwatorów (odpowiednik `MutableStateFlow` z Androida).
final class LiveSnapshotBox: Sendable {
    private struct State {
        var value: LiveSnapshot?
        var observers: [UInt64: AsyncStream<LiveSnapshot?>.Continuation] = [:]
        var nextId: UInt64 = 0
    }

    private let state = Mutex(State())

    func set(_ value: LiveSnapshot?) {
        state.withLock { current in
            current.value = value
            for continuation in current.observers.values { continuation.yield(value) }
        }
    }

    /// Bieżąca wartość zaraz po zapisaniu się, potem każda zmiana (najnowsza wygrywa).
    func updates() -> AsyncStream<LiveSnapshot?> {
        AsyncStream<LiveSnapshot?>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = state.withLock { current -> UInt64 in
                current.nextId += 1
                current.observers[current.nextId] = continuation
                continuation.yield(current.value)
                return current.nextId
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { current in current.observers[id] = nil }
            }
        }
    }
}

/// Łączy strumień wiersza aktywnej sesji ze strumieniem migawki na żywo (`combine` z Androida): pierwsza wartość dopiero, gdy są obie,
/// kolejne tylko przy zmianie wyniku.
private final class ActiveMerge: Sendable {
    private struct State {
        var row: RideSessionRow?
        var hasRow = false
        var live: LiveSnapshot?
        var hasLive = false
        var last: ActiveRide?
        var emitted = false
    }

    private let state = Mutex(State())
    private let continuation: AsyncStream<ActiveRide?>.Continuation

    init(_ continuation: AsyncStream<ActiveRide?>.Continuation) {
        self.continuation = continuation
    }

    func setRow(_ row: RideSessionRow?) {
        state.withLock { current in
            current.row = row
            current.hasRow = true
            publish(&current)
        }
    }

    func setLive(_ live: LiveSnapshot?) {
        state.withLock { current in
            current.live = live
            current.hasLive = true
            publish(&current)
        }
    }

    private func publish(_ current: inout State) {
        guard current.hasRow, current.hasLive else { return }
        let ride: ActiveRide?
        if let row = current.row {
            ride = ActiveRide(
                sessionId: row.id, horseName: row.horseName, startedAt: RideSessionStore.date(row.startedAtMillis),
                snapshot: RideSessionStore.snapshot(of: row, live: current.live)
            )
        } else {
            ride = nil
        }
        if current.emitted, current.last == ride { return }
        current.emitted = true
        current.last = ride
        continuation.yield(ride)
    }
}

// MARK: - RideSessionStore

/// Repozytorium sesji nagrywania (port `RideSessionRepository` z Androida 3.0.2, decyzja A13). Maszyna `RideRecorder` żyje w pamięci
/// aktora nagrywania; tu trafia to, co ma przetrwać zabicie procesu: stan, pauzy, czas ostatniego zapisu i punkty — zawsze w jednej
/// transakcji. Jest jedna aktywna (niezakończona) sesja naraz. Klucz punktu to jego przesunięcie od startu sesji w milisekundach (`seq` i
/// `tMillis`): maszyna odrzuca punkty niemonotoniczne, więc czas jednoznacznie wskazuje punkt, a punkt uzupełniony rytmem po zapisie
/// (wraca w kolejnym `drainUnsaved()`) trafia na ten sam wiersz — także po restarcie procesu.
///
/// Trasy nagrań leżą w `RecordStore` (`track`/`putTrack`/`deleteTrack`), bo należą do transakcji magazynu rekordów. Sesji nagrywania nie
/// rusza `RecordAccess.clear()` (jak `RoomLocalStore.clear()` w Androidzie): zastąpienie danych telefonu przy niezapisanej jeździe blokuje
/// osobna blokada trybów (Task 31), a nie kasowanie sesji.
///
/// Współrzędne i nazwa konia nie trafiają do dziennika diagnostycznego — to repozytorium w ogóle nie pisze do dziennika.
public final class RideSessionStore: Sendable {
    /// Najdłuższa jazda, jaką zapisuje repozytorium: przesunięcia czasu mieszczą się w `Int32` (jak w Androidzie, ok. 24,8 doby) — dzięki
    /// temu arytmetyka maszyny nagrywania na czasach z bazy nie może się przepełnić.
    static let maxOffsetMillis = Int64(Int32.max)

    /// Największy poprawny czas startu sesji (epoka, ms): początek roku 3000.
    static let maxEpochMillis: Int64 = 32_503_680_000_000

    private let db: any DatabaseWriter
    private let now: @Sendable () -> Date
    private let timeZoneId: String
    private let live = LiveSnapshotBox()

    /// - Parameters:
    ///   - now: źródło „teraz” (testy podają stałe)
    ///   - timeZone: identyfikator strefy zapisywany w sesji (strefa urządzenia w chwili startu)
    public init(db: any DatabaseWriter, now: @escaping @Sendable () -> Date = { Date() }, timeZone: String = TimeZone.current.identifier) {
        self.db = db
        self.now = now
        self.timeZoneId = timeZone
    }

    public convenience init(database: AppDatabase, now: @escaping @Sendable () -> Date = { Date() }, timeZone: String = TimeZone.current.identifier) {
        self.init(db: database.writer, now: now, timeZone: timeZone)
    }

    // MARK: - Cykl życia sesji

    /// Zakłada sesję w stanie `.recording` i zwraca jej id. W tabeli jest najwyżej jedna sesja: dopóki poprzednia jazda (także zakończona,
    /// a jeszcze niezapisana jako nagranie) nie zostanie zapisana albo odrzucona (`discard`), rzuca `RideSessionError.onlyOneActiveSession`.
    ///
    /// `startedAtMillis` jest źródłem prawdy czasu startu: wywołujący (aktor nagrywania) musi utworzyć `RideRecorder` z TĄ SAMĄ wartością.
    /// Inna wartość w maszynie dałaby punkty o czasie sprzed startu sesji, które `flush` odrzuci, albo po odtworzeniu przesunęłaby czas aktywny.
    public func start(horse: HorseRef, params: EffectiveRideParameters, startedAtMillis: Int64? = nil) async throws -> String {
        let startedAt = startedAtMillis ?? Self.millis(now())
        let id = UUID().uuidString.lowercased()
        let thresholdsJson = try Self.encode(StoredThresholds(params.thresholds))
        let loadJson = try Self.encode(StoredLoad(params))
        let pausesJson = try Self.encode([StoredPause]())
        let zone = timeZoneId
        let horseId = horse.id
        let horseName = horse.name
        try await db.write { db in
            if try Self.pendingSession(db) != nil { throw RideSessionError.onlyOneActiveSession }
            try db.execute(
                sql: """
                    INSERT INTO ride_session
                        (id, horseId, horseName, state, startedAtMillis, endedAtMillis, timeZone, pausesJson, thresholdsJson, loadJson, accelerometerUsed, lastFlushMillis, distanceMeters, activeSeconds)
                    VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, 0, ?, 0, 0)
                    """,
                arguments: [id, horseId, horseName, RideState.recording.rawValue, startedAt, zone, pausesJson, thresholdsJson, loadJson, startedAt]
            )
        }
        live.set(nil)
        return id
    }

    /// Zapisuje w jednej transakcji stan z `snapshot`, `pauses` (`RideRecorder.pauses()`), czas zapisu, dystans i czas aktywny oraz
    /// `points` (`RideRecorder.drainUnsaved()`; ponowny zapis punktu zastępuje jego wiersz). Błąd w którejkolwiek części cofa całość.
    /// Rzuca `.sessionNotFound`, gdy sesji nie ma, i `.pointOutsideSession` (przed jakąkolwiek zmianą w bazie) dla punktu sprzed startu
    /// sesji — znak, że maszyna powstała z innym `startedAtMillis` niż podany w `start`; nie jest to tolerowane po cichu.
    public func flush(sessionId: String, points: [TrackPoint], snapshot: RideSnapshot, pauses: [Pause]) async throws {
        let flushedAt = Self.millis(now())
        let pausesJson = try Self.encode(pauses.map { StoredPause(startMillis: $0.startMillis, endMillis: $0.endMillis) })
        try await db.write { db in
            guard let row = try Self.fetchSession(db, id: sessionId) else { throw RideSessionError.sessionNotFound(sessionId) }
            var pointRows: [RidePointRow] = []
            pointRows.reserveCapacity(points.count)
            for point in points {
                let (offset, overflow) = point.tMillis.subtractingReportingOverflow(row.startedAtMillis)
                guard !overflow, offset >= 0, offset <= Self.maxOffsetMillis else {
                    throw RideSessionError.pointOutsideSession(offsetMillis: overflow ? Int64.max : offset)
                }
                pointRows.append(
                    RidePointRow(
                        sessionId: sessionId, seq: Int(offset), tMillis: Int(offset), lat: point.lat, lon: point.lon, altM: point.altM,
                        speedMs: point.speedMs, hAccM: point.hAccM, vAccM: nil, cadence: point.cadence, intensity: point.intensity
                    )
                )
            }
            let usesMotion = points.contains { $0.cadence != nil || $0.intensity != nil }
            let accelerometerUsed: Int = (row.accelerometerUsed != 0 || usesMotion) ? 1 : 0
            let endedAt: Int64? = snapshot.state == .finished ? (row.endedAtMillis ?? flushedAt) : row.endedAtMillis
            try db.execute(
                sql: """
                    UPDATE ride_session
                    SET state = ?, pausesJson = ?, lastFlushMillis = ?, distanceMeters = ?, activeSeconds = ?, accelerometerUsed = ?, endedAtMillis = ?
                    WHERE id = ?
                    """,
                arguments: [snapshot.state.rawValue, pausesJson, flushedAt, snapshot.distanceMeters, snapshot.activeSeconds, accelerometerUsed, endedAt, sessionId]
            )
            try Self.insertPoints(db, pointRows)
        }
        live.set(LiveSnapshot(sessionId: sessionId, snapshot: snapshot))
    }

    /// Zmienia stan sesji (np. `.interrupted` po zabiciu procesu, `.finished` po zakończeniu — wtedy zapisuje też chwilę końca: dotychczasową,
    /// a gdy jej nie ma, `endedAtMillis` albo bieżący czas). `endedAtMillis` podaje wołający, który zna prawdziwy koniec jazdy (odzyskanie
    /// po zabiciu procesu: ostatnia aktywność z trasy, nie chwila zapisu).
    public func setState(sessionId: String, state: RideState, endedAtMillis: Int64? = nil) async throws {
        let nowMillis = Self.millis(now())
        try await db.write { db in
            guard let row = try Self.fetchSession(db, id: sessionId) else { throw RideSessionError.sessionNotFound(sessionId) }
            let ended: Int64? = state == .finished ? (row.endedAtMillis ?? endedAtMillis ?? nowMillis) : row.endedAtMillis
            try db.execute(sql: "UPDATE ride_session SET state = ?, endedAtMillis = ? WHERE id = ?", arguments: [state.rawValue, ended, sessionId])
        }
        live.set(nil)
    }

    /// Dodaje plik zrobiony w trakcie jazdy; ten sam `uri` zastępuje wcześniejszy wpis.
    public func addMedia(sessionId: String, uri: String, contentType: String, capturedAt: Date, lat: Double?, lon: Double?) async throws {
        let media = RideMediaRow(sessionId: sessionId, uri: uri, contentType: contentType, capturedAtMillis: Int(Self.millis(capturedAt)), lat: lat, lon: lon)
        try await insertMedia(media)
    }

    /// Usuwa sesję razem z punktami i plikami (klucz obcy z kaskadą). Same pliki zdjęć i filmów zostają — sprząta je zamiatacz.
    public func discard(sessionId: String) async throws {
        try await deleteSession(id: sessionId)
        live.set(nil)
    }

    // MARK: - Odzyskiwanie

    /// Sesja czekająca na zapisanie albo odrzucenie, z dystansem liczonym z zapisanych punktów, albo `nil`: `.recording`, `.paused`,
    /// `.interrupted` (bez działającego nagrywania) oraz `.finished` (jazda zakończona, a nagranie jeszcze niezapisane).
    public func unfinished() async throws -> UnfinishedRide? {
        try await db.read { db -> UnfinishedRide? in
            guard let row = try Self.pendingSession(db) else { return nil }
            // Uszkodzony wiersz (nieznany stan, nieczytelne progi, pauzy albo czas startu) nie może zablokować odzyskiwania — `start` odmawia,
            // dopóki wiersz istnieje, więc użytkownik musi móc go zapisać albo odrzucić. Wtedy stan to `.interrupted`, dystans pochodzi
            // z kolumny zapisanej przy ostatnim zapisie, a `damaged` mówi, że to odzyskanie częściowe.
            let known = RideState(rawValue: row.state)
            var damaged = known == nil
            var distance = row.distanceMeters
            let pointRows = try Self.fetchPoints(db, sessionId: row.id)
            do {
                let track = try Self.decodeTrack(row, points: pointRows)
                let recorder = RideRecorder.restore(
                    session: RideRestoreState(
                        startedAtMillis: track.startedAtMillis, thresholds: track.thresholds, state: track.state, lastFlushMillis: track.lastFlushMillis
                    ),
                    points: track.points,
                    pauses: track.pauses
                )
                distance = recorder.snapshot().distanceMeters
                if track.repaired { damaged = true }
            } catch {
                damaged = true
            }
            return UnfinishedRide(
                sessionId: row.id, horseName: row.horseName, startedAt: Self.date(row.startedAtMillis), distanceMeters: distance,
                state: known ?? .interrupted, damaged: damaged
            )
        }
    }

    /// Adresy plików zapisanych przy sesji — odczyt wprost z tabeli, więc działa także dla uszkodzonego wiersza sesji (sprzątanie po odrzuceniu).
    public func mediaUris(sessionId: String) async throws -> [String] {
        try await media(sessionId: sessionId).map(\.uri)
    }

    /// Adresy plików ze wszystkich sesji (zamiatacz: pliki spoza tej listy nie mają już odwołania).
    public func allMediaUris() async throws -> [String] {
        try await db.read { db in try String.fetchAll(db, sql: "SELECT uri FROM ride_media") }
    }

    /// Wczytuje sesję z punktami, pauzami i plikami. Błędne wartości z bazy są oczyszczane (pauza poza zakresem albo odwrócona, punkt
    /// z czasem poza zakresem, czas ostatniego zapisu poza sesją), nieznany stan wraca jako `.interrupted` — sesja się nie wywraca i nie
    /// znika. Rzuca `.sessionNotFound`, gdy sesji nie ma, i `.corruptSession`, gdy nie da się odczytać czasu startu, progów, obciążenia
    /// albo pauz.
    public func load(sessionId: String) async throws -> LoadedSession {
        try await db.read { db -> LoadedSession in
            guard let row = try Self.fetchSession(db, id: sessionId) else { throw RideSessionError.sessionNotFound(sessionId) }
            let track = try Self.decodeTrack(row, points: try Self.fetchPoints(db, sessionId: sessionId))
            let media = try Self.fetchMedia(db, sessionId: sessionId).map {
                RideMedia(uri: $0.uri, contentType: $0.contentType, capturedAt: Self.date(Int64($0.capturedAtMillis)), latitude: $0.lat, longitude: $0.lon)
            }
            let stored: StoredLoad
            do {
                stored = try JSONDecoder().decode(StoredLoad.self, from: Data(row.loadJson.utf8))
            } catch {
                throw RideSessionError.corruptSession(row.id)
            }
            let params = EffectiveRideParameters(
                thresholds: track.thresholds, load: stored.load, warnPercent: stored.warnPercent, heavyRidePoints: stored.heavyRidePoints,
                ownFields: stored.ownFields
            )
            let info = RideSessionInfo(
                id: row.id, horse: HorseRef(id: row.horseId, name: row.horseName, passportNumber: nil), state: track.state,
                startedAt: Self.date(row.startedAtMillis), endedAt: row.endedAtMillis.map { Self.date($0) }, timeZone: row.timeZone,
                accelerometerUsed: row.accelerometerUsed != 0, lastFlushMillis: track.lastFlushMillis, distanceMeters: row.distanceMeters,
                activeSeconds: row.activeSeconds
            )
            return LoadedSession(
                session: info, track: Track(startedAtMillis: track.startedAtMillis, points: track.points, pauses: track.pauses), media: media,
                params: params
            )
        }
    }

    // MARK: - Obserwacja (pasek NAG-01)

    /// Stan niezakończonej sesji dla paska NAG-01: ostatnia migawka z `flush`, a gdy jej nie ma (nowy proces) lub stan sesji zdążył się
    /// zmienić — wartości zapisane w bazie (bez prędkości i chodu). `nil`, gdy nie ma niezakończonej sesji.
    public func observeActive() -> AsyncStream<RideSnapshot?> {
        let rides = observeActiveRide()
        return AsyncStream<RideSnapshot?> { continuation in
            let task = Task {
                for await ride in rides { continuation.yield(ride?.snapshot) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// To samo co `observeActive`, ale razem z id sesji, koniem i początkiem (pasek „Trwa nagrywanie — Grom · 24 min · 3,2 km” i ekran jazdy).
    public func observeActiveRide() -> AsyncStream<ActiveRide?> {
        let writer = db
        let box = live
        return AsyncStream<ActiveRide?> { continuation in
            let merge = ActiveMerge(continuation)
            let rows = Task {
                let observation = ValueObservation.tracking { db in try Self.fetchActive(db) }
                do {
                    for try await row in observation.values(in: writer) { merge.setRow(row) }
                } catch {
                    // Obserwacja bazy padła (np. zamknięta baza) — strumień się kończy.
                }
                continuation.finish()
            }
            let updates = Task {
                for await snapshot in box.updates() { merge.setLive(snapshot) }
            }
            continuation.onTermination = { _ in
                rows.cancel()
                updates.cancel()
            }
        }
    }

    // MARK: - Wiersze sesji (zapytania bez logiki)

    /// Aktywna sesja nagrywania (najpóźniej rozpoczęta, niezakończona) — `nil`, gdy nie ma sesji.
    func activeSession() async throws -> RideSessionRow? {
        try await db.read { db in try Self.fetchActive(db) }
    }

    /// Sesja o podanym id.
    func session(id: String) async throws -> RideSessionRow? {
        try await db.read { db in try Self.fetchSession(db, id: id) }
    }

    /// Zapisz lub zaktualizuj sesję. Aktualizacja w miejscu (`ON CONFLICT … DO UPDATE`), nie `INSERT OR REPLACE`: zastąpienie
    /// usuwa wiersz, a `ON DELETE CASCADE` zabrałby wtedy punkty i pliki sesji.
    func saveSession(_ session: RideSessionRow) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO ride_session
                        (id, horseId, horseName, state, startedAtMillis, endedAtMillis, timeZone, pausesJson, thresholdsJson, loadJson, accelerometerUsed, lastFlushMillis, distanceMeters, activeSeconds)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        horseId = excluded.horseId, horseName = excluded.horseName, state = excluded.state,
                        startedAtMillis = excluded.startedAtMillis, endedAtMillis = excluded.endedAtMillis, timeZone = excluded.timeZone,
                        pausesJson = excluded.pausesJson, thresholdsJson = excluded.thresholdsJson, loadJson = excluded.loadJson,
                        accelerometerUsed = excluded.accelerometerUsed, lastFlushMillis = excluded.lastFlushMillis,
                        distanceMeters = excluded.distanceMeters, activeSeconds = excluded.activeSeconds
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

    /// Usuń sesję; punkty i pliki z jazdy usuwa klucz obcy `ON DELETE CASCADE`.
    func deleteSession(id: String) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM ride_session WHERE id = ?", arguments: [id])
        }
    }

    /// Punkty dla sesji, posortowane po seq.
    func points(sessionId: String) async throws -> [RidePointRow] {
        try await db.read { db in try Self.fetchPoints(db, sessionId: sessionId) }
    }

    /// Wstaw punkty (batch); ponowny zapis tego samego `seq` zastępuje wiersz.
    func insertPoints(_ points: [RidePointRow]) async throws {
        try await db.write { db in try Self.insertPoints(db, points) }
    }

    /// Pliki multimediów dla sesji, w kolejności zrobienia.
    func media(sessionId: String) async throws -> [RideMediaRow] {
        try await db.read { db in try Self.fetchMedia(db, sessionId: sessionId) }
    }

    /// Dodaj wpis media; ten sam `uri` zastępuje wcześniejszy wpis.
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

    // MARK: - Zapytania w transakcji

    private static let activeSql = "SELECT * FROM ride_session WHERE state != 'Finished' ORDER BY startedAtMillis DESC LIMIT 1"

    static func fetchActive(_ db: Database) throws -> RideSessionRow? {
        try Row.fetchOne(db, sql: activeSql).map { RideSessionRow(row: $0) }
    }

    /// Sesja czekająca na zapisanie albo odrzucenie: dowolny wiersz, a gdy jest ich kilka — najpierw niezakończony, potem najpóźniej
    /// rozpoczęty. `start` dopuszcza najwyżej jeden wiersz, więc zwykle to po prostu jedyna sesja (także `Finished`).
    static func pendingSession(_ db: Database) throws -> RideSessionRow? {
        let sql = "SELECT * FROM ride_session ORDER BY CASE WHEN state != 'Finished' THEN 0 ELSE 1 END, startedAtMillis DESC LIMIT 1"
        return try Row.fetchOne(db, sql: sql).map { RideSessionRow(row: $0) }
    }

    static func fetchSession(_ db: Database, id: String) throws -> RideSessionRow? {
        try Row.fetchOne(db, sql: "SELECT * FROM ride_session WHERE id = ?", arguments: [id]).map { RideSessionRow(row: $0) }
    }

    static func fetchPoints(_ db: Database, sessionId: String) throws -> [RidePointRow] {
        try Row.fetchAll(db, sql: "SELECT * FROM ride_point WHERE sessionId = ? ORDER BY seq ASC", arguments: [sessionId]).map { RidePointRow(row: $0) }
    }

    static func fetchMedia(_ db: Database, sessionId: String) throws -> [RideMediaRow] {
        try Row.fetchAll(db, sql: "SELECT * FROM ride_media WHERE sessionId = ? ORDER BY capturedAtMillis, uri", arguments: [sessionId])
            .map { RideMediaRow(row: $0) }
    }

    static func insertPoints(_ db: Database, _ points: [RidePointRow]) throws {
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

    // MARK: - Odczyt zapisanej trasy

    /// Trasa sesji odczytana z wierszy: progi, stan, czas ostatniego zapisu, punkty i pauzy po oczyszczeniu.
    struct StoredTrackData {
        let state: RideState
        let thresholds: GaitThresholds
        let startedAtMillis: Int64
        let lastFlushMillis: Int64
        let points: [TrackPoint]
        let pauses: [Pause]

        /// Czy coś pominięto albo poprawiono (pauza, punkt, czas ostatniego zapisu).
        let repaired: Bool
    }

    /// Dekoduje trasę sesji i oczyszcza ją z błędnych wartości, żeby arytmetyka `RideRecorder.restore` (Int64) nie mogła się przepełnić:
    /// czas startu musi leżeć w 1970–3000, punkt — w przesunięciu 0…`maxOffsetMillis` od startu, pauza — w tym samym zakresie z
    /// `start ≤ end`; czas ostatniego zapisu jest przycinany do zakresu sesji. Nieznany stan to `.interrupted`.
    /// Rzuca `.corruptSession`, gdy czas startu jest poza zakresem albo progi lub pauzy nie są poprawnym JSON.
    static func decodeTrack(_ row: RideSessionRow, points pointRows: [RidePointRow]) throws -> StoredTrackData {
        guard row.startedAtMillis >= 0, row.startedAtMillis <= maxEpochMillis else { throw RideSessionError.corruptSession(row.id) }
        let thresholds: StoredThresholds
        let storedPauses: [StoredPause]
        do {
            let decoder = JSONDecoder()
            thresholds = try decoder.decode(StoredThresholds.self, from: Data(row.thresholdsJson.utf8))
            storedPauses = try decoder.decode([StoredPause].self, from: Data(row.pausesJson.utf8))
        } catch {
            throw RideSessionError.corruptSession(row.id)
        }
        let startedAt = row.startedAtMillis
        let limit = startedAt + maxOffsetMillis
        var repaired = false

        var points: [TrackPoint] = []
        points.reserveCapacity(pointRows.count)
        for point in pointRows {
            let offset = Int64(point.tMillis)
            guard offset >= 0, offset <= maxOffsetMillis else {
                repaired = true
                continue
            }
            points.append(
                TrackPoint(
                    tMillis: startedAt + offset, lat: point.lat, lon: point.lon, altM: point.altM, speedMs: point.speedMs, hAccM: point.hAccM,
                    cadence: point.cadence, intensity: point.intensity
                )
            )
        }

        var pauses: [Pause] = []
        for pause in storedPauses {
            guard pause.startMillis >= startedAt, pause.endMillis >= pause.startMillis, pause.endMillis <= limit else {
                repaired = true
                continue
            }
            pauses.append(Pause(startMillis: pause.startMillis, endMillis: pause.endMillis))
        }

        let lastFlush = min(max(row.lastFlushMillis, startedAt), limit)
        if lastFlush != row.lastFlushMillis { repaired = true }
        return StoredTrackData(
            state: RideState(rawValue: row.state) ?? .interrupted, thresholds: thresholds.thresholds, startedAtMillis: startedAt,
            lastFlushMillis: lastFlush, points: points, pauses: pauses, repaired: repaired
        )
    }

    /// Stan z wiersza i migawka na żywo albo — gdy jej brak lub nie pasuje do sesji — wartości z kolumn (bez prędkości i chodu).
    /// Nieznany stan (uszkodzony zapis) to `.interrupted`, żeby strumień paska nie wywracał ekranu.
    static func snapshot(of row: RideSessionRow, live: LiveSnapshot?) -> RideSnapshot {
        if let live, live.sessionId == row.id, live.snapshot.state.rawValue == row.state { return live.snapshot }
        return RideSnapshot(
            state: RideState(rawValue: row.state) ?? .interrupted, activeSeconds: row.activeSeconds, distanceMeters: row.distanceMeters,
            speedKmh: nil, gait: nil, weakGps: false
        )
    }

    // MARK: - Pomocnicze

    static func date(_ millis: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func encode(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
