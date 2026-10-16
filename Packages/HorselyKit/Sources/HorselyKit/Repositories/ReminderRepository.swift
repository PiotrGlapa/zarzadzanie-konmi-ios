import Foundation
import HorselyCore

/// Filtr listy terminów (FR-M-TER-02): koń, rodzaj, status (domyślnie „Otwarty”) i zakres dat.
public struct ReminderFilter: Sendable, Hashable {
    public var horseId: String?
    public var kind: ReminderKind?
    public var status: ReminderStatus? = .open
    public var from: LocalDate?
    public var to: LocalDate?

    public init(horseId: String? = nil, kind: ReminderKind? = nil, status: ReminderStatus? = .open, from: LocalDate? = nil, to: LocalDate? = nil) {
        self.horseId = horseId
        self.kind = kind
        self.status = status
        self.from = from
        self.to = to
    }
}

/// Terminy w magazynie lokalnym: lista z filtrami, akcje Zrealizowany · Odrzuć · Otwórz ponownie, zapis i usunięcie.
public final class ReminderRepository: Sendable {
    private let entries: EntryRepository

    public init(entries: EntryRepository) {
        self.entries = entries
    }

    /// Terminy rosnąco po dacie terminu (przeterminowane na początku), z nazwą konia i rodzaju specjalisty.
    public func reminders(_ filter: ReminderFilter = ReminderFilter()) async throws -> [ReminderItem] {
        try await entries.read { source, today in
            let reminders = try source.records(.reminder, as: LocalReminder.self, horseId: filter.horseId)
                .filter { reminder in
                    (filter.kind == nil || reminder.kind == filter.kind)
                        && (filter.status == nil || reminder.status == filter.status)
                        && (filter.from == nil || reminder.dueDate >= filter.from!)
                        && (filter.to == nil || reminder.dueDate <= filter.to!)
                }
                .sorted { ($0.dueDate, $0.id) < ($1.dueDate, $1.id) }
            return try LocalViews(source: source).reminderItems(reminders, today: today)
        }
    }

    public func reminder(id: String) async throws -> ReminderItem? {
        try await entries.read { source, today in
            guard let reminder = try source.find(.reminder, id: id, as: LocalReminder.self) else { return nil }
            return try LocalViews(source: source).reminderItems([reminder], today: today).first
        }
    }

    public func create(_ input: ReminderInput) async throws -> EntryResult {
        try await entries.perform { $0.createReminder(input) }
    }

    public func update(id: String, _ input: ReminderInput, expectedVersion: Int) async throws -> EntryResult {
        try await entries.perform { $0.updateReminder(id: id, input, expectedVersion: expectedVersion) }
    }

    public func complete(id: String) async throws -> EntryResult {
        try await entries.perform(.completeReminder) { $0.reminderAction(id: id, .complete) }
    }

    public func dismiss(id: String) async throws -> EntryResult {
        try await entries.perform(.dismissReminder) { $0.reminderAction(id: id, .dismiss) }
    }

    public func reopen(id: String) async throws -> EntryResult {
        try await entries.perform { $0.reminderAction(id: id, .reopen) }
    }

    /// „Przełóż”: ta sama treść z nową datą terminu.
    public func postpone(_ reminder: ReminderItem, to date: LocalDate) async throws -> EntryResult {
        var input = ReminderInput()
        input.horseId = reminder.horseId
        input.kind = reminder.kind
        input.dueDate = date
        input.title = reminder.title
        input.specialistTypeId = reminder.specialistTypeId
        input.notes = reminder.notes
        let id = reminder.id
        let version = reminder.version
        let changed = input
        return try await entries.perform(.reschedule) { $0.updateReminder(id: id, changed, expectedVersion: version) }
    }

    public func delete(id: String) async throws -> EntryResult {
        try await entries.delete(.reminder, id: id)
    }
}
