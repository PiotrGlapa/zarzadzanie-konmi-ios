import HorselyCore
import HorselyKit
import SwiftUI

/// Oznaczenie rekordu z niewysłaną zmianą na listach (T090): „czeka na wysłanie” / „wymaga poprawy” / „konflikt”. Tylko w trybie
/// online; bez środowiska (podglądy) — nic.
struct RecordMarkerLabel: View {
    let type: RecordType
    let id: String
    @Environment(AppEnvironment.self) private var environment: AppEnvironment?

    var body: some View {
        if let marker = environment?.marker(type, id: id) {
            HStack(spacing: 4) {
                HIcon(name: marker == .pending ? "cloud_sync" : "sync_problem", size: 14)
                Text(LocalizedStringKey(Self.key(marker))).font(.caption.weight(.semibold))
            }
            .foregroundStyle(marker == .pending ? HorselyColor.onSurfaceVariant : HorselyColor.warning)
            .accessibilityIdentifier("record-marker")
        }
    }

    static func key(_ marker: RecordMarker) -> String {
        switch marker {
        case .pending: "queued_marker"
        case .needsFix: "needs_fix_marker"
        case .conflict: "conflict_marker"
        }
    }
}
