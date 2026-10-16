import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageError: Error, Equatable {
    case unreadable
    case encodingFailed
}

/// Obraz po przygotowaniu do zapisu: JPEG bez metadanych (w tym bez lokalizacji GPS), orientacja wypalona w pikselach.
public struct PreparedImage: Sendable, Equatable {
    public let jpeg: Data
    public let width: Int
    public let height: Int

    public init(jpeg: Data, width: Int, height: Int) {
        self.jpeg = jpeg
        self.width = width
        self.height = height
    }
}

/// Przygotowanie zdjęć (FR-M-ZAL-03, FR-ZDK-02): zmniejszenie dłuższego boku do 2560 px, JPEG ~85 %, usunięcie danych EXIF z lokalizacją
/// (GPS), miniatury. Wszystko przez ImageIO — bez zależności i bez zgody na bibliotekę zdjęć.
public enum ImagePreparer {
    public static let defaultMaxSide = 2560
    public static let defaultQuality = 0.85
    public static let thumbnailSide = 256

    /// Zmniejsza (tylko gdy trzeba) i koduje jako JPEG. Metadane źródła nie są przenoszone — zdjęcie nie niesie lokalizacji.
    public static func prepare(_ data: Data, maxSide: Int = defaultMaxSide, quality: Double = defaultQuality) throws -> PreparedImage {
        let source = try makeSource(data)
        let longest = try longestSide(of: source)
        let image = try decode(source, maxPixelSize: min(longest, maxSide))
        return PreparedImage(jpeg: try encodeJPEG(image, quality: quality), width: image.width, height: image.height)
    }

    /// Miniatura (dłuższy bok `side` px) do list koni i kafli Pulpitu.
    public static func thumbnail(_ data: Data, side: Int = thumbnailSide, quality: Double = 0.8) throws -> Data {
        let source = try makeSource(data)
        let image = try decode(source, maxPixelSize: min(try longestSide(of: source), side))
        return try encodeJPEG(image, quality: quality)
    }

    /// Czy plik zawiera słownik GPS w metadanych (do testów i kontroli przed wysłaniem).
    public static func hasGPS(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return properties[kCGImagePropertyGPSDictionary] != nil
    }

    // MARK: Pomocnicze (wspólne z kadrowaniem)

    static func makeSource(_ data: Data) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { throw ImageError.unreadable }
        return source
    }

    static func longestSide(of source: CGImageSource) throws -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageError.unreadable
        }
        return max(width, height)
    }

    /// Obraz z zastosowaną orientacją EXIF, nie większy niż `maxPixelSize` na dłuższym boku.
    static func decode(_ source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ImageError.unreadable }
        return image
    }

    static func encodeJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw ImageError.encodingFailed }
        // Bez właściwości źródła: ani GPS, ani EXIF aparatu nie trafiają do pliku.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.encodingFailed }
        return output as Data
    }
}

/// Kadrowanie zdjęcia konia (FR-ZDK-02): obrót o wielokrotność 90° zgodnie z ruchem wskazówek zegara i wycięcie prostokąta wskazanego
/// jako ułamki szerokości i wysokości obrazu PO obrocie. Wynik jest zmniejszany jak inne zdjęcia (do 2560 px), bez lokalizacji.
public enum PhotoCropper {
    public static func crop(
        _ data: Data, quarterTurns: Int, normalizedRect: CGRect, maxSide: Int = ImagePreparer.defaultMaxSide, quality: Double = ImagePreparer.defaultQuality
    ) throws -> PreparedImage {
        let source = try ImagePreparer.makeSource(data)
        let full = try ImagePreparer.decode(source, maxPixelSize: try ImagePreparer.longestSide(of: source))
        let rotated = try rotate(full, quarterTurns: ((quarterTurns % 4) + 4) % 4)

        let width = CGFloat(rotated.width)
        let height = CGFloat(rotated.height)
        let rect = CGRect(
            x: (normalizedRect.minX * width).rounded(), y: (normalizedRect.minY * height).rounded(),
            width: (normalizedRect.width * width).rounded(), height: (normalizedRect.height * height).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1, let cropped = rotated.cropping(to: rect) else { throw ImageError.unreadable }

        let scaled = try scaleDown(cropped, maxSide: maxSide)
        return PreparedImage(jpeg: try ImagePreparer.encodeJPEG(scaled, quality: quality), width: scaled.width, height: scaled.height)
    }

    static func rotate(_ image: CGImage, quarterTurns: Int) throws -> CGImage {
        guard quarterTurns != 0 else { return image }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let swapped = quarterTurns % 2 == 1
        let transform: CGAffineTransform
        switch quarterTurns {
        case 1: transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
        case 2: transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        default: transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
        }
        guard let context = makeContext(width: swapped ? image.height : image.width, height: swapped ? image.width : image.height) else { throw ImageError.encodingFailed }
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw ImageError.encodingFailed }
        return result
    }

    static func scaleDown(_ image: CGImage, maxSide: Int) throws -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let ratio = Double(maxSide) / Double(longest)
        let width = max(Int((Double(image.width) * ratio).rounded()), 1)
        let height = max(Int((Double(image.height) * ratio).rounded()), 1)
        guard let context = makeContext(width: width, height: height) else { throw ImageError.encodingFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw ImageError.encodingFailed }
        return result
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    }
}
