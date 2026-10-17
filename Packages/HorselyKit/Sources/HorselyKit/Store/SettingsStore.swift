import Foundation
import HorselyCore

/// Motyw aplikacji (FR-M-UST-04): systemowy, jasny, ciemny.
public enum ThemeSetting: String, Sendable, CaseIterable {
    case system
    case light
    case dark
}

/// Ustawienia w `UserDefaults` grupy App Group (data-model.md §5), z wartościami domyślnymi. Klucz API nie jest tutaj — leży
/// w pęku kluczy (`KeychainStore`). Rozszerzenie udostępniania czyta te same ustawienia (tryb pracy).
public struct SettingsStore: @unchecked Sendable {
    public static let appGroupSuiteName = "group.pl.glapa.horsely"

    private let defaults: UserDefaults

    /// `UserDefaults` grupy; gdy grupa jest niedostępna (testy bez uprawnień), standardowe ustawienia procesu.
    public init(defaults: UserDefaults? = UserDefaults(suiteName: SettingsStore.appGroupSuiteName)) {
        self.defaults = defaults ?? .standard
    }

    enum Key {
        static let workMode = "workMode"
        static let modeChangePending = "modeChange.pending"
        static let theme = "theme"
        static let notificationsEnabled = "notifications.enabled"
        static let notificationsDailyTime = "notifications.dailyTime"
        static let notificationsOnDueDate = "notifications.onDueDate"
        static let notificationsHideDetails = "notifications.hideDetails"
        static let timelineMonths = "data.timelineMonths"
        static let attachmentLimitMB = "data.attachmentLimitMB"
        static let sendOriginals = "data.sendOriginals"
        static let keepPhotoLocation = "data.keepPhotoLocation"
        static let wifiOnly = "data.wifiOnly"
        static let downloadAllAttachments = "data.downloadAllAttachments"
        static let backupLastAt = "backup.lastAt"
        static let backupLastKind = "backup.lastKind"
        static let backupLastChangeCounter = "backup.lastChangeCounter"
        static let backupReminderSnoozedUntil = "backup.reminderSnoozedUntil"
        static let backupAutoEnabled = "backup.auto.enabled"
        static let backupAutoFolderBookmark = "backup.auto.folderBookmark"
        static let backupAutoLastError = "backup.auto.lastError"
        static let appLockEnabled = "appLock.enabled"
        static let appLockLastBackgroundAt = "appLock.lastBackgroundAt"
        static let connectionLogUntil = "connectionLog.until"
        static let programVersionWarnedFor = "programVersion.warnedFor"
    }

    // MARK: Tryb pracy i motyw

