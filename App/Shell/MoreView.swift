import HorselyCore
import SwiftUI

/// Pozycja menu „Więcej”.
struct MoreItem: Identifiable, Equatable {
    enum Destination: String, Hashable {
        case competitions, purchases, contacts, reports, conflicts, queue, trash, dictionaries, backup, settings, about
    }

    var id: Destination { destination }
    let destination: Destination
    /// Klucz tytułu ze `strings.xml` (nazwy `nav_*`).
    let titleKey: String
    let icon: String
    /// Kolor ikony: dział z palety albo kolor tekstu drugorzędnego (Kolejka, Słowniki, Ustawienia, O aplikacji).
    let accent: SectionAccent?
    /// Licznik zamiast strzałki (kolejka, konflikty); `nil` — strzałka.
    var count: Int?

    static func == (lhs: MoreItem, rhs: MoreItem) -> Bool {
        lhs.destination == rhs.destination && lhs.count == rhs.count
    }
}

/// Zawartość menu „Więcej” zależna od trybu pracy (5.2, contracts/android/ui-screens.md §3): Zawody · Zakupy · Kontakty · Raporty,
/// separator pełnej szerokości, potem pozycje telefonu — online: Konflikty (tylko gdy są) · Kolejka wysyłki · Ustawienia · O aplikacji;
/// samodzielny: Kosz · Słowniki · Kopia zapasowa · Ustawienia · O aplikacji. Tryb nieustawiony: tylko Ustawienia i O aplikacji.
enum MoreMenu {
    static func sections(mode: WorkMode, queueCount: Int, conflictCount: Int) -> (sections: [MoreItem], phone: [MoreItem]) {
        let sections = [
            MoreItem(destination: .competitions, titleKey: "nav_competitions", icon: SectionAccent.competitions.icon, accent: .competitions),
            MoreItem(destination: .purchases, titleKey: "nav_purchases", icon: SectionAccent.purchases.icon, accent: .purchases),
            MoreItem(destination: .contacts, titleKey: "nav_contacts", icon: SectionAccent.contacts.icon, accent: .contacts),
            MoreItem(destination: .reports, titleKey: "nav_reports", icon: SectionAccent.reports.icon, accent: .reports),
        ]
        let settings = MoreItem(destination: .settings, titleKey: "nav_settings", icon: "settings", accent: nil)
        let about = MoreItem(destination: .about, titleKey: "nav_about", icon: "info", accent: nil)
        var phone: [MoreItem] = []
        switch mode {
        case .online:
            if conflictCount > 0 {
                phone.append(MoreItem(destination: .conflicts, titleKey: "conflicts_title", icon: SectionAccent.conflicts.icon, accent: .conflicts, count: conflictCount))
            }
            phone.append(MoreItem(destination: .queue, titleKey: "nav_queue", icon: "cloud_sync", accent: nil, count: queueCount))
        case .standalone:
            phone.append(MoreItem(destination: .trash, titleKey: "nav_trash", icon: SectionAccent.trash.icon, accent: .trash))
            phone.append(MoreItem(destination: .dictionaries, titleKey: "nav_dictionaries", icon: "menu_book", accent: nil))
            phone.append(MoreItem(destination: .backup, titleKey: "nav_backup", icon: SectionAccent.backup.icon, accent: .backup))
        case .unset:
            break
        }
        phone += [settings, about]
        return (sections, phone)
    }
}

struct MoreView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let menu = MoreMenu.sections(mode: environment.workMode, queueCount: environment.queueCount, conflictCount: environment.conflictCount)
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    DividedList(menu.sections) { MoreRow(item: $0) }
                    // Separator pełnej szerokości między działami a pozycjami telefonu.
                    Rectangle()
                        .fill(HorselyColor.outlineVariant)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                    DividedList(menu.phone) { MoreRow(item: $0) }
                }
            }
            .background(HorselyColor.background)
            .toolbarBackground(HorselyColor.background, for: .tabBar)
            .navigationTitle("nav_more")
            .navigationBarTitleDisplayMode(.large)
            .connectionChrome()
            .navigationDestination(for: MoreItem.Destination.self) { destination in
                switch destination {
                case .queue: QueueView()
                case .conflicts: ConflictsView()
                case .settings: SettingsHubView()
                case .purchases: PurchasesView()
                case .competitions: CompetitionsView()
                case .contacts: ContactsView()
                case .reports: ReportsListView()
                case .trash: TrashView()
                case .dictionaries: DictionariesView()
                case .backup: BackupView()
                case .about: AboutView()
                default:
                    MorePlaceholder(titleKey: menu.sections.first { $0.destination == destination }?.titleKey
                        ?? menu.phone.first { $0.destination == destination }?.titleKey ?? "nav_more")
                }
            }
        }
    }
}

/// Wiersz: kolorowa ikona działu w kółku, nazwa, licznik albo strzałka. Cały wiersz ma cel dotyku ≥ 44 pt.
struct MoreRow: View {
    let item: MoreItem

    var body: some View {
        NavigationLink(value: item.destination) {
            HStack(spacing: Spacing.between + 4) {
                if let accent = item.accent {
                    AccentIcon(icon: item.icon, color: accent.color)
                } else {
                    AccentIcon(icon: item.icon, color: HorselyColor.onSurfaceVariant)
                }
                Text(LocalizedStringKey(item.titleKey))
                    .font(.body)
                    .foregroundStyle(HorselyColor.onBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count = item.count {
                    Text("\(count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.accent == .conflicts ? HorselyColor.warning : HorselyColor.onSurfaceVariant)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HorselyColor.onSurfaceVariant)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.vertical, Spacing.between)
            .frame(minHeight: Spacing.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("more-\(item.destination.rawValue)")
    }
}

/// Tymczasowy ekran pozycji menu (treść w kolejnych fazach).
private struct MorePlaceholder: View {
    let titleKey: String

    var body: some View {
        HorselyColor.background
            .navigationTitle(LocalizedStringKey(titleKey))
            .navigationBarTitleDisplayMode(.inline)
    }
}
