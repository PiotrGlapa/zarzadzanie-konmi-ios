import SwiftUI

/// Stan ekranu ładowanego asynchronicznie: ładowanie, pusto (z podpowiedzią), błąd z „Spróbuj ponownie”, albo treść.
enum ScreenState<Value> {
    case loading
    case empty(title: LocalizedStringKey, hint: LocalizedStringKey?)
    case failed(message: String)
    case content(Value)
}

/// Widok wspólnych stanów ekranu — treść dostarcza wywołujący.
struct ScreenStateView<Value, Content: View>: View {
    let state: ScreenState<Value>
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView("common_loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(tr("common_loading_description"))
        case let .empty(title, hint):
            VStack(spacing: Spacing.between) {
                Text(title).font(.headline)
                if let hint { Text(hint).font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant) }
            }
            .multilineTextAlignment(.center)
            .padding(Spacing.screenEdge)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            VStack(spacing: Spacing.between) {
                Text(message).multilineTextAlignment(.center)
                Button(tr("common_retry"), action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(HorselyColor.primary)
                    .frame(minHeight: Spacing.minTouchTarget)
            }
            .padding(Spacing.screenEdge)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .content(value):
            content(value)
        }
    }
}
