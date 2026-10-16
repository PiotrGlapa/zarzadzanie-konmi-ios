import HorselyCore
import HorselyKit
import SwiftUI

/// Pliki z rozszerzenia „Udostępnij → Horsely” (T117): przy otwarciu aplikacji, powrocie na pierwszy plan i w zadaniu w tle
/// pozycje skrzynki stają się załącznikami wybranego wpisu (albo nowej notatki konia) — zdjęcia są zmniejszane i pozbawiane
/// lokalizacji jak przy dodawaniu w aplikacji, w trybie online trafiają do kolejki i są wysyłane.
extension AppEnvironment {
    var sharedInbox: SharedInbox { SharedInbox.inGroup(files.root.deletingLastPathComponent()) }

    /// Zwraca liczbę dodanych plików.
    @discardableResult
    func processSharedInbox() async -> Int {
        guard workMode != .unset, !inboxRunning else { return 0 }
        inboxRunning = true
        defer { inboxRunning = false }
        let inbox = sharedInbox
        inbox.removeAbandoned()
        var added = 0
        for (entry, folder) in inbox.entries() {
            defer { inbox.remove(folder) }
            guard let owner = await sharedOwner(entry) else {
                log.log("share", "pominięto pliki udostępnione do nieistniejącego konia")
                continue
            }
            let store = attachments
            let picked = entry.files.map { file in
                PickedFile.file(folder.appendingPathComponent(file.name), name: file.name, mimeType: file.contentType, securityScoped: false)
            }
            let (ready, rejected) = await Task.detached(priority: .utility) { PickedFile.prepare(picked, with: store) }.value
            if !rejected.isEmpty { log.log("share", "pominięto \(rejected.count) plików") }
            guard !ready.isEmpty else { continue }
            do {
                try await store.add(owner, ready.map { PendingAttachment(file: $0, description: entry.description) })
                added += ready.count
            } catch {
                ready.forEach(store.discard)
                log.log("share", "nie udało się dodać plików: \(error.localizedDescription)")
            }
        }
        if added > 0 {
            router.banner = BannerMessage(text: workMode == .online ? tr("common_saved_queued") : tr("common_saved"))
            if workMode == .online { Task { _ = await sendQueue() } }
        }
        return added
    }

    /// Wpis docelowy; gdy go już nie ma albo wybrano „Nowa notatka” — nowa notatka konia z dzisiejszą datą.
    private func sharedOwner(_ entry: SharedInboxEntry) async -> AttachmentOwner? {
        if case let .entry(type, id) = entry.target, let recordType = Self.recordType(type),
           let record = try? await entries.record(recordType, id: id) {
            return AttachmentOwner(type: type, id: id, horseId: record.primaryHorseId ?? entry.horseId)
        }
        var input = NoteInput()
        input.horseId = entry.horseId
        input.noteDate = dates.today()
        if case let .newNote(title) = entry.target, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            input.title = title.trimmingCharacters(in: .whitespaces)
        } else {
            input.title = Self.sharedNoteTitle
        }
        let note = input
        guard let saved = try? await entries.perform({ $0.createNote(note) }).saved, let id = saved.record?.id else { return nil }
        return AttachmentOwner(type: .note, id: id, horseId: entry.horseId)
    }

    /// Tytuł nowej notatki bez wpisanego tytułu (jak na Androidzie).
    static let sharedNoteTitle = "Załącznik"

    static func recordType(_ owner: AttachmentOwnerType) -> RecordType? {
        switch owner {
        case .horse: .horse
        case .vetVisit: .vetVisit
        case .farrierVisit: .farrierVisit
        case .physioVisit: .physioVisit
        case .specialistVisit: .specialistVisit
        case .competition: .competition
        case .competitionStart: .competitionStart
        case .purchase: .purchase
        case .note: .note
        case .contact: .contact
        }
    }
}
