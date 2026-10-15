import SwiftUI

/// Plakietka „Kontuzjowany”: ikona `healing` 18 pt i tekst w kolorze ostrzeżenia (informacja nigdy tylko kolorem).
struct InjuredBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            HIcon(name: "healing", size: 18)
            Text("horse_injured_badge")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(HorselyColor.warning)
        .accessibilityElement(children: .combine)
    }
}
