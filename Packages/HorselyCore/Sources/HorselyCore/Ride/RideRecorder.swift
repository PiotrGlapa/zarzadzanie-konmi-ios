import Foundation

// Maszyna stanów nagrywania jazdy (NAG-*) — port `RideRecorder.kt` z Androida 3.0.2: czysta logika bez zegara i bez systemu. Czas
// zawsze podaje wywołujący (`tMillis`, epoka w ms), więc zachowanie jest deterministyczne. Aktor nagrywania (zadanie 15) przekazuje
// punkty GPS, okna akcelerometru i tiki, a po zdarzeniach `.flushDue` zapisuje wynik `drainUnsaved()` oraz `snapshot()` w bazie.

/// Stan sesji nagrywania; nazwy zapisywane w kolumnie `ride_session.state`. `.interrupted` ustawia tylko repozytorium po zabiciu procesu.
public enum RideState: String, Sendable, Hashable, CaseIterable {
    case recording = "Recording"
    case paused = "Paused"
    case interrupted = "Interrupted"
    case finished = "Finished"
}

/// Zdarzenia, na które reaguje usługa nagrywania (powiadomienia, zapis, zakończenie).
public enum RideEvent: Sendable, Hashable {
    /// Od ponad 30 s nie było punktu o dokładności ≤ 25 m.
    case weakGpsStarted

    /// Po słabym sygnale przyszedł punkt o dokładności ≤ 25 m.
    case weakGpsEnded

    /// Bateria spadła do 15 % lub niżej — zgłaszane raz w sesji.
    case batteryLow

    /// Minęło 8 godzin od startu; nagrywanie jest zakończone (`.finished`), usługa ma zapisać i zamknąć jazdę.
    case autoFinished

    /// Minęło co najmniej 5 s od ostatniego `drainUnsaved()`; zdarzenie powtarza się przy kolejnych wywołaniach do czasu zapisu.
    case flushDue
}

/// Stan jazdy na żywo (pasek NAG-01 i powiadomienie): czas aktywny bez pauz, dystans z dobrych punktów, prędkość wygładzona
/// i chód. `speedKmh` i `gait` są `nil` przed pierwszą prędkością, w pauzie, po zakończeniu i przy słabym GPS (stara prędkość
/// wprowadzałaby w błąd).
public struct RideSnapshot: Sendable, Hashable {
    public var state: RideState
    public var activeSeconds: Int
    public var distanceMeters: Int
    public var speedKmh: Double?
    public var gait: Gait?
    public var weakGps: Bool

    public init(state: RideState, activeSeconds: Int, distanceMeters: Int, speedKmh: Double?, gait: Gait?, weakGps: Bool) {
        self.state = state
        self.activeSeconds = activeSeconds
        self.distanceMeters = distanceMeters
        self.speedKmh = speedKmh
        self.gait = gait
        self.weakGps = weakGps
    }
}

/// Dane sesji potrzebne do odtworzenia maszyny po zabiciu procesu (wypełnia je repozytorium z wiersza `ride_session`; rdzeń nie zna
/// bazy, więc wiersz mapuje warstwa wyżej). Dystans i czas aktywny nie są przechowywane osobno — maszyna liczy je ponownie z punktów
/// i pauz (dokładniej niż zaokrąglone kolumny). `lastFlushMillis` to czas ostatniego zapisu (epoka, ms).
public struct RideRestoreState: Sendable, Hashable {
    public var startedAtMillis: Int64
    public var thresholds: GaitThresholds
    public var state: RideState
    public var lastFlushMillis: Int64

    public init(startedAtMillis: Int64, thresholds: GaitThresholds, state: RideState, lastFlushMillis: Int64) {
        self.startedAtMillis = startedAtMillis
        self.thresholds = thresholds
        self.state = state
        self.lastFlushMillis = lastFlushMillis
    }
}