    /// Domyślnie `unset` — ekran powitalny prosi o wybór trybu (FR-TRB-01).
    public var workMode: WorkMode {
        get { defaults.string(forKey: Key.workMode).flatMap(WorkMode.init(rawValue:)) ?? .unset }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.workMode) }
    }

    /// Przerwana zmiana trybu do wznowienia (FR-TRB-07); `nil` — brak.
    public var modeChangePending: String? {
        get { defaults.string(forKey: Key.modeChangePending) }
        nonmutating set { set(newValue, Key.modeChangePending) }
    }

    public var theme: ThemeSetting {
        get { defaults.string(forKey: Key.theme).flatMap(ThemeSetting.init(rawValue:)) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.theme) }
    }

    // MARK: Powiadomienia

    public var notificationsEnabled: Bool {
        get { bool(Key.notificationsEnabled, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    /// Godzina podsumowania dnia jako `HH:mm`; domyślnie 08:00.
    public var notificationsDailyTime: String {
        get { defaults.string(forKey: Key.notificationsDailyTime) ?? "08:00" }
        nonmutating set { defaults.set(newValue, forKey: Key.notificationsDailyTime) }
    }

    public var notificationsOnDueDate: Bool {
        get { bool(Key.notificationsOnDueDate, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.notificationsOnDueDate) }
    }

    public var notificationsHideDetails: Bool {
        get { bool(Key.notificationsHideDetails, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.notificationsHideDetails) }
    }

    // MARK: Dane

    /// Zakres osi czasu w miesiącach: 3, 12 albo 24 (domyślnie 12).
    public var timelineMonths: Int {
        get { int(Key.timelineMonths, default: 12) }
        nonmutating set { defaults.set(newValue, forKey: Key.timelineMonths) }
    }

    public var attachmentLimitMB: Int {
        get { int(Key.attachmentLimitMB, default: 200) }
        nonmutating set { defaults.set(newValue, forKey: Key.attachmentLimitMB) }
    }

    public var sendOriginals: Bool {
        get { bool(Key.sendOriginals, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.sendOriginals) }
    }

    public var keepPhotoLocation: Bool {
        get { bool(Key.keepPhotoLocation, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.keepPhotoLocation) }
    }

    /// Wysyłka i pobieranie plików tylko przez Wi‑Fi (domyślnie włączone).
    public var wifiOnly: Bool {
        get { bool(Key.wifiOnly, default: true) }
        nonmutating set { defaults.set(newValue, forKey: Key.wifiOnly) }
    }

    public var downloadAllAttachments: Bool {
        get { bool(Key.downloadAllAttachments, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.downloadAllAttachments) }
    }

    // MARK: Kopia zapasowa

    public var backupLastAt: String? {
        get { defaults.string(forKey: Key.backupLastAt) }
        nonmutating set { set(newValue, Key.backupLastAt) }
    }

    public var backupLastKind: String? {
        get { defaults.string(forKey: Key.backupLastKind) }
        nonmutating set { set(newValue, Key.backupLastKind) }
    }

    public var backupLastChangeCounter: Int64 {
        get { Int64(defaults.integer(forKey: Key.backupLastChangeCounter)) }
        nonmutating set { defaults.set(newValue, forKey: Key.backupLastChangeCounter) }
    }

    public var backupReminderSnoozedUntil: String? {
        get { defaults.string(forKey: Key.backupReminderSnoozedUntil) }
        nonmutating set { set(newValue, Key.backupReminderSnoozedUntil) }
    }

    public var backupAutoEnabled: Bool {
        get { bool(Key.backupAutoEnabled, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.backupAutoEnabled) }
    }

    /// Zakładka bezpieczeństwa wybranego folderu kopii automatycznej.
    public var backupAutoFolderBookmark: Data? {
        get { defaults.data(forKey: Key.backupAutoFolderBookmark) }
        nonmutating set { defaults.set(newValue, forKey: Key.backupAutoFolderBookmark) }
    }

    public var backupAutoLastError: String? {
        get { defaults.string(forKey: Key.backupAutoLastError) }
        nonmutating set { set(newValue, Key.backupAutoLastError) }
    }

    // MARK: Blokada, dziennik, wersje

    public var appLockEnabled: Bool {
        get { bool(Key.appLockEnabled, default: false) }
        nonmutating set { defaults.set(newValue, forKey: Key.appLockEnabled) }
    }

    /// Nieużywane od 2.0.2: trwały znacznik przejścia w tło, nigdy niezerowany, powodował ponowną blokadę zaraz po
    /// odblokowaniu (`AppLockMachine` trzyma ten czas tylko w pamięci). Klucz zostaje bez migracji i bez odczytu.
    public var appLockLastBackgroundAt: Double? {
        get { defaults.object(forKey: Key.appLockLastBackgroundAt) as? Double }
        nonmutating set { defaults.set(newValue, forKey: Key.appLockLastBackgroundAt) }
    }

    /// Do kiedy włączony jest szczegółowy dziennik połączeń (FR-029), jako `yyyy-MM-ddTHH:mm:ss`.
    public var connectionLogUntil: String? {
        get { defaults.string(forKey: Key.connectionLogUntil) }
        nonmutating set { set(newValue, Key.connectionLogUntil) }
    }

    /// Wersja programu, o której już ostrzeżono (FR-M-UST-06).
    public var programVersionWarnedFor: String? {
        get { defaults.string(forKey: Key.programVersionWarnedFor) }
        nonmutating set { set(newValue, Key.programVersionWarnedFor) }
    }

    // MARK: Pomocnicze

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    private func int(_ key: String, default value: Int) -> Int {
        defaults.object(forKey: key) == nil ? value : defaults.integer(forKey: key)
    }

    private func set(_ value: String?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
