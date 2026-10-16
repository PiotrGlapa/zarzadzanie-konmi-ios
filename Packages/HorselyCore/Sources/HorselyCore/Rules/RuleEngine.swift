import Foundation

public enum ReminderActionKind: Sendable, Equatable {
    case complete, dismiss, reopen
}

/// Silnik reguł trybu samodzielnego (port `RuleEngine` z Androida 2.0.1): zapis wpisów z walidacją programu, skutkami (terminy,
/// zamykanie terminów wizytą, podział zakupu) i numeracją wersji. Operacja czyta z `RecordSource`, niczego nie zapisuje — zwraca
/// `RuleSaved` z listą zapisów do wykonania w jednej transakcji magazynu (rekord + skutki + licznik zmian).
public struct RuleEngine {
    let source: RecordSource
    let dates: any DateProvider
    let settings: RuleSettings
    let newId: () -> String

    public init(
        source: RecordSource, dates: any DateProvider, settings: RuleSettings = RuleSettings(),
        newId: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.source = source
        self.dates = dates
        self.settings = settings
        self.newId = newId
    }

    /// Wykonuje operację w świeżej sesji; odrzucenie w dowolnym miejscu porzuca wszystkie zapisy tej operacji.
    func run(_ operation: (RuleSession) throws -> (record: (any LocalRecord)?, batchId: String?)) -> RuleOutcome {
        let session = RuleSession(source: source, now: dates.now(), settings: settings, newId: newId)
        do {
            let result = try operation(session)
            return session.finish(result.record, batchId: result.batchId)
        } catch let failure as RuleFailure {
            return .rejected(failure.problem)
        } catch {
            return .rejected(.validation(errors: ["": [error.localizedDescription]]))
        }
    }

    // MARK: Wspólne

    /// Sprawdza wersję z żądania względem zapisanej (`If-Match`); niezgodna → `409`.
    static func requireVersion(_ session: RuleSession, current: Int, expected: Int?) throws {
        guard let expected else { throw session.invalid("version", Messages.required) }
        if expected != current { throw session.conflict(.versionMismatch, Messages.recordChanged) }
    }

    static func dictionaryOfType(_ session: RuleSession, _ id: String?, _ type: DictionaryType) throws -> LocalDictionaryItem? {
        guard let id, let item = try session.dictionary(id), item.dictionaryType == type else { return nil }
        return item
    }

    static func checkContact(_ session: RuleSession, _ id: String?) throws {
        if let id = HorseRules.clean(id), try session.contact(id) == nil { throw session.invalid("contactId", Messages.contactNotFound) }
    }

    /// Błąd pola wskazującego jeźdźca: kontakt musi istnieć i mieć typ Jeździec; niezmieniony jeździec nie jest sprawdzany ponownie.
    static func riderError(_ session: RuleSession, riderId: String?, currentRiderId: String?) throws -> String? {
        guard let riderId = HorseRules.clean(riderId), riderId != currentRiderId else { return nil }
        guard let contact = try session.contact(riderId) else { return Messages.contactNotFound }
        return contact.types.contains(.rider) ? nil : Messages.contactNotRider
    }

    /// Załącznik wskazuje konia wpisu — przy zmianie konia wpisu załączniki przechodzą na nowego konia.
    static func syncAttachmentsHorse(_ session: RuleSession, ownerType: AttachmentOwnerType, ownerId: String, horseId: String) throws {
        for attachment in try session.byOwner(.attachment, ownerId, as: LocalAttachment.self) where attachment.ownerType == ownerType && attachment.horseId != horseId {
            var copy = attachment
            copy.horseId = horseId
            try session.replaceDerived(old: attachment, with: copy)
        }
    }

    static func currency(_ session: RuleSession, _ amount: Money?, _ currency: String?) -> String? {
        amount == nil ? nil : session.clean(currency)?.uppercased()
    }

    static func id(_ text: String?) -> String? { HorseRules.clean(text) }

