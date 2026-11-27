import HorselyCore
import HorselyKit
import SwiftUI
import UIKit

/// Powłoka aplikacji (5.2): pasek pięciu kart Pulpit · Konie · Terminy · Treningi · Więcej z ikonami w kolorach działów, plakietka
/// liczby niewysłanych operacji na „Więcej”, przycisk „+” nad paskiem (Pulpit, Konie, Terminy) i wybór motywu.
/// Treść kart dochodzi w kolejnych fazach; na razie każda karta pokazuje swój tytuł.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    /// Niezakończona jazda do pytania „Zapisz / Odrzuć” przy starcie aplikacji (NAG-09, Task 17).
    @State private var rideRecovery: UnfinishedRide?

    var body: some View {
        @Bindable var router = environment.router
        Group {
            if environment.workMode == .unset {
                // Pierwsze uruchomienie: najpierw wybór trybu pracy (FR-TRB-02), potem karty.
                ModeChoiceView()
            } else {
                TabView(selection: $router.selectedTab) {
                    DashboardView()
                        .tabItem { TabLabel(title: "nav_dashboard", icon: .section(.dashboard)) }
                        .tag(AppTab.dashboard)
                    HorsesView()
                        .tabItem { TabLabel(title: "nav_horses", icon: .section(.horses)) }
                        .tag(AppTab.horses)
                    RemindersView()
                        .tabItem { TabLabel(title: "nav_reminders", icon: .section(.reminders)) }
                        .tag(AppTab.reminders)
                    TrainingsSectionView()
                        .tabItem { TabLabel(title: "nav_trainings", icon: .section(.trainings)) }
                        .tag(AppTab.trainings)
                    MoreView()
                        .tabItem { TabLabel(title: "nav_more", icon: moreIcon) }
                        .badge(environment.queueCount)
                        .tag(AppTab.more)
                }
                .tint(HorselyColor.primary)
                // Odzyskiwanie jazdy przy starcie (NAG-09): nie nad otwartym ekranem nagrywania (ten pyta sam).
                .rideRecoveryAlert(
                    Binding(get: { environment.router.ride == nil ? rideRecovery : nil }, set: { rideRecovery = $0 }),
                    onSave: { ride in Task { handleRecovery(await environment.rideRecovery.saveReporting(ride)) } },
                    onDiscard: { ride in Task { handleRecovery(await environment.rideRecovery.discardReporting(sessionId: ride.sessionId)) } }
                )
            }
        }
        .tint(HorselyColor.primary)
        // Blokada aplikacji (FR-TRB-09): osobne okno nad wszystkim (także nad otwartymi arkuszami) — bez danych na ekranie i w przełączniku.
        .background(LockWindowHost(environment: environment, locked: environment.appLock.locked, covered: environment.appLock.covered))
        .alert(tr("app_lock_notice_title"), isPresented: Binding(get: { environment.appLock.notice }, set: { environment.appLock.notice = $0 })) {
            Button(tr("common_ok")) {}
        } message: {
            Text("app_lock_notice_text")
        }
        .preferredColorScheme(environment.theme.colorScheme)
        .task { await environment.horseDirectory.run() }
        .task { await environment.observeChanges() }
        .task(id: environment.workMode) {
            await environment.prepareStore()
            await environment.cleanUpStalePush()
            await environment.startOnline()
            await environment.processSharedInbox()
            // Filmy, których przygotowanie przerwało zamknięcie aplikacji (decyzja A10).
            await environment.prepareVideos()
        }
        .task { await environment.observeQueue() }
        .task { await environment.observeActiveRide() }
        .task(id: environment.workMode) {
            // Po decyzji startowej kontrolera nagrywania (`RideRecovery` czeka na `prepareRelaunch`): przerwana albo zakończona
            // i niezapisana jazda — pytanie; jazda wznowiona w tle — bez pytania (pasek NAG-01).
            guard environment.workMode != .unset else { return }
            rideRecovery = await environment.rideRecovery.pending()
            openFinishedRide()
        }
        .task { await environment.observePushState() }
        .task { await openPushForTests() }
        .onChange(of: environment.connection.problem) { old, new in
            withAnimation { environment.indicator.problemChanged(from: old, to: new) }
        }
        .fullScreenCover(isPresented: Binding(get: { router.ride != nil }, set: { if !$0 { router.ride = nil } })) {
            if let route = router.ride { RideFlowView(environment: environment, route: route) }
        }
        .onChange(of: router.ride) { _, route in
            // Ekran nagrywania sam pyta o niezakończoną jazdę — pytanie z startu aplikacji nie wraca po jego zamknięciu.
            if route != nil { rideRecovery = nil }
        }
        .fullScreenCover(isPresented: $router.showPairing) {
            PairingFlowView(purpose: .repair) { environment.router.showPairing = false }
                .environment(environment)
        }
        .onChange(of: scenePhase) { _, phase in
            environment.appLock.sceneChanged(phase, settings: environment.settings)
            if phase == .active {
                openFinishedRide()
                Task { await environment.processSharedInbox() }
                // Powrót na pierwszy plan ponawia miniatury zdjęć koni także wtedy, gdy odświeżenie nie jest jeszcze należne (FR-008).
                Task { await environment.horseDirectory.retryMissingThumbnails() }
            }
            guard environment.workMode == .online else { return }
            switch phase {
            case .active:
                environment.connection.enterForeground()
                Task { await environment.refresh(force: false) }
                Task { await environment.pushEnteredForeground() }
            case .background:
                environment.connection.enterBackground()
                Task { await environment.pushEnteredBackground() }
            default:
                break
            }
        }
        .onChange(of: environment.router.pendingDestination) { _, destination in
            if case let .newEntry(kind) = destination {
                environment.router.pendingDestination = nil
                if environment.workMode != .unset { environment.router.entryRequest = EntryRequest(kind: FormKind(linkName: kind)) }
            }
        }
        .sheet(item: $router.entryRequest) { request in
            NewEntryView(request: request) { saved, edited in
                Task {
                    let text = await environment.messageAfterSave(saved, edited: edited)
                    environment.router.banner = BannerMessage(text: text) {
                        Task { try? await environment.entries.undo(saved.undo) }
                    }
                }
            }
            .environment(environment)
        }
        .overlay(alignment: .bottom) {
            if let banner = environment.router.banner {
                SaveBanner(message: banner.text, undo: banner.undo) { environment.router.banner = nil }
                    .id(banner.id)
                    .padding(.bottom, 56)
            }
        }
        .animation(.default, value: environment.router.banner)
        .onOpenURL { url in
            environment.router.handle(url: url, mode: environment.workMode)
        }
        .onChange(of: QuickActions.shared.pending, initial: true) { _, type in
            guard let type else { return }
            QuickActions.shared.pending = nil
            environment.router.handle(shortcut: type, mode: environment.workMode)
        }
    }

    /// Wynik „Zapisz / Odrzuć” z pytania przy starcie: zakończenie → ekran zakończenia; błąd → komunikat u dołu ekranu i ponowne pytanie
    /// o stan sprawdzony po błędzie (wpis w dzienniku robi `RideRecovery`).
    private func handleRecovery(_ outcome: RideActionOutcome) {
        switch outcome {
        case let .finished(id):
            environment.router.openRideFinish(sessionId: id)
        case .discarded:
            break
        case let .failed(key, pending):
            environment.router.banner = BannerMessage(text: tr(key))
            rideRecovery = pending
        }
    }

    /// „Zakończ” z Live Activity zakończyło jazdę i otworzyło aplikację (`openAppWhenRun`): ekran zakończenia tej jazdy (hak Task 21).
    /// Id odbiera się raz — z wejścia na pierwszy plan albo z obserwatora akcji (`HorselyApp`), zależnie od tego, co przyjdzie pierwsze.
    private func openFinishedRide() {
        guard environment.workMode != .unset, let id = RideActivityActions.shared.takeFinishedSessionId() else { return }
        environment.router.openRideFinish(sessionId: id)
    }

    /// Testy UI (`-UITestOpenPush <reminder|summary|backup|test>`, tylko Debug): symuluje dotknięcie wiadomości z serwera.
    private func openPushForTests() async {
        #if DEBUG
        guard let type = environment.launchOptions.openPush else { return }
        try? await Task.sleep(for: .seconds(1))
        if let message = PushMessage(userInfo: ["type": type, "reminderId": "brak-takiego-terminu"]) { environment.open(serverMessage: message) }
        #endif
    }

    private var moreIcon: TabIconSource { .named("more_horiz", ColorPair(light: Palette.onSurfaceVariant.light, dark: Palette.onSurfaceVariant.dark)) }

    private func tab(_ value: AppTab, accent: SectionAccent, title: LocalizedStringKey) -> some View {
        NavigationStack {
            TabPlaceholder(title: title)
        }
        .tabItem { TabLabel(title: title, icon: .section(accent)) }
        .tag(value)
    }
}

