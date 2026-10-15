import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Ustawienia (wartości domyślne z data-model.md §5), dziennik diagnostyczny (rotacja) i pamięć klucza.
struct SettingsAndLogTests {
    private func freshSettings() -> SettingsStore {
        let suite = "horsely.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults)
    }

    @Test func settingsHaveTheDocumentedDefaults() {
        let settings = freshSettings()
        #expect(settings.workMode == .unset)
        #expect(settings.theme == .system)
        #expect(settings.notificationsEnabled == false)
        #expect(settings.notificationsDailyTime == "08:00")
        #expect(settings.notificationsOnDueDate == false)
        #expect(settings.notificationsHideDetails == false)
        #expect(settings.timelineMonths == 12)
        #expect(settings.attachmentLimitMB == 200)
        #expect(settings.sendOriginals == false)
        #expect(settings.keepPhotoLocation == false)
        #expect(settings.wifiOnly == true)
        #expect(settings.downloadAllAttachments == false)
        #expect(settings.appLockEnabled == false)
        #expect(settings.backupAutoEnabled == false)
        #expect(settings.modeChangePending == nil)
    }

    @Test func settingsRememberChanges() {
        let settings = freshSettings()
        settings.workMode = .standalone
        settings.theme = .dark
        settings.wifiOnly = false
        settings.timelineMonths = 24
        settings.modeChangePending = "toOnline"
        #expect(settings.workMode == .standalone)
        #expect(settings.theme == .dark)
        #expect(settings.wifiOnly == false)
        #expect(settings.timelineMonths == 24)
        #expect(settings.modeChangePending == "toOnline")
        settings.modeChangePending = nil
        #expect(settings.modeChangePending == nil)
    }

    private func logDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("horsely-log-\(UUID().uuidString)")
    }

    @Test func logWritesEntriesNewestFirstWithoutLineBreaks() {
        let directory = logDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory, dates: FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 5)!))
        log.log("sync", "pierwszy\nwpis")
        log.log("sync", "drugi")
        let entries = log.entries()
        #expect(entries.count == 2)
        #expect(entries[0].hasSuffix("\tsync\tdrugi"))
        #expect(entries[1].hasSuffix("\tsync\tpierwszy wpis"))
        #expect(entries[0].hasPrefix("2026-10-05T12:00:00"))
        log.clear()
        #expect(log.entries().isEmpty)
    }

    @Test func logRotatesAndKeepsAtMostTwoFiles() {
        let directory = logDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory, maxFileBytes: 1_000)
        let line = String(repeating: "x", count: 90)
        for index in 0..<60 { log.log("test", "\(index) \(line)") }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(Set(files) == ["diagnostic-0.log", "diagnostic-1.log"])
        #expect(log.sizeBytes <= 2_000 + 200)
        // Najnowszy wpis zawsze jest zachowany, najstarsze mogły zostać odrzucone.
        #expect(log.entries().first?.contains("59 ") == true)
        #expect(log.entries().count < 60)
    }

    @Test func inMemorySecretStoreKeepsAndDeletesTheKey() throws {
        let store = InMemorySecretStore()
        #expect(try store.read() == nil)
        try store.save("klucz")
        #expect(try store.read() == "klucz")
        try store.delete()
        #expect(try store.read() == nil)
    }
}
