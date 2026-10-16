import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HorselyKit

/// Obrazy testowe rysowane CoreGraphics (bez UIKit, żeby działały w `swift test` na macOS).
enum TestImages {
    enum Color {
        case red, blue, green

        var components: (CGFloat, CGFloat, CGFloat) {
            switch self {
            case .red: (1, 0, 0)
            case .blue: (0, 0, 1)
            case .green: (0, 1, 0)
            }
        }
    }

    /// JPEG `width` × `height`: lewa połowa w `leftColor`, prawa w `rightColor`; opcjonalnie z lokalizacją GPS w metadanych.
    static func jpeg(width: Int, height: Int, leftColor: Color, rightColor: Color, withGPS: Bool = false) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let left = leftColor.components
        let right = rightColor.components
        context.setFillColor(red: left.0, green: left.1, blue: left.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(red: right.0, green: right.1, blue: right.2, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let image = context.makeImage()!

        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
        if withGPS {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 52.2297, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 21.0122, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// Kolor piksela (R, G, B w 0–255) w punkcie (x, y) liczonym od lewego górnego rogu.
    static func pixel(_ data: Data, x: Int, y: Int) -> (Int, Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let base = context.data else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        // Bufor CGContext ma pierwszy wiersz u góry obrazu.
        let offset = (y * image.width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    static func isReddish(_ pixel: (Int, Int, Int)?) -> Bool { pixel.map { $0.0 > 200 && $0.1 < 60 && $0.2 < 60 } ?? false }
    static func isBluish(_ pixel: (Int, Int, Int)?) -> Bool { pixel.map { $0.2 > 200 && $0.0 < 60 && $0.1 < 60 } ?? false }
}

/// Przygotowanie i kadrowanie zdjęć konia (T041, FR-ZDK-02, FR-M-ZAL-03).
struct PhotoCropTests {
    @Test func theSourceImageReallyCarriesGPS() {
        let data = TestImages.jpeg(width: 40, height: 20, leftColor: .red, rightColor: .blue, withGPS: true)
        #expect(ImagePreparer.hasGPS(data))
        #expect(TestImages.isReddish(TestImages.pixel(data, x: 5, y: 10)))
        #expect(TestImages.isBluish(TestImages.pixel(data, x: 35, y: 10)))
    }

    @Test func preparingShrinksTheLongestSideAndDropsLocation() throws {
        let data = TestImages.jpeg(width: 3000, height: 1500, leftColor: .red, rightColor: .blue, withGPS: true)
        let prepared = try ImagePreparer.prepare(data)
        #expect(prepared.width == 2560)
        #expect(prepared.height == 1280)
        #expect(!ImagePreparer.hasGPS(prepared.jpeg))
    }

    @Test func aSmallerImageIsNotEnlarged() throws {
        let prepared = try ImagePreparer.prepare(TestImages.jpeg(width: 800, height: 600, leftColor: .green, rightColor: .green))
        #expect(prepared.width == 800)
        #expect(prepared.height == 600)
    }

    @Test func aThumbnailIsSmallAndHasNoLocation() throws {
        let data = TestImages.jpeg(width: 2000, height: 1000, leftColor: .red, rightColor: .blue, withGPS: true)
        let thumbnail = try ImagePreparer.thumbnail(data)
        #expect(!ImagePreparer.hasGPS(thumbnail))
        let prepared = try ImagePreparer.prepare(thumbnail)
        #expect(max(prepared.width, prepared.height) == ImagePreparer.thumbnailSide)
    }

    @Test func cropProducesASquareFromTheChosenRegion() throws {
        let data = TestImages.jpeg(width: 400, height: 200, leftColor: .red, rightColor: .blue, withGPS: true)
        let leftSquare = try PhotoCropper.crop(data, quarterTurns: 0, normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(leftSquare.width == 200 && leftSquare.height == 200)
        #expect(TestImages.isReddish(TestImages.pixel(leftSquare.jpeg, x: 100, y: 100)))
        #expect(!ImagePreparer.hasGPS(leftSquare.jpeg))

        let rightSquare = try PhotoCropper.crop(data, quarterTurns: 0, normalizedRect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        #expect(TestImages.isBluish(TestImages.pixel(rightSquare.jpeg, x: 100, y: 100)))
    }

    @Test func rotatingByNinetyDegreesMovesTheLeftHalfToTheTop() throws {
        let data = TestImages.jpeg(width: 400, height: 200, leftColor: .red, rightColor: .blue)
        // Po obrocie zgodnie z ruchem wskazówek obraz ma 200 × 400: czerwień (była z lewej) u góry, błękit na dole.
        let top = try PhotoCropper.crop(data, quarterTurns: 1, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        #expect(top.width == 200 && top.height == 200)
        #expect(TestImages.isReddish(TestImages.pixel(top.jpeg, x: 100, y: 100)))
        let bottom = try PhotoCropper.crop(data, quarterTurns: 1, normalizedRect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        #expect(TestImages.isBluish(TestImages.pixel(bottom.jpeg, x: 100, y: 100)))
    }

    @Test func rotatingByOneHundredEightyDegreesSwapsTheHalves() throws {
        let data = TestImages.jpeg(width: 400, height: 200, leftColor: .red, rightColor: .blue)
        let left = try PhotoCropper.crop(data, quarterTurns: 2, normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(TestImages.isBluish(TestImages.pixel(left.jpeg, x: 100, y: 100)))
    }

    @Test func threeTurnsAreAQuarterTurnTheOtherWay() throws {
        let data = TestImages.jpeg(width: 400, height: 200, leftColor: .red, rightColor: .blue)
        let top = try PhotoCropper.crop(data, quarterTurns: 3, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        #expect(TestImages.isBluish(TestImages.pixel(top.jpeg, x: 100, y: 100)))
        let wrapped = try PhotoCropper.crop(data, quarterTurns: -1, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        #expect(TestImages.isBluish(TestImages.pixel(wrapped.jpeg, x: 100, y: 100)))
    }

    @Test func aLargeCropIsShrunkToTheMaximumSide() throws {
        let data = TestImages.jpeg(width: 4000, height: 3000, leftColor: .green, rightColor: .green)
        let cropped = try PhotoCropper.crop(data, quarterTurns: 0, normalizedRect: CGRect(x: 0, y: 0, width: 0.75, height: 1))
        #expect(cropped.width == 2560 && cropped.height == 2560)
    }

    @Test func garbageIsReportedAsUnreadable() {
        #expect(throws: ImageError.unreadable) { try ImagePreparer.prepare(Data("to nie jest obraz".utf8)) }
    }
}
