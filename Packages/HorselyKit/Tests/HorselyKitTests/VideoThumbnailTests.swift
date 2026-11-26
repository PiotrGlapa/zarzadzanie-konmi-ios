import AVFoundation
import CoreVideo
import Foundation
import HorselyCore
import ImageIO
import Testing
@testable import HorselyKit

/// Miniatura pierwszej klatki i odczyt parametrów filmu na prawdziwym pliku (`VideoThumbnailTest.kt` Androida). Próbka 1 s powstaje w teście
/// (`AVAssetWriter`) zamiast binarnego `sample-1s.mov` w zasobach — tak samo dekodowalna na runnerze macOS, bez pliku w repozytorium.
/// Testy idą po kolei: AVFoundation na maszynie wirtualnej runnera (bez sprzętowego skalera i kodera) nie znosi równoległych sesji.
@Suite(.serialized)
struct VideoThumbnailTests {
    @Test func thumbnailOfSampleIsJpegUnder1MB() async throws {
        let sample = try await SampleVideo.make(width: 1280, height: 720)
        defer { try? FileManager.default.removeItem(at: sample.deletingLastPathComponent()) }

        let jpeg = try #require(await VideoThumbnail.make(video: sample), "miniatura pierwszej klatki próbki")
        #expect(jpeg.starts(with: [0xFF, 0xD8, 0xFF]), "JPEG")
        #expect(Int64(jpeg.count) <= OutboxFile.maxThumbnailBytes)
        let image = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(max(image.width, image.height) == VideoThumbnail.size, "dłuższy bok 512")
        #expect(image.height == 288, "proporcje 16:9 zachowane")
    }

    @Test func aSmallFrameIsNotEnlarged() async throws {
        let sample = try await SampleVideo.make(width: 64, height: 48)
        defer { try? FileManager.default.removeItem(at: sample.deletingLastPathComponent()) }

        let jpeg = try #require(await VideoThumbnail.make(video: sample))
        let image = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width == 64 && image.height == 48)
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

/// Próbki filmów do testów: 1 s (10 klatek po 0,1 s) w `.mov` z kodekiem Motion JPEG — koder programowy, dostępny także na maszynie
/// wirtualnej runnera CI, gdzie próbki H.264 razem z prawdziwym eksportem `AVAssetExportSession` kończyły proces testów sygnałem 11.
enum SampleVideo {
    struct WriteFailed: Error {
        let reason: String
    }

    static func make(width: Int, height: Int) async throws -> URL {
        var failures: [String] = []
        for codec in [AVVideoCodecType.jpeg] {
            do {
                return try await write(codec: codec, width: width, height: height)
            } catch {
                failures.append("\(codec.rawValue): \(error)")
            }
        }
        throw WriteFailed(reason: failures.joined(separator: "; "))
    }

    private static func write(codec: AVVideoCodecType, width: Int, height: Int) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-sample-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("sample-1s.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw WriteFailed(reason: "canAdd") }
        writer.add(input)
        guard writer.startWriting() else { throw WriteFailed(reason: "startWriting: \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0 ..< 10 {
            var waited = 0
            while !input.isReadyForMoreMediaData {
                waited += 1
                if waited > 500 { throw WriteFailed(reason: "isReadyForMoreMediaData") }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard let pool = adaptor.pixelBufferPool else { throw WriteFailed(reason: "pixelBufferPool: \(String(describing: writer.error))") }
            var created: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
            guard let buffer = created else { throw WriteFailed(reason: "pixelBuffer") }
            fill(buffer, shade: UInt8(60 + frame * 15))
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)) else {
                throw WriteFailed(reason: "append: \(String(describing: writer.error))")
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 10, timescale: 10))
        await writer.finishWriting()
        guard writer.status == .completed else { throw WriteFailed(reason: "finishWriting: \(String(describing: writer.error))") }
        return url
    }

    /// Zielone tło z jaśniejszym prostokątem w środku (BGRA).
    private static func fill(_ buffer: CVPixelBuffer, shade: UInt8) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let inner = x > width / 4 && x < width * 3 / 4 && y > height / 4 && y < height * 3 / 4
                let offset = y * row + x * 4
                pixels[offset] = inner ? 240 : 40
                pixels[offset + 1] = inner ? 240 : shade
                pixels[offset + 2] = inner ? 240 : 30
                pixels[offset + 3] = 255
            }
        }
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
