import SwiftUI
import UIKit

/// Powłoka aplikacji (5.2): pasek pięciu kart Pulpit · Konie · Terminy · Treningi · Więcej z ikonami w kolorach działów, plakietka
/// liczby niewysłanych operacji na „Więcej”, przycisk „+” nad paskiem (Pulpit, Konie, Terminy) i wybór motywu.
/// Treść kart dochodzi w kolejnych fazach; na razie każda karta pokazuje swój tytuł.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var router = environment.router
        TabView(selection: $router.selectedTab) {
            tab(.dashboard, accent: .dashboard, title: "nav_dashboard", showsAdd: true)
            tab(.horses, accent: .horses, title: "nav_horses", showsAdd: true)
            tab(.reminders, accent: .reminders, title: "nav_reminders", showsAdd: true)
            tab(.trainings, accent: .trainings, title: "nav_trainings", showsAdd: false)
            MoreView()
                .tabItem { TabLabel(title: "nav_more", icon: moreIcon) }
                .badge(environment.queueCount)
                .tag(AppTab.more)
        }
        .tint(HorselyColor.primary)
        .preferredColorScheme(environment.theme.colorScheme)
        .onOpenURL { url in
            environment.router.handle(url: url, mode: environment.workMode)
        }
    }

    private var moreIcon: TabIconSource { .named("more_horiz", ColorPair(light: Palette.onSurfaceVariant.light, dark: Palette.onSurfaceVariant.dark)) }

    private func tab(_ value: AppTab, accent: SectionAccent, title: LocalizedStringKey, showsAdd: Bool) -> some View {
        NavigationStack {
            TabPlaceholder(title: title)
                .overlay(alignment: .bottomTrailing) {
                    if showsAdd { AddEntryButton() }
                }
        }
        .tabItem { TabLabel(title: title, icon: .section(accent)) }
        .tag(value)
    }
}

/// Tymczasowa treść karty (do czasu faz z ekranami): tytuł w pasku nawigacji.
private struct TabPlaceholder: View {
    let title: LocalizedStringKey

    var body: some View {
        HorselyColor.background
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

    var body: some View {
        Button {
            environment.router.pendingDestination = .newEntry(kind: "")
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
