import HorselyCore
import HorselyKit
import SwiftUI
import UserNotifications

/// Ustawienia → Powiadomienia (T120, FR-M-POW-02/04, FR-M-UST): włączenie z wyjaśnieniem przed prośbą systemu o zgodę, godzina
/// podsumowania, powiadomienie w dniu terminu, ukrywanie szczegółów na ekranie blokady; po odmowie — jak włączyć zgodę.
struct NotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var enabled = false
    @State private var time = Date()
    @State private var onDueDate = false
    @State private var hideDetails = false
    @State private var denied = false
    @State private var explaining = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { enabled }, set: { turn($0) })) { Text("notif_settings_enable") }
                    .accessibilityIdentifier("notif-enable")
            } footer: {
                Text("notif_settings_enable_hint")
            }
            if denied {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.between) {
                        Text("notif_settings_denied_title").font(.headline)
                        Text("notif_settings_denied_text").font(.subheadline)
                        Button(tr("notif_settings_open_notifications")) {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                        .frame(minHeight: Spacing.minTouchTarget)
                        .accessibilityIdentifier("notif-open-settings")
                    }
                }
            }
            Section {
                DatePicker(selection: $time, displayedComponents: .hourAndMinute) { Text("notif_settings_summary_time") }
                    .onChange(of: time) { _, value in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                        environment.settings.notificationsDailyTime = String(format: "%02d:%02d", parts.hour ?? 8, parts.minute ?? 0)
                        changed()
                    }
                Toggle(isOn: $onDueDate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("notif_settings_due_day")
                        Text("notif_settings_due_day_hint").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    }
                }
                .onChange(of: onDueDate) { _, value in
                    environment.settings.notificationsOnDueDate = value
                    changed()
                }
                Toggle(isOn: $hideDetails) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("notif_settings_hide")
                        Text("notif_settings_hide_hint").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    }
                }
                .onChange(of: hideDetails) { _, value in
                    environment.settings.notificationsHideDetails = value
                    changed()
                }
            }
            .disabled(!enabled)
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("notif_settings_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            // Powrót z ustawień systemu: zgoda mogła się zmienić.
            if phase == .active { Task { await refreshAuthorization() } }
        }
        .alert(tr("notif_permission_title"), isPresented: $explaining) {
            Button(tr("common_next")) { Task { await requestPermission() } }
            Button(tr("notif_settings_not_now"), role: .cancel) {}
        } message: {
            Text("notif_permission_text")
        }
    }

    private func load() async {
        let settings = environment.settings
        enabled = settings.notificationsEnabled
        onDueDate = settings.notificationsOnDueDate
        hideDetails = settings.notificationsHideDetails
        let plan = NotificationPlanSettings(time: settings.notificationsDailyTime, onDueDate: false)
        time = Calendar.current.date(from: DateComponents(hour: plan.hour, minute: plan.minute)) ?? Date()
        await refreshAuthorization()
        loaded = true
    }

    private func refreshAuthorization() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        denied = status == .denied && enabled
    }

    /// Włączenie: zgoda już jest — od razu; nieznana — najpierw wyjaśnienie, potem prośba systemu; odmówiona — instrukcja.
    private func turn(_ on: Bool) {
        guard on else {
            enabled = false
            denied = false
            environment.settings.notificationsEnabled = false
            changed()
            return
        }
        Task {
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .notDetermined:
                explaining = true
            case .denied:
                save(enabled: true)
                denied = true
            default:
                save(enabled: true)
            }
        }
    }

    private func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        save(enabled: true)
        denied = !granted
    }

    private func save(enabled value: Bool) {
        enabled = value
        environment.settings.notificationsEnabled = value
        changed()
    }

    private func changed() {
        guard loaded else { return }
        Task { await environment.rescheduleNotificationsNow() }
    }
}