/// Maszyna stanów nagrywania. Reguły:
/// - punkty w pauzie (także dostarczone spóźnione ze znacznikiem z pauzy) i punkty niemonotoniczne są odrzucane;
/// - dystans na żywo i prędkość tylko z punktów o dokładności ≤ 25 m, bez skoku powyżej 70 km/h względem poprzedniego zachowanego
///   punktu (kotwicy); odcinek przez pauzę się nie liczy (haversine, `haversineMeters`); punkt gorszy lub ze skokiem zostaje w śladzie
///   (ślad jest surowy), ale nie wpływa na dystans; kotwica przesuwa się po skoku spójnym z poprzednio odrzuconym punktem albo po
///   3 skokach z rzędu (zob. `JumpAnchorFilter`) — trwałe przesunięcie współrzędnych nie blokuje dystansu;
/// - słaby GPS: > 30 s bez punktu o dokładności ≤ 25 m (licznik liczy od startu, wznowienia lub ostatniego dobrego punktu i nie biegnie w pauzie);
/// - bateria ≤ 15 % — jedno ostrzeżenie; po 8 h od startu — samoczynne zakończenie; zapis co 5 s (zdarzenie `.flushDue`).
///
/// Nie jest bezpieczna wątkowo i nie jest `Sendable` — aktor nagrywania (zadanie 15) tworzy ją u siebie i wywołuje z jednego kontekstu.
public final class RideRecorder {
    /// Najgorsza dokładność pozioma (m) punktu liczonego do dystansu i prędkości.
    public static let maxGoodAccuracyM = 25.0

    /// Prędkość (km/h) powyżej której skok między punktami uznaje się za błąd GPS.
    public static let maxJumpKmh = JumpAnchorFilter.maxJumpKmh

    private static let weakGpsMillis: Int64 = 30_000
    private static let batteryLowPercent = 15
    private static let autoFinishMillis: Int64 = 8 * 3600 * 1000
    private static let flushMillis: Int64 = 5_000
    private static let smoothingPoints = 3

    public let startedAtMillis: Int64

    private let stopMaxKmh: Double
    private let walkMaxKmh: Double
    private let trotMaxKmh: Double

    private var state = RideState.recording
    private var points: [TrackPoint] = []

    /// Liczba początkowych punktów już oddanych przez `drainUnsaved()`.
    private var savedCount = 0

    /// Indeksy (< `savedCount`) punktów uzupełnionych rytmem po zapisie — wracają w następnym `drainUnsaved()`.
    private var amended = Set<Int>()
    private var closedPauses: [Pause] = []
    private var pauseStart: Int64?

    private var lastTimeMillis: Int64
    private var lastFlushMillis: Int64

    private var distanceMeters = 0.0

    /// Kotwica dystansu i reguła odrzucania skoków GPS — wspólna ze statystykami końcowymi (`JumpAnchorFilter`).
    private var jumpFilter = JumpAnchorFilter()
    private var recentSpeedsMs: [Double] = []

    /// Od tej chwili liczy się 30 s słabego GPS: start, wznowienie albo ostatni punkt o dokładności ≤ 25 m.
    private var weakBaseMillis: Int64
    private var weakGps = false
    private var batteryWarned = false

    public init(startedAtMillis: Int64, thresholds: GaitThresholds) {
        self.startedAtMillis = startedAtMillis
        self.stopMaxKmh = NSDecimalNumber(decimal: thresholds.stopMaxKmh).doubleValue
        self.walkMaxKmh = NSDecimalNumber(decimal: thresholds.walkMaxKmh).doubleValue
        self.trotMaxKmh = NSDecimalNumber(decimal: thresholds.trotMaxKmh).doubleValue
        self.lastTimeMillis = startedAtMillis
        self.lastFlushMillis = startedAtMillis
        self.weakBaseMillis = startedAtMillis
    }

    /// Odtwarza maszynę z danych sesji, punktów i pauz zapisanych w bazie. Dla stanu `.paused` ostatnia pauza z `pauses` jest otwarta
    /// (jej koniec jest ignorowany; `pauses()` zapisuje ją w tej postaci). Stan `.interrupted` wraca jako `.paused` od chwili
    /// ostatniego zapisu — czas po nim (proces nie działał) nie jest czasem aktywnym, a wznowienie zamyka tę pauzę. Odtworzona maszyna
    /// nie ma niezapisanych punktów.
    public static func restore(session: RideRestoreState, points: [TrackPoint], pauses: [Pause]) -> RideRecorder {
        let recorder = RideRecorder(startedAtMillis: session.startedAtMillis, thresholds: session.thresholds)
        recorder.restoreFrom(session, savedPoints: points, savedPauses: pauses)
        return recorder
    }

