import SwiftUI
import WidgetKit

/// Rozszerzenie widżetów `HorselyRideActivity` (Task 16, SPECYFIKACJA_MOBILE_IOS.md 9.5): tylko Live Activity nagrywanej jazdy — bez widżetów
/// ekranu głównego.
@main
struct RideActivityBundle: WidgetBundle {
    var body: some Widget {
        RideActivityWidget()
    }
}
