import XCTest
@testable import Horsely

/// Kontrast palety (FR-KOL-04, SC-2-10; odpowiednik `AccentColorsContrastTest` z Androida): ikona i pasek to obiekty graficzne (≥ 3:1)
/// na tle strony, na obszarach neutralnych i na własnym tle ikony (akcent o kryciu 12 %), tekst ≥ 4,5:1 — w obu motywach.
final class PaletteContrastTests: XCTestCase {
    private func assertContrast(_ name: String, _ foreground: Contrast.RGB, _ background: Contrast.RGB, minimum: Double, file: StaticString = #filePath, line: UInt = #line) {
        let ratio = Contrast.ratio(foreground, background)
        XCTAssertGreaterThanOrEqual(ratio, minimum, "\(name): kontrast \(String(format: "%.2f", ratio)):1 < \(minimum):1", file: file, line: line)
    }

    private func rgb(_ hex: UInt32) -> Contrast.RGB { Contrast.RGB(hex: hex) }

    private func assertGraphic(_ name: String, accent: UInt32, background: UInt32, surfaceVariant: UInt32) {
        let accentRGB = rgb(accent)
        assertContrast("\(name)/tło strony", accentRGB, rgb(background), minimum: 3)
        assertContrast("\(name)/obszar neutralny", accentRGB, rgb(surfaceVariant), minimum: 3)
        assertContrast("\(name)/ikona na tle strony", accentRGB, accentRGB.composited(over: rgb(background), alpha: accentTintAlpha), minimum: 3)
        assertContrast("\(name)/ikona na obszarze neutralnym", accentRGB, accentRGB.composited(over: rgb(surfaceVariant), alpha: accentTintAlpha), minimum: 3)
    }

    func testEntryAccentsAreVisibleInBothThemes() {
        for accent in EntryAccent.allCases {
            assertGraphic("jasny \(accent)", accent: accent.colors.light, background: Palette.background.light, surfaceVariant: Palette.surfaceVariant.light)
            assertGraphic("ciemny \(accent)", accent: accent.colors.dark, background: Palette.background.dark, surfaceVariant: Palette.surfaceVariant.dark)
        }
    }

    func testSectionAccentsAreVisibleInBothThemes() {
        for accent in SectionAccent.allCases {
            assertGraphic("jasny \(accent)", accent: accent.colors.light, background: Palette.background.light, surfaceVariant: Palette.surfaceVariant.light)
            assertGraphic("ciemny \(accent)", accent: accent.colors.dark, background: Palette.background.dark, surfaceVariant: Palette.surfaceVariant.dark)
        }
    }

    func testReminderIconsAreVisibleOnDashboardToneAreas() {
        for accent in EntryAccent.allCases {
            assertContrast("jasny \(accent)/Nadchodzące", rgb(accent.colors.light), rgb(Palette.upcomingContainer.light), minimum: 3)
            assertContrast("jasny \(accent)/Przeterminowane", rgb(accent.colors.light), rgb(Palette.warningContainer.light), minimum: 3)
            assertContrast("ciemny \(accent)/Nadchodzące", rgb(accent.colors.dark), rgb(Palette.upcomingContainer.dark), minimum: 3)
            assertContrast("ciemny \(accent)/Przeterminowane", rgb(accent.colors.dark), rgb(Palette.warningContainer.dark), minimum: 3)
        }
    }

    func testTabBarIconsAreVisibleOnTheSelectedIndicator() {
        for accent in [SectionAccent.dashboard, .horses, .reminders, .trainings] {
            assertContrast("jasny \(accent)/wskaźnik", rgb(accent.colors.light), rgb(Palette.secondaryContainer.light), minimum: 3)
            assertContrast("ciemny \(accent)/wskaźnik", rgb(accent.colors.dark), rgb(Palette.secondaryContainer.dark), minimum: 3)
        }
    }

    func testAccentColorsUsedAsTextMeetAA() {
        for accent in EntryAccent.allCases {
            assertContrast("jasny tekst \(accent)", rgb(accent.colors.light), rgb(Palette.background.light), minimum: 4.5)
            assertContrast("ciemny tekst \(accent)", rgb(accent.colors.dark), rgb(Palette.background.dark), minimum: 4.5)
        }
    }

    func testTextPairsOfTheThemeMeetAA() {
        let pairs: [(String, ColorPair, ColorPair)] = [
            ("primary", Palette.primary, Palette.onPrimary),
            ("primaryContainer", Palette.primaryContainer, Palette.onPrimaryContainer),
            ("secondaryContainer", Palette.secondaryContainer, Palette.onSecondaryContainer),
            ("tertiaryContainer", Palette.tertiaryContainer, Palette.onTertiaryContainer),
            ("error", Palette.error, Palette.onError),
            ("errorContainer", Palette.errorContainer, Palette.onErrorContainer),
            ("background", Palette.background, Palette.onBackground),
            ("surfaceVariant", Palette.surfaceVariant, Palette.onSurfaceVariant),
            ("warning", Palette.warning, Palette.onWarning),
            ("warningContainer", Palette.warningContainer, Palette.onWarningContainer),
            ("upcomingContainer", Palette.upcomingContainer, Palette.onUpcomingContainer),
        ]
        for (name, background, text) in pairs {
            assertContrast("jasny \(name)", rgb(text.light), rgb(background.light), minimum: 4.5)
            assertContrast("ciemny \(name)", rgb(text.dark), rgb(background.dark), minimum: 4.5)
        }
    }

    func testPrimaryHeadingsAndWarningTextAreReadableOnThePage() {
        // Nagłówki sekcji (kolor główny) i ikony ostrzeżeń na tle strony.
        assertContrast("jasny nagłówek", rgb(Palette.primary.light), rgb(Palette.background.light), minimum: 4.5)
        assertContrast("ciemny nagłówek", rgb(Palette.primary.dark), rgb(Palette.background.dark), minimum: 4.5)
        assertContrast("jasne ostrzeżenie", rgb(Palette.warning.light), rgb(Palette.background.light), minimum: 4.5)
        assertContrast("ciemne ostrzeżenie", rgb(Palette.warning.dark), rgb(Palette.background.dark), minimum: 4.5)
    }

    func testContrastMathMatchesKnownValues() {
        XCTAssertEqual(Contrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.ratio(0xFFFFFF, 0xFFFFFF), 1, accuracy: 0.001)
    }
}
