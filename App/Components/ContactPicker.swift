import HorselyCore
import SwiftUI

/// Wybór kontaktu danego typu (trener, jeździec, lekarz…) z listy niezarchiwizowanych oraz „Dodaj kontakt” bez opuszczania formularza.
/// Zapisany kontakt zarchiwizowany pozostaje widoczny, żeby edycja go nie gubiła.
struct ContactPicker: View {
    let title: LocalizedStringKey
    let contacts: [LocalContact]
    let type: ContactType
    @Binding var selection: String?
    /// Dodaje kontakt o podanej nazwie i zwraca jego id (albo `nil`, gdy nazwa jest niepoprawna).
    let add: (String) async -> String?
    var identifier: String?
    @State private var adding = false
    @State private var newName = ""

    private var options: [LocalContact] {
        contacts.filter { ($0.types.contains(type) && !$0.isArchived) || $0.id == selection }
    }

    var body: some View {
        Picker(selection: $selection) {
            Text("contact_picker_not_selected").tag(String?.none)
            ForEach(options) { contact in
                Text(contact.name).tag(String?.some(contact.id))
            }
        } label: {
            Text(title)
        }
        .accessibilityIdentifier(identifier ?? "")
        Button {
            newName = ""
            adding = true
        } label: {
            Label {
                Text("contact_picker_add")
            } icon: {
                HIcon(name: "add", size: 20)
            }
            .foregroundStyle(HorselyColor.primary)
            .frame(minHeight: Spacing.minTouchTarget, alignment: .leading)
        }
        .alert(Text("contacts_form_new"), isPresented: $adding) {
            TextField(tr("contacts_label_name"), text: $newName)
            Button(tr("common_save")) {
                let name = newName
                Task { if let id = await add(name) { selection = id } }
            }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(type.labelKey))
        }
    }
}
