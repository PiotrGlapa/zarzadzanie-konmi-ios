// Testy formatu trasy `zk-track/1` — port testu Androida 3.0.2 `core/src/test/.../ride/ZkTrackTest.kt`. Te same pliki wzorcowe
// (`Resources/golden/zk-track`, opis w `README.md` obok) czyta Android i UI webowe; dokument JSON jest umową, bajty gzip nie
// (różne kompresory dają różne bajty), więc porównujemy dokument po rozpakowaniu.

import Foundation
import Testing
@testable import HorselyCore

// MARK: - Pliki wzorcowe

private struct ZkFixtureFile: Decodable {
    let zrodlo: ZkFixtureTrack
    let odczyt: ZkFixtureTrack
}

private struct ZkFixtureTrack: Decodable {
    let startedAtMillis: Int64
    let points: [ZkFixturePoint]
    let pauses: [ZkFixturePause]

    var track: Track {
        Track(
            startedAtMillis: startedAtMillis,
            points: points.map {
                TrackPoint(tMillis: $0.tMillis, lat: $0.lat, lon: $0.lon, altM: $0.altM, speedMs: $0.speedMs, hAccM: $0.hAccM,
                           cadence: $0.cadence, intensity: $0.intensity)
            },
            pauses: pauses.map { Pause(startMillis: $0.startMillis, endMillis: $0.endMillis) }
        )
    }
}

private struct ZkFixturePoint: Decodable {
    let tMillis: Int64
    let lat: Double
    let lon: Double
    let altM: Double?
    let speedMs: Double?
    let hAccM: Double?
    let cadence: Double?
    let intensity: Double?
}

private struct ZkFixturePause: Decodable {
    let startMillis: Int64
    let endMillis: Int64
}

private func zkFixture() throws -> ZkFixtureFile {
    try JSONDecoder().decode(ZkFixtureFile.self, from: Fixtures.data("golden/zk-track/krotka.json"))
}

/// Sekcja `dokument` z `krotka.json` jako drzewo JSON (porównanie bez względu na kolejność pól).
private func zkFixtureDocument() throws -> NSDictionary {
    let object = try JSONSerialization.jsonObject(with: Fixtures.data("golden/zk-track/krotka.json"))
    let root = try #require(object as? NSDictionary)
    return try #require(root["dokument"] as? NSDictionary)
}

/// `krotka.b64` = bajty gzip dokumentu z Androida (`GZIPOutputStream`); plik to jedna linia bez końcowego znaku nowej linii.
private func zkGoldenBytes() throws -> Data {
    let text = try Fixtures.string("golden/zk-track/krotka.b64").trimmingCharacters(in: .whitespacesAndNewlines)
    return try #require(Data(base64Encoded: text))
}

private func zkGunzipText(_ bytes: Data) throws -> String {
    String(decoding: try Gzip.decompress(bytes, limit: 64 * 1024 * 1024), as: UTF8.self)
}

private func zkTree(_ text: String) throws -> NSDictionary {
    let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
    return try #require(object as? NSDictionary)
}

private func zkGzip(_ text: String) throws -> Data {
    try Gzip.compress(Data(text.utf8))
}

// MARK: - Jazda syntetyczna

/// Deterministyczny generator (SplitMix64) — Swift nie ma odpowiednika `kotlin.random.Random(seed)`, więc ciąg liczb różni się od
/// Androida; kształt jazdy i rozkłady wartości są te same, a testy sprawdzają własności (tolerancje, rozmiar), nie konkretne bajty.
private struct ZkSplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Jazda 1 Hz jak w teście Androida: łuk o zmiennej prędkości (stęp-kłus), szum GPS, wysokość z szumem, rytm i intensywność
/// co 5 s, dwie pauzy.
private func zkSyntheticRide(points: Int) -> Track {
    var random = ZkSplitMix64(state: 20_261_115)
    let t0: Int64 = 1_767_225_600_000
    var list: [TrackPoint] = []
    list.reserveCapacity(points)
    var lat = 51.7520
    var lon = -1.2577
    for i in 0 ..< points {
        let gait = (i / 300) % 2 == 0 ? 1.4 : 3.2
        let heading = Double(i) / 120.0
        lat += (gait * cos(heading) + Double.random(in: -0.3 ..< 0.3, using: &random)) / 111_320.0
        lon += (gait * sin(heading) + Double.random(in: -0.3 ..< 0.3, using: &random)) / 70_000.0
        let windowEnd = i % 5 == 4
        list.append(TrackPoint(
            tMillis: t0 + 1000 * Int64(i + 1) + Int64.random(in: -20 ..< 21, using: &random),
            lat: lat,
            lon: lon,
            altM: 100.0 + 10 * sin(Double(i) / 400.0) + Double.random(in: -0.4 ..< 0.4, using: &random),
            speedMs: gait + Double.random(in: -0.25 ..< 0.25, using: &random),
            hAccM: Double.random(in: 2.0 ..< 9.0, using: &random),
            cadence: windowEnd ? Double.random(in: 80.0 ..< 170.0, using: &random) : nil,
            intensity: windowEnd ? Double.random(in: 0.5 ..< 4.0, using: &random) : nil
        ))
    }
    return Track(
        startedAtMillis: t0,
        points: list,
        pauses: [Pause(startMillis: t0 + 600_500, endMillis: t0 + 640_250), Pause(startMillis: t0 + 2_000_000, endMillis: t0 + 2_030_000)]
    )
}

