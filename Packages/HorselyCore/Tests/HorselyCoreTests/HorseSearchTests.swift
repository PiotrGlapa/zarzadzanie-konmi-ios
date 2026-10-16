import Foundation
import Testing
@testable import HorselyCore

/// Lista koni (T039, FR-M-KON-01): wyszukiwanie, filtry statusu, „Tylko źrebięta” i sortowanie po polsku (`HorseSearchTest`).
struct HorseSearchTests {
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 5, hour: 10)!

    private func horse(_ name: String, stable: String? = nil, passport: String? = nil, foal: Bool = false, status: HorseStatus = .active, usesDefaultPassport: Bool = true) -> LocalHorse {
        LocalHorse(
            id: name, createdAt: stamp, updatedAt: stamp, version: 1, name: name, passportNumber: usesDefaultPassport ? (passport ?? "PL-\(name)") : passport,
            isFoal: foal, stableName: stable, status: status
        )
    }

    private var horses: [LocalHorse] {
        [
            horse("Grom", stable: "Gromek"),
            horse("Źrebię", foal: true, usesDefaultPassport: false),
            horse("Ćma"),
            horse("Burza", status: .sold),
            horse("Antek", foal: true),
            horse("Łoś", status: .deceased),
            horse("Pegaz", status: .injured),
        ]
    }

    private func names(_ query: String = "", _ filter: HorseListFilter = .inStable, foals: Bool = false) -> [String] {
        HorseSearch.apply(horses, query: query, filter: filter, onlyFoals: foals).map(\.name)
    }

    @Test func byDefaultOnlyHorsesInTheStableAreListedSortedByPolishName() {
        #expect(names() == ["Antek", "Ćma", "Grom", "Pegaz", "Źrebię"])
    }

    @Test func searchFindsByNameStableNameAndPassport() {
        #expect(names("grom") == ["Grom"])
        #expect(names("gromek") == ["Grom"])
        #expect(names("pl-antek") == ["Antek"])
    }

    @Test func searchIgnoresCaseAndPolishLetters() {
        #expect(names("zrebie") == ["Źrebię"])
        #expect(names("CMA") == ["Ćma"])
        #expect(names("ŹREBIĘ") == ["Źrebię"])
    }

    @Test func showAllAddsSoldAndDeceasedHorses() {
        #expect(names("", .all) == ["Antek", "Burza", "Ćma", "Grom", "Łoś", "Pegaz", "Źrebię"])
    }

    @Test func statusChipsNarrowToOneStatus() {
        #expect(names("", .active) == ["Antek", "Ćma", "Grom", "Źrebię"])
        #expect(names("", .injured) == ["Pegaz"])
    }

    @Test func onlyFoalsNarrowsTheListAndCombinesWithTheOthers() {
        #expect(names("", .inStable, foals: true) == ["Antek", "Źrebię"])
        #expect(names("zrebie", .inStable, foals: true) == ["Źrebię"])
        #expect(names("grom", .inStable, foals: true).isEmpty)
        #expect(names("", .all, foals: true) == ["Antek", "Źrebię"])
    }

    @Test func aQueryThatMatchesNothingGivesAnEmptyListAndABlankQueryListsEveryone() {
        #expect(names("nieistniejący").isEmpty)
        #expect(names("   ") == names())
    }

    @Test func sortingPutsPolishLettersAfterTheirBaseLetters() {
        let list = ["Zefir", "Żółtko", "Ósemka", "Olek", "Łabędź", "Lord", "Ćma", "Cezar"].map { horse($0) }
        let sorted = HorseSearch.apply(list, query: "", filter: .all).map(\.name)
        #expect(sorted == ["Cezar", "Ćma", "Lord", "Łabędź", "Olek", "Ósemka", "Zefir", "Żółtko"])
    }
}
