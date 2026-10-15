import SwiftUI

/// Odstępy i kształty (5.4): krawędź ekranu 16 pt, przed nagłówkiem sekcji 16 pt (pod nim 4 pt), między elementami 8 pt,
/// wnętrze obszaru 12 pt, obszar zaokrąglony 12 pt z ramką 1 pt, cel dotyku ≥ 44 pt. Rozmiary z dp Androida 1:1 na punkty.
enum Spacing {
    static let screenEdge: CGFloat = 16
    static let beforeSection: CGFloat = 16
    static let afterSectionTitle: CGFloat = 4
    static let between: CGFloat = 8
    static let cardPadding: CGFloat = 12
    static let cardRadius: CGFloat = 12
    static let cardBorder: CGFloat = 1
    static let dividerInset: CGFloat = 16
    static let accentBar: CGFloat = 4
    static let minTouchTarget: CGFloat = 44
    /// Zapas pod listą dla przycisku „+” (96 pt, Pulpit).
    static let addButtonClearance: CGFloat = 96
}

/// Ikona z katalogu zasobów (SVG Material jako obraz szablonowy), barwiona kolorem pierwszego planu.
struct HIcon: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Tekst z `Localizable.xcstrings` (klucz = nazwa ze `strings.xml` Androida) dla kodu, który potrzebuje `String`.
func tr(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Tekst z podstawionymi argumentami (`%1$@`, `%2$lld` w katalogu).
func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), locale: Locale(identifier: "pl_PL"), arguments: arguments)
}

/// Tekst z liczbą mnogą (`plurals` ze `strings.xml`: one / few / many / other) dla podanej liczby.
func trPlural(_ key: String, _ count: Int) -> String {
    String(format: tr(key), locale: Locale(identifier: "pl_PL"), count)
}
