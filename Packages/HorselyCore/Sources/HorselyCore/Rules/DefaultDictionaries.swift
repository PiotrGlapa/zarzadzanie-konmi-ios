import Foundation

/// Domyślne wartości słowników (`DictionarySeeder`, SPECYFIKACJA 4.5): wartości z kluczami systemowymi (`vet.vaccination`,
/// `vet.deworming`, `training.jumping`) są systemowe — da się zmienić nazwę i kolejność, nie usunąć ani wyłączyć.
public enum DefaultDictionaries {
    public static let vetVaccination = "vet.vaccination"
    public static let vetDeworming = "vet.deworming"
    public static let trainingJumping = "training.jumping"

    /// Rodzaje treningów dodane w programie 2.0.0 (FR-002) — dopisywane u istniejących użytkowników trybu samodzielnego.
    public static let trainingTypesAddedIn200 = ["Zajeżdżanie", "Gimnastyka", "Wszechstronny"]

    private static func plain(_ names: String...) -> [(String, String?)] { names.map { ($0, nil) } }

    /// Wartości domyślne typu w kolejności wyświetlania (nazwa i klucz systemowy).
    public static func values(of type: DictionaryType) -> [(value: String, systemKey: String?)] {
        let pairs: [(String, String?)]
        switch type {
        case .vetVisitType:
            pairs = [("Kontrola", nil), ("Nagła", nil), ("Szczepienie", vetVaccination), ("Odrobaczanie", vetDeworming), ("Badanie", nil), ("Zabieg", nil)]
        case .farrierService: pairs = plain("Korekcja", "Kucie pełne", "Kucie przód", "Kucie tył", "Zdjęcie podków", "Podkucie specjalistyczne")
        case .physioBodyArea: pairs = plain("Szyja", "Grzbiet", "Lędźwie", "Zad", "Kończyny przednie", "Kończyny tylne", "Inne")
        case .physioTechnique: pairs = plain("Masaż", "Terapia manualna", "Kinesiotaping", "Laser", "Fala uderzeniowa", "Magnetoterapia", "Rozciąganie")
        case .specialistType: pairs = plain("Dentysta", "Siodlarz", "Osteopata", "Inny")
        case .competitionRank: pairs = plain("Towarzyskie", "Regionalne", "Ogólnopolskie", "Międzynarodowe")
        case .competitionDiscipline: pairs = plain("Skoki", "Ujeżdżenie", "WKKW", "Powożenie", "Rajdy", "Western", "Inne")
        case .purchaseCategory: pairs = plain("Pasza", "Suplementy", "Sprzęt", "Leki", "Pielęgnacja", "Ściółka", "Usługi", "Pensjonat", "Inne")
        case .unit: pairs = plain("szt.", "kg", "g", "l", "ml", "worek", "opak.", "balot")
        case .trainingType:
            pairs = [
                ("Ujeżdżenie", nil), ("Skoki", trainingJumping), ("Teren", nil), ("Lonża", nil), ("Karuzela", nil), ("Spacer", nil),
                ("Zajeżdżanie", nil), ("Gimnastyka", nil), ("Wszechstronny", nil), ("Inne", nil),
            ]
        }
        return pairs.map { (value: $0.0, systemKey: $0.1) }
    }

    /// Wszystkie słowniki trybu samodzielnego z nowymi identyfikatorami.
    public static func items(newId: () -> String, now: LocalDateTime) -> [LocalDictionaryItem] {
        DictionaryType.allCases.flatMap { type in
            values(of: type).enumerated().map { index, entry in
                LocalDictionaryItem(
                    id: newId(), createdAt: now, updatedAt: now, version: 1, dictionaryType: type, value: entry.value, sortOrder: index + 1,
                    isActive: true, isSystem: entry.systemKey != nil, systemKey: entry.systemKey
                )
            }
        }
    }
}
