import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Blokada aplikacji (5 min w tle) i „Wyczyść pamięć podręczną” bez utraty kolejki (T131, T132).
struct SettingsMaintenanceTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 5, hour: 9)!

    @Test func theLockReturnsAfterMoreThanFiveMinutesInTheBackground() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!AppLockPolicy.requiresUnlock(enabled: false, backgroundedAt: nil, now: now))
        #expect(AppLockPolicy.requiresUnlock(enabled: true, backgroundedAt: nil, now: now))
        #expect(!AppLockPolicy.requiresUnlock(enabled: true, backgroundedAt: now.addingTimeInterval(-300), now: now))
        #expect(AppLockPolicy.requiresUnlock(enabled: true, backgroundedAt: now.addingTimeInterval(-301), now: now))
    }

    @Test func clearingTheCacheKeepsUnsentRecordsTheQueueAndTheirFiles() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-cache-\(UUID().uuidString)", isDirectory: true)
        let files = try LocalFileStore(root: root)
        let synced = LocalNote(id: "n1", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", noteDate: LocalDate("2026-10-01")!, title: "Z programu")
        let pending = LocalNote(id: "n2", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", noteDate: LocalDate("2026-10-02")!, title: "Z telefonu")
        let downloaded = try files.write(Data("stary".utf8), attachmentId: "a-old", kind: .original, pinned: false)
        let unsent = try files.write(Data("nowy".utf8), attachmentId: "a-new", kind: .thumbnail, pinned: true)
        let attachment = LocalAttachment(
            id: "a-new", createdAt: stamp, updatedAt: stamp, version: 1, ownerType: .note, ownerId: "n2", horseId: "h1", fileName: "a.jpg",
            contentType: "image/jpeg", sizeBytes: 4, sha256: unsent.sha256
        )
        let operation = OutboxOperation(
            id: "op-1", kind: .createNote, localRef: "n2", payload: .object([:]), summary: "Notatka", createdAt: Date(), updatedAt: Date(), recordType: .note, recordId: "n2"
        )
        try await store.write { access in
            try access.upsert([try StoredRecord.of(synced, syncState: .synced), try StoredRecord.of(pending, syncState: .pending), try StoredRecord.of(attachment, syncState: .pending)])
            try access.upsertFile(downloaded)
            try access.upsertFile(unsent)
            try access.enqueue(operation)
            try access.setMeta(SyncMetaKey.lastSyncAt, "2026-10-05T08:00:00Z")
            try access.setMeta(PairingMetaKey.pairedAt, "2026-10-01T08:00:00Z")
        }
        #expect(try await store.filesSize() == 9)

        let kept = try await store.clearCache(files: files)
        #expect(kept == ["a-new"])
        #expect(try await store.get(.note, id: "n1") == nil)
        #expect(try await store.get(.note, id: "n2") != nil)
        #expect(try await store.read { try $0.operations() }.count == 1)
        #expect(try await store.read { try $0.file(attachmentId: "a-old", kind: .original) } == nil)
        #expect(try await store.read { try $0.file(attachmentId: "a-new", kind: .thumbnail) } != nil)
        #expect(!FileManager.default.fileExists(atPath: files.url(for: downloaded).path))
        #expect(try await store.meta(SyncMetaKey.lastSyncAt) == nil)
        #expect(try await store.meta(SyncMetaKey.forceFull) == "true")
        #expect(try await store.meta(PairingMetaKey.pairedAt) != nil, "parowanie zostaje")
    }
}
