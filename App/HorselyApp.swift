import SwiftUI

/// Punkt wejścia aplikacji. Środowisko (magazyn, ustawienia, zegar, router) tworzone raz przy starcie.
@main
struct HorselyApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
    }
}
