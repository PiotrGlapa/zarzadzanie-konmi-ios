import Foundation

/// Porównywanie nazw wartości słowników tak, jak myśli o nich użytkownik (2.0.0, FR-002; `DictionaryNames.kt`, `DictionaryNameComparer`
/// programu): bez względu na wielkość liter, spacje wokół nazwy i znaki diakrytyczne („Zajeżdżanie” = „zajezdzanie”, „Łonża” = „lonza”).
public enum DictionaryNames {
    /// Postać wspólna dla dwóch równych nazw; pusta i same białe znaki → "".
    public static func normalize(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "ł", with: "l")
        var scalars = String.UnicodeScalarView()
        for scalar in lowered.decomposedStringWithCanonicalMapping.unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar)
        }
        return String(scalars).precomposedStringWithCanonicalMapping
    }

    /// Nazwy z `wanted`, których nie ma w `existing`, w kolejności `wanted`.
    public static func missing(_ wanted: [String], existing: [String]) -> [String] {
        let known = Set(existing.map(normalize))
        return wanted.filter { !known.contains(normalize($0)) }
    }
}

/// Dopisanie zmian słowników programu 2.0.0 do danych sprzed niej (tryb samodzielny i odtworzenie starszej kopii — FR-002, FR-003;
/// `DictionaryUpgrades.kt`, `ImportUpgrades.AddMissingTrainingTypes` programu).
public enum DictionaryUpgrades {
    /// Znacznik w `local_meta`: rodzaje treningów 2.0.0 były już dopisywane — usunięta później wartość nie wraca.
    public static let trainingTypesMarker = "dict.trainingTypes200"

    /// Zajeżdżanie, Gimnastyka i Wszechstronny na końcu rodzajów treningów, każdy tylko gdy nie ma rodzaju o tej nazwie (nieaktywne
    /// i usunięte do kosza też się liczą). Brak jakiegokolwiek rodzaju — komplet domyślny.
    public static func missingTrainingTypes(existing all: [LocalDictionaryItem], newId: () -> String, now: LocalDateTime) -> [LocalDictionaryItem] {
        let existing = all.filter { $0.dictionaryType == .trainingType }
        if existing.isEmpty {
            return DefaultDictionaries.items(newId: newId, now: now).filter { $0.dictionaryType == .trainingType }
        }
        var next = existing.map(\.sortOrder).max() ?? 0
        return DictionaryNames.missing(DefaultDictionaries.trainingTypesAddedIn200, existing: existing.map(\.value)).map { name in
            next += 1
            return LocalDictionaryItem(
                id: newId(), createdAt: now, updatedAt: now, version: 1, dictionaryType: .trainingType, value: name, sortOrder: next,
                isActive: true, isSystem: false, systemKey: nil
            )
        }
    }

    /// Schemat eksportu starszy niż 1.5 (kopie i pliki sprzed programu 2.0.0): bez rodzajów treningów 2.0.0.
    public static func isBeforeTrainingTypes200(_ exportSchemaVersion: String) -> Bool {
        let parts = exportSchemaVersion.split(separator: ".").map { Int($0) }
        guard !parts.contains(where: { $0 == nil }) else { return false }
        let major = parts.first.flatMap { $0 } ?? 0
        let minor = parts.count > 1 ? (parts[1] ?? 0) : 0
        return major < 1 || (major == 1 && minor < 5)
    }
}

extension Messages {
    public static let dictionaryValueNotUnique = "Taka wartość już istnieje w tym słowniku."
    public static let dictionarySystemValue = "To wartość systemowa: można zmienić tylko jej nazwę i kolejność."
    public static let dictionaryValueInUse = "Wartość jest używana we wpisach, więc nie można jej usunąć. Możesz ją dezaktywować."
    public static let dictionaryReorderMismatch = "Lista do zmiany kolejności musi zawierać wszystkie wartości słownika."
}

/// Słowniki trybu samodzielnego (T124, FR-SAM-05; `EntryOps.kt`): dodanie, zmiana nazwy, włączenie/wyłączenie, kolejność, usunięcie.
extension RuleEngine {
    public func createDictionaryItem(type: DictionaryType, value: String, isActive: Bool = true) -> RuleOutcome {
        run { s in
            let name = try Self.validDictionaryValue(s, value)
            if try Self.dictionaryValueTaken(s, type: type, value: name, excludeId: nil) { throw s.conflict(.unique, Messages.dictionaryValueNotUnique) }
            let maxOrder = try s.all(.dictionary, as: LocalDictionaryItem.self).filter { $0.dictionaryType == type }.map(\.sortOrder).max() ?? 0
            let item = LocalDictionaryItem(
                id: s.newId(), createdAt: s.now, updatedAt: s.now, version: 1, dictionaryType: type, value: name, sortOrder: maxOrder + 1,
                isActive: isActive, isSystem: false, systemKey: nil
            )
            return (try s.insert(item, primary: true), nil)
        }
    }

