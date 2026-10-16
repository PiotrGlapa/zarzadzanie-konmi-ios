import Foundation

/// Filtr statusu listy koni (FR-009): domyślnie konie w stajni, chipy zawężają do jednego statusu albo pokazują wszystkie.
public enum HorseListFilter: Sendable, CaseIterable {
    /// Domyślnie: aktywne i kontuzjowane.
    case inStable
    /// Chip „Aktywny”: tylko aktywne.
    case active
    /// Chip „Kontuzjowany”: tylko kontuzjowane.
    case injured
    /// „Pokaż wszystkie”: także sprzedane, padłe i wydzierżawione.
    case all
}

/// Lista koni (FR-M-KON-01): wyszukiwanie po imieniu, imieniu stajennym i numerze paszportu bez rozróżniania wielkości liter i polskich
/// znaków, domyślnie konie w stajni (aktywne i kontuzjowane), filtr statusu i przełącznik „Tylko źrebięta”, sortowanie po imieniu.
public enum HorseSearch {
    public static func apply(_ horses: [LocalHorse], query: String, filter: HorseListFilter = .inStable, onlyFoals: Bool = false) -> [LocalHorse] {
        let key = Formats.searchKey(query)
        return horses
            .filter { matches(filter, $0.status) }
            .filter { !onlyFoals || $0.isFoal }
            .filter { key.isEmpty || searchKey(of: $0).contains(key) }
            .sorted { PolishNames.compareForList($0.name, $1.name) == .orderedAscending }
    }

    private static func matches(_ filter: HorseListFilter, _ status: HorseStatus) -> Bool {
        switch filter {
        case .inStable: HorseStatuses.isInStable(status)
        case .active: status == .active
        case .injured: status == .injured
        case .all: true
        }
    }

    private static func searchKey(of horse: LocalHorse) -> String {
        Formats.searchKey([horse.name, horse.stableName, horse.passportNumber].compactMap { $0 }.joined(separator: " "))
    }
}
