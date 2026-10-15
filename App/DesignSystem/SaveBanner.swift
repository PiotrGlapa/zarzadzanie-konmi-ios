import SwiftUI

/// Baner u dołu po zapisie: „Zapisano” (albo „Zapisano — wyślę po połączeniu z komputerem”) z akcją „Cofnij”, znika po 4 s.
struct SaveBanner: View {
    let message: String
    let undo: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.between) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(HorselyColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let undo {
                Button(tr("common_undo")) {
                    undo()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HorselyColor.primary)
                .frame(minHeight: Spacing.minTouchTarget)
            }
        }
        .padding(.horizontal, Spacing.screenEdge)
        .background(HorselyColor.surfaceVariant, in: RoundedRectangle(cornerRadius: Spacing.cardRadius))
        .padding(.horizontal, Spacing.screenEdge)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .task {
            try? await Task.sleep(for: .seconds(4))
            dismiss()
        }
    }
}
