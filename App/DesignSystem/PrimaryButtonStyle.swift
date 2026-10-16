import SwiftUI

/// Główny przycisk wypełniony kolorem głównym z tekstem „na głównym” (5.4): w motywie ciemnym jasna zieleń z ciemnym tekstem,
/// dzięki czemu kontrast tekstu wynosi ≥ 4,5:1 (systemowy `borderedProminent` zawsze używa białego tekstu).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(HorselyColor.onPrimary)
            .background(HorselyColor.primary, in: RoundedRectangle(cornerRadius: Spacing.cardRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Spacing.cardRadius))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryFilled: PrimaryButtonStyle { PrimaryButtonStyle() }
}
