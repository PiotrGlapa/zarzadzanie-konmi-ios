import Foundation
import Testing
@testable import HorselyCore

/// Zamiana pól formularza na treść zapisu i z powrotem (draft ↔ `*Input`).
struct EntryDraftTests {
    private let day = LocalDate("2026-10-05")!
    private let stamp = LocalDateTime("2026-10-05T10:00:00")!

    @Test func aVetDraftBuildsTheDateTimeMoneyAndSkipsEmptyMedications() {
        var draft = EntryDraft()
        draft.horseId = "h"; draft.date = day; draft.hour = 9; draft.minute = 30; draft.visitTypeId = "t"
        draft.cost = "1 250,5"; draft.originalCurrency = " eur "
        draft.medications = [MedicationDraft(), {
            var medication = MedicationDraft()
            medication.name = " Banamina "
            medication.administration = .prescribed
            return medication
        }()]
        let built = draft.vetInput()
        #expect(built.parseErrors.isEmpty)
        #expect(built.input.visitDateTime == LocalDateTime("2026-10-05T09:30:00"))
        #expect(built.input.cost == Money(string: "1250.50"))
        #expect(built.input.originalCurrency == "EUR")
        #expect(built.input.medications?.map(\.name) == ["Banamina"])
    }

    @Test func anUnreadableAmountIsReportedAtItsField() {
        var draft = EntryDraft()
        draft.cost = "abc"; draft.originalAmount = "10,001"
        let built = draft.farrierInput()
        #expect(built.parseErrors["cost"] == [MoneyParse.Reason.notANumber.message])
        #expect(built.parseErrors["originalAmount"] == [MoneyParse.Reason.tooManyDecimals.message])
    }

    @Test func aPurchaseUsesTheHorsesOfItsAssignment() {
        var draft = EntryDraft()
        draft.horseId = "a"; draft.horseIds = ["b", "c"]; draft.amount = "10"
        draft.assignment = .singleHorse
        #expect(draft.purchaseInput().input.horseIds == ["a"])
        draft.assignment = .multipleHorses
        #expect(draft.purchaseInput().input.horseIds == ["b", "c"])
        draft.assignment = .general
        #expect(draft.purchaseInput().input.horseIds == [])
        #expect(draft.purchaseInput().input.deliveryCost == .zero)
    }

    @Test func theObstacleHeightIsSentOnlyForJumping() {
        var draft = EntryDraft()
        draft.horseId = "h"; draft.obstacleHeight = "120"; draft.duration = "45"
        #expect(draft.trainingInput(isJumping: true).input.obstacleHeightCm == 120)
        #expect(draft.trainingInput(isJumping: false).input.obstacleHeightCm == nil)
        #expect(draft.trainingInput(isJumping: false).input.durationMinutes == 45)
        draft.duration = "x"
        #expect(draft.trainingInput(isJumping: false).parseErrors["durationMinutes"] == [Messages.invalidValue])
    }

    @Test func aTrainingAlwaysCarriesTheCoachingObject() {
        var draft = EntryDraft()
        draft.trainerId = "tr"; draft.cost = "80"
        let coaching = draft.trainingInput(isJumping: false).input.coaching
        #expect(coaching?.trainerContactId == "tr" && coaching?.cost == Money(80))
    }

    @Test func aRecordRoundTripsThroughTheDraft() {
        let purchase = LocalPurchase(
            id: "p", createdAt: stamp, updatedAt: stamp, version: 1, purchaseDate: day, productName: "Siano", categoryId: "c", supplierContactId: nil,
            quantity: Money(string: "2.5"), unitId: "u", unitPrice: Money(string: "10.1"), totalAmount: Money(string: "25.25")!, deliveryCost: Money(5),
            assignment: .multipleHorses, horseIds: ["a", "b"], notes: "Uwaga", originalAmount: nil, originalCurrency: nil
        )
        let draft = EntryDraft(purchase: purchase)
        #expect(draft.quantity == "2,5" && draft.unitPrice == "10,1" && draft.amount == "25,25" && draft.deliveryCost == "5,00")
        let input = draft.purchaseInput().input
        #expect(input == PurchaseInput(purchase: purchase))
    }

    @Test func aStartKeepsItsResultFields() {
        let start = LocalCompetitionStart(
            id: "s", createdAt: stamp, updatedAt: stamp, version: 1, competitionId: "c", horseId: "h", startDate: day, className: "L", placement: 2,
            participantsCount: 15, resultStatus: .completed, scorePercent: Money(string: "68.5"), subjectiveRating: 4, entryFee: Money(50)
        )
        let built = EntryDraft(start: start).startInput()
        #expect(built.parseErrors.isEmpty)
        #expect(built.input.placement == 2 && built.input.participantsCount == 15)
        #expect(built.input.scorePercent == Money(string: "68.5"))
        #expect(built.input.subjectiveRating == 4 && built.input.entryFee == Money(50))
    }
}
