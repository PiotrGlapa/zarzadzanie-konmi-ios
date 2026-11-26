import CoreGraphics
import Foundation
import HorselyCore
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HorselyKit

/// Metadane plików z galerii (ZAT-05; `MediaMetadataReaderTest.kt` Androida): chwila i miejsce wykonania ze zdjęcia (EXIF) albo filmu
/// (QuickTime). JPEG z EXIF i GPS powstaje w teście przez ImageIO (`CGImageDestination` z słownikiem metadanych) zamiast binarnego pliku
/// w zasobach, więc nie ma w repozytorium niezweryfikowanego pliku; film — próbka `SampleVideo` składana z atomów QuickTime. Parsowanie
/// tekstów (ISO 6709, daty) jest czystymi funkcjami, sprawdzanymi bez AVAsset.
struct MediaMetadataReaderTests {
    private func instant(_ text: String) throws -> Date {
        try #require(InstantText.parse(text), "data \(text)")
    }

    /// Mały JPEG (64 × 48) z podanymi słownikami `{Exif}` i `{GPS}` w metadanych.
    private func photo(exif: [CFString: Any]? = nil, gps: [CFString: Any]? = nil, in folder: URL, name: String = "zdjecie.jpg") throws -> URL {
        let context = try #require(CGContext(
            data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.04, green: 0.47, blue: 0.16, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let image = try #require(context.makeImage())
        var properties: [CFString: Any] = [:]
        if let exif { properties[kCGImagePropertyExifDictionary] = exif }
        if let gps { properties[kCGImagePropertyGPSDictionary] = gps }
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let url = folder.appendingPathComponent(name)
        try (output as Data).write(to: url)
        return url
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func gps(_ latitude: Double, _ latitudeRef: String, _ longitude: Double, _ longitudeRef: String) -> [CFString: Any] {
        [
            kCGImagePropertyGPSLatitude: latitude, kCGImagePropertyGPSLatitudeRef: latitudeRef,
            kCGImagePropertyGPSLongitude: longitude, kCGImagePropertyGPSLongitudeRef: longitudeRef,
        ]
    }

    // MARK: Zdjęcie

    @Test func exifGpsAndTimeAreRead() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try photo(
            exif: [kCGImagePropertyExifDateTimeOriginal: "2026:09:15 12:45:33", kCGImagePropertyExifOffsetTimeOriginal: "+02:00"],
            gps: gps(50.0614, "N", 19.9366, "E"), in: folder
        )

        let metadata = await MediaMetadataReader.read(file: file, contentType: "image/jpeg")

        #expect(metadata.capturedAt == (try instant("2026-09-15T10:45:33Z")), "czas zdjęcia z przesunięciem +02:00 w UTC")
        #expect(abs(try #require(metadata.latitude) - 50.0614) < 1e-4)
        #expect(abs(try #require(metadata.longitude) - 19.9366) < 1e-4)
        #expect(metadata.hasLocation)
    }

    @Test func southAndWestHemispheresGiveNegativeCoordinates() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try photo(gps: gps(33.8688, "S", 74.006, "W"), in: folder)

        let metadata = await MediaMetadataReader.read(file: file, contentType: "image/jpeg")

