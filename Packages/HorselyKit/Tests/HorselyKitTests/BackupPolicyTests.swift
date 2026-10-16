import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Przypomnienie o kopii i kopia automatyczna (T128; `BackupReminderTest`, `AutoBackupWorkerTest`).
struct BackupPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func due(
        mode: WorkMode = .standalone, changes: Int64 = 5, last: Int64 = 1, auto: Bool = false, error: String? = nil, lastAt: Date? = nil, snoozed: Date? = nil
    ) -> Bool {
        BackupPolicy.reminderDue(
            mode: mode, changeCounter: changes, lastChangeCounter: last, autoEnabled: auto, autoLastError: error, lastAt: lastAt, snoozedUntil: snoozed, now: now
        )
    }

    @Test func theReminderNeedsChangedDataAndAWeekSinceTheLastBackup() {
        #expect(due())
        #expect(!due(mode: .online))
        #expect(!due(changes: 1, last: 1))
        #expect(!due(lastAt: now.addingTimeInterval(-6 * day)))
        #expect(due(lastAt: now.addingTimeInterval(-7 * day)))
    }

    @Test func remindLaterAndAWorkingAutomaticBackupHideTheCard() {
        #expect(!due(snoozed: now.addingTimeInterval(day)))
        #expect(due(snoozed: now.addingTimeInterval(-1)))
        #expect(!due(auto: true))
        #expect(due(auto: true, error: "Brak dostępu do folderu"))
    }

    @Test func anAutomaticBackupRunsWeeklyOnlyWhenDataChanged() {
        #expect(BackupPolicy.autoDue(enabled: true, mode: .standalone, changeCounter: 3, lastChangeCounter: 1, lastAt: nil, now: now))
        #expect(!BackupPolicy.autoDue(enabled: false, mode: .standalone, changeCounter: 3, lastChangeCounter: 1, lastAt: nil, now: now))
        #expect(!BackupPolicy.autoDue(enabled: true, mode: .standalone, changeCounter: 1, lastChangeCounter: 1, lastAt: nil, now: now))
        #expect(!BackupPolicy.autoDue(enabled: true, mode: .standalone, changeCounter: 3, lastChangeCounter: 1, lastAt: now.addingTimeInterval(-day), now: now))
    }

    @Test func onlyTheFourNewestAutomaticBackupsStay() {
        let names = [
            "zk-auto-2026-09-01.zkkopia", "zk-auto-2026-09-08.zkkopia", "zk-auto-2026-09-15.zkkopia", "zk-auto-2026-09-22.zkkopia",
            "zk-auto-2026-09-29.zkkopia", "Zarzadzanie-konmi-kopia-2026-08-01.zkkopia", "notatka.txt",
        ]
        #expect(BackupPolicy.autoSurplus(names, keep: "zk-auto-2026-09-29.zkkopia") == ["zk-auto-2026-09-01.zkkopia"])
        #expect(BackupManifest.manualFileName(LocalDate(year: 2026, month: 10, day: 9)!) == "Zarzadzanie-konmi-kopia-2026-10-09.zkkopia")
    }
}
