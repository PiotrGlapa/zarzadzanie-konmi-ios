import SwiftUI

/// Nagłówek sekcji (5.4): styl `subheadline` półgruby w kolorze głównym, oznaczony jako nagłówek dla VoiceOver;
/// odstęp przed 16 pt, pod nagłówkiem 4 pt.
struct SectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HorselyColor.primary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.beforeSection)
            .padding(.bottom, Spacing.afterSectionTitle)
    }
}
