import Foundation

/// Dane formularza kontaktu (FR-M-KTK-03): nazwa, typy, firma, telefon, e‑mail, adres, specjalizacja, notatki.
public struct ContactInput: Codable, Equatable, Sendable {
    public var name: String
    public var types: [ContactType]
    public var company: String?
    public var phone: String?
    public var email: String?
    public var address: String?
    public var specialization: String?
    public var notes: String?

    public init(
        name: String = "", types: [ContactType] = [], company: String? = nil, phone: String? = nil, email: String? = nil, address: String? = nil,
        specialization: String? = nil, notes: String? = nil
    ) {
        self.name = name
        self.types = types
        self.company = company
        self.phone = phone
        self.email = email
        self.address = address
        self.specialization = specialization
        self.notes = notes
    }

    public init(contact: LocalContact) {
        self.init(
            name: contact.name, types: contact.types, company: contact.company, phone: contact.phone, email: contact.email, address: contact.address,
            specialization: contact.specialization, notes: contact.notes
        )
    }
}

/// Reguły kontaktów (`ContactRules.kt`, FR-M-KTK-01/03): wyszukiwanie, filtr typu bez zarchiwizowanych, walidacja formularza.
public enum ContactRules {
    public static let maxName = 200
    public static let maxCompany = 200
    public static let maxPhone = 30
    public static let maxEmail = 150
    public static let maxSpecialization = 200

    /// Lista kontaktów: bez zarchiwizowanych, z filtrem typu i wyszukiwaniem po nazwie, telefonie i e‑mailu (bez wielkości liter
    /// i polskich znaków), posortowana po nazwie po polsku.
    public static func search(_ contacts: [LocalContact], query: String, type: ContactType?) -> [LocalContact] {
        let key = Formats.searchKey(query)
        let digits = query.filter(\.isNumber)
        return contacts
            .filter { !$0.isArchived && (type == nil || $0.types.contains(type!)) }
            .filter { contact in
                guard !key.isEmpty else { return true }
                if Formats.searchKey(contact.name).contains(key) { return true }
                if let email = contact.email, Formats.searchKey(email).contains(key) { return true }
                if let phone = contact.phone {
                    if Formats.searchKey(phone).contains(key) { return true }
                    if !digits.isEmpty && phone.filter(\.isNumber).contains(digits) { return true }
                }
                return false
            }
            .sorted { PolishNames.compare($0.name, $1.name) == .orderedAscending }
    }

    /// Błędy przy polach (klucze jak w treści żądania).
    public static func validate(_ input: ContactInput) -> ValidationReport {
        var report = ValidationReport()
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            report.error("name", "Nazwa jest wymagana")
        } else if name.count > maxName {
            report.error("name", tooLong(maxName))
        }
        if input.types.isEmpty { report.error("types", "Wybierz co najmniej jeden typ") }
        for (field, value, limit) in [("company", input.company, maxCompany), ("phone", input.phone, maxPhone), ("email", input.email, maxEmail),
                                      ("specialization", input.specialization, maxSpecialization)] {
            if let value, value.trimmingCharacters(in: .whitespacesAndNewlines).count > limit { report.error(field, tooLong(limit)) }
        }
        return report
    }

    static func tooLong(_ max: Int) -> String { "Najwyżej \(max) znaków" }

    /// Pola puste lub z samych spacji nie są zapisywane; typy bez powtórzeń.
    public static func normalize(_ input: ContactInput) -> ContactInput {
        var types: [ContactType] = []
        for type in input.types where !types.contains(type) { types.append(type) }
        return ContactInput(
            name: input.name.trimmingCharacters(in: .whitespacesAndNewlines), types: types, company: HorseRules.clean(input.company),
            phone: HorseRules.clean(input.phone), email: HorseRules.clean(input.email), address: HorseRules.clean(input.address),
            specialization: HorseRules.clean(input.specialization), notes: HorseRules.clean(input.notes)
        )
    }
}

// MARK: - Zapis kontaktu w silniku reguł

extension RuleEngine {
    private func contact(_ s: RuleSession, _ input: ContactInput, id: String, old: LocalContact?) -> LocalContact {
        let clean = ContactRules.normalize(input)
        return LocalContact(
            id: id, createdAt: old?.createdAt ?? s.now, updatedAt: s.now, version: old?.version ?? 1, name: clean.name, types: clean.types,
            company: clean.company, phone: clean.phone, email: clean.email, address: clean.address, specialization: clean.specialization,
            notes: clean.notes, isArchived: old?.isArchived ?? false
        )
    }

    public func createContact(_ input: ContactInput) -> RuleOutcome {
        run { s in
            try s.check(ContactRules.validate(input))
            return (try s.insert(contact(s, input, id: s.newId(), old: nil), primary: true), nil)
        }
    }

    public func updateContact(id: String, _ input: ContactInput, expectedVersion: Int?) -> RuleOutcome {
        run { s in
            try s.check(ContactRules.validate(input))
            guard let old = try s.find(.contact, id, as: LocalContact.self) else { throw s.notFound("Contact", id) }
            try Self.requireVersion(s, current: old.version, expected: expectedVersion)
            return (try s.replace(old: old, with: contact(s, input, id: id, old: old), primary: true), nil)
        }
    }

    /// „Archiwizuj” / „Przywróć z archiwum” — kontakt znika z list wyboru, wpisy zachowują odwołanie.
    public func setContactArchived(id: String, _ archived: Bool) -> RuleOutcome {
        run { s in
            guard let old = try s.find(.contact, id, as: LocalContact.self) else { throw s.notFound("Contact", id) }
            var updated = old
            updated.isArchived = archived
            updated = updated.withAudit(version: old.version, updatedAt: s.now)
            return (try s.replace(old: old, with: updated, primary: true), nil)
        }
    }
}
