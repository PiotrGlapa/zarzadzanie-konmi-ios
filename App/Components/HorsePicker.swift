import HorselyCore
import SwiftUI

/// Wybór konia z listy koni w stajni (aktywne i kontuzjowane); koń zapisany we wpisie, który już nie jest w stajni, pozostaje na liście.
struct HorsePicker: View {
    let title: LocalizedStringKey
    let horses: [LocalHorse]
    @Binding var selection: String?
    var identifier: String?

    private var options: [LocalHorse] {
        let inStable = HorseSearch.apply(horses, query: "", filter: .inStable)
        guard let selection, !inStable.contains(where: { $0.id == selection }), let current = horses.first(where: { $0.id == selection }) else { return inStable }
        return inStable + [current]
    }

    var body: some View {
        Picker(selection: $selection) {
            Text("dictionary_picker_not_selected").tag(String?.none)
            ForEach(options) { horse in
                Text(horse.name).tag(String?.some(horse.id))
            }
        } label: {
            Text(title)
        }
        .accessibilityIdentifier(identifier ?? "")
    }
}