private func zkNear(_ expected: Double?, _ actual: Double?, _ delta: Double, _ field: String, _ index: Int) {
    guard let expected else {
        #expect(actual == nil, "\(field) w punkcie \(index)")
        return
    }
    guard let actual else {
        Issue.record("\(field) w punkcie \(index): brak wartości")
        return
    }
    #expect(abs(expected - actual) <= delta + 1e-12, "\(field) w punkcie \(index): \(expected) vs \(actual)")
}

// MARK: - Testy

@Test func zkTrackFormatName() {
    #expect(ZkTrack.format == "zk-track/1")
}

@Test func roundTripKeepsValuesWithinRounding() throws {
    let original = zkSyntheticRide(points: 600)
    let decoded = try ZkTrack.decode(ZkTrack.encode(original))
    #expect(decoded.startedAtMillis == original.startedAtMillis)
    #expect(decoded.pauses == original.pauses)
    #expect(decoded.points.count == original.points.count)
    for (i, (a, b)) in zip(original.points, decoded.points).enumerated() {
        #expect(a.tMillis == b.tMillis, "t w punkcie \(i)")
        #expect(abs(a.lat - b.lat) <= 1e-7, "lat w punkcie \(i)")
        #expect(abs(a.lon - b.lon) <= 1e-7, "lon w punkcie \(i)")
        zkNear(a.altM, b.altM, 0.05, "alt", i)
        zkNear(a.speedMs, b.speedMs, 0.005, "spd", i)
        zkNear(a.hAccM, b.hAccM, 0.5, "acc", i)
        zkNear(a.cadence, b.cadence, 0.05, "cad", i)
        zkNear(a.intensity, b.intensity, 0.0005, "int", i)
    }
}

@Test func roundTripKeepsNullsAndEmptyPauses() throws {
    let original = Track(
        startedAtMillis: 1_700_000_000_000,
        points: [
            TrackPoint(tMillis: 1_700_000_000_000, lat: 0.0, lon: 0.0, altM: nil, speedMs: nil, hAccM: nil, cadence: nil, intensity: nil),
            TrackPoint(tMillis: 1_700_000_001_000, lat: -33.8688197, lon: 151.2092955, altM: nil, speedMs: nil, hAccM: nil, cadence: nil, intensity: nil),
        ],
        pauses: []
    )
    let decoded = try ZkTrack.decode(ZkTrack.encode(original))
    #expect(decoded.points.map(\.tMillis) == original.points.map(\.tMillis))
    #expect(decoded.pauses.isEmpty)
    #expect(decoded.points.allSatisfy { $0.altM == nil && $0.speedMs == nil && $0.hAccM == nil && $0.cadence == nil && $0.intensity == nil })
    #expect(abs(decoded.points[1].lat - -33.8688197) <= 1e-9)
}

@Test func goldenBytesDecodeToFixture() throws {
    let fixture = try zkFixture()
    let bytes = try zkGoldenBytes()
    // dokument po rozpakowaniu = dokładnie to, co opisuje README i krotka.json (kolejność pól nie ma znaczenia dla porównania drzewa)
    let documentTree = try zkTree(zkGunzipText(bytes))
    let expectedDocument = try zkFixtureDocument()
    #expect(expectedDocument == documentTree)
    // czytnik daje wartości po zaokrągleniu do siatki formatu
    let decoded = try ZkTrack.decode(bytes)
    #expect(decoded == fixture.odczyt.track)
}

