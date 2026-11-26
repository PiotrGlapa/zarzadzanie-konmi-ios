import HorselyCore
import HorselyKit
import SwiftUI

// Pasek NAG-01 i przycisk „Nagraj jazdę” (Task 17 = Android 3.0.2 `RideBanner.kt`, przycisk z `TrainingsSectionScreen.kt` / `TrainingsTab.kt`).

/// Wspólne teksty jazdy dla paska, ekranu nagrywania i pytania o odzyskanie — te same formy co w Live Activity (`RideNotificationContent`).
enum RideText {
    /// „24 min” albo „1 h 05 min” (czas aktywny, pełne minuty).
    static func duration(_ activeSeconds: Int) -> String { RideNotificationContent.duration(activeSeconds, .app) }
    /// „3,2 km”.
    static func distance(_ meters: Int) -> String { RideNotificationContent.distance(meters, .app) }
    /// „9,4 km/h”.
    static func speed(_ kmh: Double) -> String { RideStartPolicy.speed(kmh, template: tr("ride_speed_kmh")) }
    /// „stęp”, „kłus”…
    static func gait(_ gait: Gait) -> String { RideNotificationContent.gaitName(gait, .app) }

    /// Treść paska z szablonu (`ride_banner*`).
    static func banner(_ content: RideBannerContent) -> String {
        tr(content.textKey, content.horseName, duration(content.activeSeconds), distance(content.distanceMeters))
    }

    /// „Masz niezakończone nagranie (Grom, 14:05, 6,1 km).”
    static func recovery(_ content: RideRecoveryContent) -> String {
        tr(content.textKey, content.horseName, content.startTime, distance(content.distanceMeters))
    }
}

/// Pasek NAG-01 na Pulpicie i w dziale Treningi: „Trwa nagrywanie — Grom · 24 min · 3,2 km”. Dotknięcie otwiera ekran nagrywania.
/// Wstrzymana i przerwana jazda mają własne brzmienie, żeby pasek nie obiecywał nagrywania, którego nie ma. Kolory jak `tertiaryContainer`
/// Androida (pomarańczowy kontener z ciemnym tekstem, kontrast ≥ 4,5:1).
struct RideBanner: View {
    let content: RideBannerContent
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.between) {
                HIcon(name: "fiber_manual_record", size: 22)
                Text(RideText.banner(content))
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(HorselyColor.onTertiaryContainer)
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget, alignment: .leading)
            .background(HorselyColor.tertiaryContainer, in: RoundedRectangle(cornerRadius: Spacing.cardRadius))
            .contentShape(RoundedRectangle(cornerRadius: Spacing.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr(content.openLabelKey))
        .accessibilityIdentifier("ride-banner")
    }
}

/// Pasek dla bieżącej jazdy ze środowiska (nic, gdy nie ma niezakończonej jazdy); dotknięcie — ekran nagrywania.
struct ActiveRideBanner: View {
    @Environment(AppEnvironment.self) private var environment
    /// Odstęp od krawędzi ekranu (0, gdy kontener ma już własny).
    var horizontalPadding: CGFloat = Spacing.screenEdge

    var body: some View {
        if let content = RideStartPolicy.banner(environment.activeRide) {
            RideBanner(content: content) { environment.router.ride = .recording }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, Spacing.between)
        }
    }
}

/// „Nagraj jazdę” (obok „+” w dziale Treningi, na karcie konia z wybranym koniem). Gdy jazda już trwa, start otwiera ekran nagrywania
/// (jedno nagrywanie naraz — decyduje ekran startu).
struct RideRecordButton: View {
    @Environment(AppEnvironment.self) private var environment
    var horseId: String?

    var body: some View {
        Button {
            guard environment.workMode != .unset else { return }
            environment.router.ride = .start(horseId: horseId)
        } label: {
            HStack(spacing: 6) {
                HIcon(name: "fiber_manual_record", size: 20)
                Text("ride_record").font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            // Przycisk pływa nad listą obok „+” (stały rozmiar 56 pt) — przy największym tekście nie może zasłonić podliczenia.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(HorselyColor.onSecondaryContainer)
            .padding(.horizontal, 16)
            .frame(minHeight: Spacing.minTouchTarget)
            .background(HorselyColor.secondaryContainer, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ride-record")
    }
}
