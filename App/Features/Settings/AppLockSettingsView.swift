import HorselyKit
import SwiftUI

/// Ustawienia → Blokada aplikacji (T132, FR-M-UST-08): „Wymagaj odblokowania” — włączenie wymaga potwierdzenia zabezpieczeniem
/// telefonu; telefon bez blokady ekranu — przełącznik nieaktywny z wyjaśnieniem.
struct AppLockSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = false
    @State private var availability: AppLockAvailability = .available
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { enabled }, set: { turn($0) })) { Text("app_lock_setting_switch") }
                    .disabled(availability != .available)
                    .accessibilityIdentifier("app-lock-switch")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.between) {
                    Text("app_lock_setting_hint")
                    if availability != .available { Text("app_lock_unavailable").foregroundStyle(HorselyColor.error) }
                    if failed { Text("app_lock_enable_failed").foregroundStyle(HorselyColor.error) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("app_lock_setting_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        enabled = environment.settings.appLockEnabled
        availability = AppLockAuthenticator().availability()
    }

    private func turn(_ on: Bool) {
        failed = false
        guard on else {
            enabled = false
            environment.settings.appLockEnabled = false
            environment.appLock.settingChanged(environment.settings)
            return
        }
        Task {
            if await AppLockAuthenticator().authenticate(reason: tr("app_lock_prompt_title")) {
                enabled = true
                environment.settings.appLockEnabled = true
                environment.appLock.settingChanged(environment.settings)
            } else {
                failed = true
            }
        }
    }
}
