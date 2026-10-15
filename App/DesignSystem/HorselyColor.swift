import SwiftUI
import UIKit

/// Kolor w dwóch wariantach motywu (jasny / ciemny), zapisany szesnastkowo — jedno źródło prawdy dla aplikacji i testu kontrastu
/// (`PaletteContrastTests`). Wartości z SPECYFIKACJA_MOBILE_IOS.md 5.4 i `Color.kt` / `AccentColors.kt` Androida 2.0.1.
struct ColorPair: Sendable, Equatable {
    let light: UInt32
    let dark: UInt32

    func hex(dark isDark: Bool) -> UInt32 { isDark ? dark : light }

    /// Kolor dynamiczny — wariant zależy od motywu (`preferredColorScheme` albo ustawienia systemu), bez kolorów zależnych od tapety.
    var color: Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

/// Paleta motywu (5.4): zieleń (kolor główny), pomarańcz (ostrzeżenia), czerwień (błędy); pary tło/tekst mają kontrast ≥ 4,5:1.
enum Palette {
    static let primary = ColorPair(light: 0x2E7D32, dark: 0x81C784)
    static let onPrimary = ColorPair(light: 0xFFFFFF, dark: 0x003910)
    static let primaryContainer = ColorPair(light: 0xC8E6C9, dark: 0x1B5E20)
    static let onPrimaryContainer = ColorPair(light: 0x0B3D12, dark: 0xC8E6C9)
    static let secondary = ColorPair(light: 0x4F6354, dark: 0xB7CCBA)
    static let onSecondary = ColorPair(light: 0xFFFFFF, dark: 0x223527)
    static let secondaryContainer = ColorPair(light: 0xD2E8D5, dark: 0x384B3D)
    static let onSecondaryContainer = ColorPair(light: 0x0D1F13, dark: 0xD2E8D5)
    static let tertiary = ColorPair(light: 0x9A4A00, dark: 0xFFB77C)
    static let onTertiary = ColorPair(light: 0xFFFFFF, dark: 0x4F2500)
    static let tertiaryContainer = ColorPair(light: 0xFFDCC2, dark: 0x723600)
    static let onTertiaryContainer = ColorPair(light: 0x3A1B00, dark: 0xFFDCC2)
    static let error = ColorPair(light: 0xB3261E, dark: 0xF2B8B5)
    static let onError = ColorPair(light: 0xFFFFFF, dark: 0x601410)
    static let errorContainer = ColorPair(light: 0xF9DEDC, dark: 0x8C1D18)
    static let onErrorContainer = ColorPair(light: 0x410E0B, dark: 0xF9DEDC)
    static let background = ColorPair(light: 0xFBFDF8, dark: 0x191C19)
    static let onBackground = ColorPair(light: 0x191C19, dark: 0xE1E3DD)
    static let surfaceVariant = ColorPair(light: 0xDDE5DB, dark: 0x414941)
    static let onSurfaceVariant = ColorPair(light: 0x414941, dark: 0xC1C9C0)
    static let outline = ColorPair(light: 0x6E766D, dark: 0x8B938A)
    static let outlineVariant = ColorPair(light: 0xC1C9C0, dark: 0x414941)

    // Poza schematem Material 3: ostrzeżenie, powodzenie i obszar „Nadchodzące” na Pulpicie.
    static let warning = ColorPair(light: 0xB45309, dark: 0xFFB77C)
    static let onWarning = ColorPair(light: 0xFFFFFF, dark: 0x4F2500)
    static let warningContainer = ColorPair(light: 0xFFE8CC, dark: 0x5B2C00)
    static let onWarningContainer = ColorPair(light: 0x3A1B00, dark: 0xFFDCC2)
    static let success = ColorPair(light: 0x2E7D32, dark: 0x81C784)
    static let upcomingContainer = ColorPair(light: 0xE2F0E1, dark: 0x213A23)
    static let onUpcomingContainer = ColorPair(light: 0x0B3D12, dark: 0xC8E6C9)
    static let upcomingBorder = ColorPair(light: 0x81C784, dark: 0x2E7D32)
}

/// Krycie tła okrągłej ikony w kolorze akcentu (12 %).
let accentTintAlpha: Double = 0.12

/// Kolor rodzaju wpisu — ikona, pasek w wierszu, akcent nagłówka formularza (FR-KOL-01/02).
enum EntryAccent: CaseIterable, Sendable {
    case vet, farrier, physio, specialist, note, purchase, competition, training

