import SwiftUI

/// Ton obszaru (5.4): neutralny (wariant powierzchni) — koszty, bilans; główny („Nadchodzące”: jasnozielone tło z zieloną ramką);
/// ostrzegawczy (pomarańczowe tło i ramka) — przeterminowane terminy, konflikty.
enum InfoTone: Sendable {
    case neutral, primary, warning

    var background: Color {
        switch self {
        case .neutral: HorselyColor.surfaceVariant
        case .primary: HorselyColor.upcomingContainer
        case .warning: HorselyColor.warningContainer
        }
    }

    var foreground: Color {
        switch self {
        case .neutral: HorselyColor.onSurfaceVariant
        case .primary: HorselyColor.onUpcomingContainer
        case .warning: HorselyColor.onWarningContainer
        }
    }

    var border: Color? {
        switch self {
        case .neutral: nil
        case .primary: HorselyColor.upcomingBorder
        case .warning: HorselyColor.warning
        }
    }
}

/// Obszar (kafelek) zaokrąglony 12 pt, wnętrze 12 pt, ramka 1 pt tylko dla tonów głównego i ostrzegawczego.
struct InfoCard<Content: View>: View {
    let tone: InfoTone
    private let content: Content

    init(tone: InfoTone = .neutral, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(tone.foreground)
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.background, in: RoundedRectangle(cornerRadius: Spacing.cardRadius))
            .overlay {
                if let border = tone.border {
                    RoundedRectangle(cornerRadius: Spacing.cardRadius).strokeBorder(border, lineWidth: Spacing.cardBorder)
                }
            }
    }
}
