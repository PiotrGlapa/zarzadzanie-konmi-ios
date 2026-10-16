import HorselyCore
import SwiftUI

/// Pulpit — część koni (T051): karta „Dodaj pierwszego konia” (tryb samodzielny, brak koni), kafle koni po 2 w rzędzie (równa wysokość,
/// treść do góry, miniatura 40 pt, imię stajenne, „bez paszportu od X mies.” z tłem ostrzegawczym od 12 mies., ikona `healing` 24 pt
/// w prawym górnym rogu kontuzjowanego); kafel otwiera kartę konia. Terminy, koszty i ostatnie wpisy dochodzą w fazie US2 (T068).
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showingForm = false
    @State private var banner: String?

    private var directory: HorseDirectory { environment.horseDirectory }

    /// Konie w stajni (aktywne i kontuzjowane), po imieniu.
    private var stableHorses: [LocalHorse] {
        HorseSearch.apply(directory.horses, query: "", filter: .inStable)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if directory.isLoaded, directory.horses.isEmpty, environment.workMode == .standalone {
                        addFirstHorseCard.padding(.top, Spacing.between)
                    }
                    if !stableHorses.isEmpty {
                        SectionHeader("dashboard_horses")
                        tiles
                    }
                    Color.clear.frame(height: Spacing.addButtonClearance)
                }
                .padding(.horizontal, Spacing.screenEdge)
            }
            .background(HorselyColor.background)
            .toolbarBackground(HorselyColor.background, for: .tabBar)
            .navigationTitle("nav_dashboard")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { id in HorseCardView(horseId: id) }
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

    private var addFirstHorseCard: some View {
        InfoCard(tone: .primary) {
            VStack(alignment: .leading, spacing: Spacing.between) {
                Text("dashboard_add_first_horse_title").font(.headline).accessibilityAddTraits(.isHeader)
                Text("dashboard_add_first_horse_hint").font(.subheadline)
                Button {
                    showingForm = true
                } label: {
                    Text("dashboard_add_first_horse_action").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.primaryFilled)
                .tint(HorselyColor.primary)
                .accessibilityIdentifier("dashboard-add-first-horse")
            }
        }
    }

    private var tiles: some View {
        let rows = stride(from: 0, to: stableHorses.count, by: 2).map { Array(stableHorses[$0..<min($0 + 2, stableHorses.count)]) }
        return Grid(horizontalSpacing: Spacing.between, verticalSpacing: Spacing.between) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { horse in tile(horse) }
                    if row.count == 1 { Color.clear }
                }
            }
        }
    }

    private func tile(_ horse: LocalHorse) -> some View {
        let today = environment.dates.today()
        let months = HorseRules.monthsWithoutPassport(of: horse, on: today)
        let warns = HorseDescription.isForgottenPassport(horse, today: today)
        return NavigationLink(value: horse.id) {
            HStack(alignment: .top, spacing: Spacing.between) {
                VStack(alignment: .leading, spacing: 4) {
                    HorseAvatar(photo: directory.thumbnail(for: horse), diameter: 40)
                    Text(horse.name).font(.body.weight(.semibold)).foregroundStyle(warns ? HorselyColor.onWarningContainer : HorselyColor.onBackground)
                    if let stable = HorseDescription.stableName(horse) {
                        Text(stable).font(.footnote).foregroundStyle(warns ? HorselyColor.onWarningContainer : HorselyColor.onSurfaceVariant)
                    }
                    if let months, horse.isFoal {
                        Text(trPlural("foal_months_without_passport", months))
                            .font(.footnote)
                            .foregroundStyle(warns ? HorselyColor.onWarningContainer : HorselyColor.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                if horse.status == .injured {
                    HIcon(name: "healing", size: 24).foregroundStyle(HorselyColor.warning)
                }
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(warns ? HorselyColor.warningContainer : HorselyColor.surfaceVariant, in: RoundedRectangle(cornerRadius: Spacing.cardRadius))
            .overlay {
                if warns { RoundedRectangle(cornerRadius: Spacing.cardRadius).strokeBorder(HorselyColor.warning, lineWidth: Spacing.cardBorder) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(HorseDescription.accessibilityName(horse))
        .accessibilityHint(tr("dashboard_open_horse", horse.name))
        .accessibilityIdentifier("horse-tile-\(horse.name)")
    }
}
