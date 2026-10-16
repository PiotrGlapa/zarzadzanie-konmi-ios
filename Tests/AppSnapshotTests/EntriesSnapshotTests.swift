import HorselyCore
import HorselyKit
import SwiftUI
import XCTest
@testable import Horsely

/// Dane wpisów do zrzutów (dziś 2026-10-05): wizyty z terminami (przeterminowany, nadchodzący, później), szczepienie, zakupy w tym i
/// poprzednim miesiącu, trening na skokach, notatka i start w zawodach.
@MainActor
enum SnapshotEntries {
    struct SeedError: Error {}

    static func seed(_ env: AppEnvironment) async throws -> [LocalHorse] {
        let horses = try await SnapshotHorses.seed(env)
        try await env.entries.seedDictionariesIfNeeded()
        let dictionary = try await env.entries.allDictionaryItems()
        func id(_ type: DictionaryType, _ name: String) throws -> String {
            guard let item = dictionary.first(where: { $0.dictionaryType == type && $0.value == name }) else { throw SeedError() }
            return item.id
        }
        func day(_ text: String) throws -> LocalDate {
            guard let date = LocalDate(text) else { throw SeedError() }
            return date
        }
        guard let grom = horses.first(where: { $0.name == "Grom" })?.id, let iskra = horses.first(where: { $0.name == "Iskra" })?.id else { throw SeedError() }

        var vet = VetVisitInput()
        vet.horseId = grom
        vet.visitDateTime = LocalDateTime("2026-09-28T10:00:00")
        vet.visitTypeId = try id(.vetVisitType, "Kontrola")
        vet.reason = "Kontrola po kuciu"
        vet.cost = Money(250)
        vet.nextVisitDate = try day("2026-10-08")
        let vetInput = vet
        _ = try await env.entries.perform { $0.createVetVisit(vetInput) }

        var vaccination = VetVisitInput()
        vaccination.horseId = grom
        vaccination.visitDateTime = LocalDateTime("2026-09-20T09:00:00")
        vaccination.visitTypeId = try id(.vetVisitType, "Szczepienie")
        vaccination.vaccineOrProduct = "Equilis Prequenza"
        vaccination.batchNumber = "A123"
        vaccination.nextVisitDate = try day("2027-03-20")
        let vaccinationInput = vaccination
        _ = try await env.entries.perform { $0.createVetVisit(vaccinationInput) }

        var farrier = FarrierVisitInput()
        farrier.horseId = iskra
        farrier.visitDate = try day("2026-09-20")
        farrier.serviceId = try id(.farrierService, "Korekcja")
        farrier.cost = Money(180)
        farrier.nextVisitDate = try day("2026-10-03")
        let farrierInput = farrier
        _ = try await env.entries.perform { $0.createFarrierVisit(farrierInput) }

        var reminder = ReminderInput()
        reminder.horseId = grom
        reminder.kind = .other
        reminder.dueDate = try day("2026-10-20")
        reminder.title = "Wizyta dentysty"
        let reminderInput = reminder
        _ = try await env.entries.perform { $0.createReminder(reminderInput) }

        for (date, product, amount) in [("2026-10-02", "Siano", 300), ("2026-09-15", "Owies", 120)] {
            var purchase = PurchaseInput()
            purchase.purchaseDate = try day(date)
            purchase.productName = product
            purchase.categoryId = try id(.purchaseCategory, "Pasza")
            purchase.assignment = .general
            purchase.totalAmount = Money(amount)
            let input = purchase
            _ = try await env.entries.perform { $0.createPurchase(input) }
        }

        var training = TrainingInput()
        training.horseId = grom
        training.trainingDate = try day("2026-10-01")
        training.trainingTypeId = try id(.trainingType, "Skoki")
        training.durationMinutes = 75
        training.intensity = .medium
        training.obstacleHeightCm = 110
        training.rating = 4
        training.coaching = TrainingCoachingInput(cost: Money(120))
        let trainingInput = training
        _ = try await env.entries.perform { $0.createTraining(trainingInput) }

        var note = NoteInput()
        note.horseId = grom
        note.noteDate = try day("2026-10-03")
        note.title = "Kuleje na lewą przednią"
        note.content = "Obserwować przez tydzień."
        let noteInput = note
        _ = try await env.entries.perform { $0.createNote(noteInput) }

        var competition = CompetitionInput()
        competition.name = "Puchar Jesieni"
        competition.dateFrom = try day("2026-09-27")
        competition.city = "Warszawa"
        let competitionInput = competition
        let created = try await env.entries.perform { $0.createCompetition(competitionInput) }
        guard let competitionId = created.saved?.record?.id else { throw SeedError() }
        var start = CompetitionStartInput()
        start.horseId = grom
        start.className = "L"
        start.placement = 2
        start.participantsCount = 15
        start.entryFee = Money(100)
        start.prizeMoney = Money(300)
        start.subjectiveRating = 4
        let startInput = start
        _ = try await env.entries.perform { $0.createCompetitionStart(competitionId: competitionId, startInput) }
        return horses
    }
}

/// Testy migawkowe wpisów (T070): Pulpit, formularz weterynarza, Terminy i zakładki karty konia; jasny / ciemny / tekst 200 %.
@MainActor
final class EntriesSnapshotTests: XCTestCase {
    private func environment(_ variant: SnapshotVariant) async throws -> (AppEnvironment, [LocalHorse]) {
        let env = makeEnvironment(mode: .standalone, variant: variant)
        let horses = try await SnapshotEntries.seed(env)
        return (env, horses)
    }

    func testDashboardWithRemindersCostsAndRecentEntries() async throws {
        for variant in SnapshotVariant.allCases {
            let (env, _) = try await environment(variant)
            let dashboard = try await env.entries.dashboard()
            await assertSettledScreen(DashboardView(preloaded: dashboard).environment(env), name: "dashboard-full", variant: variant)
        }
    }

    func testVetForm() async throws {
        for variant in SnapshotVariant.allCases {
            let (env, horses) = try await environment(variant)
            let model = EntryFormModel(kind: .vet, horseId: horses.first?.id, today: env.dates.today(), now: LocalDateTime("2026-10-05T12:00:00")!)
            await model.load(using: env)
            assertScreen(EntryFormView(model: model) { _, _ in }.environment(env), name: "vet-form", variant: variant)
        }
    }

    func testReminders() async throws {
        for variant in SnapshotVariant.allCases {
            let (env, _) = try await environment(variant)
            let items = try await env.reminders.reminders(ReminderFilter())
            assertScreen(RemindersView(preloaded: items).environment(env), name: "reminders", variant: variant)
        }
    }

    func testHorseCardTabs() async throws {
        let tabs: [(HorseCardView.CardTab, String)] = [
            (.timeline, "timeline"), (.reminders, "reminders"), (.passport, "passport"), (.trainings, "trainings"),
            (.competitions, "competitions"), (.purchases, "purchases"),
        ]
        for variant in SnapshotVariant.allCases {
            let (env, horses) = try await environment(variant)
            let grom = try XCTUnwrap(horses.first { $0.name == "Grom" })
            for (tab, name) in tabs {
                await assertSettledScreen(
                    NavigationStack { HorseCardView(horseId: grom.id, initialTab: tab) }.environment(env), name: "horse-tab-\(name)", variant: variant,
                    testName: "testHorseCardTabs.\(name)"
                )
            }
        }
    }
}