@Test func encodedDocumentEqualsAndroidAfterGunzip() throws {
    let fixture = try zkFixture()
    let encoded = try ZkTrack.encode(fixture.zrodlo.track)
    let androidText = try zkGunzipText(zkGoldenBytes())
    let encodedText = try zkGunzipText(encoded)
    // drzewo JSON z `krotka.json` (sekcja `dokument`) i dokument z Androida
    let expectedDocument = try zkFixtureDocument()
    let encodedTree = try zkTree(encodedText)
    #expect(expectedDocument == encodedTree)
    // kolejność pól i zwarty zapis są umową (README): porównujemy tekst po gunzipie, nie bajty gzipu
    #expect(encodedText == androidText)
    let decoded = try ZkTrack.decode(encoded)
    #expect(decoded == fixture.odczyt.track)
}

@Test func encodedBytesHaveRealGzipHeaderAndTrailer() throws {
    let encoded = try ZkTrack.encode(zkSyntheticRide(points: 50))
    let bytes = [UInt8](encoded)
    // nagłówek gzip (RFC 1952): magia 1f 8b, metoda 08 (deflate) — nie surowy deflate i nie zlib (78 xx)
    #expect(Array(bytes.prefix(3)) == [0x1F, 0x8B, 0x08])
    // stopka: CRC32 (4 B) i ISIZE (4 B, little-endian) = długość dokumentu po rozpakowaniu
    let documentLength = try Gzip.decompress(encoded, limit: 64 * 1024 * 1024).count
    let trailer = Array(bytes.suffix(4))
    let isize = trailer.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    #expect(isize == documentLength)
}

@Test func readsGzipWithOptionalHeaderFields() throws {
    // gzip z nazwą pliku (FNAME), komentarzem (FCOMMENT) i polem dodatkowym (FEXTRA) w nagłówku — czytnik musi je pominąć
    let document = #"{"v":1,"t0":100,"n":1,"dt":[3],"lat":[10],"lon":[-5],"alt":[-12],"spd":[150],"acc":[7],"cad":[null],"int":[null],"pauses":[[10,20]]}"#
    let plain = [UInt8](try zkGzip(document))
    var withFields = Array(plain[0 ..< 10])
    withFields[3] = 0x04 | 0x08 | 0x10
    withFields += [3, 0, 0xAA, 0xBB, 0xCC]          // FEXTRA: XLEN = 3 + dane
    withFields += Array("a.json".utf8) + [0]        // FNAME
    withFields += Array("komentarz".utf8) + [0]     // FCOMMENT
    withFields += plain[10...]
    let track = try ZkTrack.decode(Data(withFields))
    #expect(track.points.count == 1)
    #expect(track.points[0].tMillis == 103)
}

@Test func oneHourAt1HzIsUnder60KB() throws {
    let ride = zkSyntheticRide(points: 3600)
    let bytes = try ZkTrack.encode(ride)
    print("zk-track/1: 3600 punktów = \(bytes.count) B po gzip")
    #expect(bytes.count < 60 * 1024, "godzina jazdy ma \(bytes.count) B")
    // serwer sprawdza base64 i rozmiar po zdekodowaniu (≤ 5 242 880 B)
    #expect(bytes.base64EncodedString().count < 80 * 1024)
    let decoded = try ZkTrack.decode(bytes)
    #expect(decoded.points.count == 3600)
}

@Test func rejectsBytesThatAreNotZkTrackDocument() throws {
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(Data([1, 2, 3])) }
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(zkGzip(#"{"v":2,"t0":0,"n":0}"#)) }
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(zkGzip("[1,2]")) }
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(zkGzip("{nie json")) }
    // kolumna o złej długości
    let shortColumn = #"{"v":1,"t0":0,"n":2,"dt":[0],"lat":[0,0],"lon":[0,0],"alt":[null,null],"spd":[null,null],"acc":[null,null],"cad":[null,null],"int":[null,null],"pauses":[]}"#
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(zkGzip(shortColumn)) }
    // pusta wartość w kolumnie czasu
    let nullTime = #"{"v":1,"t0":0,"n":1,"dt":[null],"lat":[0],"lon":[0],"alt":[null],"spd":[null],"acc":[null],"cad":[null],"int":[null],"pauses":[]}"#
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(zkGzip(nullTime)) }
    // wartość niecałkowita (README: wszystkie liczby są całkowite)
    let fractional = #"{"v":1,"t0":0,"n":1,"dt":[1.0],"lat":[0],"lon":[0],"alt":[null],"spd":[null],"acc":[null],"cad":[null],"int":[null],"pauses":[]}"#
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(zkGzip(fractional)) }
    // pauza nie jest parą
    let badPause = #"{"v":1,"t0":0,"n":0,"dt":[],"lat":[],"lon":[],"alt":[],"spd":[],"acc":[],"cad":[],"int":[],"pauses":[[1]]}"#
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(zkGzip(badPause)) }
}

