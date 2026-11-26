import AVFoundation
import Foundation
import HorselyCore
import ImageIO

/// Chwila i miejsce wykonania pliku (ZAT-05): `capturedAt` oraz `latitude`/`longitude` (WGS84, stopnie). Każde pole osobno może być
/// `nil` — wiele plików ma sam czas albo nie ma nic. Współrzędne zawsze występują parą (obie albo żadna).
public struct MediaMetadata: Hashable, Sendable {
    public let capturedAt: Date?
    public let latitude: Double?
    public let longitude: Double?

    public init(capturedAt: Date?, latitude: Double?, longitude: Double?) {
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Plik bez żadnych metadanych (albo typ, z którego ich nie czytamy).
    public static let none = MediaMetadata(capturedAt: nil, latitude: nil, longitude: nil)

    /// Czy plik ma położenie (obie współrzędne).
    public var hasLocation: Bool { latitude != nil && longitude != nil }

    /// Te same metadane bez położenia (czas zostaje).
    var withoutLocation: MediaMetadata { MediaMetadata(capturedAt: capturedAt, latitude: nil, longitude: nil) }
}

/// Odczyt metadanych pliku wybranego z galerii (`MediaMetadataReader.kt` Androida; ZAT-05: plik dodany później dostaje pinezkę na mapie
/// trasy, gdy ma czas i położenie):
///  - zdjęcie: EXIF (`CGImageSource`) — `DateTimeOriginal` z `OffsetTimeOriginal` (bez przesunięcia: strefa telefonu) i położenie GPS
///    (znak z `GPSLatitudeRef`/`GPSLongitudeRef`);
///  - film: QuickTime (`AVAsset`) — położenie `commonIdentifierLocation` (ISO 6709, `±DD.DDDD±DDD.DDDD/`) i `creationDate`.
/// Metadane czyta się z kopii pliku PRZED przygotowaniem (zmniejszenie zdjęcia usuwa EXIF, przekodowanie filmu — metadane kontenera).
/// Plik uszkodzony albo bez metadanych daje `MediaMetadata.none`, nigdy błąd. Parsowanie tekstów jest osobno (czyste funkcje).
public enum MediaMetadataReader {
    /// Czasy sprzed tej chwili (1990-01-01 UTC) to „zero” aparatu (QuickTime liczy od 1904, EXIF bywa wyzerowany) — traktujemy jako brak.
    private static let earliest = Date(timeIntervalSince1970: 631_152_000)

    public static func read(file: URL, contentType: String) async -> MediaMetadata {
        if FilePolicy.isImage(contentType) { return readPhoto(file) }
        if FilePolicy.isVideo(contentType) { return await readVideo(file) }
        return .none
    }

    // MARK: Zdjęcie