/// Tymczasowa treść karty (do czasu faz z ekranami): tytuł w pasku nawigacji.
private struct TabPlaceholder: View {
    let title: LocalizedStringKey

    var body: some View {
        ScrollView { Color.clear.frame(height: 1) }
            .background(HorselyColor.background)
            .toolbarBackground(HorselyColor.background, for: .tabBar)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }
}

/// Źródło ikony karty: dział albo ikona o własnym kolorze.
enum TabIconSource {
    case section(SectionAccent)
    case named(String, ColorPair)

    var name: String {
        switch self {
        case let .section(accent): accent.icon
        case let .named(name, _): name
        }
    }

    var colors: ColorPair {
        switch self {
        case let .section(accent): accent.colors
        case let .named(_, colors): colors
        }
    }
}

/// Etykieta karty z ikoną w kolorze działu. Pasek kart barwi obrazy szablonowe jednym kolorem, więc ikona jest wcześniej
/// zabarwiona (`alwaysOriginal`) kolorem odpowiednim dla bieżącego motywu.
struct TabLabel: View {
    let title: LocalizedStringKey
    let icon: TabIconSource
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let image = UIImage(named: icon.name)?.withTintColor(UIColor(hex: icon.colors.hex(dark: scheme == .dark)), renderingMode: .alwaysOriginal) {
                Image(uiImage: image)
            } else {
                Image(systemName: "circle")
            }
        }
    }
}

/// Pływający przycisk „+” (Dodaj wpis) w prawym dolnym rogu nad paskiem kart. Wybór rodzaju wpisu i konia dochodzi w fazie 4.
struct AddEntryButton: View {
    @Environment(AppEnvironment.self) private var environment
    /// Prośba otwierana po dotknięciu; domyślnie użytkownik wybiera rodzaj i konia.
    var request = EntryRequest()

    var body: some View {
        Button {
            if environment.workMode != .unset { environment.router.entryRequest = request.renewed() }
        } label: {
            HIcon(name: "add", size: 28)
                .foregroundStyle(HorselyColor.onPrimary)
                .frame(width: 56, height: 56)
                .background(HorselyColor.primary, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .padding(.trailing, Spacing.screenEdge)
        .padding(.bottom, Spacing.screenEdge)
        .accessibilityLabel(tr("nav_add"))
        .accessibilityIdentifier("add-entry-button")
    }
}
