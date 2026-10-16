import Foundation

// Zakupy, notatki, treningi, terminy ręczne, zawody i starty (`PurchaseService`, `NoteService`, `TrainingService`, `ReminderService`,
// `CompetitionService`, `CompetitionStartService`).

extension RuleEngine {
    // MARK: Zakupy

    private func purchase(_ s: RuleSession, _ input: PurchaseInput, id: String, old: LocalPurchase?) throws -> LocalPurchase {
        let horseIds = Self.unique(input.horseIds ?? [])
        var errors: [String: [String]] = [:]
        if !horseIds.isEmpty, try horseIds.filter({ try s.horse($0) != nil }).count != horseIds.count { errors["horseIds"] = [Messages.horseNotFound] }
        let categoryId = Self.id(input.categoryId)!
        if try Self.dictionaryOfType(s, categoryId, .purchaseCategory) == nil { errors["categoryId"] = [Messages.invalidDictionaryValue] }
        let unitId = Self.id(input.unitId)
        if let unitId, try Self.dictionaryOfType(s, unitId, .unit) == nil { errors["unitId"] = [Messages.invalidDictionaryValue] }
        let supplierId = Self.id(input.supplierContactId)
        if let supplierId, try s.contact(supplierId) == nil { errors["supplierContactId"] = [Messages.contactNotFound] }
        if !errors.isEmpty { throw s.reject(.validation(errors: errors)) }
        return LocalPurchase(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, purchaseDate: input.purchaseDate!,
            productName: (input.productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines), categoryId: categoryId, supplierContactId: supplierId,
            quantity: input.quantity, unitId: unitId, unitPrice: input.unitPrice, totalAmount: input.totalAmount ?? .zero, deliveryCost: input.deliveryCost ?? .zero,
            assignment: input.assignment!, horseIds: horseIds, notes: s.clean(input.notes), originalAmount: input.originalAmount,
            originalCurrency: Self.currency(s, input.originalAmount, input.originalCurrency)
        )
    }

