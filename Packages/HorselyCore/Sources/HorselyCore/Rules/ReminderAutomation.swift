import Foundation

/// Terminy wynikające z wpisów (FR-TER-01…04, `ReminderService` i `*Registrations` programu): termin z daty następnej wizyty, zamknięcie
/// pasującego otwartego terminu przez późniejszą wizytę (najwyżej 14 dni po jej dacie), termin zawodów.
enum ReminderAutomation {
    /// Wizyta zamyka otwarty termin tego samego rodzaju, który przypada najpóźniej tyle dni po jej dacie (`ReminderRules`).
    static let completionToleranceDays = 14
    static let maxTitle = 200

    /// Zamyka otwarte terminy konia rodzaju `kind` przypadające najpóźniej `completionToleranceDays` dni po `visitDate`; termin utworzony
    /// przez sam wpis (`completedById`) nie jest zamykany. Dla specjalisty dodatkowo pasuje rodzaj specjalisty.
    static func autoComplete(
        _ session: RuleSession, horseId: String, kind: ReminderKind, specialistTypeId: String?, visitDate: LocalDate, completedByType: String, completedById: String
    ) throws {
        let latestDue = visitDate.adding(days: completionToleranceDays)
        for reminder in try session.all(.reminder, as: LocalReminder.self, horseId: horseId) {
            let matches = reminder.kind == kind && reminder.status == .open && reminder.dueDate <= latestDue
                && (reminder.sourceId == nil || reminder.sourceId != completedById)
                && (specialistTypeId == nil || reminder.specialistTypeId == specialistTypeId)
            if matches { try session.replaceDerived(old: reminder, with: complete(session, reminder, byType: completedByType, byId: completedById)) }
        }
    }

    static func complete(_ session: RuleSession, _ reminder: LocalReminder, byType: String?, byId: String?) -> LocalReminder {
        var copy = reminder
        copy.status = .completed
        copy.completedByType = byType
        copy.completedById = byId
        copy.completedAt = session.now
        return copy
    }

    static func reopen(_ reminder: LocalReminder) -> LocalReminder {
        var copy = reminder
        copy.status = .open
        copy.completedByType = nil
        copy.completedById = nil
        copy.completedAt = nil
        return copy
    }

    /// Utrzymuje jedyny termin rekordu źródłowego zgodnie z jego datą następnej wizyty (`nextDate`): brak terminu + data → nowy otwarty;
    /// otwarty + data → przełożony; otwarty bez daty → odrzucony; odrzucony + data → otwarty i przełożony; wykonany — bez zmian.
    @discardableResult
    static func syncFromSource(
        _ session: RuleSession, sourceType: String, sourceId: String, horseId: String, kind: ReminderKind, nextDate: LocalDate?, title: String,
        specialistTypeId: String? = nil
    ) throws -> LocalReminder? {
        let trimmed = title.count > maxTitle ? String(title.prefix(maxTitle)) : title
        let existing = try session.byOwner(.reminder, sourceId, as: LocalReminder.self).first { $0.sourceType == sourceType }
        guard let reminder = existing else {
            guard let due = nextDate else { return nil }
            let created = LocalReminder(
                id: session.newId(), createdAt: session.now, updatedAt: session.now, version: 1, horseId: horseId, kind: kind, dueDate: due, title: trimmed,
                sourceType: sourceType, sourceId: sourceId, specialistTypeId: specialistTypeId
            )
            return try session.insert(created, primary: false)
        }
        if reminder.status == .completed { return reminder }
        var changed = reminder
        changed.horseId = horseId
        changed.kind = kind
        changed.title = trimmed
        changed.specialistTypeId = specialistTypeId
        if reminder.status == .open, nextDate == nil {
            changed.status = .dismissed
        } else if reminder.status == .open, let nextDate, nextDate != reminder.dueDate {
            changed.dueDate = nextDate
        } else if reminder.status == .dismissed, let nextDate {
            changed = reopen(changed)
            changed.dueDate = nextDate
        }
        return try session.replaceDerived(old: reminder, with: changed)
    }

    /// Odrzuca wszystkie otwarte terminy konia (gdy przestaje być w stajni, FR-KON-04).
    static func dismissOpen(_ session: RuleSession, horseId: String) throws {
        for reminder in try session.all(.reminder, as: LocalReminder.self, horseId: horseId) where reminder.status == .open {
            var copy = reminder
            copy.status = .dismissed
            try session.replaceDerived(old: reminder, with: copy)
        }
    }
}
