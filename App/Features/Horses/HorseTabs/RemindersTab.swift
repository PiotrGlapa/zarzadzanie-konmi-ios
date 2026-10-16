import HorselyCore
import HorselyKit
import SwiftUI

/// Terminy konia: otwarte terminy w obszarach „Przeterminowane” (ostrzegawczy), „Nadchodzące” (zielony) i „Później” (neutralny).
struct RemindersTab: View {
    @Environment(AppEnvironment.self) private var environment
    let horseId: String
    @State private var items: [ReminderItem]?

    private var today: LocalDate { environment.dates.today() }
    private var horizonEnd: LocalDate { today.adding(days: RuleSettings().upcomingHorizonDays) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let items {
                if items.isEmpty {
                    TabEmptyText(key: "horse_no_reminders")
                } else {
                    area(LocalizedStringKey("dashboard_overdue"), items.filter { $0.dueDate < today }, .warning)
                    area(LocalizedStringKey(trPlural("dashboard_upcoming", RuleSettings().upcomingHorizonDays)), items.filter { $0.dueDate >= today && $0.dueDate <= horizonEnd }, .primary)
                    area(LocalizedStringKey("dashboard_later"), items.filter { $0.dueDate > horizonEnd }, .neutral)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
        .task(id: environment.dataRevision) {
            items = try? await environment.reminders.reminders(ReminderFilter(horseId: horseId))
        }
    }

    @ViewBuilder
    private func area(_ title: LocalizedStringKey, _ list: [ReminderItem], _ tone: InfoTone) -> some View {
        if !list.isEmpty {
            SectionHeader(title)
            InfoCard(tone: tone) {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { DividerLine(inset: 0).padding(.vertical, 6) }
                        NavigationLink(value: ReminderRoute(id: item.id)) {
                            ReminderContent(reminder: item, today: today, showsHorse: false).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
