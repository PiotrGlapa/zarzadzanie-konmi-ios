import Foundation

// Format punktów trasy `zk-track/1` (port `ZkTrack.kt` z Androida 3.0.2; decyzja A7). Serwer przechowuje go bez interpretacji
// (sprawdza tylko base64, rozmiar ≤ 5 MB i `pointCount ≥ 2`), więc umową z Androidem i UI webowym są wyłącznie pliki
// `Tests/HorselyCoreTests/Resources/golden/zk-track/{README.md,krotka.json,krotka.b64}` — kopie 1:1 z repozytorium Androida.

/// Punkt trasy. `tMillis` to czas bezwzględny (epoka, ms). Wysokość `altM` w metrach, prędkość `speedMs` w m/s, dokładność poziomą
/// `hAccM` w metrach, rytm `cadence` w 1/min, intensywność `intensity` w m/s². Rytm i intensywność wypełnia tylko punkt zamykający
/// okno 5 s.
public struct TrackPoint: Sendable, Hashable {
    public var tMillis: Int64
    public var lat: Double
    public var lon: Double
    public var altM: Double?
    public var speedMs: Double?
    public var hAccM: Double?
    public var cadence: Double?
    public var intensity: Double?

    public init(
        tMillis: Int64, lat: Double, lon: Double, altM: Double?, speedMs: Double?, hAccM: Double?, cadence: Double?, intensity: Double?
    ) {
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

/// Pauza nagrania: `startMillis` i `endMillis` to czasy bezwzględne (epoka, ms).
public struct Pause: Sendable, Hashable {
    public var startMillis: Int64
    public var endMillis: Int64

    public init(startMillis: Int64, endMillis: Int64) {
        self.startMillis = startMillis
        self.endMillis = endMillis
    }
}

/// Trasa nagrania: `startedAtMillis` (epoka, ms) jest punktem odniesienia czasu pierwszego punktu i pauz.
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

/// Błąd trasy: dane nie są poprawnym dokumentem `zk-track/1` albo zapisywana wartość jest niedozwolona (`message` po polsku).
public struct ZkTrackError: Error, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    static let notGzip = ZkTrackError("Trasa nie jest poprawnym gzipem.")
    static let invalidJSON = ZkTrackError("Dokument trasy nie jest poprawnym JSON.")
    static let tooLarge = ZkTrackError("Trasa po rozpakowaniu jest zbyt duża.")
}

/// Kodek `zk-track/1`: gzip z dokumentu JSON z kolumnami (kolejność pól i reguły zaokrągleń — `golden/zk-track/README.md`).
public enum ZkTrack {
    public static let format = "zk-track/1"

    /// Wersja dokumentu (pole `v`).
    private static let version: Int64 = 1

    /// Najwięcej bajtów po rozpakowaniu (64 MiB) — ochrona przed „bombą” gzip; realna trasa (8 h co sekundę) to kilka MB JSON.
    private static let maxDocumentBytes = 64 * 1024 * 1024

    /// Koduje `track` do gzipu z dokumentu JSON; bajty gzip zależą od kompresora, dokument po rozpakowaniu jest jednoznaczny.
    public static func encode(_ track: Track) throws -> Data {
        try Gzip.compress(Data(document(track).utf8))
    }

    /// Czyta bajty `zk-track/1` (gzip). Rzuca `ZkTrackError`, gdy bajty nie są poprawnym dokumentem w wersji 1.
    public static func decode(_ data: Data) throws -> Track {
        let text = try Gzip.decompress(data, limit: maxDocumentBytes)
        guard case .object(let root) = try ZkJSONParser.parse(text) else {
            throw ZkTrackError("Dokument trasy nie jest obiektem JSON.")
        }
        return try read(root)
    }

    // MARK: - Zapis

