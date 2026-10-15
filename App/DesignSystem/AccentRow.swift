import SwiftUI

/// Wiersz z paskiem 4 pt po lewej w kolorze akcentu (ostatnie wpisy, oś czasu, terminy).
struct AccentRow<Content: View>: View {
    let color: Color
    private let content: Content

    init(color: Color, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.between + 4) {
            RoundedRectangle(cornerRadius: Spacing.accentBar / 2)
                .fill(color)
                .frame(width: Spacing.accentBar)
                .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
