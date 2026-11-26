import AVFoundation
import CoreVideo
import Foundation
import HorselyCore
import ImageIO
import Testing
@testable import HorselyKit

/// Miniatura pierwszej klatki i odczyt parametrów filmu na prawdziwym pliku (`VideoThumbnailTest.kt` Androida). Próbka 1 s powstaje w teście
/// (`SampleVideo`, Photo-JPEG w `.mov`) zamiast binarnego `sample-1s.mov` w zasobach — dekodowalna na runnerze macOS, bez pliku w repozytorium.
/// Testy idą po kolei, żeby ślad kroków (`SampleVideo.trace`) w dzienniku CI był jednoznaczny.
@Suite(.serialized)
struct VideoThumbnailTests {
    @Test func aSmallSampleIsWrittenAndInspected() async throws {
        let sample = try await SampleVideo.make(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: sample.deletingLastPathComponent()) }

        SampleVideo.trace("inspect 64x48")
        #expect(await VideoInspector.inspect(sample) == VideoInfo(shortSidePx: 48, durationSeconds: 1))
        SampleVideo.trace("inspect 64x48: gotowe")
    }

    @Test func aSmallFrameIsNotEnlarged() async throws {
        let sample = try await SampleVideo.make(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: sample.deletingLastPathComponent()) }

        SampleVideo.trace("miniatura 64x48")
        let jpeg = try #require(await VideoThumbnail.make(video: sample))
        SampleVideo.trace("miniatura 64x48: gotowa")
        let image = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width == 64 && image.height == 48)
    }

    @Test func thumbnailOfSampleIsJpegUnder1MB() async throws {
        let sample = try await SampleVideo.make(width: 1280, height: 720)
        defer { try? FileManager.default.removeItem(at: sample.deletingLastPathComponent()) }

        SampleVideo.trace("miniatura 1280x720")
        let jpeg = try #require(await VideoThumbnail.make(video: sample), "miniatura pierwszej klatki próbki")
        SampleVideo.trace("miniatura 1280x720: gotowa")
        #expect(jpeg.starts(with: [0xFF, 0xD8, 0xFF]), "JPEG")
        #expect(Int64(jpeg.count) <= OutboxFile.maxThumbnailBytes)
        let image = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(max(image.width, image.height) == VideoThumbnail.size, "dłuższy bok 512")
        #expect(image.height == 288, "proporcje 16:9 zachowane")
    }

    @Test func aFileThatIsNotAVideoHasNoThumbnailAndNoParameters() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-video-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("jazda.mp4")
        try Data((0 ..< 2048).map { UInt8(truncatingIfNeeded: $0 % 200) }).write(to: fake)

        #expect(await VideoThumbnail.make(video: fake) == nil)
        #expect(await VideoInspector.inspect(fake) == nil)
    }

    @Test func inspectorReadsShortSideAndDuration() async throws {
        let sample = try await SampleVideo.make(width: 1280, height: 720)
        defer { try? FileManager.default.removeItem(at: sample.deletingLastPathComponent()) }

        #expect(await VideoInspector.inspect(sample) == VideoInfo(shortSidePx: 720, durationSeconds: 1))
    }

    @Test func thumbnailQualityIsLoweredUntilItFits() throws {
        let frame = try #require(SampleVideo.noiseImage(width: 512, height: 512))
        let best = try #require(VideoThumbnail.encode(frame, maxBytes: .max))
        let smaller = try #require(VideoThumbnail.encode(frame, maxBytes: Int64(best.count) - 1), "niższa jakość mieści się w mniejszym limicie")
        #expect(smaller.count < best.count)
        #expect(VideoThumbnail.encode(frame, maxBytes: 10) == nil, "nawet najniższa jakość się nie mieści")
    }
}

/// Próbki filmów do testów: 1 s (10 klatek po 0,1 s) w `.mov` z kodekiem Photo-JPEG (`jpeg`). Plik jest składany bajt po bajcie
/// (atomy QuickTime), a klatki koduje ImageIO — bez `AVAssetWriter`: na maszynie wirtualnej runnera CI (bez sprzętowego skalera
/// i koderów) `AVAssetWriter.finishWriting()` kończył proces testów sygnałem 11, a próbka H.264 z eksportem `AVAssetExportSession` — tak samo.
/// Odczyt (`AVURLAsset`, `AVAssetImageGenerator`) idzie już prawdziwą ścieżką AVFoundation.
enum SampleVideo {
    struct WriteFailed: Error {
        let reason: String
    }

    private static let frames = 10
    private static let timescale: UInt32 = 600
    private static let frameDuration: UInt32 = 60

    /// Ślad na stderr (bez buforowania) — przy awarii procesu w AVFoundation dziennik CI pokazuje, na którym kroku.
    static func trace(_ step: String) {
        FileHandle.standardError.write(Data("[SampleVideo] \(step)\n".utf8))
    }