    var colors: ColorPair {
        switch self {
        case .vet: ColorPair(light: 0x1565C0, dark: 0x90CAF9)
        case .farrier: ColorPair(light: 0x6D4C41, dark: 0xBCAAA4)
        case .physio: ColorPair(light: 0x00796B, dark: 0x80CBC4)
        case .specialist: ColorPair(light: 0x5E35B1, dark: 0xB39DDB)
        case .note: ColorPair(light: 0x546E7A, dark: 0xB0BEC5)
        case .purchase: ColorPair(light: 0xA15C00, dark: 0xFFCC80)
        case .competition: ColorPair(light: 0xB71C3C, dark: 0xF48FB1)
        case .training: Palette.primary
        }
    }

    /// Nazwa ikony Material (Outlined) w katalogu zasobów.
    var icon: String {
        switch self {
        case .vet: "medical_services"
        case .farrier: "handyman"
        case .physio: "fitness_center"
        case .specialist: "person"
        case .note: "edit_note"
        case .purchase: "shopping_cart"
        case .competition: "emoji_events"
        case .training: "directions_run"
        }
    }

    var color: Color { colors.color }
}

/// Kolor działu — ikony w „Więcej” i w dolnym pasku (FR-KOL-03).
enum SectionAccent: CaseIterable, Sendable {
    case dashboard, horses, reminders, trainings, purchases, competitions, contacts, reports, trash, backup, conflicts

    var colors: ColorPair {
        switch self {
        case .dashboard: ColorPair(light: 0x3949AB, dark: 0x9FA8DA)
        case .horses: ColorPair(light: 0x8D4A2B, dark: 0xFFAB91)
        case .reminders: ColorPair(light: 0x00838F, dark: 0x80DEEA)
        case .trainings: EntryAccent.training.colors
        case .purchases: EntryAccent.purchase.colors
        case .competitions: EntryAccent.competition.colors
        case .contacts: EntryAccent.vet.colors
        case .reports: EntryAccent.specialist.colors
        case .trash: ColorPair(light: 0x616161, dark: 0xBDBDBD)
        case .backup: EntryAccent.physio.colors
        case .conflicts: Palette.warning
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "home"
        case .horses: "horse_head"
        case .reminders: "event"
        case .trainings: "directions_run"
        case .purchases: "shopping_cart"
        case .competitions: "emoji_events"
        case .contacts: "contacts"
        case .reports: "assessment"
        case .trash: "delete"
        case .backup: "backup"
        case .conflicts: "warning"
        }
    }

    var color: Color { colors.color }
}

/// Wygodne nazwy kolorów motywu w widokach.
enum HorselyColor {
    static var primary: Color { Palette.primary.color }
    static var onPrimary: Color { Palette.onPrimary.color }
    static var primaryContainer: Color { Palette.primaryContainer.color }
    static var onPrimaryContainer: Color { Palette.onPrimaryContainer.color }
    static var secondaryContainer: Color { Palette.secondaryContainer.color }
    static var onSecondaryContainer: Color { Palette.onSecondaryContainer.color }
    static var error: Color { Palette.error.color }
    static var errorContainer: Color { Palette.errorContainer.color }
    static var onErrorContainer: Color { Palette.onErrorContainer.color }
    static var background: Color { Palette.background.color }
    static var onBackground: Color { Palette.onBackground.color }
    static var surfaceVariant: Color { Palette.surfaceVariant.color }
    static var onSurfaceVariant: Color { Palette.onSurfaceVariant.color }
    static var outline: Color { Palette.outline.color }
    static var outlineVariant: Color { Palette.outlineVariant.color }
    static var warning: Color { Palette.warning.color }
    static var onWarning: Color { Palette.onWarning.color }
    static var warningContainer: Color { Palette.warningContainer.color }
    static var onWarningContainer: Color { Palette.onWarningContainer.color }
    static var success: Color { Palette.success.color }
    static var upcomingContainer: Color { Palette.upcomingContainer.color }
    static var onUpcomingContainer: Color { Palette.onUpcomingContainer.color }
    static var upcomingBorder: Color { Palette.upcomingBorder.color }
}
