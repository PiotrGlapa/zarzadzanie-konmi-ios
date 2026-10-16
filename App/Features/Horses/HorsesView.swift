import HorselyCore
import SwiftUI

/// Karta „Konie” (FR-M-KON-01): wyszukiwanie po imieniu, imieniu stajennym i paszporcie (bez wielkości liter i polskich znaków),
/// chipy Aktywny · Kontuzjowany · Pokaż wszystkie · Tylko źrebięta, sortowanie po imieniu, „Dodaj konia” na końcu listy.
struct HorsesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var query = ""
    @State private var filter: HorseListFilter = .inStable
    @State private var onlyFoals = false
    @State private var showingForm = false
    @State private var banner: String?

    private var directory: HorseDirectory { environment.horseDirectory }

    private var visible: [LocalHorse] {
        HorseSearch.apply(directory.horses, query: query, filter: filter, onlyFoals: onlyFoals)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    chips
                    if !directory.isLoaded {
                        ProgressView().padding(.top, 48)
                    } else if visible.isEmpty {
                        emptyState
                    } else {
                        DividedList(visible) { horse in
                            NavigationLink(value: horse.id) {
                                HorseRow(horse: horse, photo: directory.thumbnail(for: horse), today: environment.dates.today())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("horse-row-\(horse.name)")
                        }
                    }
                    addButton
                    Color.clear.frame(height: Spacing.addButtonClearance)
                }
            }
            .background(HorselyColor.background)
            .toolbarBackground(HorselyColor.background, for: .tabBar)
            .navigationTitle("horses_title")
            .connectionChrome()
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: Text("horses_search"))
            .navigationDestination(for: String.self) { id in
                HorseCardView(horseId: id)
            }
            .sheet(isPresented: $showingForm) {
                HorseFormView(horse: nil) { banner = tr("horse_form_saved") }
            }
            .overlay(alignment: .bottom) {
                if let banner {
                    SaveBanner(message: banner, undo: nil) { self.banner = nil }.padding(.bottom, Spacing.between)
                }
            }
            .overlay(alignment: .bottomTrailing) { AddEntryButton() }
            .animation(.default, value: banner)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.between) {
                chip("horse_status_active", selected: filter == .active) { filter = filter == .active ? .inStable : .active }
                chip("horse_status_injured", icon: "healing", selected: filter == .injured) { filter = filter == .injured ? .inStable : .injured }
                chip("horses_show_all", selected: filter == .all) { filter = filter == .all ? .inStable : .all }
                chip("horses_only_foals", selected: onlyFoals) { onlyFoals.toggle() }
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.vertical, Spacing.between)
        }
    }

    private func chip(_ title: LocalizedStringKey, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { HIcon(name: icon, size: 18) }
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: Spacing.minTouchTarget - 8)
            .foregroundStyle(selected ? HorselyColor.onSecondaryContainer : HorselyColor.onSurfaceVariant)
            .background(selected ? HorselyColor.secondaryContainer : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : HorselyColor.outlineVariant, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Spacing.between) {
            if query.isEmpty {
                Text("horses_empty_title").font(.headline)
                Text("horses_empty_hint").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
            } else {
                Text(tr("horses_empty_search", query)).font(.headline)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.screenEdge)
        .padding(.top, 24)
    }

    private var addButton: some View {
        VStack(spacing: 0) {
            if !visible.isEmpty { DividerLine() }
            Button {
                showingForm = true
            } label: {
                HStack(spacing: Spacing.between + 4) {
                    AccentIcon(icon: "add", color: HorselyColor.primary)
                    Text("horses_add").font(.body.weight(.semibold)).foregroundStyle(HorselyColor.primary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.vertical, Spacing.between)
                .frame(minHeight: Spacing.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("horses-add")
        }
    }
}
