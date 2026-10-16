import HorselyKit
import SwiftUI

/// Ustawienia → Wygląd (T131, FR-M-UST-04): motyw systemowy / jasny / ciemny, zmiana od razu.
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = environment
        Form {
            Section {
                Picker(selection: $environment.theme) {
                    Text("appearance_theme_system").tag(ThemeSetting.system)
                    Text("appearance_theme_light").tag(ThemeSetting.light)
                    Text("appearance_theme_dark").tag(ThemeSetting.dark)
                } label: {
                    Text("appearance_settings_theme")
                }
                .pickerStyle(.inline)
                .accessibilityIdentifier("appearance-theme")
            } footer: {
                Text("appearance_settings_hint")
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("appearance_settings_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
