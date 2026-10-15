import SwiftUI

/// Szkielet aplikacji (T004): pasek pięciu kart bez treści. Powłoka (`RootView`, tryby, motyw) dochodzi w fazie 2 (T033–T036).
@main
struct HorselyApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                placeholderTab(title: "nav_dashboard", icon: "home")
                placeholderTab(title: "nav_horses", icon: "horse_head")
                placeholderTab(title: "nav_reminders", icon: "event")
                placeholderTab(title: "nav_trainings", icon: "directions_run")
                placeholderTab(title: "nav_more", icon: "more_horiz")
            }
        }
    }

    private func placeholderTab(title: LocalizedStringKey, icon: String) -> some View {
        NavigationStack {
            Color.clear
                .navigationTitle(title)
        }
        .tabItem {
            Label {
                Text(title)
            } icon: {
                Image(icon)
            }
        }
    }
}
