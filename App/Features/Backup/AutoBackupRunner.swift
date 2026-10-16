import HorselyCore
import HorselyKit
import SwiftUI
import UserNotifications

/// Kopia automatyczna co tydzień (T127/T128, FR-KOP-08): bez hasła, do folderu wskazanego przez użytkownika (zakładka
/// bezpieczeństwa), tylko gdy dane się zmieniły; zostają 4 najnowsze `zk-auto-*.zkkopia`. Uruchamiana przy otwarciu aplikacji
/// (nadrabianie) i w zadaniu w tle `pl.glapa.horsely.backup`. Błąd zapisuje się w ustawieniach i trafia do powiadomienia.
@MainActor
enum AutoBackupRunner {
    static let failureNotification = "backup-error"

    /// Folder kopii automatycznych z zakładki (odświeżonej, gdy system ją unieważnił).
    static func folder(_ settings: SettingsStore) -> URL? {
        guard let bookmark = settings.backupAutoFolderBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() { settings.backupAutoFolderBookmark = fresh }
        return url
    }

    /// Wykonuje kopię, gdy jest pora; zwraca nazwę zapisanego pliku.
    @discardableResult
    static func runIfDue(_ environment: AppEnvironment, now: Date = Date()) async -> String? {
        let settings = environment.settings
        let counter = (try? await environment.store.changeCounter()) ?? 0
        guard BackupPolicy.autoDue(
            enabled: settings.backupAutoEnabled, mode: environment.workMode, changeCounter: counter,
            lastChangeCounter: settings.backupLastChangeCounter, lastAt: BackupPolicy.date(settings.backupLastAt), now: now
        ) else { return nil }
        guard let folder = folder(settings) else {
            fail(settings, "Nie wskazano folderu kopii automatycznych.")
            return nil
        }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let name = BackupManifest.autoFileName(environment.dates.today())
        do {
            let result = try await environment.backup.write(to: folder.appendingPathComponent(name), password: nil, attachmentsCacheMb: settings.attachmentLimitMB)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for surplus in BackupPolicy.autoSurplus(names, keep: name) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(surplus))
            }
            settings.backupLastAt = BackupPolicy.stamp(now)
            settings.backupLastKind = "auto"
            settings.backupLastChangeCounter = result.changeCounter
            settings.backupAutoLastError = nil
            return name
        } catch {
            fail(settings, (error as? BackupError)?.message ?? error.localizedDescription)
            return nil
        }
    }

    private static func fail(_ settings: SettingsStore, _ reason: String) {
        settings.backupAutoLastError = reason
        let content = UNMutableNotificationContent()
        content.title = tr("backup_auto_failed_title")
        content.body = tr("backup_auto_failed_text")
        content.userInfo = [NotificationScheduler.linkKey: "horsely://dashboard"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: failureNotification, content: content, trigger: nil))
    }
}

/// Karta Pulpitu „Zadbaj o kopię zapasową” (T128, FR-KOP-05): tryb samodzielny, dane zmienione, ≥ 7 dni od ostatniej kopii;
/// „Utwórz teraz” otwiera Kopię zapasową, „Przypomnij później” ukrywa kartę na 7 dni.
struct BackupReminderCard: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var due = false
    @State private var showingBackup = false

    var body: some View {
        Group {
            if due {
                InfoCard(tone: .warning) {
                    VStack(alignment: .leading, spacing: Spacing.between) {
                        Text("backup_reminder_title").font(.headline)
                        Text(detail).font(.subheadline)
                        HStack(spacing: Spacing.between) {
                            Button(tr("backup_reminder_now")) { showingBackup = true }
                                .buttonStyle(.primaryFilled)
                                .tint(HorselyColor.primary)
                                .accessibilityIdentifier("backup-reminder-now")
                            Button(tr("backup_reminder_later")) { snooze() }
                                .buttonStyle(.bordered)
                                .tint(HorselyColor.primary)
                                .accessibilityIdentifier("backup-reminder-later")
                        }
                    }
                }
                .padding(.top, Spacing.between)
                .accessibilityIdentifier("backup-reminder")
            }
        }
        .task(id: environment.dataRevision) { await evaluate() }
        .sheet(isPresented: $showingBackup, onDismiss: { Task { await evaluate() } }) {
            NavigationStack {
                BackupView().toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common_close")) { showingBackup = false } } }
            }
            .environment(environment)
        }
    }

    private var detail: String {
        guard let at = BackupPolicy.date(environment.settings.backupLastAt) else { return tr("backup_reminder_never") }
        return tr("backup_reminder_since", ConnectionTexts.stamp(at) ?? "")
    }

    private func evaluate() async {
        let settings = environment.settings
        let counter = (try? await environment.store.changeCounter()) ?? 0
        due = BackupPolicy.reminderDue(
            mode: environment.workMode, changeCounter: counter, lastChangeCounter: settings.backupLastChangeCounter, autoEnabled: settings.backupAutoEnabled,
            autoLastError: settings.backupAutoLastError, lastAt: BackupPolicy.date(settings.backupLastAt),
            snoozedUntil: BackupPolicy.date(settings.backupReminderSnoozedUntil), now: Date()
        )
    }

    private func snooze() {
        environment.settings.backupReminderSnoozedUntil = BackupPolicy.stamp(Date().addingTimeInterval(BackupPolicy.interval))
        due = false
    }
}