    /// `location` — tekst ISO 6709 zapisany w atomie użytkownika `udta/©xyz` (QuickTime), który AVFoundation udostępnia jako położenie.
    static func make(width: Int, height: Int, location: String? = nil) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-sample-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("sample-1s.mov")
        var jpegs: [Data] = []
        for frame in 0 ..< frames {
            guard let image = frameImage(width: width, height: height, shade: UInt8(60 + frame * 15)) else { throw WriteFailed(reason: "klatka \(frame)") }
            jpegs.append(try ImagePreparer.encodeJPEG(image, quality: 0.8))
        }
        try movie(jpegs, width: width, height: height, location: location).write(to: url)
        trace("próbka \(width)x\(height) zapisana")
        return url
    }

    /// Zielone tło z jaśniejszym prostokątem w środku.
    private static func frameImage(width: Int, height: Int, shade: UInt8) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 30 / 255, green: CGFloat(shade) / 255, blue: 40 / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1)
        context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        return context.makeImage()
    }

    // MARK: Atomy QuickTime

    private static func be32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    private static func be16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }

    private static func box(_ type: String, _ parts: Data...) -> Data {
        let payload = parts.reduce(into: Data()) { $0.append($1) }
        return be32(UInt32(8 + payload.count)) + Data(type.utf8) + payload
    }

    private static let matrix = [0x0001_0000, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000].reduce(into: Data()) { $0.append(be32(UInt32($1))) }

    /// Atom użytkownika `©xyz` (bajt 0xA9, nie UTF-8): długość tekstu, język (0x15C7 = „und”) i tekst.
    private static func locationAtom(_ text: String) -> Data {
        let payload = be16(UInt16(text.utf8.count)) + be16(0x15C7) + Data(text.utf8)
        return box("udta", be32(UInt32(8 + payload.count)) + Data([0xA9, 0x78, 0x79, 0x7A]) + payload)
    }

    private static func movie(_ jpegs: [Data], width: Int, height: Int, location: String?) -> Data {
        let duration = UInt32(jpegs.count) * frameDuration
        let ftyp = box("ftyp", Data("qt  ".utf8), be32(0x2005_0300), Data("qt  ".utf8))
        let mdat = box("mdat", jpegs.reduce(into: Data()) { $0.append($1) })
        let chunkOffset = UInt32(ftyp.count + 8)

        let mvhd = box(
            "mvhd", be32(0), be32(0), be32(0), be32(timescale), be32(duration), be32(0x0001_0000), be16(0x0100), Data(count: 10), matrix,
            Data(count: 24), be32(2)
        )
        let tkhd = box(
            "tkhd", be32(0x0000_0003), be32(0), be32(0), be32(1), be32(0), be32(duration), Data(count: 8), be16(0), be16(0), be16(0), be16(0),
            matrix, be32(UInt32(width) << 16), be32(UInt32(height) << 16)
        )
        let mdhd = box("mdhd", be32(0), be32(0), be32(0), be32(timescale), be32(duration), be16(0), be16(0))
        let mediaHandler = box("hdlr", be32(0), Data("mhlr".utf8), Data("vide".utf8), be32(0), be32(0), be32(0), Data([0]))
        let vmhd = box("vmhd", be32(0x0000_0001), be16(0x0040), be16(0x8000), be16(0x8000), be16(0x8000))
        let dataHandler = box("hdlr", be32(0), Data("dhlr".utf8), Data("alis".utf8), be32(0), be32(0), be32(0), Data([0]))
        let dinf = box("dinf", box("dref", be32(0), be32(1), box("alis", be32(0x0000_0001))))
        var compressor = Data([10]) + Data("Photo-JPEG".utf8)
        compressor.append(Data(count: 32 - compressor.count))
        let sampleEntry = box(
            "jpeg", Data(count: 6), be16(1), be16(0), be16(0), be32(0), be32(0), be32(0x0000_0200), be16(UInt16(width)), be16(UInt16(height)),
            be32(0x0048_0000), be32(0x0048_0000), be32(0), be16(1), compressor, be16(24), be16(0xFFFF)
        )
        let stsd = box("stsd", be32(0), be32(1), sampleEntry)
        let stts = box("stts", be32(0), be32(1), be32(UInt32(jpegs.count)), be32(frameDuration))
        let stsc = box("stsc", be32(0), be32(1), be32(1), be32(UInt32(jpegs.count)), be32(1))
        let stsz = box("stsz", be32(0), be32(0), be32(UInt32(jpegs.count)), jpegs.reduce(into: Data()) { $0.append(be32(UInt32($1.count))) })
        let stco = box("stco", be32(0), be32(1), be32(chunkOffset))
        let stbl = box("stbl", stsd, stts, stsc, stsz, stco)
        let minf = box("minf", vmhd, dataHandler, dinf, stbl)
        let mdia = box("mdia", mdhd, mediaHandler, minf)
        let moov = box("moov", mvhd, box("trak", tkhd, mdia), location.map(locationAtom) ?? Data())
        return ftyp + mdat + moov
    }

    /// Obraz szumu (trudny do kompresji) do sprawdzania obniżania jakości JPEG.
    static func noiseImage(width: Int, height: Int) -> CGImage? {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0 ..< width * height * 4).map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
