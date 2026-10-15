import Foundation

/// Kontrast WCAG 2.1 między kolorami szesnastkowymi (RGB) — używany w testach palety (`PaletteContrastTests`).
enum Contrast {
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        init(hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Kolor o danym kryciu nałożony na tło (kompozycja alfa).
        func composited(over background: RGB, alpha: Double) -> RGB {
            RGB(
                red: red * alpha + background.red * (1 - alpha),
                green: green * alpha + background.green * (1 - alpha),
                blue: blue * alpha + background.blue * (1 - alpha)
            )
        }
    }

    private static func channel(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ color: RGB) -> Double {
        0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    static func ratio(_ first: RGB, _ second: RGB) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
        ratio(RGB(hex: first), RGB(hex: second))
    }
}
