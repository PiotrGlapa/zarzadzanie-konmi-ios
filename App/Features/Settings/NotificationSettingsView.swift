import HorselyCore
import HorselyKit
import SwiftUI
import UserNotifications

/// Dane sekcji „Powiadomienia z serwera” podane z zewnątrz — migawki ekranu (bez sieci i bez rejestratora).
struct PushPreview {
    var state: PushState
    var device: PushDevice?
    /// `nil` — lista jeszcze niepobrana albo pobranie się nie udało (`rulesFailed`).
    var rules: [ClientPushRule]?
    var rulesFailed = false
}

/// Ustawienia → Powiadomienia (T120, FR-M-POW-02/04, FR-M-UST; spec 003, contracts/ui-push-ios.md): włączenie z wyjaśnieniem przed
/// prośbą systemu o zgodę, godzina podsumowania, powiadomienie w dniu terminu, ukrywanie szczegółów na ekranie blokady; po odmowie —
/// jak włączyć zgodę. W trybie z serwerem na górze sekcja „Powiadomienia z serwera”: stan push, daty i lista reguł przypisanych
/// telefonowi albo powód, dla którego powiadomienia planuje telefon. Gdy powiadomienia wysyła serwer, ustawienia lokalne
/// (włączenie, godzina, „w dniu terminu”) są ukryte — zostaje „ukryj szczegóły”.
struct NotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// Gotowe dane sekcji serwera (migawki); `nil` — dane z rejestratora.
    var preview: PushPreview?

    @State private var enabled = false
    @State private var time = Date()
    @State private var onDueDate = false
    @State private var hideDetails = false
    @State private var denied = false
    @State private var explaining = false
    @State private var loaded = false

    @State private var device: PushDevice?
    @State private var rules: [ClientPushRule]?
    @State private var rulesFailed = false
    @State private var loadingPush = false
    @State private var deviceRemoved = false

    init(preview: PushPreview? = nil) {
        self.preview = preview
    }

    private var pushState: PushState { preview?.state ?? environment.pushState }
    private var showsServerSection: Bool { pushState != .standalone && (preview != nil || environment.workMode == .online) }
    private var shownDevice: PushDevice? { preview?.device ?? device }
    private var shownRules: [ClientPushRule]? { preview == nil ? rules : preview?.rules }
    private var shownRulesFailed: Bool { preview?.rulesFailed ?? rulesFailed }

    var body: some View {
        Form {
            if showsServerSection { serverSection }
            if pushState == .registered {
                registeredLockScreenSection
            } else {
                localSections
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("notif_settings_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task(id: pushState) { await loadPush() }
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
        .alert(tr("push_section_title"), isPresented: $deviceRemoved) {
            Button(tr("push_device_removed_ok")) { Task { await environment.pushRegistrar.acknowledgeDeviceRemoved() } }
        } message: {
            Text("push_device_removed")
        }
    }

    // MARK: Sekcja serwera

    @ViewBuilder
    private var serverSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.between) {
                switch pushState {
                case .registered:
                    registeredBlock
                case .pending, .noPermission(asked: false):
                    // Przed pytaniem o zgodę ekran nie mówi o odmowie (FR-012a).
                    Text("push_state_pending").accessibilityIdentifier("push-state")
                case .fallback(.serverHasNoPush):
                    warning("push_state_no_push")
                case .fallback(.apnsUnavailable):
                    warning("push_state_no_apns")
                case .fallback(.registrationFailed):
                    warning("push_state_failed")
                case .noPermission(asked: true):
                    warning("push_state_no_permission")
                    Button(tr("notif_settings_open_notifications")) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .frame(minHeight: Spacing.minTouchTarget)
                    .accessibilityIdentifier("push-open-settings")
                case .standalone:
                    EmptyView()
                }
            }
        } header: {
            Text("push_section_title")
        }
    }

    private var registeredBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            Text("push_state_registered").accessibilityIdentifier("push-state")
            if let registeredAt = shownDevice?.registeredAt ?? environment.settings.pushRegistration.registeredAt {
                Text(tr("push_registered_at", Self.stamp(registeredAt))).font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
            }
            if let delivered = shownDevice?.lastDeliveredAt {
                Text(tr("push_last_delivered", Self.stamp(delivered))).font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
            } else if shownDevice != nil {
                Text("push_never_delivered").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
            }
            Text("push_rules_title").font(.headline).padding(.top, Spacing.between)
            rulesBlock
            Button {
                Task { await loadPush() }
            } label: {
                Text("push_refresh")
            }
            .frame(minHeight: Spacing.minTouchTarget)
            .disabled(loadingPush)
            .accessibilityIdentifier("push-refresh")
        }
    }

    @ViewBuilder
    private var rulesBlock: some View {
        if shownRulesFailed {
            Text("push_rules_failed").font(.subheadline).accessibilityIdentifier("push-rules")
        } else if let rules = shownRules {
            if rules.isEmpty {
                InfoCard(tone: .warning) {
                    HStack(alignment: .top, spacing: Spacing.between) {
                        HIcon(name: "warning", size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("push_rules_empty_title").font(.headline)
                            Text("push_rules_empty_text").font(.footnote)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("push-rules")
            } else {
                VStack(alignment: .leading, spacing: Spacing.between) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                        Text(rule.description).font(.subheadline)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("push-rules")
            }
        } else if loadingPush {
            ProgressView()
        }
    }

    private func warning(_ key: String) -> some View {
        InfoCard(tone: .warning) {
            HStack(alignment: .top, spacing: Spacing.between) {
                HIcon(name: "warning", size: 24)
                Text(LocalizedStringKey(key)).font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("push-state")
    }

    // MARK: Powiadomienia lokalne

    @ViewBuilder
    private var localSections: some View {
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
            hideDetailsToggle
        }
        .disabled(!enabled)
    }

    /// Gdy powiadomienia wysyła serwer, zostaje tylko ukrywanie szczegółów — z dopiskami, bo treść z serwera odebrana w tle
    /// pokazuje się na ekranie blokady w całości (Clarifications Q2) i zależy też od systemowego „Pokazuj podglądy”.
    @ViewBuilder
    private var registeredLockScreenSection: some View {
        Section {
            hideDetailsToggle
            if hideDetails {
                Text("push_hide_background_note").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                Text("push_hide_previews_hint").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
            }
        }
    }

    private var hideDetailsToggle: some View {
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

    // MARK: Ładowanie

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

    /// `GET push/device` i `GET push/rules` — przy otwarciu ekranu, zmianie stanu i po „Odśwież” (tylko przy zarejestrowanym telefonie).
    private func loadPush() async {
        guard preview == nil, pushState == .registered, environment.workMode == .online else { return }
        loadingPush = true
        defer { loadingPush = false }
        async let fetchedDevice = environment.pushRegistrar.deviceInfo()
        async let fetchedRules = environment.pushRegistrar.rules()
        device = await fetchedDevice
        let list = await fetchedRules
        rules = list
        rulesFailed = list == nil
        if environment.settings.pushRegistration.deviceRemovedNotice { deviceRemoved = true }
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
        environment.settings.pushPermissionAsked = true
        save(enabled: true)
        denied = !granted
        await environment.pushRegistrar.reconcile(.permissionChanged)
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

    /// „05.11.2026, 08:15” w czasie lokalnym telefonu.
    private static func stamp(_ date: Date) -> String {
        Formats.dataStamp(NotificationScheduler.local(date))
    }
}
