import HorselyCore
import HorselyKit
import SwiftUI

/// Chip filtra (zakładki karty konia): zaznaczony w kolorze kontenera drugorzędnego.
struct FilterChip: View {
    let title: LocalizedStringKey
    let selected: Bool
    let action: () -> Void
    var identifier: String?

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(minHeight: Spacing.minTouchTarget - 4)
                .foregroundStyle(selected ? HorselyColor.onSecondaryContainer : HorselyColor.onSurfaceVariant)
                .background(selected ? HorselyColor.secondaryContainer : HorselyColor.surfaceVariant, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// Tekst pustej zakładki.
struct TabEmptyText: View {
    let key: LocalizedStringKey
    var hint: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 4) {
            Text(key).font(.headline).foregroundStyle(HorselyColor.onSurfaceVariant)
            if let hint { Text(hint).font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

/// Przycisk „Dodaj …” w zakładce (otwiera formularz z koniem już wybranym).
struct TabAddButton: View {
    @Environment(AppEnvironment.self) private var environment
    let title: LocalizedStringKey
    let request: EntryRequest
    var identifier: String?

    var body: some View {
        Button {
            if environment.workMode == .standalone { environment.router.entryRequest = request.renewed() }
        } label: {
            Label {
                Text(title)
            } icon: {
                HIcon(name: "add", size: 20)
            }
            .frame(minHeight: Spacing.minTouchTarget, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(HorselyColor.primary)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// Nazwy pozycji słowników (rodzaj treningu, kategoria zakupu…) do wierszy zakładek.
@MainActor
@Observable
final class DictionaryNames {
    private(set) var names: [String: String] = [:]

    func load(using environment: AppEnvironment) async {
        let items = (try? await environment.entries.allDictionaryItems()) ?? []
        names = Dictionary(items.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    func name(_ id: String?) -> String? { id.flatMap { names[$0] } }
}
