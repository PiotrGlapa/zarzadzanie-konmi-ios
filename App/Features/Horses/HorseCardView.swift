import HorselyCore
import HorselyKit
import SwiftUI

/// Karta konia (FR-M-KON-02): nagłówek (miniatura 72 pt, imię, imię stajenne, plakietka statusu, paszport, UELN, chip), przewijane
/// zakładki Oś czasu · Terminy · Paszport · Treningi · Zawody · Zakupy · Załączniki (treść zakładek dochodzi w fazach US2/US4/US6),
/// „Edytuj”, zdjęcie z arkuszem akcji. Nieistniejący koń — „Nie znaleziono konia” z przyciskiem „Wróć”.
struct HorseCardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let horseId: String

    init(horseId: String, initialTab: CardTab = .timeline) {
        self.horseId = horseId
        self._tab = State(initialValue: initialTab)
    }

    enum CardTab: CaseIterable, Hashable {
        case timeline, reminders, passport, trainings, competitions, purchases, attachments

        var titleKey: String {
            switch self {
            case .timeline: "horse_tab_timeline"
            case .reminders: "horse_tab_reminders"
            case .passport: "horse_tab_passport"
            case .trainings: "horse_tab_trainings"
            case .competitions: "horse_tab_competitions"
            case .purchases: "horse_tab_purchases"
            case .attachments: "horse_tab_attachments"
            }
        }
    }

    @State private var tab: CardTab
    @State private var editing = false
    @State private var showingPhotoSheet = false
    @State private var banner: String?
    @State private var overview: HorseOverview?

    private var directory: HorseDirectory { environment.horseDirectory }

    var body: some View {
        Group {
            if let horse = directory.horse(id: horseId) {
                content(horse)
            } else if directory.isLoaded {
                notFound
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(HorselyColor.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ horse: LocalHorse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.between) {
                header(horse)
                overviewSections
                tabStrip
                tabContent(horse)
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.bottom, Spacing.addButtonClearance)
        }
        .navigationTitle(horse.name)
        .navigationDestination(for: EntryRoute.self) { route in EntryDetailView(route: route) }
        .navigationDestination(for: ReminderRoute.self) { route in ReminderDetailView(reminderId: route.id) }
        .task(id: environment.dataRevision) { overview = try? await environment.entries.overview(horseId: horseId) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(tr("common_edit")) { editing = true }.accessibilityIdentifier("horse-edit")
            }
        }
        .sheet(isPresented: $editing) {
            HorseFormView(horse: horse) { banner = tr("horse_form_saved") }
        }
        .sheet(isPresented: $showingPhotoSheet) {
            HorsePhotoSheet(horse: horse, hasPhoto: horse.photoAttachmentId != nil, context: .card) { result in
                switch result {
                case let .picked(image):
                    Task {
                        do {
                            try await environment.horses.setPhoto(horseId: horse.id, image: image)
                            banner = tr("photo_saved")
                        } catch {
                            banner = tr("photo_failed")
                        }
                    }
                case .removed:
                    Task {
                        try? await environment.horses.clearPhoto(horseId: horse.id)
                        banner = tr("photo_removed")
                    }
                case .chosenFromAttachments:
                    banner = tr("photo_saved")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let banner {
                SaveBanner(message: banner, undo: nil) { self.banner = nil }.padding(.bottom, Spacing.between)
            }
        }
        .animation(.default, value: banner)
    }

    // MARK: Nagłówek

    private func header(_ horse: LocalHorse) -> some View {
        HStack(alignment: .top, spacing: Spacing.between + 4) {
            Button { showingPhotoSheet = true } label: {
                HorseAvatar(photo: directory.thumbnail(for: horse), diameter: 72)
                    .frame(minWidth: Spacing.minTouchTarget, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("photo_sheet_title"))
            .accessibilityIdentifier("horse-card-photo")

            VStack(alignment: .leading, spacing: 4) {
                Text(horse.name).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if let stable = HorseDescription.stableName(horse) {
                    Text(stable).font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                statusBadge(horse)
                Text(HorseDescription.passportLine(horse, today: environment.dates.today())).font(.subheadline)
                if let ueln = HorseRules.clean(horse.ueln) {
                    Text(tr("horse_ueln", ueln)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                if let chip = HorseRules.clean(horse.microchipNumber) {
                    Text(tr("horse_microchip", chip)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                if let age = HorseRules.age(of: horse, on: environment.dates.today()) {
                    Text(trPlural("horse_age_years", age)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, Spacing.between)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func statusBadge(_ horse: LocalHorse) -> some View {
        switch horse.status {
        case .active:
            EmptyView()
        case .injured:
            InjuredBadge()
        default:
            Text(LocalizedStringKey(horse.status.labelKey))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(HorselyColor.onSurfaceVariant)
                .background(HorselyColor.surfaceVariant, in: Capsule())
        }
    }

    // MARK: Zakładki

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.between) {
                ForEach(CardTab.allCases, id: \.self) { item in
                    let selected = tab == item
                    Button { tab = item } label: {
                        Text(LocalizedStringKey(item.titleKey))
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .frame(minHeight: Spacing.minTouchTarget - 4)
                            .foregroundStyle(selected ? HorselyColor.onSecondaryContainer : HorselyColor.onSurfaceVariant)
                            .background(selected ? HorselyColor.secondaryContainer : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("horse-tab-\(item.titleKey)")
                }
            }
        }
    }

    // MARK: Podsumowanie

    @ViewBuilder
    private var overviewSections: some View {
        if let overview {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("horse_next_reminders")
                if overview.nextReminders.isEmpty {
                    Text("horse_no_reminders").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant).padding(.vertical, 4)
                } else {
                    VStack(spacing: Spacing.between) {
                        ForEach(overview.nextReminders) { item in
                            InfoCard(tone: item.isOverdue ? .warning : .neutral) {
                                NavigationLink(value: ReminderRoute(id: item.id)) {
                                    ReminderContent(reminder: item, today: environment.dates.today(), showsHorse: false).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                SectionHeader(LocalizedStringKey(tr("horse_costs_year", overview.year)))
                InfoCard {
                    VStack(alignment: .leading, spacing: 4) {
                        if overview.yearCosts.isEmpty {
                            Text("horse_costs_none").font(.subheadline)
                        } else {
                            ForEach(overview.yearCosts) { cost in
                                HStack {
                                    Text(cost.category).font(.subheadline)
                                    Spacer()
                                    Text(Formats.money(cost.amount)).font(.subheadline)
                                }
                            }
                            DividerLine(inset: 0)
                            Text(tr("horse_costs_total", Formats.money(overview.yearTotal))).font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .accessibilityIdentifier("horse-costs-year")
                SectionHeader("horse_balance_title")
                InfoCard {
                    VStack(spacing: 4) {
                        balanceRow("horse_balance_purchase", overview.balance.purchase)
                        balanceRow("horse_balance_costs", overview.balance.costs)
                        balanceRow("horse_balance_prizes", overview.balance.prizes)
                        balanceRow("horse_balance_sale", overview.balance.sale)
                        DividerLine(inset: 0)
                        balanceRow("horse_balance_result", overview.balance.result, bold: true)
                    }
                }
                .accessibilityIdentifier("horse-balance")
            }
        }
    }

    private func balanceRow(_ title: LocalizedStringKey, _ amount: Money?, bold: Bool = false) -> some View {
        HStack {
            Text(title).font(bold ? .subheadline.weight(.semibold) : .subheadline)
            Spacer()
            Text(amount.map { Formats.money($0) } ?? Formats.dash).font(bold ? .subheadline.weight(.semibold) : .subheadline)
        }
    }

    /// Treść zakładek: oś czasu, terminy, paszport, treningi, zawody, zakupy (US2); załączniki dochodzą w US6.
    @ViewBuilder
    private func tabContent(_ horse: LocalHorse) -> some View {
        switch tab {
        case .timeline: TimelineTab(horseId: horse.id)
        case .reminders: RemindersTab(horseId: horse.id)
        case .passport: PassportTab(horse: horse)
        case .trainings: TrainingsTab(horseId: horse.id)
        case .competitions: CompetitionsTab(horseId: horse.id)
        case .purchases: PurchasesTab(horseId: horse.id)
        case .attachments:
            Text(LocalizedStringKey(tab.titleKey))
                .font(.headline)
                .foregroundStyle(HorselyColor.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        }
    }

    private var notFound: some View {
        VStack(spacing: Spacing.beforeSection) {
            Text("horse_not_found").multilineTextAlignment(.center)
            Button(tr("horse_not_found_back")) { dismiss() }
                .buttonStyle(.primaryFilled)
                .tint(HorselyColor.primary)
                .frame(minHeight: Spacing.minTouchTarget)
        }
        .padding(Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
