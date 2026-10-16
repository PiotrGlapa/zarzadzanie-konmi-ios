import HorselyKit
import SwiftUI

/// Karty Pulpitu w trybie online: baner pierwszego pobrania danych (postęp, „Możesz już korzystać z aplikacji”) i „Konflikty do
/// rozstrzygnięcia: N” (T087, T089).
struct OnlineDashboardCards: View {
    @Environment(AppEnvironment.self) private var environment

    private enum Route: Hashable { case conflicts }

    var body: some View {
        if environment.workMode == .online {
            VStack(alignment: .leading, spacing: Spacing.between) {
                if environment.initialSyncRunning {
                    InfoCard(tone: .primary) {
                        VStack(alignment: .leading, spacing: Spacing.between) {
                            Text("initial_sync_title").font(.headline)
                            if let progress = environment.initialSync, progress.records > 0 || progress.bytes > 0 {
                                if let fraction = progress.fraction { ProgressView(value: fraction) } else { ProgressView() }
                                if progress.records > 0 { Text(tr("initial_sync_progress", progress.records)).font(.subheadline) }
                            } else {
                                ProgressView()
                                Text("initial_sync_starting").font(.subheadline)
                            }
                            Text("initial_sync_usable").font(.footnote)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("initial-sync-banner")
                }
                if environment.conflictCount > 0 {
                    NavigationLink(value: Route.conflicts) {
                        InfoCard(tone: .warning) {
                            HStack(spacing: Spacing.between) {
                                HIcon(name: "sync_problem", size: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tr("conflicts_dashboard_card", environment.conflictCount)).font(.headline)
                                    Text("conflicts_dashboard_hint").font(.footnote)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard-conflicts")
                }
            }
            .padding(.top, Spacing.between)
            .navigationDestination(for: Route.self) { _ in ConflictsView() }
        }
    }
}
