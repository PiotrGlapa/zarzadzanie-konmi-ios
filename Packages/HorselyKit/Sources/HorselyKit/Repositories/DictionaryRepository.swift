import Foundation
import HorselyCore

/// Słowniki trybu samodzielnego (T126, FR-SAM-05): wartości typu (także nieaktywne), dodanie, zmiana nazwy, ukrycie, kolejność,
/// usunięcie do kosza i jednorazowe dopisanie rodzajów treningów programu 2.0.0 (FR-002).
extension EntryRepository {
    /// Wartości typu w kolejności wyświetlania, także nieaktywne (ekran słownika).
    public func dictionaryValues(_ type: DictionaryType) async throws -> [LocalDictionaryItem] {
        try await read { source, _ in
            try source.records(.dictionary, as: LocalDictionaryItem.self).filter { $0.dictionaryType == type }
                .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
        }
    }

    public func addDictionaryValue(_ type: DictionaryType, value: String) async throws -> EntryResult {
        try await perform { $0.createDictionaryItem(type: type, value: value) }
    }

    public func renameDictionaryValue(id: String, value: String) async throws -> EntryResult {
        try await perform { $0.updateDictionaryItem(id: id, value: value) }
    }

    public func setDictionaryValueActive(id: String, value: String, active: Bool) async throws -> EntryResult {
        try await perform { $0.updateDictionaryItem(id: id, value: value, isActive: active) }
    }

    public func reorderDictionary(_ type: DictionaryType, orderedIds: [String]) async throws -> EntryResult {
        try await perform { $0.reorderDictionary(type: type, orderedIds: orderedIds) }
    }

    public func deleteDictionaryValue(id: String) async throws -> EntryResult {
        try await perform { $0.deleteDictionaryItem(id: id) }
    }

    /// Raz na instalację w trybie samodzielnym: Zajeżdżanie, Gimnastyka i Wszechstronny dopisane do rodzajów treningów; znacznik
    /// w `local_meta` sprawia, że usunięta później wartość nie wraca. Zwraca `true`, gdy dopisanie właśnie się odbyło.
    @discardableResult
    public func addMissingTrainingTypesOnce() async throws -> Bool {
        guard try await store.meta(DictionaryUpgrades.trainingTypesMarker) == nil else { return false }
        _ = try await perform { $0.addMissingTrainingTypes() }
        try await store.setMeta(DictionaryUpgrades.trainingTypesMarker, "done")
        return true
    }
}
