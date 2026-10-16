import Foundation
import HorselyCore

/// Zasady kopii zapasowej trybu samodzielnego (FR-KOP-05, FR-KOP-08; `BackupReminder.kt`, `AutoBackup.kt` Androida).
public enum BackupPolicy {
    public static let interval: TimeInterval = 7 * 24 * 60 * 60
    /// Liczba zachowywanych kopii automatycznych `zk-auto-*.zkkopia`.
    public static let autoKeep = 4

    /// Karta „Zadbaj o kopię zapasową” na Pulpicie: tryb samodzielny, dane zmienione od ostatniej kopii, ≥ 7 dni od niej (albo
    /// kopii nie było), nieodsunięta „Przypomnij później”. Przy działającej kopii automatycznej (bez błędu) karty nie ma.
    public static func reminderDue(
        mode: WorkMode, changeCounter: Int64, lastChangeCounter: Int64, autoEnabled: Bool, autoLastError: String?, lastAt: Date?, snoozedUntil: Date?, now: Date
    ) -> Bool {
        guard mode == .standalone, changeCounter > lastChangeCounter else { return false }
        if autoEnabled && autoLastError == nil { return false }
        if let lastAt, now < lastAt.addingTimeInterval(interval) { return false }
        if let snoozedUntil, now < snoozedUntil { return false }
        return true
    }

    /// Czy pora na kopię automatyczną: włączona, tryb samodzielny, dane zmienione, minęło 7 dni od ostatniej kopii.
    public static func autoDue(enabled: Bool, mode: WorkMode, changeCounter: Int64, lastChangeCounter: Int64, lastAt: Date?, now: Date) -> Bool {
        guard enabled, mode == .standalone, changeCounter > lastChangeCounter else { return false }
        guard let lastAt else { return true }
        return now >= lastAt.addingTimeInterval(interval)
    }

    /// Nadmiarowe kopie automatyczne do usunięcia: najstarsze `zk-auto-RRRR-MM-DD.zkkopia` ponad 4 (nazwa niesie datę); kopie ręczne
    /// i inne pliki nie są ruszane.
    public static func autoSurplus(_ names: [String], keep: String) -> [String] {
        let autos = names.filter(isAutoName).sorted(by: >)
        return autos.dropFirst(autoKeep).filter { $0 != keep }
    }

    public static func isAutoName(_ name: String) -> Bool {
        let prefix = "zk-auto-"
        let suffix = ".\(BackupManifest.fileExtension)"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
        let date = name.dropFirst(prefix.count).dropLast(suffix.count)
        return date.count == 10 && LocalDate(String(date)) != nil
    }

    /// Zapis chwili w ustawieniach (`backup.lastAt`, `backup.reminderSnoozedUntil`).
    public static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    public static func date(_ stamp: String?) -> Date? {
        stamp.flatMap { ISO8601DateFormatter().date(from: $0) ?? RefreshPlan.parseInstant($0) }
    }
}
