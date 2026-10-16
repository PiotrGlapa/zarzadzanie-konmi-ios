import HorselyCore
import HorselyKit
import SwiftUI

/// Oś czasu konia (FR-M-KON-02): chipy filtra rodzaju („Wszystkie rodzaje” + 7 rodzajów), wiersze z paskiem koloru rodzaju,
/// „Pokaż starsze” dokłada kolejne wpisy.
struct TimelineTab: View {
    @Environment(AppEnvironment.self) private var environment
    let horseId: String
    @State private var type: TimelineEntryType?
    @State private var limit = TimelineTab.pageSize
    @State private var page: Page<TimelineItem>?

    static let pageSize = 20

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.between) {
                    FilterChip(title: "horse_timeline_filter_all", selected: type == nil, action: { select(nil) }, identifier: "timeline-filter-all")
                    ForEach(TimelineEntryType.allCases, id: \.self) { entry in
                        FilterChip(title: LocalizedStringKey(entry.titleKey), selected: type == entry, action: { select(entry) }, identifier: "timeline-filter-\(entry.rawValue)")
                    }
                }
            }
            if let page {
                if page.items.isEmpty {
                    TabEmptyText(key: "horse_timeline_empty")
                } else {
                    DividedList(page.items) { item in
                        NavigationLink(value: EntryRoute(recordType: item.entryType.recordType, id: item.id)) {
                            TimelineRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                    if page.totalCount > page.items.count {
                        Button(tr("horse_timeline_more")) { limit += Self.pageSize }
                            .frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                            .accessibilityIdentifier("timeline-more")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
            }
        }
        .task(id: LoadKey(type: type, limit: limit, revision: environment.dataRevision)) { await load() }
    }

    private struct LoadKey: Hashable {
        let type: TimelineEntryType?
        let limit: Int
        let revision: Int64
    }

    private func select(_ entry: TimelineEntryType?) {
        type = entry
        limit = Self.pageSize
    }

    private func load() async {
        let filter = TimelineFilter(horseId: horseId, types: type.map { [$0] } ?? [], page: 1, pageSize: limit)
        page = try? await environment.entries.timeline(filter)
    }
}