    private static func document(_ track: Track) throws -> String {
        let points = track.points
        let count = points.count
        let t0 = track.startedAtMillis
        var text = ""
        text.reserveCapacity(64 + count * 48)
        text += "{\"v\":\(version),\"t0\":\(t0),\"n\":\(count)"

        var previousTime = t0
        try appendColumn(&text, "dt", count) { i in
            let time = points[i].tMillis
            let delta = time &- previousTime
            previousTime = time
            return delta
        }
        var previousLat: Int64 = 0
        try appendColumn(&text, "lat", count) { i in
            let value = try scaled(points[i].lat, digits: 7, field: "lat")
            let delta = value &- previousLat
            previousLat = value
            return delta
        }
        var previousLon: Int64 = 0
        try appendColumn(&text, "lon", count) { i in
            let value = try scaled(points[i].lon, digits: 7, field: "lon")
            let delta = value &- previousLon
            previousLon = value
            return delta
        }
        try appendColumn(&text, "alt", count) { i in try points[i].altM.map { try scaled($0, digits: 1, field: "alt") } }
        try appendColumn(&text, "spd", count) { i in try points[i].speedMs.map { try scaled($0, digits: 2, field: "spd") } }
        try appendColumn(&text, "acc", count) { i in try points[i].hAccM.map { try scaled($0, digits: 0, field: "acc") } }
        try appendColumn(&text, "cad", count) { i in try points[i].cadence.map { try scaled($0, digits: 1, field: "cad") } }
        try appendColumn(&text, "int", count) { i in try points[i].intensity.map { try scaled($0, digits: 3, field: "int") } }

        text += ",\"pauses\":["
        for (i, pause) in track.pauses.enumerated() {
            if i > 0 { text += "," }
            text += "[\(pause.startMillis &- t0),\(pause.endMillis &- t0)]"
        }
        text += "]}"
        return text
    }

    private static func appendColumn(_ text: inout String, _ name: String, _ count: Int, _ value: (Int) throws -> Int64?) throws {
        text += ",\"\(name)\":["
        for i in 0 ..< count {
            if i > 0 { text += "," }
            if let number = try value(i) {
                text += String(number)
            } else {
                text += "null"
            }
        }
        text += "]"
    }

    /// Wartość × 10^`digits`, zaokrąglona HALF_UP (połówki od zera) do liczby całkowitej — jak
    /// `BigDecimal.valueOf(x).scaleByPowerOfTen(digits).setScale(0, RoundingMode.HALF_UP)` w Androidzie. Liczymy na dziesiętnym zapisie
    /// najkrótszej reprezentacji liczby (`Double.description`, jak `Double.toString` w Javie), żeby 1,005 · 100 dawało 100,5 → 101,
    /// a nie 100,49999… → 100. Cała arytmetyka na liczbach całkowitych — bez `Decimal` i bez mnożenia w `Double`.
    static func scaled(_ value: Double, digits: Int, field: String) throws -> Int64 {
        guard value.isFinite else { throw ZkTrackError("Pole \(field) trasy musi być liczbą skończoną.") }
        let outOfRange = ZkTrackError("Pole \(field) trasy jest poza zakresem.")

        // `description` to np. "-51.752", "5e-05", "1.2345e+17"
        var text = value.description
        let negative = text.hasPrefix("-")
        if negative { text.removeFirst() }
        var exponent = 0
        var mantissa = Substring(text)
        if let marker = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            guard let parsed = Int(text[text.index(after: marker)...]) else { throw outOfRange }
            exponent = parsed
            mantissa = text[..<marker]
        }
        var fractionLength = 0
        var integerAndFraction = String(mantissa)
        if let dot = mantissa.firstIndex(of: ".") {
            fractionLength = mantissa.distance(from: mantissa.index(after: dot), to: mantissa.endIndex)
            integerAndFraction = String(mantissa[..<dot]) + String(mantissa[mantissa.index(after: dot)...])
        }
        // wartość = cyfry × 10^(exponent − fractionLength); po pomnożeniu przez 10^digits: cyfry × 10^shift
        let decimalDigits = integerAndFraction.utf8.map { Int($0) - 48 }
        guard !decimalDigits.isEmpty, decimalDigits.allSatisfy({ (0 ... 9).contains($0) }) else { throw outOfRange }
        let shift = exponent - fractionLength + digits

