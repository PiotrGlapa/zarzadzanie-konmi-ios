import HorselyCore
import SwiftUI

/// Ocena gwiazdkami — wyświetlanie („★★★☆☆” w kolorze ostrzeżenia) z etykietą VoiceOver „Ocena: N z 5” / „Brak oceny”.
struct StarRatingDisplay: View {
    let rating: Int?

    var body: some View {
        if let stars = Stars.format(rating), let rating {
            Text(stars)
                .foregroundStyle(HorselyColor.warning)
                .accessibilityLabel(tr("rating_content", rating))
        } else {
            Text(Formats.dash)
                .accessibilityLabel(tr("rating_none"))
        }
    }
}

/// Ocena gwiazdkami — wejście: pięć przycisków o celu dotyku ≥ 44 pt i „Wyczyść ocenę”.
struct StarRatingInput: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...Stars.max, id: \.self) { value in
                Button {
                    rating = value
                } label: {
                    Text((rating ?? 0) >= value ? "★" : "☆")
                        .font(.title2)
                        .foregroundStyle(HorselyColor.warning)
                        .frame(minWidth: Spacing.minTouchTarget, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("rating_star_label", value))
                .accessibilityAddTraits(rating == value ? .isSelected : [])
            }
            if rating != nil {
                Button(tr("rating_clear")) { rating = nil }
                    .frame(minHeight: Spacing.minTouchTarget)
            }
        }
    }
}
