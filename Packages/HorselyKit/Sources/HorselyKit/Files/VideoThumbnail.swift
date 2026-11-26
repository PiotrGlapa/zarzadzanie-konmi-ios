import AVFoundation
import CoreGraphics
import Foundation
import HorselyCore

/// Miniatura filmu do wysyłki razem z załącznikiem (część `thumbnail`, `VideoThumbnail.kt` Androida): pierwsza klatka (z uwzględnieniem
/// obrotu), JPEG, dłuższy bok najwyżej `size` px (mniejsze klatki nie są powiększane), jakość obniżana, aż plik zmieści się w
/// `OutboxFile.maxThumbnailBytes` (1 MB). Robi ją telefon — program 3.0 przyjmuje miniaturę od klienta i nie ma ffmpeg.
public enum VideoThumbnail {
    /// Dłuższy bok miniatury w pikselach.
    public static let size = 512
    private static let startQuality = 85
    private static let minQuality = 20
    private static let qualityStep = 10

    /// JPEG pierwszej klatki `video` albo `nil`, gdy plik nie jest filmem, który da się odczytać (film idzie wtedy bez miniatury).
    public static func make(video: URL) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        guard let frame = try? await generator.image(at: .zero).image, let small = scaled(frame) else { return nil }
        return encode(small)
    }

    /// Zmniejsza klatkę do dłuższego boku `size` (programowo, `CGContext`); mniejsza zostaje bez zmian.
    static func scaled(_ frame: CGImage) -> CGImage? {
        let longest = max(frame.width, frame.height)
        guard longest > size else { return frame }
        let factor = Double(size) / Double(longest)
        let width = max(Int((Double(frame.width) * factor).rounded()), 1)
        let height = max(Int((Double(frame.height) * factor).rounded()), 1)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Koduje `frame` do JPEG o rozmiarze ≤ `maxBytes`, obniżając jakość od 85 % co 10 punktów do 20 %; `nil`, gdy to niemożliwe.
    static func encode(_ frame: CGImage, maxBytes: Int64 = OutboxFile.maxThumbnailBytes) -> Data? {
        var quality = startQuality
        while quality >= minQuality {
            if let jpeg = try? ImagePreparer.encodeJPEG(frame, quality: Double(quality) / 100), Int64(jpeg.count) <= maxBytes { return jpeg }
            quality -= qualityStep
        }
        return nil
    }
}
