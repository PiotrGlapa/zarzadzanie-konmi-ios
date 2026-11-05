import HorselyKit
import SwiftUI
import UserNotifications

/// Pulpit: karta „Powiadomienia o terminach są wyłączone” (oba tryby pracy) i — w trybie z serwerem, który wysyła powiadomienia —
/// pytanie o zgodę telefonu (spec 003, FR-012a, FR-014, contracts/ui-push-ios.md).
///
/// - Karta jest widoczna, gdy powiadomienia lokalne są wyłączone, powiadomień nie wysyła serwer (`PushState != .registered`)
///   i użytkownik nie wybrał „Nie pokazuj”. „Włącz” prowadzi tą samą ścieżką zgody co Ustawienia: wyjaśnienie przed pytaniem
///   systemu, instrukcja po odmowie.
/// - Pytanie o zgodę pada tylko tu, tylko gdy serwer ogłasza `push`, zgoda jest nieustalona i pytanie nie padło wcześniej;
///   odmowa jest szanowana. Nigdy z tła ani z innych ekranów.
struct NotificationsDashboardCards: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL

    /// Migawki: wymusza widoczność karty niezależnie od ustawień.
    var showsCard: Bool?

    @State private var dismissed = false
    @State private var enabledHere = false
    @State private var explaining = false
    @State private var showingDenied = false
    @State private var asking = false

    init(showsCard: Bool? = nil) {
        self.showsCard = showsCard
    }

    private var visible: Bool {
        if let showsCard { return showsCard }
        guard environment.workMode != .unset, !dismissed, !enabledHere else { return false }
        // Przebiegi testowe UI nie widzą karty (nie zasłania Pulpitu w istniejących testach), chyba że wymuszają stan push.
        guard !environment.launchOptions.isTestRun || environment.launchOptions.push != nil else { return false }
        return !environment.settings.notificationsEnabled && environment.pushState != .registered && !environment.settings.notificationsOffCardDismissed
    }

    /// Serwer ogłasza `push`, telefon jeszcze nie odpowiedział na pytanie o zgodę i nie padło ono wcześniej.
    private var shouldAskForPushPermission: Bool {
        !environment.launchOptions.isTestRun && environment.workMode == .online && environment.capabilities.push
            && environment.pushState == .noPermission(asked: false) && !environment.settings.pushPermissionAsked
    }

    var body: some View {
        VStack(spacing: 0) {
            if visible { card.padding(.top, Spacing.between) }
        }
        .onChange(of: shouldAskForPushPermission, initial: true) { _, ask in
            if ask { asking = true }
        }
        .alert(tr("notif_permission_title"), isPresented: $explaining) {
            Button(tr("common_next")) { Task { await requestPermission(forPush: false) } }
            Button(tr("notif_settings_not_now"), role: .cancel) {}
        } message: {
            Text("notif_permission_text")
        }
        .alert(tr("notif_permission_title"), isPresented: $asking) {
            Button(tr("common_next")) { Task { await requestPermission(forPush: true) } }
        } message: {
            Text("push_permission_text")
        }
        .alert(tr("notif_settings_denied_title"), isPresented: $showingDenied) {
            Button(tr("notif_settings_open_notifications")) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            Button(tr("common_ok"), role: .cancel) {}
        } message: {
            Text("notif_settings_denied_text")
        }
    }

    private var card: some View {
        InfoCard(tone: .warning) {
            VStack(alignment: .leading, spacing: Spacing.between) {
                HStack(alignment: .top, spacing: Spacing.between) {
                    HIcon(name: "warning", size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("dashboard_notifications_off_title").font(.headline).accessibilityAddTraits(.isHeader)
                        Text("dashboard_notifications_off_text").font(.footnote)
                    }
                }
                HStack(spacing: Spacing.between) {
                    Button {
                        enable()
                    } label: {
                        Text("dashboard_notifications_off_enable").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                    }
                    .buttonStyle(.primaryFilled)
                    .tint(HorselyColor.primary)
                    .accessibilityIdentifier("dashboard-notifications-enable")
                    Button {
                        environment.settings.notificationsOffCardDismissed = true
                        dismissed = true
                    } label: {
                        Text("dashboard_notifications_off_hide").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                    }
                    .accessibilityIdentifier("dashboard-notifications-hide")
                }
            }
        }
        .accessibilityIdentifier("dashboard-notifications-off")
    }

    /// „Włącz”: zgoda już jest — od razu; nieustalona — najpierw wyjaśnienie; odmówiona — instrukcja (jak w Ustawieniach).
    private func enable() {
        Task {
            switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
            case .notDetermined:
                explaining = true
            case .denied:
                turnOn()
                showingDenied = true
            default:
                turnOn()
            }
        }
    }

    private func turnOn() {
        environment.settings.notificationsEnabled = true
        enabledHere = true
        Task { await environment.rescheduleNotificationsNow() }
    }

    private func requestPermission(forPush: Bool) async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        environment.settings.pushPermissionAsked = true
        if !forPush {
            turnOn()
            if !granted { showingDenied = true }
        }
        await environment.pushRegistrar.reconcile(.permissionChanged)
    }
}