@Test func truncatedOrCorruptedGzipIsRejected() throws {
    let encoded = [UInt8](try ZkTrack.encode(zkSyntheticRide(points: 100)))
    // ucięty strumień
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(Data(encoded.dropLast(20))) }
    // przekłamana suma kontrolna w stopce
    var badCrc = encoded
    badCrc[badCrc.count - 8] ^= 0xFF
    #expect(throws: ZkTrackError.self) { try ZkTrack.decode(Data(badCrc)) }
}

@Test func gzipBombAbove64MiBIsRejected() throws {
    // Same spacje kompresują się prawie do zera: ~65 MiB po rozpakowaniu to kilkadziesiąt KB gzip.
    let bomb = try Gzip.compress(Data(repeating: 0x20, count: 65 * 1024 * 1024))
    #expect(bomb.count < 1024 * 1024, "bomba jest mała po kompresji: \(bomb.count) B")
    // Konkretny błąd limitu: bez limitu 65 MiB spacji rozpakowałoby się poprawnie (CRC i ISIZE się zgadzają) i dopiero parser JSON
    // rzuciłby `invalidJSON` — inny komunikat, więc usunięcie limitu w `Gzip.process` oblewa ten test.
    #expect { try ZkTrack.decode(bomb) } throws: { error in
        (error as? ZkTrackError) == ZkTrackError.tooLarge
    }
}

@Test func readsDocumentsWrittenByAnotherPlatformWithDifferentFieldOrder() throws {
    let document = #"{"pauses":[[10,20]],"int":[null],"cad":[null],"acc":[7],"spd":[150],"alt":[-12],"lon":[-5],"lat":[10],"dt":[3],"n":1,"t0":100,"v":1}"#
    let track = try ZkTrack.decode(zkGzip(document))
    let point = try #require(track.points.first)
    #expect(track.points.count == 1)
    #expect(point.tMillis == 103)
    #expect(abs(point.lat - 1e-6) <= 1e-12)
    let alt = try #require(point.altM)
    #expect(abs(alt - -1.2) <= 1e-9)
    #expect(point.hAccM == 7.0)
    #expect(track.pauses == [Pause(startMillis: 110, endMillis: 120)])
}

@Test func ignoresUnknownFieldsInRootObject() throws {
    let document = #"{"v":1,"t0":0,"n":0,"dt":[],"lat":[],"lon":[],"alt":[],"spd":[],"acc":[],"cad":[],"int":[],"pauses":[],"x":{"a":[1,"bA\n",true,null,-2.5e3]}}"#
    let track = try ZkTrack.decode(zkGzip(document))
    #expect(track.points.isEmpty)
    #expect(track.pauses.isEmpty)
}

@Test func roundsHalfAwayFromZeroOnDecimalRepresentation() throws {
    // 1,005 m/s · 100 = 100,5 → 101 (mnożenie w double dałoby 100,49999… → 100); −0,25 m · 10 = −2,5 → −3; 0,0005 · 1000 = 0,5 → 1
    let track = Track(
        startedAtMillis: 0,
        points: [
            TrackPoint(tMillis: 0, lat: 1.00000005, lon: -1.00000005, altM: -0.25, speedMs: 1.005, hAccM: 4.5, cadence: 87.25, intensity: 0.0005),
            TrackPoint(tMillis: 1, lat: 5e-8, lon: -5e-8, altM: 0.04, speedMs: 5e-5, hAccM: -2.5, cadence: 0.05, intensity: 1e-4),
        ],
        pauses: []
    )
    let text = try zkGunzipText(ZkTrack.encode(track))
    #expect(text == #"{"v":1,"t0":0,"n":2,"dt":[0,1],"lat":[10000001,-10000000],"lon":[-10000001,10000000],"alt":[-3,0],"spd":[101,0],"acc":[5,-3],"cad":[873,1],"int":[1,0],"pauses":[]}"#)
}

@Test func rejectsNonFiniteValues() {
    let nan = TrackPoint(tMillis: 1000, lat: .nan, lon: 0.0, altM: nil, speedMs: nil, hAccM: nil, cadence: nil, intensity: nil)
    #expect(throws: ZkTrackError.self) { try ZkTrack.encode(Track(startedAtMillis: 0, points: [nan], pauses: [])) }
    let infinite = TrackPoint(tMillis: 1000, lat: 0.0, lon: 0.0, altM: .infinity, speedMs: nil, hAccM: nil, cadence: nil, intensity: nil)
    #expect(throws: ZkTrackError.self) { try ZkTrack.encode(Track(startedAtMillis: 0, points: [infinite], pauses: [])) }
}