    /// Bez powtórzeń, w kolejności wpisania.
    static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    // MARK: Wizyty weterynaryjne

    private static func reminderKind(forVetSystemKey key: String?) -> ReminderKind {
        switch key {
        case DefaultDictionaries.vetVaccination: .vaccination
        case DefaultDictionaries.vetDeworming: .deworming
        default: .vet
        }
    }

    private func vetVisit(_ s: RuleSession, _ input: VetVisitInput, id: String, old: LocalVetVisit?) throws -> (visit: LocalVetVisit, horseName: String) {
        guard let horseId = Self.id(input.horseId), let horse = try s.horse(horseId) else { throw s.invalid("horseId", Messages.horseNotFound) }
        let visitTypeId = Self.id(input.visitTypeId)!
        guard let type = try Self.dictionaryOfType(s, visitTypeId, .vetVisitType) else { throw s.invalid("visitTypeId", Messages.invalidDictionaryValue) }
        try Self.checkContact(s, input.contactId)
        let vaccination = type.systemKey == DefaultDictionaries.vetVaccination || type.systemKey == DefaultDictionaries.vetDeworming
        let medications = (input.medications ?? []).enumerated().map { index, medication in
            LocalVetMedication(
                id: s.newId(), createdAt: s.now, updatedAt: s.now, version: 1, name: (medication.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                dosage: s.clean(medication.dosage), startDate: medication.startDate, endDate: medication.endDate, administration: medication.administration,
                notes: s.clean(medication.notes), sortOrder: index + 1
            )
        }
        let visit = LocalVetVisit(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, horseId: horseId, visitDateTime: input.visitDateTime!,
            contactId: Self.id(input.contactId), visitTypeId: visitTypeId, reason: s.clean(input.reason), diagnosis: s.clean(input.diagnosis),
            recommendations: s.clean(input.recommendations), vaccineOrProduct: vaccination ? s.clean(input.vaccineOrProduct) : nil,
            batchNumber: vaccination ? s.clean(input.batchNumber) : nil, cost: input.cost, nextVisitDate: input.nextVisitDate,
            nextVisitPurpose: s.clean(input.nextVisitPurpose), originalAmount: input.originalAmount,
            originalCurrency: Self.currency(s, input.originalAmount, input.originalCurrency), medications: medications
        )
        return (visit, horse.name)
    }

    private func applyVetReminders(_ s: RuleSession, _ visit: LocalVetVisit, horseName: String) throws {
        let type = try s.dictionary(visit.visitTypeId)!
        let kind = Self.reminderKind(forVetSystemKey: type.systemKey)
        try ReminderAutomation.autoComplete(s, horseId: visit.horseId, kind: kind, specialistTypeId: nil, visitDate: visit.visitDateTime.date, completedByType: "VetVisit", completedById: visit.id)
        let title = visit.nextVisitPurpose ?? Messages.reminderTitle(subject: type.value, horse: horseName)
        try ReminderAutomation.syncFromSource(s, sourceType: "VetVisit", sourceId: visit.id, horseId: visit.horseId, kind: kind, nextDate: visit.nextVisitDate, title: title)
    }

    public func createVetVisit(_ input: VetVisitInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.vet(input))
            let (visit, horseName) = try vetVisit(s, input, id: s.newId(), old: nil)
            let saved = try s.insert(visit, primary: true)
            try applyVetReminders(s, saved, horseName: horseName)
            return (saved, nil)
        }
    }

    public func updateVetVisit(id: String, _ input: VetVisitInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.vet(input))
            guard let old = try s.find(.vetVisit, id, as: LocalVetVisit.self) else { throw s.notFound("VetVisit", id) }
            let (visit, horseName) = try vetVisit(s, input, id: id, old: old)
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            let saved = try s.replace(old: old, with: visit, primary: true)
            try Self.syncAttachmentsHorse(s, ownerType: .vetVisit, ownerId: id, horseId: saved.horseId)
            try applyVetReminders(s, saved, horseName: horseName)
            return (saved, nil)
        }
    }

    // MARK: Kowal

    private func farrierVisit(_ s: RuleSession, _ input: FarrierVisitInput, id: String, old: LocalFarrierVisit?) throws -> (visit: LocalFarrierVisit, horseName: String) {
        guard let horseId = Self.id(input.horseId), let horse = try s.horse(horseId) else { throw s.invalid("horseId", Messages.horseNotFound) }
        let serviceId = Self.id(input.serviceId)!
        if try Self.dictionaryOfType(s, serviceId, .farrierService) == nil { throw s.invalid("serviceId", Messages.invalidDictionaryValue) }
        try Self.checkContact(s, input.contactId)
        let visit = LocalFarrierVisit(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, horseId: horseId, visitDate: input.visitDate!,
            contactId: Self.id(input.contactId), serviceId: serviceId, hoofNotes: s.clean(input.hoofNotes), cost: input.cost, nextVisitDate: input.nextVisitDate,
            originalAmount: input.originalAmount, originalCurrency: Self.currency(s, input.originalAmount, input.originalCurrency)
        )
        return (visit, horse.name)
    }

    private func applyFarrierReminders(_ s: RuleSession, _ visit: LocalFarrierVisit, horseName: String) throws {
        try ReminderAutomation.autoComplete(s, horseId: visit.horseId, kind: .farrier, specialistTypeId: nil, visitDate: visit.visitDate, completedByType: "FarrierVisit", completedById: visit.id)
        try ReminderAutomation.syncFromSource(
            s, sourceType: "FarrierVisit", sourceId: visit.id, horseId: visit.horseId, kind: .farrier, nextDate: visit.nextVisitDate,
            title: Messages.reminderTitle(subject: Messages.reminderKindFarrier, horse: horseName)
        )
    }

    public func createFarrierVisit(_ input: FarrierVisitInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.farrier(input))
            let (visit, horseName) = try farrierVisit(s, input, id: s.newId(), old: nil)
            let saved = try s.insert(visit, primary: true)
            try applyFarrierReminders(s, saved, horseName: horseName)
            return (saved, nil)
        }
    }

    public func updateFarrierVisit(id: String, _ input: FarrierVisitInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.farrier(input))
            guard let old = try s.find(.farrierVisit, id, as: LocalFarrierVisit.self) else { throw s.notFound("FarrierVisit", id) }
            let (visit, horseName) = try farrierVisit(s, input, id: id, old: old)
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            let saved = try s.replace(old: old, with: visit, primary: true)
            try Self.syncAttachmentsHorse(s, ownerType: .farrierVisit, ownerId: id, horseId: saved.horseId)
            try applyFarrierReminders(s, saved, horseName: horseName)
            return (saved, nil)
        }
    }

    // MARK: Fizjoterapia

    private func physioVisit(_ s: RuleSession, _ input: PhysioVisitInput, id: String, old: LocalPhysioVisit?) throws -> (visit: LocalPhysioVisit, horseName: String) {
        guard let horseId = Self.id(input.horseId), let horse = try s.horse(horseId) else { throw s.invalid("horseId", Messages.horseNotFound) }
        let areaIds = Self.unique(input.bodyAreaIds ?? [])
        let techniqueIds = Self.unique(input.techniqueIds ?? [])
        var errors: [String: [String]] = [:]
        if try !areaIds.allSatisfy({ try Self.dictionaryOfType(s, $0, .physioBodyArea) != nil }) { errors["bodyAreaIds"] = [Messages.invalidDictionaryValue] }
        if try !techniqueIds.allSatisfy({ try Self.dictionaryOfType(s, $0, .physioTechnique) != nil }) { errors["techniqueIds"] = [Messages.invalidDictionaryValue] }
        let contactId = Self.id(input.contactId)
        if let contactId, try s.contact(contactId) == nil { errors["contactId"] = [Messages.contactNotFound] }
        if !errors.isEmpty { throw s.reject(.validation(errors: errors)) }
        let visit = LocalPhysioVisit(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, horseId: horseId, visitDate: input.visitDate!,
            contactId: contactId, reason: s.clean(input.reason), bodyAreaIds: areaIds, techniqueIds: techniqueIds, observations: s.clean(input.observations),
            recommendations: s.clean(input.recommendations), cost: input.cost, nextVisitDate: input.nextVisitDate, nextVisitPurpose: s.clean(input.nextVisitPurpose),
            originalAmount: input.originalAmount, originalCurrency: Self.currency(s, input.originalAmount, input.originalCurrency)
        )
        return (visit, horse.name)
    }

    private func applyPhysioReminders(_ s: RuleSession, _ visit: LocalPhysioVisit, horseName: String) throws {
        try ReminderAutomation.autoComplete(s, horseId: visit.horseId, kind: .physio, specialistTypeId: nil, visitDate: visit.visitDate, completedByType: "PhysioVisit", completedById: visit.id)
        try ReminderAutomation.syncFromSource(
            s, sourceType: "PhysioVisit", sourceId: visit.id, horseId: visit.horseId, kind: .physio, nextDate: visit.nextVisitDate,
            title: visit.nextVisitPurpose ?? Messages.reminderTitle(subject: Messages.reminderKindPhysio, horse: horseName)
        )
    }

    public func createPhysioVisit(_ input: PhysioVisitInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.physio(input))
            let (visit, horseName) = try physioVisit(s, input, id: s.newId(), old: nil)
            let saved = try s.insert(visit, primary: true)
            try applyPhysioReminders(s, saved, horseName: horseName)
            return (saved, nil)
        }
    }

    public func updatePhysioVisit(id: String, _ input: PhysioVisitInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.physio(input))
            guard let old = try s.find(.physioVisit, id, as: LocalPhysioVisit.self) else { throw s.notFound("PhysioVisit", id) }
            let (visit, horseName) = try physioVisit(s, input, id: id, old: old)
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            let saved = try s.replace(old: old, with: visit, primary: true)
            try Self.syncAttachmentsHorse(s, ownerType: .physioVisit, ownerId: id, horseId: saved.horseId)
            try applyPhysioReminders(s, saved, horseName: horseName)
            return (saved, nil)
        }
    }

    // MARK: Inny specjalista

    private func specialistVisit(_ s: RuleSession, _ input: SpecialistVisitInput, id: String, old: LocalSpecialistVisit?) throws -> (visit: LocalSpecialistVisit, horseName: String, typeName: String) {
        guard let horseId = Self.id(input.horseId), let horse = try s.horse(horseId) else { throw s.invalid("horseId", Messages.horseNotFound) }
        let typeId = Self.id(input.specialistTypeId)!
        guard let type = try Self.dictionaryOfType(s, typeId, .specialistType) else { throw s.invalid("specialistTypeId", Messages.invalidDictionaryValue) }
        try Self.checkContact(s, input.contactId)
        let visit = LocalSpecialistVisit(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, horseId: horseId, visitDate: input.visitDate!,
            specialistTypeId: typeId, contactId: Self.id(input.contactId), reason: s.clean(input.reason), description: s.clean(input.description),
            recommendations: s.clean(input.recommendations), cost: input.cost, nextVisitDate: input.nextVisitDate, nextVisitPurpose: s.clean(input.nextVisitPurpose),
            originalAmount: input.originalAmount, originalCurrency: Self.currency(s, input.originalAmount, input.originalCurrency)
        )
        return (visit, horse.name, type.value)
    }

    private func applySpecialistReminders(_ s: RuleSession, _ visit: LocalSpecialistVisit, horseName: String, typeName: String) throws {
        try ReminderAutomation.autoComplete(
            s, horseId: visit.horseId, kind: .specialist, specialistTypeId: visit.specialistTypeId, visitDate: visit.visitDate, completedByType: "SpecialistVisit", completedById: visit.id
        )
        try ReminderAutomation.syncFromSource(
            s, sourceType: "SpecialistVisit", sourceId: visit.id, horseId: visit.horseId, kind: .specialist, nextDate: visit.nextVisitDate,
            title: visit.nextVisitPurpose ?? Messages.reminderTitle(subject: typeName, horse: horseName), specialistTypeId: visit.specialistTypeId
        )
    }

    public func createSpecialistVisit(_ input: SpecialistVisitInput) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.specialist(input))
            let (visit, horseName, typeName) = try specialistVisit(s, input, id: s.newId(), old: nil)
            let saved = try s.insert(visit, primary: true)
            try applySpecialistReminders(s, saved, horseName: horseName, typeName: typeName)
            return (saved, nil)
        }
    }

    public func updateSpecialistVisit(id: String, _ input: SpecialistVisitInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(EntryValidation.specialist(input))
            guard let old = try s.find(.specialistVisit, id, as: LocalSpecialistVisit.self) else { throw s.notFound("SpecialistVisit", id) }
            let (visit, horseName, typeName) = try specialistVisit(s, input, id: id, old: old)
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            let saved = try s.replace(old: old, with: visit, primary: true)
            try Self.syncAttachmentsHorse(s, ownerType: .specialistVisit, ownerId: id, horseId: saved.horseId)
            try applySpecialistReminders(s, saved, horseName: horseName, typeName: typeName)
            return (saved, nil)
        }
    }

    // MARK: Usuwanie i przywracanie

    /// Usuwa rekord wraz z zależnymi do kosza (jedna partia); `Cofnij` przywraca partię.
    public func delete(_ type: RecordType, id: String) -> RuleOutcome {
        run { s in
            if type == .contact, try Self.contactUsed(s, id) { throw s.conflict(.inUse, Messages.contactInUse) }
            let batch = try TrashRules.softDelete(s, type: type, id: id)
            return (nil, batch)
        }
    }

    public func restore(batchId: String) -> RuleOutcome {
        run { s in
            try TrashRules.restore(s, source: source, batchId: batchId)
            return (nil, batchId)
        }
    }

    /// Czy kontakt jest użyty (jako lekarz, kowal, organizator, dostawca, trener, jeździec…) przez jakikolwiek rekord, także z kosza.
    static func contactUsed(_ s: RuleSession, _ id: String) throws -> Bool {
        let source = s.sourceForDeepChecks
        func any(_ type: RecordType, _ match: (any LocalRecord) -> Bool) throws -> Bool {
            try source.query(type, horseId: nil, from: nil, to: nil, includeDeleted: true).contains { match($0.record) }
        }
        return try any(.vetVisit) { ($0 as? LocalVetVisit)?.contactId == id }
            || any(.farrierVisit) { ($0 as? LocalFarrierVisit)?.contactId == id }
            || any(.physioVisit) { ($0 as? LocalPhysioVisit)?.contactId == id }
            || any(.specialistVisit) { ($0 as? LocalSpecialistVisit)?.contactId == id }
            || any(.competition) { ($0 as? LocalCompetition)?.organizerContactId == id }
            || any(.competitionStart) { ($0 as? LocalCompetitionStart)?.riderContactId == id }
            || any(.purchase) { ($0 as? LocalPurchase)?.supplierContactId == id }
            || any(.training) { record in
                guard let training = record as? LocalTraining else { return false }
                return training.trainerContactId == id || training.riderContactId == id
            }
    }

    // MARK: Słowniki trybu samodzielnego

    /// Wstawia domyślne słowniki, gdy ich jeszcze nie ma (pierwsze uruchomienie w trybie samodzielnym).
    public func seedDictionaries() -> RuleOutcome {
        run { s in
            guard try s.records(.dictionary).isEmpty else { return (nil, nil) }
            for item in DefaultDictionaries.items(newId: s.newId, now: s.now) { try s.insert(item, primary: false) }
            return (nil, nil)
        }
    }
}
