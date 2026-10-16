import HorselyCore
import XCTest
@testable import Horsely

/// Logika formularzy wpisów bez interfejsu: układ pól (FormSpec) i pytanie o kontuzję przy treningu.
@MainActor
final class EntryFormLogicTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 10, day: 5)!
    private let now = LocalDateTime("2026-10-05T12:00:00")!

    func testEveryRequiredFieldIsVisibleWithoutMoreFields() {
        for kind in FormKind.allCases {
            let slots = FormSpec.sections(for: kind).flatMap(\.slots)
            for slot in slots where FormSpec.isRequired(slot.field, kind: kind) {
                XCTAssertFalse(slot.more, "\(kind): pole wymagane \(slot.field) nie może być pod „Więcej szczegółów”")
            }
        }
    }

    func testEveryFormHasABasicSectionFirst() {
        for kind in FormKind.allCases {
            XCTAssertEqual(FormSpec.sections(for: kind).first?.titleKey, "form_section_basic", "\(kind)")
        }
    }

    func testEveryFieldHasAnExistingLabelKey() {
        for kind in FormKind.allCases {
            for slot in FormSpec.sections(for: kind).flatMap(\.slots) {
                let key = slot.field.labelKey(for: kind)
                XCTAssertNotEqual(tr(key), key, "brak tekstu \(key)")
            }
            XCTAssertNotEqual(tr(kind.titleKey), kind.titleKey)
        }
    }

    func testTrainingForAnInjuredHorseAsksForConfirmation() {
        var injured = LocalHorse(id: "h", createdAt: now, updatedAt: now, name: "Pegaz", passportNumber: "PL-1")
        injured.status = .injured
        let training = EntryFormModel(kind: .training, horseId: "h", today: today, now: now)
        XCTAssertTrue(training.needsInjuryConfirmation(horses: [injured]))
        injured.status = .active
        XCTAssertFalse(training.needsInjuryConfirmation(horses: [injured]))
        let note = EntryFormModel(kind: .note, horseId: "h", today: today, now: now)
        injured.status = .injured
        XCTAssertFalse(note.needsInjuryConfirmation(horses: [injured]), "pytanie dotyczy tylko treningu")
    }

    func testANewFormStartsWithTodayAndIsNotDirty() {
        let model = EntryFormModel(kind: .note, horseId: nil, today: today, now: now)
        XCTAssertEqual(model.draft.date, today)
        XCTAssertFalse(model.isDirty)
        model.draft.title = "x"
        XCTAssertTrue(model.isDirty)
    }

    func testTheKindsOfTheNewEntryListAreTheCreatableOnes() {
        XCTAssertEqual(FormKind.creatable.count, 8)
        XCTAssertFalse(FormKind.creatable.contains(.competition))
    }
}
