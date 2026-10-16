import Foundation
import Testing
@testable import HorselyCore

/// Działy Treningi, Zakupy i Zawody (T097, US11; `ListPeriodTest`, `SectionViewModelsTest`, `PurchaseRepeatTest`).
struct SectionsTests {
    private let today = LocalDate(year: 2026, month: 10, day: 5)!
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 1, hour: 10)!

    private func day(_ month: Int, _ day: Int, year: Int = 2026) -> LocalDate { LocalDate(year: year, month: month, day: day)! }

    private func source() -> InMemoryRecordSource {
        let trainings = [
            LocalTraining(id: "t1", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", trainingDate: day(3, 1), trainingTypeId: "skoki",
                          riderContactId: "r1", trainerContactId: "tr1", cost: Money(string: "80.50")),
            LocalTraining(id: "t2", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h2", trainingDate: day(9, 20), trainingTypeId: "lonza",
                          cost: Money(40)),
            LocalTraining(id: "t3", createdAt: stamp, updatedAt: stamp, version: 1, horseId: "h1", trainingDate: day(12, 30, year: 2025), trainingTypeId: "skoki",
                          cost: Money(100)),
        ]
        let purchases = [
            LocalPurchase(id: "p1", createdAt: stamp, updatedAt: stamp, version: 1, purchaseDate: day(2, 1), productName: "Siano", categoryId: "pasza",
                          supplierContactId: "s1", totalAmount: Money(300), deliveryCost: Money(20), assignment: .general, horseIds: []),
            LocalPurchase(id: "p2", createdAt: stamp, updatedAt: stamp, version: 1, purchaseDate: day(8, 15), productName: "Derka", categoryId: "sprzet",
                          totalAmount: Money(string: "100.01")!, deliveryCost: .zero, assignment: .multipleHorses, horseIds: ["h1", "h2"], notes: "na zimę"),
        ]
        let competitions = [
            LocalCompetition(id: "c1", createdAt: stamp, updatedAt: stamp, version: 1, name: "Puchar", dateFrom: day(6, 1), dateTo: day(6, 2), disciplineId: "skoki"),
            LocalCompetition(id: "c2", createdAt: stamp, updatedAt: stamp, version: 1, name: "Jesień", dateFrom: day(11, 20)),
            LocalCompetition(id: "c3", createdAt: stamp, updatedAt: stamp, version: 1, name: "Sylwester", dateFrom: day(12, 31, year: 2025), dateTo: day(1, 1)),
        ]
        let starts = [
            LocalCompetitionStart(id: "s1", createdAt: stamp, updatedAt: stamp, version: 1, competitionId: "c1", horseId: "h1", placement: 3),
            LocalCompetitionStart(id: "s2", createdAt: stamp, updatedAt: stamp, version: 1, competitionId: "c1", horseId: "h2", placement: 1),
        ]
        let records: [any LocalRecord] = trainings + purchases + competitions + starts
        return InMemoryRecordSource(rows: records.map { SourceRow(record: $0, dateKey: $0.dateKey ?? ($0 as? LocalCompetitionStart).map { _ in self.day(6, 1) }) })
    }

    @Test func theDefaultPeriodIsTheWholeCurrentYear() {
        let period = ListPeriod.default(today: today)
        #expect(period.from == day(1, 1))
        #expect(period.to == day(12, 31))
        #expect(TrainingQuery(period: period).activeCount(today: today) == 0)
        var query = TrainingQuery(period: period, horseId: "h1")
        #expect(query.activeCount(today: today) == 1)
        // „Wyczyść filtry” wraca do okresu domyślnego.
        query = TrainingQuery(period: .default(today: today))
        #expect(query.activeCount(today: today) == 0)
    }

    @Test func trainingsOfAllHorsesNewestFirstWithCountAndTotal() throws {
        let list = try LocalSections(source: source()).trainings(TrainingQuery(period: .default(today: today)))
        #expect(list.items.map(\.id) == ["t2", "t1"])
        #expect(list.count == 2)
        #expect(list.total == Money(string: "120.50"))
        let filtered = try LocalSections(source: source()).trainings(TrainingQuery(period: .default(today: today), trainerId: "tr1"))
        #expect(filtered.items.map(\.id) == ["t1"])
        let rider = try LocalSections(source: source()).trainings(TrainingQuery(period: ListPeriod(from: nil, to: nil), riderId: "r1"))
        #expect(rider.items.map(\.id) == ["t1"])
    }

    @Test func purchasesWithScopeCategoryAndSupplierAndATotalWithDelivery() throws {
        let sections = LocalSections(source: source())
        let all = try sections.purchases(PurchaseQuery(period: .default(today: today)))
        #expect(all.items.map(\.id) == ["p2", "p1"])
        #expect(all.total == Money(string: "420.01"))
        #expect(try sections.purchases(PurchaseQuery(period: .default(today: today), scope: .general)).items.map(\.id) == ["p1"])
        #expect(try sections.purchases(PurchaseQuery(period: .default(today: today), scope: .horse("h2"))).items.map(\.id) == ["p2"])
        #expect(try sections.purchases(PurchaseQuery(period: .default(today: today), supplierId: "s1")).items.map(\.id) == ["p1"])
        #expect(try sections.purchases(PurchaseQuery(period: .default(today: today), categoryId: "sprzet")).total == Money(string: "100.01"))
    }

    @Test func competitionsOverlappingThePeriodWithStartsAndBestPlace() throws {
        let sections = LocalSections(source: source())
        let list = try sections.competitions(CompetitionQuery(period: .default(today: today)))
        #expect(list.map(\.id) == ["c2", "c1", "c3"], "zawody zaplanowane na później i nachodzące na początek roku też są")
        #expect(list[1].startsCount == 2)
        #expect(list[1].bestPlacement == 1)
        #expect(try sections.competitions(CompetitionQuery(period: .default(today: today), horseId: "h2")).map(\.id) == ["c1"])
        #expect(try sections.competitions(CompetitionQuery(period: .default(today: today), disciplineId: "skoki")).map(\.id) == ["c1"])
    }

    @Test func repeatingAPurchaseCopiesItWithTodaysDate() throws {
        let purchase = try #require(try source().records(.purchase, as: LocalPurchase.self).first { $0.id == "p2" })
        let input = PurchaseRepeat.from(purchase, today: today)
        #expect(input.purchaseDate == today)
        #expect(input.productName == "Derka")
        #expect(input.horseIds == ["h1", "h2"])
        #expect(input.assignment == .multipleHorses)
        #expect(input.totalAmount == Money(string: "100.01"))
        #expect(input.notes == "na zimę")
    }
}