        let magnitude: Int64
        if shift >= 0 {
            guard var number = integer(decimalDigits[...]) else { throw outOfRange }
            if number != 0 {
                for _ in 0 ..< shift {
                    let (next, overflow) = number.multipliedReportingOverflow(by: 10)
                    if overflow { throw outOfRange }
                    number = next
                }
            }
            magnitude = number
        } else {
            let keep = decimalDigits.count + shift // ile cyfr zostaje przed przecinkiem; reszta to część ułamkowa
            guard let integral = keep > 0 ? integer(decimalDigits[0 ..< keep]) : 0 else { throw outOfRange }
            // HALF_UP „od zera" na module: o zaokrągleniu decyduje pierwsza odrzucana cyfra (>= 5 → w górę)
            let roundsUp = keep >= 0 && decimalDigits[keep] >= 5
            let (rounded, overflow) = integral.addingReportingOverflow(roundsUp ? 1 : 0)
            if overflow { throw outOfRange }
            magnitude = rounded
        }
        return negative ? -magnitude : magnitude
    }

    /// Liczba z cyfr dziesiętnych (`nil` przy przepełnieniu `Int64`).
    private static func integer(_ digits: ArraySlice<Int>) -> Int64? {
        var number: Int64 = 0
        for digit in digits {
            let (shifted, overflowMultiply) = number.multipliedReportingOverflow(by: 10)
            let (sum, overflowAdd) = shifted.addingReportingOverflow(Int64(digit))
            if overflowMultiply || overflowAdd { return nil }
            number = sum
        }
        return number
    }

    // MARK: - Odczyt

    private static func read(_ root: [String: ZkJSONValue]) throws -> Track {
        let documentVersion = try integer(root, "v")
        guard documentVersion == version else { throw ZkTrackError("Nieobsługiwana wersja trasy: \(documentVersion).") }
        let t0 = try integer(root, "t0")
        let pointCount = try integer(root, "n")
        guard pointCount >= 0, pointCount <= Int64(Int32.max) else { throw ZkTrackError("Zła liczba punktów: \(pointCount).") }
        let n = Int(pointCount)

        let dt = try column(root, "dt", n)
        let lat = try column(root, "lat", n)
        let lon = try column(root, "lon", n)
        let alt = try column(root, "alt", n)
        let spd = try column(root, "spd", n)
        let acc = try column(root, "acc", n)
        let cad = try column(root, "cad", n)
        let intensity = try column(root, "int", n)

        var time = t0
        var latScaled: Int64 = 0
        var lonScaled: Int64 = 0
        var points: [TrackPoint] = []
        points.reserveCapacity(n)
        for i in 0 ..< n {
            guard let timeDelta = dt[i] else { throw ZkTrackError("Kolumna dt: pusta wartość w punkcie \(i).") }
            guard let latDelta = lat[i] else { throw ZkTrackError("Kolumna lat: pusta wartość w punkcie \(i).") }
            guard let lonDelta = lon[i] else { throw ZkTrackError("Kolumna lon: pusta wartość w punkcie \(i).") }
            time = try add(time, timeDelta)
            latScaled = try add(latScaled, latDelta)
            lonScaled = try add(lonScaled, lonDelta)
            points.append(TrackPoint(
                tMillis: time,
                lat: Double(latScaled) / 1e7,
                lon: Double(lonScaled) / 1e7,
                altM: alt[i].map { Double($0) / 10.0 },
                speedMs: spd[i].map { Double($0) / 100.0 },
                hAccM: acc[i].map { Double($0) },
                cadence: cad[i].map { Double($0) / 10.0 },
                intensity: intensity[i].map { Double($0) / 1000.0 }
            ))
        }

        guard case .array(let pauseList)? = root["pauses"] else { throw ZkTrackError("Brak tablicy pauses.") }
        var pauses: [Pause] = []
        pauses.reserveCapacity(pauseList.count)
        for element in pauseList {
            guard case .array(let pair) = element, pair.count == 2, case .integer(let start) = pair[0], case .integer(let end) = pair[1] else {
                throw ZkTrackError("Pauza musi być parą [start, koniec].")
            }
            pauses.append(Pause(startMillis: try add(t0, start), endMillis: try add(t0, end)))
        }
        return Track(startedAtMillis: t0, points: points, pauses: pauses)
    }

