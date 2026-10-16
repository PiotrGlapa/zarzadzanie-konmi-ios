import HorselyCore
import HorselyKit
import SwiftUI

/// Wynik parowania: wersja programu i liczba koni; ostrzeżenia — połączenie bez szyfrowania, program nowszy niż testowany.
struct PairingResultView: View {
    let result: PairingResult
    let saving: Bool
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.beforeSection) {
                AccentIcon(icon: "cloud_sync", color: HorselyColor.primary, diameter: 72)
                Text("pairing_result_title").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("pairing_result_program", result.programVersion)).font(.body).accessibilityIdentifier("pairing-result-version")
                    Text(trPlural("pairing_horses_count", result.horseCount)).font(.body).accessibilityIdentifier("pairing-result-horses")
                }
                if result.unencrypted {
                    InfoCard(tone: .warning) { Text("pairing_cleartext_body").font(.subheadline) }
                }
                if result.versionCheck == .newerThanTested {
                    InfoCard(tone: .warning) { Text(tr("pairing_newer_program", result.programVersion)).font(.subheadline) }
                }
                Button(action: onContinue) {
                    Group {
                        if saving { ProgressView() } else { Text("pairing_result_continue").font(.headline) }
                    }
                    .frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.primaryFilled)
                .tint(HorselyColor.primary)
                .disabled(saving)
                .accessibilityIdentifier("pairing-continue")
            }
            .padding(Spacing.screenEdge)
        }
    }
}

/// Ten komputer nie wygląda na tę samą stajnię (FR-M-POL-08): „Wyślij mimo to” / „Usuń kolejkę”.
struct StableMismatchView: View {
    let identity: StableIdentity
    let onSendAnyway: () -> Void
    let onDeleteQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.beforeSection) {
            Spacer()
            AccentIcon(icon: "warning", color: HorselyColor.warning, diameter: 72)
            Text("stable_mismatch_title").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(identity.missingHorses > 0 ? trPlural("stable_mismatch_body", identity.missingHorses) : tr("stable_mismatch_empty_body"))
                .font(.body)
            Spacer()
            Button(action: onSendAnyway) {
                Text("stable_mismatch_send_anyway").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.bordered)
            .tint(HorselyColor.primary)
            .accessibilityIdentifier("stable-send-anyway")
            Button(role: .destructive, action: onDeleteQueue) {
                Text("stable_mismatch_delete").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("stable-delete-queue")
        }
        .padding(Spacing.screenEdge)
    }
}
