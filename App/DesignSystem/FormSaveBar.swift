import SwiftUI

/// Pasek „Zapisz” przypięty do dołu formularza (`safeAreaInset`) — szeroki przycisk w kolorze głównym; w trakcie zapisu nieaktywny.
struct FormSaveBar: View {
    let isSaving: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("common_save")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
        }
        .buttonStyle(.primaryFilled)
        .tint(HorselyColor.primary)
        .disabled(isSaving)
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.between)
        .background(.bar)
    }
}
