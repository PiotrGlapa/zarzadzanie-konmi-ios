import Foundation
import Testing
@testable import HorselyCore

/// Podpowiedzi formularzy (T055): kowal, kwota zakupu, trening, termin → formularz.
struct SuggestionsTests {
    private let stamp = LocalDateTime("2026-09-28T10:00:00")!

    private func date(_ text: String) -> LocalDate { LocalDate(text)! }

    // MARK: Następna wizyta kowala

    @Test func theFarrierDateComesFromTheProgramWhenOnline() {
        #expect(FarrierNextDate.suggest(online: date("2026-11-10"), visitDate: date("2026-09-28"), intervalWeeks: 6) == date("2026-11-10"))
    }

    @Test func offlineTheFarrierDateIsTheVisitPlusTheHorseInterval() {
        #expect(FarrierNextDate.suggest(visitDate: date("2026-09-28"), intervalWeeks: 6) == date("2026-11-09"))
        #expect(FarrierNextDate.suggest(visitDate: date("2026-09-28"), intervalWeeks: 1) == date("2026-10-05"))
    }

    @Test func withoutAnIntervalThereIsNoFarrierSuggestion() {
        #expect(FarrierNextDate.suggest(visitDate: date("2026-09-28"), intervalWeeks: nil) == nil)
        #expect(FarrierNextDate.suggest(visitDate: date("2026-09-28"), intervalWeeks: 0) == nil)
    }

    // MARK: Kwota zakupu

    @Test func theAmountIsQuantityTimesPriceRoundedHalfUp() {
        #expect(PurchaseAmount.suggest(quantity: Money(string: "2.5"), unitPrice: Money(string: "10.10")) == Money(string: "25.25"))
        #expect(PurchaseAmount.suggest(quantity: Money(string: "0.5"), unitPrice: Money(string: "0.01")) == Money(string: "0.01"))
        #expect(PurchaseAmount.suggest(quantity: Money(string: "3"), unitPrice: nil) == nil)
        #expect(PurchaseAmount.suggest(quantity: nil, unitPrice: Money(string: "3")) == nil)
    }

    @Test func theTotalAddsTheDelivery() {
        #expect(PurchaseAmount.total(amount: Money(string: "42.42"), delivery: Money(string: "7.58")) == Money(50))
        #expect(PurchaseAmount.total(amount: Money(10), delivery: nil) == Money(10))
        #expect(PurchaseAmount.total(amount: nil, delivery: Money(10)) == nil)
    }

    @Test func aManualAmountSwitchesTheSuggestionOff() {
        var suggestion = AmountSuggestion()
        #expect(suggestion.apply(current: "", quantity: "2", unitPrice: "12,50") == "25,00")
        #expect(suggestion.apply(current: "25,00", quantity: "3", unitPrice: "12,50") == "37,50")
        suggestion.onManualEdit()
        #expect(suggestion.apply(current: "99,00", quantity: "4", unitPrice: "12,50") == "99,00")
    }

    @Test func anIncompleteQuantityOrPriceLeavesTheField() {
        let suggestion = AmountSuggestion()
        #expect(suggestion.apply(current: "5,00", quantity: "2", unitPrice: "") == "5,00")
        #expect(suggestion.apply(current: "5,00", quantity: "abc", unitPrice: "3") == "5,00")
    }

    // MARK: Trening

    private func contact(_ id: String, _ types: [ContactType], archived: Bool = false) -> LocalContact {
        LocalContact(id: id, createdAt: stamp, updatedAt: stamp, name: id, types: types, isArchived: archived)
    }

    private func training(_ id: String, _ day: String, trainer: String? = nil, rider: String? = nil, cost: Money? = nil, at: String = "2026-09-28T10:00:00") -> LocalTraining {
        LocalTraining(
            id: id, createdAt: LocalDateTime(at)!, updatedAt: stamp, horseId: "h", trainingDate: date(day), trainingTypeId: "t",
            riderContactId: rider, trainerContactId: trainer, cost: cost, originalAmount: cost == nil ? nil : Money(5), originalCurrency: cost == nil ? nil : "EUR"
        )
    }

    @Test func theLatestTrainingGivesTheDefaults() {
        let latest = training("a", "2026-09-20", trainer: "tr", rider: "ri", cost: Money(80))
        let defaults = TrainingSuggestions.defaults(from: latest, contacts: [contact("tr", [.trainer]), contact("ri", [.rider])])
        #expect(defaults == TrainingDefaults(trainerContactId: "tr", riderContactId: "ri", cost: Money(80), originalAmount: Money(5), originalCurrency: "EUR"))
    }

    @Test func anArchivedMissingOrWrongTypeContactIsNotSuggested() {
        let latest = training("a", "2026-09-20", trainer: "tr", rider: "ri")
        #expect(TrainingSuggestions.defaults(from: latest, contacts: [contact("tr", [.trainer], archived: true), contact("ri", [.vet])]) == TrainingDefaults())
        #expect(TrainingSuggestions.defaults(from: latest, contacts: []) == TrainingDefaults())
        #expect(TrainingSuggestions.defaults(from: nil, contacts: []) == TrainingDefaults())
    }

    @Test func theLatestIsByDateThenByCreation() {
        let older = training("o", "2026-09-10")
        let sameDayEarlier = training("e", "2026-09-20", at: "2026-09-20T08:00:00")
        let sameDayLater = training("l", "2026-09-20", at: "2026-09-20T09:00:00")
        #expect(TrainingSuggestions.latest([older, sameDayLater, sameDayEarlier])?.id == "l")
        #expect(TrainingSuggestions.latest([]) == nil)
    }

    @Test func changingTheHorseKeepsManuallyEditedFields() {
        let current = TrainingDefaults(trainerContactId: "mine", riderContactId: "r1", cost: Money(10), originalAmount: nil, originalCurrency: nil)
        let fresh = TrainingDefaults(trainerContactId: "t2", riderContactId: "r2", cost: Money(99), originalAmount: Money(20), originalCurrency: "EUR")
        let merged = TrainingSuggestions.apply(current: current, defaults: fresh, edited: [.trainer, .cost])
        #expect(merged.trainerContactId == "mine")
        #expect(merged.riderContactId == "r2")
        #expect(merged.cost == Money(10))
        #expect(merged.originalAmount == nil && merged.originalCurrency == nil)
    }

    // MARK: Termin → formularz

    @Test func eachReminderKindOpensItsForm() {
        let expected: [ReminderKind: EntryForm] = [
            .vet: .vetVisit, .vaccination: .vetVisit, .deworming: .vetVisit, .farrier: .farrierVisit, .physio: .physioVisit,
            .specialist: .specialistVisit, .competition: .competitionStart, .other: .note,
        ]
        for kind in ReminderKind.allCases { #expect(ReminderFormMapping.form(for: kind) == expected[kind], "\(kind)") }
    }
}
