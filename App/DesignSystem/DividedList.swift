import SwiftUI

/// Lista wierszy rozdzielonych linią 1 pt w kolorze obrysu delikatnego, wciętą 16 pt od lewej — linie tylko MIĘDZY wierszami,
/// nigdy po ostatnim (5.4, odpowiednik `dividedItems` z Androida).
struct DividedList<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                if index > 0 { DividerLine() }
                content(element)
            }
        }
    }
}

/// Linia 1 pt z wcięciem 16 pt.
struct DividerLine: View {
    var inset: CGFloat = Spacing.dividerInset

    var body: some View {
        Rectangle()
            .fill(HorselyColor.outlineVariant)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}
