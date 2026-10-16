import Foundation
import Testing
@testable import HorselyCore

/// Walidacja pól wpisów (T054): komunikaty i klucze pól jak w programie.
struct EntryValidationTests {
    private let today = LocalDate("2026-09-28")!

    private func date(_ text: String) -> LocalDate { LocalDate(text)! }

    @Test func aVetVisitNeedsHorseDateAndKind() {
        let report = EntryValidation.vet(VetVisitInput())
        #expect(report.errors["horseId"] == [Messages.required])
        #expect(report.errors["visitDateTime"] == [Messages.required])
        #expect(report.errors["visitTypeId"] == [Messages.required])
    }

    @Test func theNextVisitMustBeLaterThanTheVisit() {
        var input = FarrierVisitInput()
        input.horseId = "h"; input.serviceId = "s"; input.visitDate = date("2026-09-28")
        input.nextVisitDate = date("2026-09-28")
        #expect(EntryValidation.farrier(input).errors["nextVisitDate"] == [Messages.nextVisitAfterVisit])
        input.nextVisitDate = date("2026-09-29")
        #expect(EntryValidation.farrier(input).errors["nextVisitDate"] == nil)
    }

    @Test func medicationsAreCheckedWithIndexedFieldNames() {
        var input = VetVisitInput()
        input.horseId = "h"; input.visitTypeId = "t"; input.visitDateTime = LocalDateTime("2026-09-28T10:00:00")
        input.medications = [
            VetMedicationInput(name: "Lek", startDate: date("2026-09-25"), endDate: date("2026-09-20")),
            VetMedicationInput(name: "  "),
        ]
        let report = EntryValidation.vet(input)
        #expect(report.errors["medications[0].endDate"] == [Messages.medicationEndBeforeStart])
        #expect(report.errors["medications[1].name"] == [Messages.required])
    }

    @Test func aForeignAmountNeedsBothPartsAndANonPlnCode() {
        var input = PhysioVisitInput()
        input.horseId = "h"; input.visitDate = date("2026-09-28")
        input.originalAmount = Money(10)
        #expect(EntryValidation.physio(input).errors["originalCurrency"] == [Messages.foreignAmountIncomplete])
        input.originalCurrency = "eur"
        #expect(EntryValidation.physio(input).errors["originalCurrency"] == [Messages.currencyFormat])
        input.originalCurrency = "PLN"
        #expect(EntryValidation.physio(input).errors["originalCurrency"] == [Messages.currencyNotPln])
        input.originalCurrency = "EUR"
        #expect(!EntryValidation.physio(input).hasErrors)
        input.originalAmount = nil
        #expect(EntryValidation.physio(input).errors["originalAmount"] == [Messages.foreignAmountIncomplete])
    }

    @Test func aSpecialistVisitNeedsTheSpecialistType() {
        var input = SpecialistVisitInput()
        input.horseId = "h"; input.visitDate = date("2026-09-28")
        #expect(EntryValidation.specialist(input).errors["specialistTypeId"] == [Messages.required])
    }

    @Test func aPurchaseNeedsAPositiveSumAndTheRightHorses() {
        var input = PurchaseInput()
        input.purchaseDate = date("2026-09-28"); input.productName = "Wiadra"; input.categoryId = "c"; input.assignment = .general
        #expect(EntryValidation.purchase(input).errors["totalAmount"] == [Messages.amountPositive])
        input.totalAmount = Money(10)
        #expect(!EntryValidation.purchase(input).hasErrors)
        input.horseIds = ["a"]
        #expect(EntryValidation.purchase(input).errors["horseIds"] == [Messages.purchaseGeneralHorses])
        input.assignment = .singleHorse
        input.horseIds = ["a", "b"]
        #expect(EntryValidation.purchase(input).errors["horseIds"] == [Messages.purchaseSingleHorse])
        input.assignment = .multipleHorses
        input.horseIds = ["a"]
        #expect(EntryValidation.purchase(input).errors["horseIds"] == [Messages.purchaseMultipleHorses])
        input.horseIds = ["a", "a"]
        #expect(EntryValidation.purchase(input).errors["horseIds"]?.contains(Messages.batchHorsesDuplicated) == true)
    }

    @Test func aDeliveryOnlyPurchaseIsValid() {
        var input = PurchaseInput()
        input.purchaseDate = date("2026-09-28"); input.productName = "Dostawa"; input.categoryId = "c"; input.assignment = .general
        input.deliveryCost = Money(15)
        #expect(!EntryValidation.purchase(input).hasErrors)
    }

