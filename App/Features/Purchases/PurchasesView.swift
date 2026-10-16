import HorselyCore
import HorselyKit
import SwiftUI

/// Dział Zakupy (T100, US11/3): zakupy (data, produkt, kategoria, dostawca, konie albo „Ogólne (stajnia)”, łączna kwota), filtry
/// (okres, kategoria, dostawca, dla kogo), stopka „Zakupów: N · Razem: kwota”; wiersz otwiera szczegóły, menu wiersza — „Powtórz
/// zakup” i „Usuń”; „+” otwiera formularz zakupu.
struct PurchasesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var list: SectionList<LocalPurchase>?
    @State private var names = SectionNames()
    @State private var showingFilters = false
    @State private var deleting: LocalPurchase?

    var body: some View {
        @Bindable var filters = environment.sectionFilters
        let today = environment.dates.today()
        ScrollView {
            if let list {
                if list.items.isEmpty {
                    SectionEmpty(title: "purchases_empty_title", hint: "purchases_empty_hint")
                } else {
                    DividedList(list.items) { purchase in
                        NavigationLink(value: EntryRoute(recordType: .purchase, id: purchase.id)) { row(purchase) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(tr("purchases_repeat")) { repeatPurchase(purchase) }
                                Button(tr("purchases_delete"), role: .destructive) { deleting = purchase }
                            }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            }
            Color.clear.frame(height: Spacing.addButtonClearance)
        }
        .safeAreaInset(edge: .bottom) {
            if let list { SectionFooter(text: tr("purchases_summary", list.count, Formats.money(list.total)), identifier: "purchases-summary") }
        }
        .background(HorselyColor.background)
        .navigationTitle(tr("nav_purchases"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FiltersButton(active: filters.purchases.activeCount(today: today)) { showingFilters = true }
            }
        }
        .connectionChrome()
        .navigationDestination(for: EntryRoute.self) { EntryDetailView(route: $0) }
        .overlay(alignment: .bottomTrailing) { AddEntryButton(request: EntryRequest(kind: .purchase)) }
        .task(id: LoadKey(query: filters.purchases, revision: environment.dataRevision)) {
            await names.load(using: environment)
            list = try? await environment.entries.purchases(filters.purchases)
        }
        .confirmationDialog(tr("purchases_delete_title"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(tr("purchases_delete"), role: .destructive) {
                if let purchase = deleting { delete(purchase) }
                deleting = nil
            }
        } message: {
            if let purchase = deleting { Text(tr("purchases_delete_message", purchase.productName)) }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                Form {
                    PeriodFields(period: $filters.purchases.period, today: today)
                    OptionalPicker(title: "purchases_filter_category", selection: $filters.purchases.categoryId,
                                   options: names.items(.purchaseCategory).map { (id: $0.id, name: $0.value) })
                    OptionalPicker(title: "purchases_filter_supplier", selection: $filters.purchases.supplierId,
                                   options: names.contacts.filter { !$0.isArchived }.map { (id: $0.id, name: $0.name) })
                    Picker(selection: scopeBinding(filters)) {
                        Text("purchases_scope_all").tag("")
                        Text("purchases_scope_general").tag("general")
                        ForEach(environment.horseDirectory.horses) { horse in Text(horse.name).tag(horse.id) }
                    } label: {
                        Text("purchases_filter_for")
                    }
                    Button(tr("sections_clear_filters")) { filters.purchases = PurchaseQuery(period: .default(today: today)) }
                        .disabled(filters.purchases.activeCount(today: today) == 0)
                        .accessibilityIdentifier("section-clear-filters")
                }
                .navigationTitle("sections_filters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("sections_filters_done")) { showingFilters = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private struct LoadKey: Hashable {
        let query: PurchaseQuery
        let revision: Int64
    }

    private func scopeBinding(_ filters: SectionFilters) -> Binding<String> {
        Binding(
            get: {
                switch filters.purchases.scope {
                case .all: ""
                case .general: "general"
                case let .horse(id): id
                }
            },
            set: { value in filters.purchases.scope = value.isEmpty ? .all : (value == "general" ? .general : .horse(value)) }
        )
    }

    private func horseNames(_ purchase: LocalPurchase) -> String {
        if purchase.assignment == .general || purchase.horseIds.isEmpty { return tr("purchases_general_label") }
        return environment.horseDirectory.horses.filter { purchase.horseIds.contains($0.id) }.map(\.name)
            .sorted { PolishNames.compare($0, $1) == .orderedAscending }.joined(separator: ", ")
    }

    private func row(_ purchase: LocalPurchase) -> some View {
        var details = [names.dictionaryName(purchase.categoryId), names.contactName(purchase.supplierContactId)].compactMap { $0 }
        details.append(horseNames(purchase))
        return AccentRow(color: EntryAccent.purchase.color) {
            HStack(alignment: .top, spacing: Spacing.between) {
                HIcon(name: EntryAccent.purchase.icon, size: 24).foregroundStyle(EntryAccent.purchase.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(purchase.productName).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                    Text(details.joined(separator: " · ")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    RecordMarkerLabel(type: .purchase, id: purchase.id)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formats.date(purchase.purchaseDate)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    Text(Formats.money(purchase.totalAmount + purchase.deliveryCost)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
            }
            .padding(.vertical, Spacing.between)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(tr("purchases_row_menu", purchase.productName))
        .accessibilityIdentifier("purchase-row")
    }

    private func repeatPurchase(_ purchase: LocalPurchase) {
        var request = EntryRequest(kind: .purchase)
        request.repeating = purchase
        environment.router.entryRequest = request
    }

    private func delete(_ purchase: LocalPurchase) {
        Task {
            if let saved = try? await environment.entries.delete(.purchase, id: purchase.id).saved {
                environment.router.banner = BannerMessage(text: tr("entry_deleted")) {
                    Task { try? await environment.entries.undo(saved.undo) }
                }
            }
        }
    }
}