    public func createPurchase(_ input: PurchaseInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.purchase(input))
            return (try s.insert(try purchase(s, input, id: s.newId(), old: nil), primary: true), nil)
        }
    }

    public func updatePurchase(id: String, _ input: PurchaseInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.purchase(input))
            guard let old = try s.find(.purchase, id, as: LocalPurchase.self) else { throw s.notFound("Purchase", id) }
            let updated = try purchase(s, input, id: id, old: old)
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            return (try s.replace(old: old, with: updated, primary: true), nil)
        }
    }

    // MARK: Notatki

    private func note(_ s: RuleSession, _ input: NoteInput, id: String, old: LocalNote?) -> LocalNote {
        LocalNote(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, horseId: Self.id(input.horseId)!, noteDate: input.noteDate ?? s.today,
            title: (input.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines), content: s.clean(input.content), isPinned: input.isPinned ?? false
        )
    }

    public func createNote(_ input: NoteInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.note(input))
            if try s.horse(Self.id(input.horseId)!) == nil { throw s.invalid("horseId", Messages.horseNotFound) }
            return (try s.insert(note(s, input, id: s.newId(), old: nil), primary: true), nil)
        }
    }

    public func updateNote(id: String, _ input: NoteInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.note(input))
            guard let old = try s.find(.note, id, as: LocalNote.self) else { throw s.notFound("Note", id) }
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            if try s.horse(Self.id(input.horseId)!) == nil { throw s.invalid("horseId", Messages.horseNotFound) }
            let saved = try s.replace(old: old, with: note(s, input, id: id, old: old), primary: true)
            try Self.syncAttachmentsHorse(s, ownerType: .note, ownerId: id, horseId: saved.horseId)
            return (saved, nil)
        }
    }

    // MARK: Treningi

    private func training(_ s: RuleSession, _ input: TrainingInput, id: String, old: LocalTraining?) throws -> LocalTraining {
        var errors: [String: [String]] = [:]
        let horseId = Self.id(input.horseId)!
        let horse = try s.horse(horseId)
        if horse == nil { errors["horseId"] = [Messages.horseNotFound] }
        let typeId = Self.id(input.trainingTypeId)!
        let type = try Self.dictionaryOfType(s, typeId, .trainingType)
        // Wyłączony rodzaj zostaje na treningach, które go już mają.
        let unchanged = old != nil && old?.trainingTypeId == typeId
        if let type, type.isActive || unchanged {
            if input.obstacleHeightCm != nil, type.systemKey != DefaultDictionaries.trainingJumping { errors["obstacleHeightCm"] = [Messages.obstacleHeightOnlyJumping] }
        } else {
            errors["trainingTypeId"] = [Messages.invalidTrainingType]
        }
        let coaching = input.coaching
        let trainerId = Self.id(coaching?.trainerContactId)
        if let trainerId, old == nil || old?.trainerContactId != trainerId {
            if let trainer = try s.contact(trainerId) {
                if !trainer.types.contains(.trainer) { errors["coaching.trainerContactId"] = [Messages.contactNotTrainer] }
            } else {
                errors["coaching.trainerContactId"] = [Messages.contactNotFound]
            }
        }
        let riderId = Self.id(input.riderContactId)
        if let message = try Self.riderError(s, riderId: riderId, currentRiderId: old?.riderContactId) { errors["riderContactId"] = [message] }
        if !errors.isEmpty { throw s.reject(.validation(errors: errors, warnings: s.warnings)) }
        let date = input.trainingDate!
        var training = LocalTraining(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, horseId: horseId, trainingDate: date, trainingTypeId: typeId,
            durationMinutes: input.durationMinutes, intensity: input.intensity, obstacleHeightCm: input.obstacleHeightCm, riderContactId: riderId, rating: input.rating,
            description: s.clean(input.description), trainerContactId: old?.trainerContactId, cost: old?.cost, originalAmount: old?.originalAmount,
            originalCurrency: old?.originalCurrency
        )
        // Brak obiektu `coaching` zostawia trenera i koszt; obiekt zastępuje wszystkie cztery pola.
        if let coaching {
            training.trainerContactId = trainerId
            training.cost = coaching.cost
            training.originalAmount = coaching.originalAmount
            training.originalCurrency = Self.currency(s, coaching.originalAmount, coaching.originalCurrency)
        }
        if let birth = horse?.birthDate, date < birth { s.warn("trainingDate", Messages.trainingBeforeBirth) }
        return training
    }

    public func createTraining(_ input: TrainingInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.training(input, today: s.today))
            return (try s.insert(try training(s, input, id: s.newId(), old: nil), primary: true), nil)
        }
    }

    public func updateTraining(id: String, _ input: TrainingInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.training(input, today: s.today))
            guard let old = try s.find(.training, id, as: LocalTraining.self) else { throw s.notFound("Training", id) }
            let updated = try training(s, input, id: id, old: old)
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            return (try s.replace(old: old, with: updated, primary: true), nil)
        }
    }

    // MARK: Terminy ręczne

    private func checkReminderReferences(_ s: RuleSession, horseId: String, specialistTypeId: String?) throws {
        var errors: [String: [String]] = [:]
        if try s.horse(horseId) == nil { errors["horseId"] = [Messages.horseNotFound] }
        if let specialistTypeId, try Self.dictionaryOfType(s, specialistTypeId, .specialistType) == nil { errors["specialistTypeId"] = [Messages.invalidDictionaryValue] }
        if !errors.isEmpty { throw s.reject(.validation(errors: errors)) }
    }

    public func createReminder(_ input: ReminderInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.reminder(input))
            let horseId = Self.id(input.horseId)!
            let specialistTypeId = Self.id(input.specialistTypeId)
            try checkReminderReferences(s, horseId: horseId, specialistTypeId: specialistTypeId)
            let reminder = LocalReminder(
                id: s.newId(), createdAt: s.now, updatedAt: s.now, version: 1, horseId: horseId, kind: input.kind ?? .other, dueDate: input.dueDate!,
                title: (input.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines), specialistTypeId: specialistTypeId, notes: s.clean(input.notes)
            )
            return (try s.insert(reminder, primary: true), nil)
        }
    }

    /// Edycja otwartego terminu; termin utworzony przez wpis zachowuje konia i rodzaj (zmieniają się data, tytuł i notatki).
    public func updateReminder(id: String, _ input: ReminderInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.reminder(input))
            guard let old = try s.find(.reminder, id, as: LocalReminder.self) else { throw s.notFound("Reminder", id) }
            if old.status != .open { throw s.conflict(.invalidState, Messages.reminderNotOpen) }
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            var changed = old
            if old.sourceId == nil {
                changed.horseId = Self.id(input.horseId)!
                changed.kind = input.kind ?? .other
                changed.specialistTypeId = Self.id(input.specialistTypeId)
                try checkReminderReferences(s, horseId: changed.horseId, specialistTypeId: changed.specialistTypeId)
            }
            changed.dueDate = input.dueDate!
            changed.title = (input.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            changed.notes = s.clean(input.notes)
            return (try s.replace(old: old, with: changed, primary: true), nil)
        }
    }

    public func reminderAction(id: String, _ action: ReminderActionKind) -> RuleOutcome {
        run { s in
            guard let old = try s.find(.reminder, id, as: LocalReminder.self) else { throw s.notFound("Reminder", id) }
            var changed: LocalReminder
            switch action {
            case .complete:
                if old.status != .open { throw s.conflict(.invalidState, Messages.reminderNotOpen) }
                changed = ReminderAutomation.complete(s, old, byType: nil, byId: nil)
            case .dismiss:
                if old.status != .open { throw s.conflict(.invalidState, Messages.reminderNotOpen) }
                changed = old
                changed.status = .dismissed
            case .reopen:
                if old.status == .open { throw s.conflict(.invalidState, Messages.reminderNotOpen) }
                changed = ReminderAutomation.reopen(old)
            }
            return (try s.replace(old: old, with: changed, primary: true), nil)
        }
    }

    // MARK: Zawody

    private func competition(_ s: RuleSession, _ input: CompetitionInput, id: String, old: LocalCompetition?) throws -> LocalCompetition {
        var errors: [String: [String]] = [:]
        let rankId = Self.id(input.rankId)
        if let rankId, try Self.dictionaryOfType(s, rankId, .competitionRank) == nil { errors["rankId"] = [Messages.invalidDictionaryValue] }
        let disciplineId = Self.id(input.disciplineId)
        if let disciplineId, try Self.dictionaryOfType(s, disciplineId, .competitionDiscipline) == nil { errors["disciplineId"] = [Messages.invalidDictionaryValue] }
        let organizerId = Self.id(input.organizerContactId)
        if let organizerId, try s.contact(organizerId) == nil { errors["organizerContactId"] = [Messages.contactNotFound] }
        if !errors.isEmpty { throw s.reject(.validation(errors: errors)) }
        return LocalCompetition(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, name: (input.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            dateFrom: input.dateFrom!, dateTo: input.dateTo, city: s.clean(input.city), venue: s.clean(input.venue), organizerContactId: organizerId, rankId: rankId,
            disciplineId: disciplineId, notes: s.clean(input.notes)
        )
    }

    public func createCompetition(_ input: CompetitionInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.competition(input))
            return (try s.insert(try competition(s, input, id: s.newId(), old: nil), primary: true), nil)
        }
    }

    /// Zmiana dat/nazwy zawodów przesuwa terminy ich startów; start poza nowymi datami blokuje zmianę.
    public func updateCompetition(id: String, _ input: CompetitionInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.competition(input))
            guard let old = try s.find(.competition, id, as: LocalCompetition.self) else { throw s.notFound("Competition", id) }
            let dateFrom = input.dateFrom!
            let lastDay = input.dateTo ?? dateFrom
            let starts = try s.byOwner(.competitionStart, id, as: LocalCompetitionStart.self)
            let outside = starts.filter { start in start.startDate.map { $0 < dateFrom || $0 > lastDay } ?? false }.sorted { ($0.startDate!, $0.id) < ($1.startDate!, $1.id) }
            if !outside.isEmpty {
                let list = try outside.map { start -> String in
                    let horseName = try s.horse(start.horseId)?.name ?? ""
                    let klass = HorseRules.clean(start.className).map { " — \($0)" } ?? ""
                    return "\(horseName)\(klass) — \(Formats.date(start.startDate))"
                }.joined(separator: "; ")
                throw s.invalid("dateFrom", Messages.startsOutsideCompetition(list))
            }
            let updated = try competition(s, input, id: id, old: old)
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            let saved = try s.replace(old: old, with: updated, primary: true)
            for start in starts { if let current = try s.find(.competitionStart, start.id, as: LocalCompetitionStart.self) { try syncStartReminder(s, saved, current) } }
            return (saved, nil)
        }
    }

    // MARK: Starty

    private func start(_ s: RuleSession, _ input: CompetitionStartInput, competition: LocalCompetition, id: String, old: LocalCompetitionStart?) throws -> LocalCompetitionStart {
        var errors: [String: [String]] = [:]
        let horseId = Self.id(input.horseId)!
        if try s.horse(horseId) == nil { errors["horseId"] = [Messages.horseNotFound] }
        let disciplineId = Self.id(input.disciplineId)
        if let disciplineId, try Self.dictionaryOfType(s, disciplineId, .competitionDiscipline) == nil { errors["disciplineId"] = [Messages.invalidDictionaryValue] }
        let lastDay = competition.dateTo ?? competition.dateFrom
        if let day = input.startDate, day < competition.dateFrom || day > lastDay {
            errors["startDate"] = [Messages.startDateOutsideCompetition(from: competition.dateFrom, to: lastDay)]
        }
        let riderId = Self.id(input.riderContactId)
        if let message = try Self.riderError(s, riderId: riderId, currentRiderId: old?.riderContactId) { errors["riderContactId"] = [message] }
        if !errors.isEmpty { throw s.reject(.validation(errors: errors)) }
        return LocalCompetitionStart(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, competitionId: competition.id, horseId: horseId, startDate: input.startDate,
            disciplineId: disciplineId, className: s.clean(input.className), riderContactId: riderId, placement: input.placement, participantsCount: input.participantsCount,
            resultStatus: EntryValidation.normalizedStatus(input), penaltyPoints: input.penaltyPoints, scorePercent: input.scorePercent, timeSeconds: input.timeSeconds,
            description: s.clean(input.description), subjectiveRating: input.subjectiveRating, entryFee: input.entryFee, otherCosts: input.otherCosts, prizeMoney: input.prizeMoney,
            originalAmount: input.originalAmount, originalCurrency: Self.currency(s, input.originalAmount, input.originalCurrency)
        )
    }

    /// Start bez wyniku w przyszłych zawodach (albo taki, który już ma termin) utrzymuje termin „Zawody” na dzień startu; wpisany wynik
    /// zamyka otwarty termin (FR-ZAW-04, FR-TER-02).
    private func syncStartReminder(_ s: RuleSession, _ competition: LocalCompetition, _ start: LocalCompetitionStart) throws {
        let existing = try s.byOwner(.reminder, start.id, as: LocalReminder.self).first { $0.sourceType == "CompetitionStart" }
        if start.resultStatus != nil {
            if let existing, existing.status == .open {
                try s.replaceDerived(old: existing, with: ReminderAutomation.complete(s, existing, byType: "CompetitionStart", byId: start.id))
            }
            return
        }
        let due = start.startDate ?? competition.dateFrom
        let horseName = try s.horse(start.horseId)?.name ?? ""
        try ReminderAutomation.syncFromSource(
            s, sourceType: "CompetitionStart", sourceId: start.id, horseId: start.horseId, kind: .competition,
            nextDate: (due > s.today || existing != nil) ? due : nil, title: Messages.reminderTitle(subject: competition.name, horse: horseName)
        )
    }

    public func createCompetitionStart(competitionId: String, _ input: CompetitionStartInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.start(input))
            guard let competition = try s.competition(competitionId) else { throw s.invalid("competitionId", Messages.competitionNotFound) }
            let saved = try s.insert(try start(s, input, competition: competition, id: s.newId(), old: nil), primary: true)
            try syncStartReminder(s, competition, saved)
            return (saved, nil)
        }
    }

    public func updateCompetitionStart(id: String, _ input: CompetitionStartInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.start(input))
            guard let old = try s.find(.competitionStart, id, as: LocalCompetitionStart.self) else { throw s.notFound("CompetitionStart", id) }
            guard let competition = try s.competition(old.competitionId) else { throw s.notFound("Competition", old.competitionId) }
            let updated = try start(s, input, competition: competition, id: id, old: old)
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            let saved = try s.replace(old: old, with: updated, primary: true)
            try Self.syncAttachmentsHorse(s, ownerType: .competitionStart, ownerId: id, horseId: saved.horseId)
            try syncStartReminder(s, competition, saved)
            return (saved, nil)
        }
    }
}