    /// Zdarzenia po nowym punkcie GPS; punkt może zostać odrzucony (pauza, brak monotoniczności), a zdarzenia mimo to są oceniane.
    @discardableResult
    public func onLocation(_ p: TrackPoint) -> [RideEvent] {
        if state == .finished { return [] }
        touch(p.tMillis)
        var events: [RideEvent] = []
        if accept(p) && isGood(p) && weakGps {
            weakGps = false
            events.append(.weakGpsEnded)
        }
        evaluate(&events, batteryPercent: nil)
        return events
    }

    /// Zapisuje rytm i intensywność okna akcelerometru zakończonego w `tMillis` w punkcie zamykającym okno: ostatnim zachowanym punkcie
    /// o czasie ≤ `tMillis`. Dane ruchu w punkcie oznaczają więc „okno zamykane tym punktem” (tak liczy je statystyka jazdy, zadanie 18).
    /// Okno jest odrzucane (nic nie zapisuje), gdy:
    /// - nie ma punktu o czasie ≤ `tMillis` albo okno zakończyło się w pauzie;
    /// - najbliższy punkt jest starszy niż ostatnie wznowienie (koniec ostatniej zamkniętej pauzy) — okno przez pauzę w większości
    ///   obejmuje postój, a punkt sprzed pauzy ma już własne, poprawne dane ruchu (albo ich brak), których nie wolno zepsuć;
    /// - punkt ma już dane ruchu z innego okna (pierwsze okno wygrywa) — przy przerwie w GPS dłuższej niż okno kolejne okna nie
    ///   nadpisują wcześniejszej wartości, nawet gdy ich rytm to `nil`.
    /// Punkt uzupełniony po zapisie wróci w następnym `drainUnsaved()` (repozytorium zastępuje punkt o tym samym `tMillis`).
    public func onMotion(tMillis: Int64, _ m: WindowMotion) {
        if state == .finished || inPause(tMillis) { return }
        var i = points.count - 1
        while i >= 0 && points[i].tMillis > tMillis { i -= 1 }
        if i < 0 { return }
        let point = points[i]
        if let lastResume = closedPauses.last?.endMillis, point.tMillis < lastResume { return }
        // Intensywność jest niepusta w każdym punkcie zamykającym okno, więc `nil` oznacza punkt bez danych ruchu.
        if point.cadence != nil || point.intensity != nil { return }
        points[i].cadence = m.cadence
        points[i].intensity = m.intensity
        if i < savedCount { amended.insert(i) }
    }

    /// Wstrzymuje nagrywanie (od `tMillis` punkty są odrzucane, a czas nie liczy się do aktywnego). Poza stanem `.recording` — bez skutku.
    public func pause(tMillis: Int64) {
        if state != .recording { return }
        touch(tMillis)
        pauseStart = tMillis
        state = .paused
    }

    /// Wznawia po pauzie (`tMillis` kończy pauzę). Poza stanem `.paused` — bez skutku.
    public func resume(tMillis: Int64) {
        guard state == .paused, let start = pauseStart else { return }
        touch(tMillis)
        closedPauses.append(Pause(startMillis: start, endMillis: max(start, tMillis)))
        pauseStart = nil
        state = .recording
        breakSegment()
        weakBaseMillis = max(weakBaseMillis, tMillis)
    }

    /// Tik zegara (usługa wywołuje go co ok. 1 s, nie rzadziej niż co 5 s) z poziomem baterii w % albo `nil`, gdy nieznany.
    /// Ocenia słaby GPS, baterię, 8 h i zapis.
    @discardableResult
    public func tick(tMillis: Int64, batteryPercent: Int?) -> [RideEvent] {
        if state == .finished { return [] }
        touch(tMillis)
        var events: [RideEvent] = []
        evaluate(&events, batteryPercent: batteryPercent)
        return events
    }

    /// Stan na żywo na chwilę ostatniego zdarzenia (czas maszyny to największy `tMillis` jaki dostała).
    public func snapshot() -> RideSnapshot {
        let speedMs: Double? = (state == .recording && !weakGps) ? smoothedSpeedMs() : nil
        let speedKmh = speedMs.map { $0 * 3.6 }
        return RideSnapshot(
            state: state,
            activeSeconds: Int(activeMillis() / 1000),
            distanceMeters: Self.roundToInt(distanceMeters),
            speedKmh: speedKmh,
            gait: speedKmh.map(gaitFor),
            weakGps: weakGps
        )
    }

