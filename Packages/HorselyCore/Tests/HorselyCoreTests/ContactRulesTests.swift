import Foundation
import Testing
@testable import HorselyCore

/// Kontakty (T098, FR-M-KTK-01/03; `ContactsViewModelTest`, `ContactFormViewModelTest`).
struct ContactRulesTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 1, hour: 10)!

    private func contact(_ id: String, _ name: String, types: [ContactType], phone: String? = nil, email: String? = nil, archived: Bool = false) -> LocalContact {
        LocalContact(id: id, createdAt: stamp, updatedAt: stamp, version: 1, name: name, types: types, phone: phone, email: email, isArchived: archived)
    }

    private var contacts: [LocalContact] {
        [
            contact("1", "Żaneta Kowalska", types: [.trainer], phone: "+48 600 100 200", email: "zaneta@stajnia.pl"),
            contact("2", "Adam Łoś", types: [.rider]),
            contact("3", "Weterynarz Nowak", types: [.vet], phone: "601-222-333"),
            contact("4", "Stary Kowal", types: [.farrier], archived: true),
        ]
    }

    @Test func searchFindsByNamePhoneAndEmailIgnoringCaseAndPolishLetters() {
        #expect(ContactRules.search(contacts, query: "zaneta", type: nil).map(\.id) == ["1"])
        #expect(ContactRules.search(contacts, query: "LOS", type: nil).map(\.id) == ["2"])
        #expect(ContactRules.search(contacts, query: "600100", type: nil).map(\.id) == ["1"])
        #expect(ContactRules.search(contacts, query: "222 333", type: nil).map(\.id) == ["3"])
        #expect(ContactRules.search(contacts, query: "@stajnia", type: nil).map(\.id) == ["1"])
    }

    @Test func theTypeFilterSkipsArchivedContactsAndTheListIsSortedInPolish() {
        #expect(ContactRules.search(contacts, query: "", type: nil).map(\.id) == ["2", "3", "1"])
        #expect(ContactRules.search(contacts, query: "", type: .trainer).map(\.id) == ["1"])
        #expect(ContactRules.search(contacts, query: "kowal", type: .farrier).isEmpty)
    }

    @Test func theFormNeedsANameAndAType() {
        let empty = ContactRules.validate(ContactInput(name: "  "))
        #expect(empty.errors["name"] == ["Nazwa jest wymagana"])
        #expect(empty.errors["types"] == ["Wybierz co najmniej jeden typ"])
        let long = ContactRules.validate(ContactInput(name: "A", types: [.vet], phone: String(repeating: "1", count: 31)))
        #expect(long.errors["phone"] == ["Najwyżej 30 znaków"])
        #expect(!ContactRules.validate(ContactInput(name: "Anna", types: [.trainer])).hasErrors)
    }

    @Test func blankFieldsAreNotStored() {
        let clean = ContactRules.normalize(ContactInput(name: " Anna ", types: [.trainer, .trainer, .rider], company: " ", phone: " 600 "))
        #expect(clean.name == "Anna")
        #expect(clean.types == [.trainer, .rider])
        #expect(clean.company == nil)
        #expect(clean.phone == "600")
    }

    @Test func aContactUsedAsATrainerCannotBeDeletedButCanBeArchived() throws {
        let training = LocalTraining(
            id: "t1", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", trainingDate: LocalDate(year: 2026, month: 10, day: 1)!,
            trainingTypeId: "d1", trainerContactId: "1"
        )
        let source = InMemoryRecordSource(rows: [SourceRow(record: contacts[0], dateKey: nil), SourceRow(record: training, dateKey: training.dateKey)])
        let engine = RuleEngine(source: source, dates: FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 5)!))
        guard case let .conflict(reason, _)? = engine.delete(.contact, id: "1").problem else { Issue.record("brak odmowy"); return }
        #expect(reason == .inUse)
        let archived = try #require(engine.setContactArchived(id: "1", true).saved?.record as? LocalContact)
        #expect(archived.isArchived)
    }

    @Test func aNewContactIsSavedWithCleanFields() throws {
        let engine = RuleEngine(source: InMemoryRecordSource(), dates: FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 5)!), newId: { "c-new" })
        let saved = try #require(engine.createContact(ContactInput(name: " Anna ", types: [.trainer], email: " ")).saved?.record as? LocalContact)
        #expect(saved.id == "c-new")
        #expect(saved.name == "Anna")
        #expect(saved.email == nil)
        guard case .validation? = engine.createContact(ContactInput(name: "", types: [])).problem else { Issue.record("brak błędów"); return }
    }
}
