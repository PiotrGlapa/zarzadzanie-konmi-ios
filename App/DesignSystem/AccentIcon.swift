import SwiftUI

/// Ikona w kółku z tłem 12 % koloru akcentu (rodzaje wpisów i działy).
struct AccentIcon: View {
    let icon: String
    let color: Color
    var diameter: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(accentTintAlpha))
            HIcon(name: icon, size: diameter * 0.55).foregroundStyle(color)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

extension AccentIcon {
    init(_ accent: EntryAccent, diameter: CGFloat = 40) {
        self.init(icon: accent.icon, color: accent.color, diameter: diameter)
    }

    init(_ accent: SectionAccent, diameter: CGFloat = 40) {
        self.init(icon: accent.icon, color: accent.color, diameter: diameter)
    }
}
