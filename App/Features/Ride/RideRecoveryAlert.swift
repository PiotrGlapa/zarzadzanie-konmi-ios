import HorselyCore
import HorselyKit
import SwiftUI

/// „Niezakończone nagranie — Masz niezakończone nagranie (Grom, 14:05, 6,1 km). Zapisz / Odrzuć” (NAG-09 = Android 3.0.2
/// `RideRecoveryDialog`). Odrzucenie jest nieodwracalne, więc przed nim pada jeszcze jedno pytanie („Odrzucić nagranie?” — „Odrzuć
/// nagranie” / „Wróć”, które wraca do pierwszego pytania).
///
/// Systemowy alert iOS zamiast okna Material: Android zamyka okno także stuknięciem obok (`onDismissRequest` — jazda czeka do następnego
/// startu), a alert iOS bez przycisku anulowania nie da się zamknąć, więc ma „Anuluj” (`common_cancel`) o tym samym skutku.
struct RideRecoveryAlert: ViewModifier {
    @Binding var ride: UnfinishedRide?
    var timeZone: TimeZone = .current
    let onSave: (UnfinishedRide) -> Void
    let onDiscard: (UnfinishedRide) -> Void
    var onDismiss: () -> Void = {}

    @State private var confirmDiscard: UnfinishedRide?

    func body(content: Content) -> some View {
        content
            .alert(
                tr("ride_recovery_title"),
                isPresented: Binding(get: { ride != nil }, set: { if !$0 { ride = nil } }),
                presenting: ride
            ) { pending in
                let texts = RideStartPolicy.recovery(pending, timeZone: timeZone)
                Button(tr(texts.saveKey)) { onSave(pending) }
                Button(tr(texts.discardKey), role: .destructive) { confirmDiscard = pending }
                Button(tr("common_cancel"), role: .cancel) { onDismiss() }
            } message: { pending in
                Text(RideText.recovery(RideStartPolicy.recovery(pending, timeZone: timeZone)))
            }
            .alert(
                tr("ride_recovery_discard_title"),
                isPresented: Binding(get: { confirmDiscard != nil }, set: { if !$0 { confirmDiscard = nil } }),
                presenting: confirmDiscard
            ) { pending in
                let texts = RideStartPolicy.recovery(pending, timeZone: timeZone)
                Button(tr(texts.discardConfirmKey), role: .destructive) { onDiscard(pending) }
                Button(tr(texts.discardBackKey), role: .cancel) { ride = pending }
            } message: { pending in
                Text(LocalizedStringKey(RideStartPolicy.recovery(pending, timeZone: timeZone).discardTextKey))
            }
    }
}

extension View {
    /// Pytanie o niezakończoną jazdę (`ride` różne od `nil` — pokazane).
    func rideRecoveryAlert(
        _ ride: Binding<UnfinishedRide?>, timeZone: TimeZone = .current, onSave: @escaping (UnfinishedRide) -> Void,
        onDiscard: @escaping (UnfinishedRide) -> Void, onDismiss: @escaping () -> Void = {}
    ) -> some View {
        modifier(RideRecoveryAlert(ride: ride, timeZone: timeZone, onSave: onSave, onDiscard: onDiscard, onDismiss: onDismiss))
    }
}
