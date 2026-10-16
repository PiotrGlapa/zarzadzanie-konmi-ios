import SwiftUI
import UIKit

/// Powłoka aplikacji (5.2): pasek pięciu kart Pulpit · Konie · Terminy · Treningi · Więcej z ikonami w kolorach działów, plakietka
/// liczby niewysłanych operacji na „Więcej”, przycisk „+” nad paskiem (Pulpit, Konie, Terminy) i wybór motywu.
/// Treść kart dochodzi w kolejnych fazach; na razie każda karta pokazuje swój tytuł.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

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
                    tab(.trainings, accent: .trainings, title: "nav_trainings")
                    MoreView()
                        .tabItem { TabLabel(title: "nav_more", icon: moreIcon) }
                        .badge(environment.queueCount)
                        .tag(AppTab.more)
                }
                .tint(HorselyColor.primary)
            }
        }
        .tint(HorselyColor.primary)
        .preferredColorScheme(environment.theme.colorScheme)
        .task { await environment.horseDirectory.run() }
        .task { await environment.observeChanges() }
        .task(id: environment.workMode) {
            await environment.prepareStore()
            await environment.startOnline()
        }
        .task { await environment.observeQueue() }
        .onChange(of: environment.connection.problem) { old, new in
            withAnimation { environment.indicator.problemChanged(from: old, to: new) }
        }
        .fullScreenCover(isPresented: $router.showPairing) {
            PairingFlowView(purpose: .repair) { environment.router.showPairing = false }
                .environment(environment)
        }
        .onChange(of: scenePhase) { _, phase in
            guard environment.workMode == .online else { return }
            switch phase {
            case .active:
                environment.connection.enterForeground()
                Task { await environment.refresh(force: false) }
            case .background:
                environment.connection.enterBackground()
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