    static func readPhoto(_ file: URL, zone: TimeZone = .current) -> MediaMetadata {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return .none }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let capturedAt = parseExifTime(
            exif?[kCGImagePropertyExifDateTimeOriginal] as? String, offset: exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String, zone: zone
        )
        let position = (properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]).flatMap(gpsLocation)
        return MediaMetadata(capturedAt: capturedAt, latitude: position?.latitude, longitude: position?.longitude)
    }

    /// Położenie ze słownika `{GPS}`: wartości są dodatnie, znak niesie `GPSLatitudeRef` (`S` = minus) i `GPSLongitudeRef` (`W` = minus).
    /// Jak `ExifInterface.latLong` Androida wymaga obu współrzędnych i obu oznaczeń stron świata.
    private static func gpsLocation(_ gps: [CFString: Any]) -> (latitude: Double, longitude: Double)? {
        guard let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue,
              let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
              let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String else { return nil }
        return validLocation(
            latitudeRef.uppercased().hasPrefix("S") ? -abs(latitude) : abs(latitude),
            longitudeRef.uppercased().hasPrefix("W") ? -abs(longitude) : abs(longitude)
        )
    }

    // MARK: Film

    private static func readVideo(_ file: URL) async -> MediaMetadata {
        let asset = AVURLAsset(url: file)
        // Uszkodzony albo nieobsługiwany plik: odczyt się nie udaje — film idzie bez metadanych.
        let position = await videoLocationText(asset).flatMap { parseLocation($0) }
        let capturedAt = await videoCreationDate(asset)
        return MediaMetadata(capturedAt: capturedAt, latitude: position?.latitude, longitude: position?.longitude)
    }

    private static func videoLocationText(_ asset: AVURLAsset) async -> String? {
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierLocation) {
            if let text = try? await item.load(.stringValue) { return text }
        }
        return nil
    }

    private static func videoCreationDate(_ asset: AVURLAsset) async -> Date? {
        guard let item = try? await asset.load(.creationDate) else { return nil }
        if let date = try? await item.load(.dateValue) { return date >= earliest ? date : nil }
        return parseVideoDate(try? await item.load(.stringValue))
    }

    // MARK: Czyste parsowanie tekstów

    /// Czas wykonania zdjęcia: `dateTime` w formacie EXIF `yyyy:MM:dd HH:mm:ss` i `offset` (`±HH:mm`, `OffsetTimeOriginal`). Bez przesunięcia
    /// czas jest lokalny, więc czytamy go w strefie telefonu (`zone`). `nil` dla pustego, wyzerowanego albo nieczytelnego czasu.
    static func parseExifTime(_ dateTime: String?, offset: String?, zone: TimeZone = .current) -> Date? {
        let text = (dateTime ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = text.split(whereSeparator: { $0 == ":" || $0 == " " })
        guard pieces.count == 6, pieces.enumerated().allSatisfy({ $0.element.count == ($0.offset == 0 ? 4 : 2) && $0.element.allSatisfy(Self.isDigit) }) else {
            return nil
        }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == 6 else { return nil }
        var timeZone = zone
        let shift = (offset ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !shift.isEmpty {
            guard let seconds = parseOffset(shift), let fixed = TimeZone(secondsFromGMT: seconds) else { return nil }
            timeZone = fixed
        }
        return date(numbers, in: timeZone).flatMap { $0 >= earliest ? $0 : nil }
    }

    /// Położenie z tekstu ISO 6709 filmu (`+52.2297+021.0122/`, z wysokością `+50.06+019.93+212.5/`, także z układem odniesienia
    /// `…+110.000CRSWGS_84/`, który zapisują iPhone'y): szerokość, długość; `nil`, gdy nie da się go odczytać albo jest poza zakresem.
    static func parseLocation(_ text: String?) -> (latitude: Double, longitude: Double)? {
        var rest = Substring((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        if rest.hasSuffix("/") { rest = rest.dropLast() }
        // Układ odniesienia (`CRSWGS_84`) po ostatniej liczbie.
        if let crs = rest.range(of: "CRS") {
            let name = rest[crs.upperBound...]
            guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
            rest = rest[..<crs.lowerBound]
        }
        var values: [Double] = []
        while !rest.isEmpty {
            guard let sign = rest.first, sign == "+" || sign == "-" else { return nil }
            let token = rest.dropFirst().prefix { Self.isDigit($0) || $0 == "." }
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }), let number = Double(token) else { return nil }
            values.append(sign == "-" ? -number : number)
            rest = rest.dropFirst(1 + token.count)
        }
        guard values.count == 2 || values.count == 3 else { return nil }
        return validLocation(values[0], values[1])
    }

    /// Czas utworzenia filmu: `yyyyMMdd'T'HHmmss[.SSS]'Z'` (UTC, jak w `MediaMetadataReader.kt`) albo ISO 8601 z przesunięciem
    /// (`2026-09-15T12:45:33+0200`, tak zapisuje QuickTime w iPhone'ach); `nil` dla pustego, wyzerowanego (1904) albo nieczytelnego.
    static func parseVideoDate(_ text: String?) -> Date? {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let parsed = parseCompactDate(value) ?? parseISODate(value) else { return nil }
        return parsed >= earliest ? parsed : nil
    }

    /// Współrzędne w zakresie WGS84; (0, 0) to „brak położenia” zapisany przez część aparatów. Para poza zakresem albo z `NaN` — brak
    /// położenia w całości.
    static func validLocation(_ latitude: Double, _ longitude: Double) -> (latitude: Double, longitude: Double)? {
        guard !latitude.isNaN, !longitude.isNaN, (-90.0 ... 90.0).contains(latitude), (-180.0 ... 180.0).contains(longitude) else { return nil }
        if latitude == 0, longitude == 0 { return nil }
        return (latitude, longitude)
    }

    // MARK: Pomocnicze

    private static func isDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }

    /// Gregoriańska data lokalna z liczb `[rok, miesiąc, dzień, godzina, minuta, sekunda]`; `nil` dla nieistniejącej (np. 31 lutego).
    private static func date(_ numbers: [Int], in zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(
            calendar: calendar, timeZone: zone, year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers[3], minute: numbers[4], second: numbers[5]
        )
        return components.isValidDate(in: calendar) ? calendar.date(from: components) : nil
    }

    /// Przesunięcie `Z`, `±HH`, `±HH:mm`, `±HHmm`, `±HH:mm:ss` w sekundach (najwyżej ±18:00, jak `ZoneOffset`).
    private static func parseOffset(_ text: String) -> Int? {
        if text == "Z" { return 0 }
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let digits = text.dropFirst().filter { $0 != ":" }
        guard digits.allSatisfy(Self.isDigit), [2, 4, 6].contains(digits.count) else { return nil }
        let hours = Int(digits.prefix(2)) ?? 0
        let minutes = digits.count >= 4 ? Int(digits.dropFirst(2).prefix(2)) ?? 0 : 0
        let seconds = digits.count == 6 ? Int(digits.dropFirst(4)) ?? 0 : 0
        let total = hours * 3600 + minutes * 60 + seconds
        guard minutes <= 59, seconds <= 59, total <= 18 * 3600 else { return nil }
        return sign == "-" ? -total : total
    }

    /// `yyyyMMdd'T'HHmmss[.fraction]'Z'` w UTC.
    private static func parseCompactDate(_ value: String) -> Date? {
        guard value.hasSuffix("Z") else { return nil }
        let body = value.dropLast()
        let halves = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let main = halves[0]
        guard main.count == 15, main.dropFirst(8).first == "T" else { return nil }
        let digits = main.filter { $0 != "T" }
        guard digits.count == 14, digits.allSatisfy(Self.isDigit) else { return nil }
        var fraction = 0.0
        if halves.count == 2 {
            let tail = halves[1]
            guard (1 ... 9).contains(tail.count), tail.allSatisfy(Self.isDigit), let value = Double("0." + tail) else { return nil }
            fraction = value
        }
        func number(_ start: Int, _ length: Int) -> Int { Int(digits.dropFirst(start).prefix(length)) ?? 0 }
        let numbers = [number(0, 4), number(4, 2), number(6, 2), number(8, 2), number(10, 2), number(12, 2)]
        return date(numbers, in: TimeZone(secondsFromGMT: 0) ?? .current).map { $0.addingTimeInterval(fraction) }
    }

    /// ISO 8601 z przesunięciem (`Z`, `+0200`, `+02:00`), z ułamkiem sekundy albo bez.
    private static func parseISODate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for pattern in ["yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ssXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXX"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
