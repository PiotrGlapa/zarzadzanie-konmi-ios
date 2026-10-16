import Contacts
import ContactsUI
import HorselyCore
import HorselyKit
import SwiftUI
import UIKit

/// Kontakty (T102, FR-M-KTK-01): wyszukiwanie po nazwie, telefonie i e‑mailu, filtr typu (bez zarchiwizowanych), „Dodaj kontakt”.
struct ContactsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var query = ""
    @State private var type: ContactType?
    @State private var contacts: [LocalContact]?
    @State private var adding = false

    struct Route: Hashable {
        let id: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.between) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.between) {
                        FilterChip(title: "contacts_all_types", selected: type == nil) { type = nil }
                        ForEach(ContactType.allCases, id: \.self) { item in
                            FilterChip(title: LocalizedStringKey(item.labelKey), selected: type == item) { type = item }
                        }
                    }
                    .padding(.horizontal, Spacing.screenEdge)
                }
                if let contacts {
                    if contacts.isEmpty {
                        SectionEmpty(title: query.isEmpty && type == nil ? "contacts_empty_title" : "contacts_no_results",
                                     hint: query.isEmpty && type == nil ? "contacts_empty_hint" : "contacts_no_results_hint")
                    } else {
                        DividedList(contacts) { contact in
                            NavigationLink(value: Route(id: contact.id)) { ContactRow(contact: contact) }.buttonStyle(.plain)
                        }
                    }
                }
                Color.clear.frame(height: Spacing.addButtonClearance)
            }
        }
        .background(HorselyColor.background)
        .searchable(text: $query, prompt: Text("contacts_search"))
        .navigationTitle(tr("nav_contacts"))
        .navigationBarTitleDisplayMode(.inline)
        .connectionChrome()
        .navigationDestination(for: Route.self) { ContactCardView(contactId: $0.id) }
        .overlay(alignment: .bottomTrailing) {
            Button { adding = true } label: {
                HIcon(name: "add", size: 28)
                    .foregroundStyle(HorselyColor.onPrimary)
                    .frame(width: 56, height: 56)
                    .background(HorselyColor.primary, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            }
            .padding(Spacing.screenEdge)
            .accessibilityLabel(tr("contacts_add"))
            .accessibilityIdentifier("contacts-add")
        }
        .task(id: LoadKey(query: query, type: type, revision: environment.dataRevision)) {
            contacts = try? await environment.entries.contacts(query: query, type: type)
        }
        .sheet(isPresented: $adding) {
            ContactFormView(contact: nil).environment(environment)
        }
    }

    private struct LoadKey: Hashable {
        let query: String
        let type: ContactType?
        let revision: Int64
    }
}

struct ContactRow: View {
    let contact: LocalContact

    var body: some View {
        HStack(spacing: Spacing.between + 4) {
            AccentIcon(icon: "person", color: SectionAccent.contacts.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                let details = [contact.types.map { tr($0.labelKey) }.joined(separator: ", "), contact.phone].compactMap { $0 }.filter { !$0.isEmpty }
                if !details.isEmpty { Text(details.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                RecordMarkerLabel(type: .contact, id: contact.id)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(HorselyColor.onSurfaceVariant).accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.between)
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("contacts_open", contact.name))
        .accessibilityIdentifier("contact-row")
    }
}

/// Karta kontaktu (FR-M-KTK-02): dane, akcje (zadzwoń, SMS, e‑mail, nawigacja w Mapach, kopiuj), historia zakupów z sumą,
/// treningi trenera i jeźdźca, starty jeźdźca; „Edytuj”, „Archiwizuj”, „Usuń” (kontakt używany — propozycja archiwizacji).
struct ContactCardView: View {
    let contactId: String
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var contact: LocalContact?
    @State private var history: ContactHistory?
    @State private var loaded = false
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var inUse = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.beforeSection) {
                if let contact {
                    header(contact)
                    actions(contact)
                    details(contact)
                    if let history { historyView(history) }
                    footerButtons(contact)
                } else if loaded {
                    Text("contacts_not_found").frame(maxWidth: .infinity).padding(.vertical, 32)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }
            .padding(Spacing.screenEdge)
        }
        .background(HorselyColor.background)
        .navigationTitle(contact?.name ?? tr("nav_contacts"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if contact != nil {
                ToolbarItem(placement: .primaryAction) { Button(tr("contacts_edit")) { editing = true }.accessibilityIdentifier("contact-edit") }
            }
        }
        .task(id: environment.dataRevision) {
            contact = try? await environment.entries.contact(id: contactId)
            history = try? await environment.entries.contactHistory(id: contactId)
            loaded = true
        }
        .sheet(isPresented: $editing) {
            if let contact { ContactFormView(contact: contact).environment(environment) }
        }
        .confirmationDialog(tr("contacts_delete_title"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(tr("contacts_delete"), role: .destructive) { delete() }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text(tr("contacts_delete_text", contact?.name ?? ""))
        }
        .alert(tr("contacts_in_use"), isPresented: $inUse) {
            Button(tr("contacts_archive")) { setArchived(true) }
            Button(tr("common_cancel"), role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if copied { SaveBanner(message: tr("contacts_copied"), undo: nil) { copied = false }.padding(.bottom, Spacing.between) }
        }
    }

    private func header(_ contact: LocalContact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contact.name).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(contact.types.map { tr($0.labelKey) }.joined(separator: ", ")).font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
            if contact.isArchived {
                Text("contacts_archived_badge").font(.footnote.weight(.semibold)).foregroundStyle(HorselyColor.warning)
            }
        }
    }

    private func actions(_ contact: LocalContact) -> some View {
        let phone = contact.phone.map { $0.filter { $0.isNumber || $0 == "+" } }
        return HStack(spacing: Spacing.between) {
            if let phone, !phone.isEmpty {
                actionButton("contacts_call", "phone") { open("tel:\(phone)") }
                actionButton("contacts_sms", "message") { open("sms:\(phone)") }
            }
            if let email = contact.email {
                actionButton("contacts_email_action", "envelope") { open("mailto:\(email)") }
            }
            if let address = contact.address {
                actionButton("contacts_navigate", "map") {
                    open("http://maps.apple.com/?q=\(address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
                }
            }
            actionButton("contacts_copy", "doc.on.doc") {
                UIPasteboard.general.string = [contact.name, contact.phone, contact.email, contact.address].compactMap { $0 }.joined(separator: "\n")
                copied = true
            }
        }
    }

    private func actionButton(_ key: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(key).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget + 12)
        }
        .buttonStyle(.bordered)
        .tint(HorselyColor.primary)
    }