    @Test func moneyHasAtMostTwoDecimalPlaces() {
        var input = PurchaseInput()
        input.purchaseDate = date("2026-09-28"); input.productName = "Siano"; input.categoryId = "c"; input.assignment = .general
        input.totalAmount = Money(string: "10.005")
        #expect(EntryValidation.purchase(input).errors["totalAmount"] == [Messages.moneyInvalid])
    }

    @Test func aNoteNeedsAHorseAndATitle() {
        var input = NoteInput()
        let report = EntryValidation.note(input)
        #expect(report.errors["horseId"] == [Messages.required])
        #expect(report.errors["title"] == [Messages.required])
        input.horseId = "h"; input.title = String(repeating: "a", count: 201)
        #expect(EntryValidation.note(input).errors["title"] == [Messages.maxLength(200)])
    }

    @Test func aTrainingCannotBeInTheFutureOrOutOfRange() {
        var input = TrainingInput()
        input.horseId = "h"; input.trainingTypeId = "t"; input.trainingDate = date("2026-09-29")
        input.durationMinutes = 601; input.obstacleHeightCm = 5; input.rating = 6
        let report = EntryValidation.training(input, today: today)
        #expect(report.errors["trainingDate"] == [Messages.trainingDateInFuture])
        #expect(report.errors["durationMinutes"] == [Messages.trainingDurationRange])
        #expect(report.errors["obstacleHeightCm"] == [Messages.obstacleHeightRange])
        #expect(report.errors["rating"] == [Messages.ratingRange])
        input.trainingDate = today; input.durationMinutes = 45; input.obstacleHeightCm = 120; input.rating = 4
        #expect(!EntryValidation.training(input, today: today).hasErrors)
    }

    @Test func coachingCostsAreCheckedWithThePrefix() {
        var input = TrainingInput()
        input.horseId = "h"; input.trainingTypeId = "t"; input.trainingDate = today
        input.coaching = TrainingCoachingInput(cost: Money(string: "10.001"), originalAmount: Money(5))
        let report = EntryValidation.training(input, today: today)
        #expect(report.errors["coaching.cost"] == [Messages.moneyInvalid])
        #expect(report.errors["coaching.originalCurrency"] == [Messages.foreignAmountIncomplete])
    }

    @Test func aReminderOfTheSpecialistKindNeedsTheType() {
        var input = ReminderInput()
        input.horseId = "h"; input.dueDate = date("2026-10-01"); input.title = "Zęby"; input.kind = .specialist
        #expect(EntryValidation.reminder(input).errors["specialistTypeId"] == [Messages.specialistTypeRequired])
        input.kind = .other
        #expect(!EntryValidation.reminder(input).hasErrors)
        input.title = "   "
        #expect(EntryValidation.reminder(input).errors["title"] == [Messages.required])
    }

    @Test func aCompetitionEndsNotBeforeItStarts() {
        var input = CompetitionInput()
        input.name = "Puchar"; input.dateFrom = date("2026-10-10"); input.dateTo = date("2026-10-09")
        #expect(EntryValidation.competition(input).errors["dateTo"] == [Messages.dateToBeforeFrom])
        input.dateTo = date("2026-10-11")
        #expect(!EntryValidation.competition(input).hasErrors)
    }

    @Test func aPlacementMeansACompletedStart() {
        var input = CompetitionStartInput()
        input.horseId = "h"; input.placement = 3
        #expect(!EntryValidation.start(input).hasErrors)
        #expect(EntryValidation.normalizedStatus(input) == .completed)
        input.resultStatus = .eliminated
        #expect(EntryValidation.start(input).errors["placement"] == [Messages.placementOnlyCompleted])
        input.resultStatus = .completed
        input.participantsCount = 2
        #expect(EntryValidation.start(input).errors["participantsCount"] == [Messages.participantsBelowPlacement])
    }

    @Test func startResultsHaveTheirRanges() {
        var input = CompetitionStartInput()
        input.horseId = "h"
        input.scorePercent = Money(101); input.timeSeconds = Money.zero; input.subjectiveRating = 0
        let report = EntryValidation.start(input)
        #expect(report.errors["scorePercent"] == [Messages.percentRange])
        #expect(report.errors["timeSeconds"] == [Messages.positiveNumber])
        #expect(report.errors["subjectiveRating"] == [Messages.ratingRange])
    }
}
