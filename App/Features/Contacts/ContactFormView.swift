import Contacts
import ContactsUI
import HorselyCore
import HorselyKit
import SwiftUI

/// Formularz kontaktu (FR-M-KTK-03): nazwa, typy, firma, telefon, e‑mail, adres, specjalizacja, notatki; przy dodawaniu „Pobierz
/// z kontaktów telefonu” (systemowe okno wyboru — bez prośby o zgodę na dostęp do kontaktów, 9.5).
struct ContactFormView: View {
    let contact: LocalContact?
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var input = ContactInput()
    @State private var errors: [String: [String]] = [:]
    @State private var picking = false
    @State private var saving = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                if contact == nil {
                    Section {
                        Button(tr("contacts_pick_from_phone")) { picking = true }.accessibilityIdentifier("contact-import")
                    }
                }
                Section {
                    textField("contacts_label_name", text: $input.name, key: "name")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("contacts_label_types").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                        ForEach(ContactType.allCases, id: \.self) { type in
                            Toggle(isOn: Binding(
                                get: { input.types.contains(type) },
                                set: { on in
                                    if on { if !input.types.contains(type) { input.types.append(type) } } else { input.types.removeAll { $0 == type } }
                                }
                            )) { Text(LocalizedStringKey(type.labelKey)) }
                        }
                        error("types")
                    }
                }
                Section {
                    optionalField("contacts_label_company", value: $input.company, key: "company")
                    optionalField("contacts_label_phone", value: $input.phone, key: "phone").keyboardType(.phonePad)
                    optionalField("contacts_label_email", value: $input.email, key: "email").keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    optionalField("contacts_label_address", value: $input.address, key: "address")
                    optionalField("contacts_label_specialization", value: $input.specialization, key: "specialization")
                    optionalField("contacts_label_notes", value: $input.notes, key: "notes")
                }
            }
            .scrollContentBackground(.hidden)
            .background(HorselyColor.background)
            .navigationTitle(tr(contact == nil ? "contacts_form_new" : "contacts_form_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common_cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("common_save")) { save() }.disabled(saving).accessibilityIdentifier("contact-save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let contact { input = ContactInput(contact: contact) }
            }
            .sheet(isPresented: $picking) {
                ContactPickerSheet { picked in
                    input = ContactImport.merge(picked, into: input)
                    picking = false
                } onCancel: {
                    picking = false
                }
                .ignoresSafeArea()
            }
        }
    }

    private func textField(_ key: LocalizedStringKey, text: Binding<String>, key field: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(key, text: text).accessibilityIdentifier("contact-\(field)")
            error(field)
        }
    }

    private func optionalField(_ key: LocalizedStringKey, value: Binding<String?>, key field: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(key, text: Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0 }))
                .accessibilityIdentifier("contact-\(field)")
            error(field)
        }
    }

    @ViewBuilder private func error(_ field: String) -> some View {
        if let message = errors[field]?.first {
            Text(message).font(.footnote).foregroundStyle(HorselyColor.error)
        }
    }

    private func save() {
        let report = ContactRules.validate(input)
        errors = report.errors
        guard !report.hasErrors else { return }
        saving = true
        let value = input
        Task {
            defer { saving = false }
            switch try? await environment.entries.saveContact(value, id: contact?.id, expectedVersion: contact?.version) {
            case let .saved(saved)?:
                let text = contact == nil ? tr("contacts_saved") : await environment.messageAfterSave(saved, edited: true)
                environment.router.banner = BannerMessage(text: text, undo: nil)
                dismiss()
            case let .rejected(.validation(fieldErrors, _))?:
                errors = fieldErrors
            case let .rejected(problem)?:
                errors = ["name": [problem.message]]
            case nil:
                break
            }
        }
    }
}

/// Dane z książki adresowej telefonu do formularza (nazwa, firma, pierwszy telefon, e‑mail i adres).
/// Dane wybranego kontaktu skopiowane z `CNContact` (który nie jest `Sendable`) w wątku delegata.
struct PickedContact: Sendable {
    let name: String
    let company: String
    let phone: String?
    let email: String?
    let address: String?

    init(_ contact: CNContact) {
        name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        company = contact.organizationName
        phone = contact.phoneNumbers.first?.value.stringValue
        email = contact.emailAddresses.first.map { $0.value as String }
        address = contact.postalAddresses.first.map {
            CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress).replacingOccurrences(of: "\n", with: ", ")
        }
    }
}

enum ContactImport {
    static func merge(_ contact: PickedContact, into input: ContactInput) -> ContactInput {
        var result = input
        if !contact.name.isEmpty { result.name = contact.name } else if !contact.company.isEmpty { result.name = contact.company }
        if !contact.company.isEmpty { result.company = contact.company }
        if let phone = contact.phone { result.phone = phone }
        if let email = contact.email { result.email = email }
        if let address = contact.address { result.address = address }
        return result
    }
}

/// Systemowe okno wyboru kontaktu (`CNContactPickerViewController`) — działa poza procesem aplikacji, więc nie wymaga zgody.
struct ContactPickerSheet: UIViewControllerRepresentable {
    let onPick: (PickedContact) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    @MainActor
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (PickedContact) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (PickedContact) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let picked = PickedContact(contact)
            MainActor.assumeIsolated { onPick(picked) }
        }

        nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            MainActor.assumeIsolated { onCancel() }
        }
    }
}
