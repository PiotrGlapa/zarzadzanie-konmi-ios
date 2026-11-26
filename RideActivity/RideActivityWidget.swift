import ActivityKit
import HorselyCore
import SwiftUI
import WidgetKit

/// Live Activity nagrywanej jazdy (FR-NAG-05): ekran blokady i Dynamic Island (kompaktowa, rozwinięta, minimalna). Widoki są w `Shared/`
/// (`RideActivityViews.swift`) — te same sprawdzają testy migawkowe aplikacji. Przyciski „Pauza” / „Wznów” i „Zakończ” to
/// `LiveActivityIntent`, które system wykonuje w procesie aplikacji.
struct RideActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            RideActivityLockScreenView(horseName: context.attributes.horseName, state: context.state.rideState)
                .activityBackgroundTint(RideActivityStyle.background)
                .activitySystemActionForegroundColor(RideActivityStyle.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RideActivityExpandedLeadingView(horseName: context.attributes.horseName)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RideActivityExpandedTrailingView(state: context.state.rideState)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RideActivityExpandedBottomView(state: context.state.rideState)
                }
            } compactLeading: {
                RideActivityHorseIcon(size: 20, color: RideActivityStyle.islandPrimary)
            } compactTrailing: {
                RideActivityCompactTrailingView(state: context.state.rideState)
            } minimal: {
                RideActivityHorseIcon(size: 18, color: RideActivityStyle.islandPrimary)
            }
            .keylineTint(RideActivityStyle.islandPrimary)
        }
    }
}