    private static func add(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (sum, overflow) = a.addingReportingOverflow(b)
        if overflow { throw ZkTrackError("Wartość w dokumencie trasy jest poza zakresem.") }
        return sum
    }

    private static func integer(_ root: [String: ZkJSONValue], _ name: String) throws -> Int64 {
        guard case .integer(let value)? = root[name] else { throw ZkTrackError("Brak pola \(name) albo nie jest liczbą całkowitą.") }
        return value
    }

    private static func column(_ root: [String: ZkJSONValue], _ name: String, _ n: Int) throws -> [Int64?] {
        guard case .array(let array)? = root[name] else { throw ZkTrackError("Brak tablicy \(name).") }
        guard array.count == n else { throw ZkTrackError("Kolumna \(name) ma \(array.count) wartości zamiast \(n).") }
        return try array.map { element -> Int64? in
            switch element {
            case .null: return nil
            case .integer(let value): return value
            default: throw ZkTrackError("Kolumna \(name): wartość nie jest liczbą całkowitą.")
            }
        }
    }
}

// MARK: - Czytnik JSON

/// Wartość JSON. Liczby całkowite (`Int64`) odróżniamy od pozostałych (`1.0`, `1e3`, poza zakresem) — README formatu mówi, że w
/// dokumencie są wyłącznie liczby całkowite, a `JSONSerialization` zamazałby tę różnicę.
fileprivate enum ZkJSONValue {
    case object([String: ZkJSONValue])
    case array([ZkJSONValue])
    case integer(Int64)
    case nonInteger
    case string(String)
    case bool(Bool)
    case null
}