    /// Zmiana nazwy (także wartości systemowej) i włączenie/wyłączenie (systemowej nie wolno wyłączyć).
    public func updateDictionaryItem(id: String, value: String, isActive: Bool? = nil) -> RuleOutcome {
        run { s in
            let name = try Self.validDictionaryValue(s, value)
            guard let item = try s.dictionary(id) else { throw s.notFound("DictionaryItem", id) }
            if try Self.dictionaryValueTaken(s, type: item.dictionaryType, value: name, excludeId: id) { throw s.conflict(.unique, Messages.dictionaryValueNotUnique) }
            if let isActive, isActive != item.isActive, item.isSystem, !isActive { throw s.conflict(.invalidState, Messages.dictionarySystemValue) }
            var changed = item
            changed.value = name
            if let isActive { changed.isActive = isActive }
            return (try s.replace(old: item, with: changed, primary: true), nil)
        }
    }

    /// Do kosza — tylko wartość niesystemowa i nieużywana (także przez rekordy w koszu).
    public func deleteDictionaryItem(id: String) -> RuleOutcome {
        run { s in
            guard let item = try s.dictionary(id) else { throw s.notFound("DictionaryItem", id) }
            if item.isSystem { throw s.conflict(.invalidState, Messages.dictionarySystemValue) }
            if try Self.dictionaryUsed(s, id) { throw s.conflict(.inUse, Messages.dictionaryValueInUse) }
            return (nil, try TrashRules.softDelete(s, type: .dictionary, id: id))
        }
    }

    /// Kolejność wartości typu: lista musi zawierać wszystkie wartości; numeracja od 1, bez zmian rekordów, których miejsce się nie zmieniło.
    public func reorderDictionary(type: DictionaryType, orderedIds: [String]) -> RuleOutcome {
        run { s in
            let items = try s.all(.dictionary, as: LocalDictionaryItem.self).filter { $0.dictionaryType == type }
            guard items.count == orderedIds.count, Set(items.map(\.id)) == Set(orderedIds) else {
                throw s.invalid("orderedIds", Messages.dictionaryReorderMismatch)
            }
            let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (index, id) in orderedIds.enumerated() {
                guard let item = byId[id], item.sortOrder != index + 1 else { continue }
                var moved = item
                moved.sortOrder = index + 1
                try s.replace(old: item, with: moved, primary: false)
            }
            return (nil, nil)
        }
    }

    /// Rodzaje treningów programu 2.0.0 dopisane do słownika (bez znacznika — znacznik prowadzi magazyn).
    public func addMissingTrainingTypes() -> RuleOutcome {
        run { s in
            let all = try s.sourceForDeepChecks.query(.dictionary, horseId: nil, from: nil, to: nil, includeDeleted: true)
                .compactMap { $0.record as? LocalDictionaryItem }
            for item in DictionaryUpgrades.missingTrainingTypes(existing: all, newId: s.newId, now: s.now) { try s.insert(item, primary: false) }
            return (nil, nil)
        }
    }

    static func validDictionaryValue(_ s: RuleSession, _ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw s.invalid("value", Messages.required) }
        if name.count > 100 { throw s.invalid("value", Messages.maxLength(100)) }
        return name
    }

    static func dictionaryValueTaken(_ s: RuleSession, type: DictionaryType, value: String, excludeId: String?) throws -> Bool {
        let wanted = value.asciiFolded
        return try s.all(.dictionary, as: LocalDictionaryItem.self).contains { $0.dictionaryType == type && $0.id != excludeId && $0.value.asciiFolded == wanted }
    }

    /// Czy pozycja słownika jest użyta przez jakikolwiek rekord (również z kosza).
    static func dictionaryUsed(_ s: RuleSession, _ id: String) throws -> Bool {
        let source = s.sourceForDeepChecks
        func any(_ type: RecordType, _ match: (any LocalRecord) -> Bool) throws -> Bool {
            try source.query(type, horseId: nil, from: nil, to: nil, includeDeleted: true).contains { match($0.record) }
        }
        if try any(.vetVisit, { ($0 as? LocalVetVisit)?.visitTypeId == id }) { return true }
        if try any(.farrierVisit, { ($0 as? LocalFarrierVisit)?.serviceId == id }) { return true }
        if try any(.physioVisit, { record in
            guard let visit = record as? LocalPhysioVisit else { return false }
            return visit.bodyAreaIds.contains(id) || visit.techniqueIds.contains(id)
        }) { return true }
        if try any(.specialistVisit, { ($0 as? LocalSpecialistVisit)?.specialistTypeId == id }) { return true }
        if try any(.competition, { record in
            guard let competition = record as? LocalCompetition else { return false }
            return competition.rankId == id || competition.disciplineId == id
        }) { return true }
        if try any(.competitionStart, { ($0 as? LocalCompetitionStart)?.disciplineId == id }) { return true }
        if try any(.purchase, { record in
            guard let purchase = record as? LocalPurchase else { return false }
            return purchase.categoryId == id || purchase.unitId == id
        }) { return true }
        if try any(.training, { ($0 as? LocalTraining)?.trainingTypeId == id }) { return true }
        return try any(.reminder) { ($0 as? LocalReminder)?.specialistTypeId == id }
    }
}