    /// Punkty do zapisania: nowe od ostatniego wywołania oraz uzupełnione rytmem po zapisie (w kolejności czasu). Ustawia chwilę
    /// ostatniego zapisu na czas maszyny — kolejne `.flushDue` po 5 s.
    @discardableResult
    public func drainUnsaved() -> [TrackPoint] {
        var out: [TrackPoint] = []
        out.reserveCapacity(amended.count + points.count - savedCount)
        for i in amended.sorted() { out.append(points[i]) }
        for i in savedCount..<points.count { out.append(points[i]) }
        amended.removeAll()
        savedCount = points.count
        lastFlushMillis = lastTimeMillis
        return out
    }

    /// Pauzy sesji do zapisu w `pausesJson`: zamknięte, a otwartą (stan `.paused`) z końcem równym czasowi maszyny — przy odtwarzaniu
    /// koniec otwartej jest ignorowany.
    public func pauses() -> [Pause] {
        guard let start = pauseStart else { return closedPauses }
        return closedPauses + [Pause(startMillis: start, endMillis: max(start, lastTimeMillis))]
    }

    // MARK: - Wnętrze

    /// `Math.round(double).toInt()` z Kotlina/Javy: `floor(x + 0,5)`, NaN → 0, wartości spoza zakresu obcinane (bez zatrzymania programu).
    private static func roundToInt(_ x: Double) -> Int {
        if x.isNaN { return 0 }
        let r = (x + 0.5).rounded(.down)
        if r >= Double(Int.max) { return Int.max }
        if r <= Double(Int.min) { return Int.min }
        return Int(r)
    }

    private func touch(_ tMillis: Int64) {
        if tMillis > lastTimeMillis { lastTimeMillis = tMillis }
    }

    private func isGood(_ p: TrackPoint) -> Bool {
        guard let accuracy = p.hAccM else { return false }
        return accuracy <= Self.maxGoodAccuracyM
    }

    private func inPause(_ tMillis: Int64) -> Bool {
        if let open = pauseStart, tMillis >= open { return true }
        for pause in closedPauses.reversed() {
            if tMillis >= pause.endMillis { return false }
            if tMillis >= pause.startMillis { return true }
        }
        return false
    }

    /// Zachowuje punkt w śladzie (jeśli nie jest w pauzie ani nie cofa czasu) i uwzględnia go w dystansie i prędkości; zwraca, czy został zachowany.
    private func accept(_ p: TrackPoint) -> Bool {
        if p.tMillis < startedAtMillis || inPause(p.tMillis) { return false }
        if let last = points.last, p.tMillis <= last.tMillis { return false }
        points.append(p)
        if isGood(p) {
            weakBaseMillis = p.tMillis
            countGoodPoint(p)
        }
        return true
    }

    /// Dystans i prędkość z punktu o dobrej dokładności względem kotwicy `jumpFilter` (reguła skoków i ponownego zakotwiczenia — opis
    /// `JumpAnchorFilter`). Punkt policzony dodaje dystans i prędkość; nowa kotwica bez dystansu przez lukę kasuje wygładzanie prędkości
    /// (bieżąca deklarowana prędkość staje się pierwszą); skok odrzucony nie zmienia niczego. Tę samą funkcję wykonuje odtwarzanie sesji
    /// (`restoreFrom`), więc dystans po restarcie jest identyczny jak na żywo.
    private func countGoodPoint(_ p: TrackPoint) {
        var declared: Double?
        if let speed = p.speedMs, speed.isFinite, speed >= 0.0 { declared = speed }
        switch jumpFilter.accept(p) {
        case let .counted(meters, seconds):
            distanceMeters += meters
            addSpeed(declared ?? (meters / seconds))
        case .anchored:
            recentSpeedsMs.removeAll()
            if let declared { addSpeed(declared) }
        case .rejected:
            break
        }
    }

    private func addSpeed(_ speedMs: Double) {
        recentSpeedsMs.append(speedMs)
        if recentSpeedsMs.count > Self.smoothingPoints { recentSpeedsMs.removeFirst() }
    }

