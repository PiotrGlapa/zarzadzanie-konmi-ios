import HorselyCore
import HorselyKit
import SwiftUI

/// Zakupy konia: „Suma zakupów”, wiersze (produkt, kategoria, kwota z dostawą) i „Dodaj zakup”. Zakup wspólny kilku koni pokazuje
/// pełną kwotę zakupu; podział kosztu między konie jest w raportach.
struct PurchasesTab: View {
    @Environment(AppEnvironment.self) private var environment
    let horseId: String
    @State private var purchases: [LocalPurchase]?
    @State private var names = DictionaryNames()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            TabAddButton(title: "purchases_add", request: EntryRequest(kind: .purchase, horseId: horseId), identifier: "purchases-add")
            if let purchases {
                if purchases.isEmpty {
                    TabEmptyText(key: "horse_purchases_empty")
                } else {
                    Text(tr("horse_purchases_total", Formats.money(purchases.reduce(Money.zero) { $0 + $1.totalAmount + $1.deliveryCost })))
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("purchases-total")
                    DividedList(purchases) { purchase in
                        NavigationLink(value: EntryRoute(recordType: .purchase, id: purchase.id)) { row(purchase) }
                            .buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
        .task(id: environment.dataRevision) {
            await names.load(using: environment)
            purchases = try? await environment.entries.purchases(horseId: horseId)
        }
    }

    private func row(_ purchase: LocalPurchase) -> some View {
        AccentRow(color: EntryAccent.purchase.color) {
            HStack(alignment: .top, spacing: Spacing.between) {
                HIcon(name: EntryAccent.purchase.icon, size: 24).foregroundStyle(EntryAccent.purchase.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(purchase.productName).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                    if let category = names.name(purchase.categoryId) {
                        Text(category).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formats.date(purchase.purchaseDate)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    Text(Formats.money(purchase.totalAmount + purchase.deliveryCost)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
            }
            .padding(.vertical, Spacing.between)
        }
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
