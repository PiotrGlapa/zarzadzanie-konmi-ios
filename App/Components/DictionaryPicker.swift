import HorselyCore
import SwiftUI

/// Wybór wartości słownika (FR-M-WPI-02): w nowych wpisach tylko pozycje aktywne; zapisana pozycja nieaktywna jest widoczna
/// z dopiskiem „(nieaktywna)”, żeby edycja nie gubiła jej po cichu.
struct DictionaryPicker: View {
    let title: LocalizedStringKey
    /// Wszystkie pozycje słownika danego typu, w kolejności wyświetlania.
    let items: [LocalDictionaryItem]
    @Binding var selection: String?
    var identifier: String?

    private var options: [LocalDictionaryItem] {
        items.filter { $0.isActive || $0.id == selection }
    }

    var body: some View {
        if items.isEmpty {
            LabeledContent {
                Text("dictionary_picker_empty").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant).multilineTextAlignment(.trailing)
            } label: {
                Text(title)
            }
        } else {
            Picker(selection: $selection) {
                Text("dictionary_picker_not_selected").tag(String?.none)
                ForEach(options) { item in
                    Text(item.isActive ? item.value : tr("dictionary_picker_inactive", item.value)).tag(String?.some(item.id))
                }
            } label: {
                Text(title)
            }
            .accessibilityIdentifier(identifier ?? "")
        }
    }
}

/// Wybór kilku wartości (okolice ciała, techniki, konie): wiersz z podsumowaniem otwiera listę z zaznaczeniem.
struct MultiSelect: View {
    struct Option: Identifiable, Hashable {
        let id: String
        let name: String
    }

    let title: LocalizedStringKey
    let options: [Option]
    @Binding var selection: [String]
    var emptyText: String = tr("common_none")
    var identifier: String?

    private var summary: String {
        let names = options.filter { selection.contains($0.id) }.map(\.name)
        return names.isEmpty ? emptyText : names.joined(separator: ", ")
    }

    var body: some View {
        NavigationLink {
            MultiSelectList(title: title, options: options, selection: $selection)
        } label: {
            LabeledContent {
                Text(summary).foregroundStyle(HorselyColor.onSurfaceVariant).multilineTextAlignment(.trailing).lineLimit(2)
            } label: {
                Text(title)
            }
        }
        .accessibilityIdentifier(identifier ?? "")
    }
}

private struct MultiSelectList: View {
    let title: LocalizedStringKey
    let options: [MultiSelect.Option]
    @Binding var selection: [String]
    @State private var query = ""

    private var visible: [MultiSelect.Option] {
        let key = Formats.searchKey(query)
        return key.isEmpty ? options : options.filter { Formats.searchKey($0.name).contains(key) }
    }

    var body: some View {
        List {
            ForEach(visible) { option in
                Button {
                    if let index = selection.firstIndex(of: option.id) {
                        selection.remove(at: index)
                    } else {
                        selection.append(option.id)
                    }
                } label: {
                    HStack {
                        Text(option.name).foregroundStyle(HorselyColor.onBackground)
                        Spacer()
                        if selection.contains(option.id) {
                            Image(systemName: "checkmark").foregroundStyle(HorselyColor.primary)
                        }
                    }
                    .frame(minHeight: Spacing.minTouchTarget)
                }
                .accessibilityAddTraits(selection.contains(option.id) ? .isSelected : [])
            }
        }
        .searchable(text: $query)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