    private func open(_ text: String) {
        guard let url = URL(string: text) else { return }
        openURL(url)
    }

    @ViewBuilder private func details(_ contact: LocalContact) -> some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            field("contacts_label_company", contact.company)
            field("contacts_label_phone", contact.phone)
            field("contacts_label_email", contact.email)
            field("contacts_label_address", contact.address)
            field("contacts_label_specialization", contact.specialization)
            field("contacts_label_notes", contact.notes)
        }
    }

    @ViewBuilder private func field(_ key: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(key).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                Text(value).font(.body).textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func historyView(_ history: ContactHistory) -> some View {
        SectionHeader("contacts_history_purchases")
        if history.purchases.isEmpty {
            Text("contacts_history_none").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
        } else {
            ForEach(history.purchases.prefix(20)) { purchase in
                historyLine(purchase.productName, Formats.date(purchase.purchaseDate), Formats.money(purchase.totalAmount + purchase.deliveryCost))
            }
            Text(tr("contacts_history_total", Formats.money(history.purchasesTotal))).font(.subheadline.weight(.semibold))
        }
        if !history.asTrainer.isEmpty {
            SectionHeader("contacts_history_trainer")
            ForEach(history.asTrainer.prefix(20)) { training in historyLine(horseName(training.horseId), Formats.date(training.trainingDate), training.cost.map(Formats.money)) }
        }
        if !history.asRider.isEmpty {
            SectionHeader("contacts_history_rider")
            ForEach(history.asRider.prefix(20)) { training in historyLine(horseName(training.horseId), Formats.date(training.trainingDate), training.cost.map(Formats.money)) }
        }
        if !history.starts.isEmpty {
            SectionHeader("contacts_history_starts")
            ForEach(history.starts.prefix(20)) { start in
                historyLine(horseName(start.horseId), start.startDate.map(Formats.date) ?? "", start.placement.map { tr("competitions_start_result", $0) })
            }
        }
    }

    private func historyLine(_ title: String, _ date: String, _ trailing: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(date).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
            }
            Spacer()
            if let trailing { Text(trailing).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
        }
        .accessibilityElement(children: .combine)
    }

    private func horseName(_ id: String) -> String {
        environment.horseDirectory.horses.first { $0.id == id }?.name ?? Formats.dash
    }

    private func footerButtons(_ contact: LocalContact) -> some View {
        VStack(spacing: Spacing.between) {
            Button { setArchived(!contact.isArchived) } label: {
                Text(contact.isArchived ? "contacts_unarchive" : "contacts_archive").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.bordered)
            .tint(HorselyColor.primary)
            .accessibilityIdentifier("contact-archive")
            Button(role: .destructive) { confirmingDelete = true } label: {
                Text("contacts_delete").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("contact-delete")
        }
    }

    private func setArchived(_ archived: Bool) {
        Task {
            if let saved = try? await environment.entries.setContactArchived(id: contactId, archived).saved {
                let text = await environment.messageAfterSave(saved, edited: true)
                environment.router.banner = BannerMessage(text: text, undo: nil)
            }
        }
    }

    private func delete() {
        Task {
            switch try? await environment.entries.delete(.contact, id: contactId) {
            case let .saved(saved)?:
                environment.router.banner = BannerMessage(text: tr("entry_deleted")) { Task { try? await environment.entries.undo(saved.undo) } }
                dismiss()
            case let .rejected(.conflict(reason, _))? where reason == .inUse:
                inUse = true
            default:
                break
            }
        }
    }
}