        #expect(abs(try #require(metadata.latitude) + 33.8688) < 1e-4)
        #expect(abs(try #require(metadata.longitude) + 74.006) < 1e-4)
        #expect(metadata.capturedAt == nil)
    }

    @Test func missingLocationGivesNil() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let timeOnly = try photo(exif: [kCGImagePropertyExifDateTimeOriginal: "2026:09:15 12:45:33"], in: folder, name: "czas.jpg")
        let withTime = MediaMetadataReader.readPhoto(timeOnly, zone: try #require(TimeZone(secondsFromGMT: 7200)))
        #expect(withTime.capturedAt == (try instant("2026-09-15T10:45:33Z")), "bez przesunięcia czas jest czasem strefy telefonu")
        #expect(withTime.latitude == nil && withTime.longitude == nil)
        #expect(!withTime.hasLocation)

        let bare = try photo(in: folder, name: "puste.jpg")
        #expect(await MediaMetadataReader.read(file: bare, contentType: "image/jpeg") == MediaMetadata.none)
    }

    @Test func zeroZeroIsNoLocationAndAnOutOfRangePairIsDroppedWholeButTheTimeStays() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2026:09:15 12:45:33", kCGImagePropertyExifOffsetTimeOriginal: "+00:00"]

        let zero = try photo(exif: exif, gps: gps(0, "N", 0, "E"), in: folder, name: "zero.jpg")
        let outside = try photo(exif: exif, gps: gps(95, "N", 21, "E"), in: folder, name: "poza.jpg")

        for file in [zero, outside] {
            let metadata = await MediaMetadataReader.read(file: file, contentType: "image/jpeg")
            #expect(metadata.latitude == nil && metadata.longitude == nil, "\(file.lastPathComponent): para poza zakresem albo (0, 0) to brak położenia")
            #expect(metadata.capturedAt == (try instant("2026-09-15T12:45:33Z")), "czas zostaje")
        }
    }

    @Test func aPhotoTimeWithoutAnOffsetIsReadInTheZoneOfThePhone() throws {
        let warsaw = try #require(TimeZone(identifier: "Europe/Warsaw"))

        #expect(MediaMetadataReader.parseExifTime("2026:01:10 12:00:00", offset: nil, zone: warsaw) == (try instant("2026-01-10T11:00:00Z")))
        #expect(MediaMetadataReader.parseExifTime("2026:07:10 12:00:00", offset: "", zone: warsaw) == (try instant("2026-07-10T10:00:00Z")))
        #expect(MediaMetadataReader.parseExifTime("2026:07:10 12:00:00", offset: "+00:00", zone: warsaw) == (try instant("2026-07-10T12:00:00Z")))
        #expect(MediaMetadataReader.parseExifTime("2026:07:10 12:00:00", offset: "-05:30", zone: warsaw) == (try instant("2026-07-10T17:30:00Z")))
    }

    @Test func anUnreadableOrEmptyExifTimeGivesNil() {
        #expect(MediaMetadataReader.parseExifTime(nil, offset: nil) == nil)
        #expect(MediaMetadataReader.parseExifTime("   ", offset: nil) == nil)
        #expect(MediaMetadataReader.parseExifTime("0000:00:00 00:00:00", offset: nil) == nil)
        #expect(MediaMetadataReader.parseExifTime("wczoraj", offset: "+02:00") == nil)
        #expect(MediaMetadataReader.parseExifTime("2026:02:31 10:00:00", offset: "+00:00") == nil, "nieistniejący dzień")
        #expect(MediaMetadataReader.parseExifTime("2026:09:15 12:45:33", offset: "jutro") == nil, "nieczytelne przesunięcie")
    }

    @Test func aFileThatIsNotAnImageGivesNoMetadata() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notImage = folder.appendingPathComponent("nie-obraz.jpg")
        try Data("to nie jest obraz".utf8).write(to: notImage)
        let pdf = folder.appendingPathComponent("dokument.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)

        #expect(await MediaMetadataReader.read(file: notImage, contentType: "image/jpeg") == MediaMetadata.none)
        #expect(await MediaMetadataReader.read(file: folder.appendingPathComponent("brak.jpg"), contentType: "image/jpeg") == MediaMetadata.none)
        #expect(await MediaMetadataReader.read(file: pdf, contentType: "application/pdf") == MediaMetadata.none)
    }

    // MARK: Film

    @Test func quicktimeIso6709LocationIsParsed() throws {
        let warsaw = try #require(MediaMetadataReader.parseLocation("+52.2297+021.0122/"))
        #expect(abs(warsaw.latitude - 52.2297) < 1e-9 && abs(warsaw.longitude - 21.0122) < 1e-9)

        let withAltitude = try #require(MediaMetadataReader.parseLocation("+50.0614+019.9366+212.500/"))
        #expect(abs(withAltitude.latitude - 50.0614) < 1e-9 && abs(withAltitude.longitude - 19.9366) < 1e-9)

        let south = try #require(MediaMetadataReader.parseLocation("-33.8688+151.2093/"))
        #expect(abs(south.latitude + 33.8688) < 1e-9 && abs(south.longitude - 151.2093) < 1e-9)

        let west = try #require(MediaMetadataReader.parseLocation("+40.7128-074.0060/"))
        #expect(abs(west.latitude - 40.7128) < 1e-9 && abs(west.longitude + 74.006) < 1e-9)

        let iPhone = try #require(MediaMetadataReader.parseLocation("+52.2297+021.0122+110.000CRSWGS_84/"), "tak zapisuje iPhone")
        #expect(abs(iPhone.latitude - 52.2297) < 1e-9 && abs(iPhone.longitude - 21.0122) < 1e-9)
    }

    @Test func aMalformedOrImpossibleLocationStringGivesNil() {
        #expect(MediaMetadataReader.parseLocation(nil) == nil)
        #expect(MediaMetadataReader.parseLocation("") == nil)
        #expect(MediaMetadataReader.parseLocation("Warszawa") == nil)
        #expect(MediaMetadataReader.parseLocation("+52.2297/") == nil)
        #expect(MediaMetadataReader.parseLocation("+52.2297+021.0122+1+2/") == nil)
        #expect(MediaMetadataReader.parseLocation("+52.+021.0122/") == nil)
        #expect(MediaMetadataReader.parseLocation("+95.0000+021.0000/") == nil, "szerokość poza ±90")
        #expect(MediaMetadataReader.parseLocation("+52.0000+200.0000/") == nil, "długość poza ±180")
        #expect(MediaMetadataReader.parseLocation("+00.0000+000.0000/") == nil, "0,0 to brak położenia zapisany przez niektóre aparaty")
    }

    @Test func quicktimeCreationDateIsParsed() throws {
        #expect(MediaMetadataReader.parseVideoDate("20260915T104533.250Z") == (try instant("2026-09-15T10:45:33.250Z")))
        #expect(MediaMetadataReader.parseVideoDate("20260915T104533Z") == (try instant("2026-09-15T10:45:33Z")))
        #expect(MediaMetadataReader.parseVideoDate("20260915T104533.000Z") == (try instant("2026-09-15T10:45:33Z")))
        #expect(MediaMetadataReader.parseVideoDate("2026-09-15T12:45:33+0200") == (try instant("2026-09-15T10:45:33Z")), "tak zapisuje iPhone")
        #expect(MediaMetadataReader.parseVideoDate("2026-09-15T12:45:33+02:00") == (try instant("2026-09-15T10:45:33Z")))
        #expect(MediaMetadataReader.parseVideoDate("2026-09-15T10:45:33Z") == (try instant("2026-09-15T10:45:33Z")))
        #expect(MediaMetadataReader.parseVideoDate(nil) == nil)
        #expect(MediaMetadataReader.parseVideoDate("jutro") == nil)
        #expect(MediaMetadataReader.parseVideoDate("19040101T000000.000Z") == nil, "puste zero QuickTime")
    }

    @Test func aVideoWithoutMetadataAndAFileThatIsNotAVideoGiveNothing() async throws {
        let sample = try await SampleVideo.make(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: sample.deletingLastPathComponent()) }
        let fake = sample.deletingLastPathComponent().appendingPathComponent("jazda.mp4")
        try Data((0 ..< 2048).map { UInt8(truncatingIfNeeded: $0 % 200) }).write(to: fake)

        #expect(await MediaMetadataReader.read(file: sample, contentType: "video/quicktime") == MediaMetadata.none, "próbka bez położenia i daty")
        #expect(await MediaMetadataReader.read(file: fake, contentType: "video/mp4") == MediaMetadata.none)
    }

    @Test func aMovieLocationIsReadThroughAVFoundation() async throws {
        let sample = try await SampleVideo.make(width: 64, height: 48, location: "+52.2297+021.0122/")
        defer { try? FileManager.default.removeItem(at: sample.deletingLastPathComponent()) }

        let metadata = await MediaMetadataReader.read(file: sample, contentType: "video/quicktime")

        #expect(abs(try #require(metadata.latitude) - 52.2297) < 1e-9)
        #expect(abs(try #require(metadata.longitude) - 21.0122) < 1e-9)
    }

    // MARK: Metadane w przygotowanym pliku i w załączniku

    private func store(keepLocation: Bool) throws -> AttachmentStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-meta-store-\(UUID().uuidString)", isDirectory: true)
        return AttachmentStore(
            store: RecordStore(database: try AppDatabase.inMemory()), files: try LocalFileStore(root: root.appendingPathComponent("Files", isDirectory: true)),
            client: nil, mode: { .standalone }, settings: { AttachmentSettings(keepPhotoLocation: keepLocation) }
        )
    }

    @Test func aGalleryPhotoKeepsItsTimeButNotItsLocationUnlessTheKeepLocationSettingIsOn() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try Data(contentsOf: photo(
            exif: [kCGImagePropertyExifDateTimeOriginal: "2026:09:15 12:45:33", kCGImagePropertyExifOffsetTimeOriginal: "+02:00"],
            gps: gps(50.0614, "N", 19.9366, "E"), in: folder
        ))
        #expect(ImagePreparer.hasGPS(data), "próbka ma GPS")

        let dropping = try await store(keepLocation: false).prepare(data: data, fileName: "zdjecie.jpg", mimeType: "image/jpeg")
        #expect(dropping.metadata.capturedAt == (try instant("2026-09-15T10:45:33Z")))
        #expect(dropping.metadata.latitude == nil && dropping.metadata.longitude == nil, "domyślnie lokalizacja jest usuwana ze zdjęć — także jako pole załącznika")
        #expect(!ImagePreparer.hasGPS(try Data(contentsOf: dropping.url)), "przygotowane zdjęcie nie niesie lokalizacji")

        let keeping = try await store(keepLocation: true).prepare(data: data, fileName: "zdjecie.jpg", mimeType: "image/jpeg")
        #expect(keeping.metadata.capturedAt == (try instant("2026-09-15T10:45:33Z")))
        #expect(abs(try #require(keeping.metadata.latitude) - 50.0614) < 1e-4)
        #expect(abs(try #require(keeping.metadata.longitude) - 19.9366) < 1e-4)
    }

    @Test func aMovieFromTheGalleryCarriesItsLocationInTheImportedFile() async throws {
        let sample = try await SampleVideo.make(width: 64, height: 48, location: "+52.2297+021.0122/")
        defer { try? FileManager.default.removeItem(at: sample.deletingLastPathComponent()) }

        let imported = try await store(keepLocation: false).prepare(fileAt: sample, mimeType: "video/quicktime")
        defer { try? FileManager.default.removeItem(at: imported.url.deletingLastPathComponent()) }

        #expect(abs(try #require(imported.metadata.latitude) - 52.2297) < 1e-9, "film nie podlega ustawieniu „Zachowuj lokalizację”")
        #expect(abs(try #require(imported.metadata.longitude) - 21.0122) < 1e-9)
    }

    @Test func aPendingAttachmentTakesTheTimeFromTheFileButTheCoordinatesOnlyForATraining() throws {
        let metadata = MediaMetadata(capturedAt: try instant("2026-09-15T10:45:33Z"), latitude: 50.0614, longitude: 19.9366)
        let file = ImportedFile(url: URL(fileURLWithPath: "/tmp/a.jpg"), fileName: "a.jpg", contentType: "image/jpeg", sizeBytes: 1, sha256: String(repeating: "a", count: 64), metadata: metadata)

        let pending = PendingAttachment(file: file)
        #expect(pending.capturedAt == metadata.capturedAt)
        #expect(pending.latitude == nil && pending.longitude == nil, "współrzędne nie są domyślane")

        let training = pending.forOwner(.training)
        #expect(training.capturedAt == metadata.capturedAt)
        #expect(training.latitude == DecimalText.parse("50.0614") && training.longitude == DecimalText.parse("19.9366"))

        let note = PendingAttachment(file: file, latitude: 1, longitude: 2).forOwner(.note)
        #expect(note.capturedAt == metadata.capturedAt, "czas wykonania zostaje wszędzie")
        #expect(note.latitude == nil && note.longitude == nil, "współrzędne tylko przy załączniku treningu")
        #expect(pending.forOwner(.horse).latitude == nil)

        let recorded = try instant("2026-09-15T08:00:00Z")
        let explicit = PendingAttachment(file: file, capturedAt: recorded, latitude: 52, longitude: 21).forOwner(.training)
        #expect(explicit.capturedAt == recorded && explicit.latitude == 52 && explicit.longitude == 21, "jawne z nagrania jazdy mają pierwszeństwo")

        let withoutLocation = ImportedFile(
            url: file.url, fileName: "b.jpg", contentType: "image/jpeg", sizeBytes: 1, sha256: file.sha256, metadata: metadata.withoutLocation
        )
        #expect(PendingAttachment(file: withoutLocation).forOwner(.training).latitude == nil, "zdjęcie bez położenia nie dostaje współrzędnych")
    }
}