    /// Mediana ostatnich `smoothingPoints` prędkości (przy dwóch — średnia); `nil` bez prędkości.
    private func smoothedSpeedMs() -> Double? {
        if recentSpeedsMs.isEmpty { return nil }
        let sorted = recentSpeedsMs.sorted()
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }

    private func gaitFor(_ speedKmh: Double) -> Gait {
        if speedKmh < stopMaxKmh { return .stop }
        if speedKmh < walkMaxKmh { return .walk }
        if speedKmh < trotMaxKmh { return .trot }
        return .canter
    }

    /// Czas aktywny: od startu do czasu maszyny, bez pauz zamkniętych i otwartej.
    private func activeMillis() -> Int64 {
        var paused: Int64 = 0
        for pause in closedPauses { paused += pause.endMillis - pause.startMillis }
        if let start = pauseStart { paused += max(0, lastTimeMillis - start) }
        return max(0, lastTimeMillis - startedAtMillis - paused)
    }

    /// Po wznowieniu odcinek przez pauzę nie liczy się do dystansu ani do prędkości.
    private func breakSegment() {
        jumpFilter.reset()
        recentSpeedsMs.removeAll()
    }

    private func evaluate(_ events: inout [RideEvent], batteryPercent: Int?) {
        let now = lastTimeMillis
        if now - startedAtMillis >= Self.autoFinishMillis {
            if let start = pauseStart { closedPauses.append(Pause(startMillis: start, endMillis: max(start, now))) }
            pauseStart = nil
            state = .finished
            events.append(.autoFinished)
            return
        }
        if state == .recording && !weakGps && now - weakBaseMillis > Self.weakGpsMillis {
            weakGps = true
            events.append(.weakGpsStarted)
        }
        if !batteryWarned, let battery = batteryPercent, battery <= Self.batteryLowPercent {
            batteryWarned = true
            events.append(.batteryLow)
        }
        if now - lastFlushMillis >= Self.flushMillis { events.append(.flushDue) }
    }

    /// Odtwarza stan z zapisanych danych (tylko `restore`); punkty uznaje za zapisane.
    private func restoreFrom(_ session: RideRestoreState, savedPoints: [TrackPoint], savedPauses: [Pause]) {
        var closed = savedPauses
        var openStart: Int64?
        let lastPointMillis = savedPoints.last?.tMillis ?? startedAtMillis
        let lastPauseEnd = savedPauses.last?.endMillis ?? startedAtMillis
        switch session.state {
        case .paused:
            // Ostatnia pauza jest otwarta (jej koniec to tylko czas zapisu) — trwa do wznowienia.
            openStart = savedPauses.last?.startMillis ?? session.lastFlushMillis
            closed = Array(savedPauses.dropLast())
        case .interrupted:
            // Zabity proces: luka od ostatniego zapisu nie jest czasem aktywnym, więc jazda wraca wstrzymana od zapisu.
            openStart = max(session.lastFlushMillis, lastPointMillis, lastPauseEnd)
        case .recording, .finished:
            break
        }
        closedPauses += closed
        switch session.state {
        case .recording: state = .recording
        case .finished: state = .finished
        case .paused, .interrupted: state = .paused
        }
        pauseStart = openStart
        lastTimeMillis = max(
            startedAtMillis, session.lastFlushMillis, lastPointMillis, lastPauseEnd, openStart ?? startedAtMillis
        )

        for p in savedPoints {
            breakSegmentAcrossPauses(untilMillis: p.tMillis)
            points.append(p)
            if isGood(p) {
                weakBaseMillis = p.tMillis
                countGoodPoint(p)
            }
        }
        breakSegmentAcrossPauses(untilMillis: Int64.max)
        if let lastClosed = closedPauses.last { weakBaseMillis = max(weakBaseMillis, lastClosed.endMillis) }
        savedCount = points.count
        lastFlushMillis = session.lastFlushMillis
    }

    /// Odtwarzanie: jeśli między ostatnim zachowanym punktem a `untilMillis` zakończyła się pauza, rozdziela odcinki jak `resume` na żywo.
    private func breakSegmentAcrossPauses(untilMillis: Int64) {
        guard let prev = jumpFilter.anchor else { return }
        if closedPauses.contains(where: { $0.endMillis > prev.tMillis && $0.endMillis <= untilMillis }) { breakSegment() }
    }
}
