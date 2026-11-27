import AppIntents
import HorselyCore
import SwiftUI
import UIKit

// Widoki Live Activity jazdy (Task 16) — wspólne dla rozszerzenia widżetów (`RideActivityWidget` składa z nich ekran blokady i Dynamic
// Island) i aplikacji (testy migawkowe `RideActivitySnapshotTests`). Treść z formatera rdzenia (ten sam co tekst powiadomienia Androida):
// „Grom · 24 min · 3,2 km · kłus”, „Słaby sygnał GPS”; przyciski „Pauza” / „Wznów” i „Zakończ”. Kolory z palety SPECYFIKACJA 5.4.

/// Kolory Live Activity (wartości z `Palette` aplikacji, SPECYFIKACJA_MOBILE_IOS.md 5.4; rozszerzenie nie ma systemu projektowego aplikacji).
enum RideActivityStyle {
    /// Zieleń — kolor główny (przyciski, ikona konia).
    static let primary = dynamic(light: 0x2E7D32, dark: 0x81C784)
    /// Tekst na zieleni (przycisk główny) — kontrast ≥ 4,5:1 w obu motywach.
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x003910)
    /// Pomarańcz — ostrzeżenie (słaby GPS).
    static let warning = dynamic(light: 0x9A4A00, dark: 0xFFB77C)
    /// Tło ekranu blokady i tekst na nim.
    static let background = dynamic(light: 0xFBFDF8, dark: 0x191C19)
    static let onBackground = dynamic(light: 0x191C19, dark: 0xE1E3DD)
    static let onSurfaceVariant = dynamic(light: 0x414941, dark: 0xC1C9C0)
    /// Dynamic Island ma zawsze czarne tło — kolory z wariantu ciemnego.
    static let islandPrimary = fixed(0x81C784)
    static let islandWarning = fixed(0xFFB77C)
    static let islandOnPrimary = fixed(0x003910)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) })
    }

    private static func fixed(_ hex: UInt32) -> Color {
        Color(uiColor: rgb(hex))
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1
        )
    }
}

/// Ikona konia (Material `horse_head` z aplikacji, kopia w katalogu `Shared/RideActivityAssets.xcassets`).
struct RideActivityHorseIcon: View {
    var size: CGFloat = 24
    var color: Color = RideActivityStyle.primary

    var body: some View {
        Image("ride_activity_horse")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// Przyciski: „Pauza” albo „Wznów” (przy pauzie) i „Zakończ” — `LiveActivityIntent` z `RideActivityIntents.swift`.
struct RideActivityButtons: View {
    let paused: Bool
    var tint: Color = RideActivityStyle.primary
    var onTint: Color = RideActivityStyle.onPrimary
    var buttons: RideActivityButtonTexts = .app

    var body: some View {
        HStack(spacing: 8) {
            if paused {
                Button(intent: ResumeRideIntent()) {
                    Text(buttons.resume).foregroundStyle(onTint).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(intent: PauseRideIntent()) {
                    Text(buttons.pause).foregroundStyle(onTint).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button(intent: FinishRideIntent()) {
                Text(buttons.finish).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .tint(tint)
        .font(.subheadline.weight(.semibold))
    }
}

/// Ekran blokady (i baner na starszych iPhone'ach): „Nagrywanie jazdy”, treść stanu i przyciski.
struct RideActivityLockScreenView: View {
    let horseName: String
    let state: RideActivityState
    var texts: RideNotificationTexts = .app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RideActivityHorseIcon(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(texts.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RideActivityStyle.onSurfaceVariant)
                    Text(RideNotificationContent.contentText(horseName: horseName, state: state, texts: texts))
                        .font(.body.weight(.medium))
                        .foregroundStyle(state.weakGps && !state.paused ? RideActivityStyle.warning : RideActivityStyle.onBackground)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            RideActivityButtons(paused: state.paused)
        }
        .padding(16)
    }
}

/// Dynamic Island, wersja kompaktowa — po prawej czas jazdy („24 min”; pomarańczowy przy słabym GPS).
struct RideActivityCompactTrailingView: View {
    let state: RideActivityState
    var texts: RideNotificationTexts = .app

    var body: some View {
        Text(RideNotificationContent.duration(state.activeSeconds, texts))
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(state.weakGps && !state.paused ? RideActivityStyle.islandWarning : RideActivityStyle.islandPrimary)
            .lineLimit(1)
    }
}

/// Dynamic Island, rozwinięta — lewa strona: koń.
struct RideActivityExpandedLeadingView: View {
    let horseName: String

    var body: some View {
        HStack(spacing: 6) {
            RideActivityHorseIcon(size: 22, color: RideActivityStyle.islandPrimary)
            Text(horseName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

/// Dynamic Island, rozwinięta — prawa strona: czas jazdy.
struct RideActivityExpandedTrailingView: View {
    let state: RideActivityState
    var texts: RideNotificationTexts = .app

    var body: some View {
        Text(RideNotificationContent.duration(state.activeSeconds, texts))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
    }
}

/// Dynamic Island, rozwinięta — dół: dystans z chodem albo „Słaby sygnał GPS” / „pauza” i przyciski.
struct RideActivityExpandedBottomView: View {
    let state: RideActivityState
    var texts: RideNotificationTexts = .app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RideNotificationContent.distanceAndStatus(state: state, texts: texts))
                .font(.subheadline)
                .foregroundStyle(state.weakGps && !state.paused ? RideActivityStyle.islandWarning : .white)
                .lineLimit(1)
            RideActivityButtons(paused: state.paused, tint: RideActivityStyle.islandPrimary, onTint: RideActivityStyle.islandOnPrimary)
        }
    }
}
