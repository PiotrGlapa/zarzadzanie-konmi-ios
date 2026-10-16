import SwiftUI

/// Pierwszy ekran parowania: krótki opis, wyjaśnienie dostępu do sieci lokalnej (iOS pyta o zgodę przy pierwszym połączeniu
/// z komputerem w domowej sieci) i wybór: skan kodu QR albo wpis ręczny. Błąd poprzedniej próby pokazany nad przyciskami.
struct LocalNetworkExplainerView: View {
    let error: String?
    let onScan: () -> Void
    let onManual: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.beforeSection) {
                Text(tr("app_full_name"))
                    .font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("pairing_welcome_body").font(.body)
                InfoCard(tone: .neutral) {
                    VStack(alignment: .leading, spacing: Spacing.between) {
                        Text("pairing_help_where").font(.subheadline)
                        // Tekst tylko w iOS (Android nie pyta o sieć lokalną) — poza katalogiem tekstów z Androida.
                        Text(verbatim: "Telefon zapyta o zgodę na dostęp do urządzeń w sieci lokalnej — zezwól, aby aplikacja mogła połączyć się z komputerem w domowej sieci Wi‑Fi.")
                            .font(.subheadline)
                    }
                }
                if let error {
                    InfoCard(tone: .warning) {
                        Text(error).font(.subheadline).accessibilityIdentifier("pairing-error")
                    }
                }
                Button(action: onScan) {
                    Label {
                        Text("pairing_scan_qr")
                    } icon: {
                        HIcon(name: "qr_code_scanner", size: 22)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.primaryFilled)
                .tint(HorselyColor.primary)
                .accessibilityIdentifier("pairing-scan")
                Button(action: onManual) {
                    Text("pairing_enter_manually").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .tint(HorselyColor.primary)
                .accessibilityIdentifier("pairing-manual")
            }
            .padding(Spacing.screenEdge)
        }
    }
}
