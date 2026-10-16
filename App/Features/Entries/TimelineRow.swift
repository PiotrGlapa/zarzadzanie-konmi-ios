import HorselyCore
import SwiftUI

extension TimelineEntryType {
    var accent: EntryAccent {
        switch self {
        case .vetVisit: .vet
        case .farrierVisit: .farrier
        case .physioVisit: .physio
        case .specialistVisit: .specialist
        case .competitionStart: .competition
        case .purchase: .purchase
        case .note: .note
        }
    }

    var titleKey: String {
        switch self {
        case .vetVisit: "timeline_type_vet_visit"
        case .farrierVisit: "timeline_type_farrier_visit"
        case .physioVisit: "timeline_type_physio_visit"
        case .specialistVisit: "timeline_type_specialist_visit"
        case .competitionStart: "timeline_type_competition_start"
        case .purchase: "timeline_type_purchase"
        case .note: "timeline_type_note"
        }
    }
}

/// Wiersz wpisu (Pulpit „Ostatnie wpisy”, oś czasu): pasek 4 pt i ikona w kolorze rodzaju, tytuł, „rodzaj · koń · skrót”, data i koszt z prawej.
struct TimelineRow: View {
    let item: TimelineItem
    var showsHorse = false

    private var subtitle: String {
        var parts = [tr(item.entryType.titleKey)]
        if showsHorse, let name = HorseRules.clean(item.horseName) { parts.append(name) }
        if let summary = HorseRules.clean(item.summary) { parts.append(summary) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        AccentRow(color: item.entryType.accent.color) {
            HStack(alignment: .top, spacing: Spacing.between) {
                HIcon(name: item.entryType.accent.icon, size: 24).foregroundStyle(item.entryType.accent.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                    Text(subtitle).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formats.date(item.date)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    if let cost = item.cost { Text(Formats.money(cost)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
                }
            }
            .padding(.vertical, Spacing.between)
        }
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(tr("dashboard_open_entry"))
    }
}