/// Ścisły czytnik JSON (RFC 8259) na bajtach UTF-8; powtórzony klucz — wygrywa ostatni (jak w kotlinx.serialization).
fileprivate struct ZkJSONParser {
    private static let maxDepth = 64

    private let bytes: [UInt8]
    private var position = 0

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    static func parse(_ data: Data) throws -> ZkJSONValue {
        var parser = ZkJSONParser(bytes: [UInt8](data))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.position == parser.bytes.count else { throw ZkTrackError.invalidJSON }
        return value
    }

    private var current: UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private mutating func skipWhitespace() {
        while let c = current, c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 {
            position += 1
        }
    }

    private mutating func skipDigits() {
        while let c = current, Self.isDigit(c) {
            position += 1
        }
    }

    private mutating func literal(_ text: String) throws {
        for byte in text.utf8 {
            guard current == byte else { throw ZkTrackError.invalidJSON }
            position += 1
        }
    }

    private mutating func value(depth: Int) throws -> ZkJSONValue {
        guard depth <= Self.maxDepth, let c = current else { throw ZkTrackError.invalidJSON }
        switch c {
        case UInt8(ascii: "{"): return try object(depth: depth)
        case UInt8(ascii: "["): return try array(depth: depth)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"):
            try literal("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try literal("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try literal("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0") ... UInt8(ascii: "9"):
            return try number()
        default:
            throw ZkTrackError.invalidJSON
        }
    }

    private mutating func object(depth: Int) throws -> ZkJSONValue {
        position += 1 // '{'
        var fields: [String: ZkJSONValue] = [:]
        skipWhitespace()
        if current == UInt8(ascii: "}") {
            position += 1
            return .object(fields)
        }
        while true {
            skipWhitespace()
            guard current == UInt8(ascii: "\"") else { throw ZkTrackError.invalidJSON }
            let key = try string()
            skipWhitespace()
            guard current == UInt8(ascii: ":") else { throw ZkTrackError.invalidJSON }
            position += 1
            skipWhitespace()
            fields[key] = try value(depth: depth + 1)
            skipWhitespace()
            guard let separator = current else { throw ZkTrackError.invalidJSON }
            switch separator {
            case UInt8(ascii: ","): position += 1
            case UInt8(ascii: "}"):
                position += 1
                return .object(fields)
            default: throw ZkTrackError.invalidJSON
            }
        }
    }

    private mutating func array(depth: Int) throws -> ZkJSONValue {
        position += 1 // '['
        var items: [ZkJSONValue] = []
        skipWhitespace()
        if current == UInt8(ascii: "]") {
            position += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try value(depth: depth + 1))
            skipWhitespace()
            guard let separator = current else { throw ZkTrackError.invalidJSON }
            switch separator {
            case UInt8(ascii: ","): position += 1
            case UInt8(ascii: "]"):
                position += 1
                return .array(items)
            default: throw ZkTrackError.invalidJSON
            }
        }
    }

    private mutating func number() throws -> ZkJSONValue {
        let start = position
        if current == UInt8(ascii: "-") { position += 1 }
        guard let first = current, Self.isDigit(first) else { throw ZkTrackError.invalidJSON }
        if first == UInt8(ascii: "0") {
            position += 1
        } else {
            skipDigits()
        }
        var isInteger = true
        if current == UInt8(ascii: ".") {
            isInteger = false
            position += 1
            guard let digit = current, Self.isDigit(digit) else { throw ZkTrackError.invalidJSON }
            skipDigits()
        }
        if current == UInt8(ascii: "e") || current == UInt8(ascii: "E") {
            isInteger = false
            position += 1
            if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") { position += 1 }
            guard let digit = current, Self.isDigit(digit) else { throw ZkTrackError.invalidJSON }
            skipDigits()
        }
        guard isInteger, let value = Int64(String(decoding: bytes[start ..< position], as: UTF8.self)) else { return .nonInteger }
        return .integer(value)
    }

    private mutating func string() throws -> String {
        position += 1 // otwierający cudzysłów
        var out: [UInt8] = []
        while let c = current {
            position += 1
            switch c {
            case UInt8(ascii: "\""):
                return String(decoding: out, as: UTF8.self)
            case UInt8(ascii: "\\"):
                guard let escaped = current else { throw ZkTrackError.invalidJSON }
                position += 1
                switch escaped {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(escaped)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"): out.append(contentsOf: try unicodeEscape())
                default: throw ZkTrackError.invalidJSON
                }
            case 0x00 ..< 0x20:
                throw ZkTrackError.invalidJSON
            default:
                out.append(c)
            }
        }
        throw ZkTrackError.invalidJSON
    }

    /// Znaki po `\u`: cztery cyfry szesnastkowe, ewentualnie z drugą połówką pary zastępczej.
    private mutating func unicodeEscape() throws -> [UInt8] {
        let replacement = Array("\u{FFFD}".utf8)
        var unit = try hex4()
        if unit >= 0xD800 && unit < 0xDC00 {
            guard current == UInt8(ascii: "\\"), position + 1 < bytes.count, bytes[position + 1] == UInt8(ascii: "u") else { return replacement }
            position += 2
            let low = try hex4()
            guard low >= 0xDC00 && low < 0xE000 else { return replacement }
            unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
        }
        guard let scalar = Unicode.Scalar(unit) else { return replacement }
        return Array(String(Character(scalar)).utf8)
    }

    private mutating func hex4() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0 ..< 4 {
            guard let c = current else { throw ZkTrackError.invalidJSON }
            let digit: UInt32
            switch c {
            case UInt8(ascii: "0") ... UInt8(ascii: "9"): digit = UInt32(c - UInt8(ascii: "0"))
            case UInt8(ascii: "a") ... UInt8(ascii: "f"): digit = UInt32(c - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A") ... UInt8(ascii: "F"): digit = UInt32(c - UInt8(ascii: "A")) + 10
            default: throw ZkTrackError.invalidJSON
            }
            value = (value << 4) | digit
            position += 1
        }
        return value
    }
}
