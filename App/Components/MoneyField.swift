import HorselyCore
import SwiftUI

/// Pole kwoty w złotych (klawiatura dziesiętna, przecinek dziesiętny) z przyrostkiem „zł”. Tekst jest przekazywany jak wpisano;
/// odczyt i granice kwoty rozstrzygają `MoneyInput` i reguły.
struct MoneyField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var suffix: String? = tr("common_currency_suffix")
    var identifier: String?

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField("", text: $text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier(identifier ?? "")
                if let suffix { Text(suffix).foregroundStyle(HorselyColor.onSurfaceVariant) }
            }
        } label: {
            Text(title)
        }
    }
}

/// Pole liczby całkowitej (czas, miejsce, wysokość).
struct IntegerField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var identifier: String?

    var body: some View {
        LabeledContent {
            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .accessibilityIdentifier(identifier ?? "")
        } label: {
            Text(title)
        }
    }
}

/// Pole tekstu: jednowierszowe (etykieta po lewej) albo wielowierszowe (etykieta nad polem).
struct TextRow: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var required = false
    var multiline = false
    var capitalization: TextInputAutocapitalization = .sentences
    var identifier: String?

    var body: some View {
        if multiline {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(2...6)
                    .textInputAutocapitalization(capitalization)
                    .accessibilityIdentifier(identifier ?? "")
            }
        } else {
            LabeledContent {
                TextField("", text: $text, prompt: required ? Text("common_required") : nil)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(capitalization)
                    .accessibilityIdentifier(identifier ?? "")
            } label: {
                Text(title)
            }
        }
    }
}
