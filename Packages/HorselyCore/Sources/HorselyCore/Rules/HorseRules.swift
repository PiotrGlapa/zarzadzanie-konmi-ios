import Foundation

/// Reguły statusu konia, których potrzebuje więcej niż jedno miejsce (port `HorseStatusRules` programu 2.0.0).
public enum HorseStatuses {
    /// Koń w stajni: jest w wyborach konia, na Pulpicie i w terminach — aktywny albo kontuzjowany.
    public static func isInStable(_ status: HorseStatus) -> Bool {
        status == .active || status == .injured
    }
}

/// Wartości formularza konia (odpowiednik treści `POST`/`PUT /horses`). Pola tekstowe mogą zawierać spacje i puste napisy —
/// czyści je `HorseRules.horse(from:)`.
public struct HorseDraft: Equatable, Sendable {
    public var name = ""
    public var passportNumber = ""
    public var isFoal = false
    public var stableName = ""
    public var ueln = ""
    public var microchipNumber = ""
    public var passportIssuer = ""
    public var passportIssueDate: LocalDate?
    public var breed = ""
    public var sex: Sex?
    public var color = ""
    public var birthDate: LocalDate?
    public var birthYearOnly = false
    public var birthCountry = ""
    public var sire = ""
    public var dam = ""
    public var damSire = ""
    public var breeder = ""
    public var owner = ""
    public var markings = ""
    public var farrierIntervalWeeks: Int? = defaultFarrierIntervalWeeks
    public var status: HorseStatus = .active
    public var statusDate: LocalDate?
    public var statusNote = ""
    public var notes = ""
    /// Kwoty konia (`finance`); `nil` — formularz ich nie zmienia (zachowane z poprzedniej wersji).
    public var finance: HorseFinanceDraft?

    public init() {}

    /// Wartości istniejącego konia do edycji (kwoty w `finance`).
    public init(horse: LocalHorse) {
        name = horse.name
        passportNumber = horse.passportNumber ?? ""
        isFoal = horse.isFoal
        stableName = horse.stableName ?? ""
        ueln = horse.ueln ?? ""
        microchipNumber = horse.microchipNumber ?? ""
        passportIssuer = horse.passportIssuer ?? ""
        passportIssueDate = horse.passportIssueDate
        breed = horse.breed ?? ""
        sex = horse.sex
        color = horse.color ?? ""
        birthDate = horse.birthDate
        birthYearOnly = horse.birthYearOnly
        birthCountry = horse.birthCountry ?? ""
        sire = horse.sire ?? ""
        dam = horse.dam ?? ""
        damSire = horse.damSire ?? ""
        breeder = horse.breeder ?? ""
        owner = horse.owner ?? ""
        markings = horse.markings ?? ""
        farrierIntervalWeeks = horse.farrierIntervalWeeks
        status = horse.status
        statusDate = horse.statusDate
        statusNote = horse.statusNote ?? ""
        notes = horse.notes ?? ""
    }
}

public struct HorseFinanceDraft: Equatable, Sendable {
    public var purchasePrice: Money?
    public var purchaseDate: LocalDate?
    public var salePrice: Money?
    public var saleDate: LocalDate?
    public var estimatedValue: Money?

    public init(purchasePrice: Money? = nil, purchaseDate: LocalDate? = nil, salePrice: Money? = nil, saleDate: LocalDate? = nil, estimatedValue: Money? = nil) {
        self.purchasePrice = purchasePrice
        self.purchaseDate = purchaseDate
        self.salePrice = salePrice
        self.saleDate = saleDate
        self.estimatedValue = estimatedValue
    }

    public init(horse: LocalHorse) {
        self.init(purchasePrice: horse.purchasePrice, purchaseDate: horse.purchaseDate, salePrice: horse.salePrice, saleDate: horse.saleDate, estimatedValue: horse.estimatedValue)
    }
}

/// Reguły konia z domeny programu (`Horse`): walidacja pól, unikalność, wiek, miesiące bez paszportu, zmiana statusu.
public enum HorseRules {
    private static let uelnPattern = #"^[0-9A-Z]{15}$"#
    private static let chipPattern = #"^[0-9]{15}$"#

    /// Pusty napis po obcięciu spacji to brak wartości (`Session.clean`).
    public static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: Walidacja (HorseValidator)

    public static func validate(_ draft: HorseDraft, today: LocalDate) -> ValidationReport {
        var report = ValidationReport()
        report.notBlank("name", draft.name)
        report.maxLength("name", draft.name, 100)
        if !draft.isFoal { report.notBlank("passportNumber", draft.passportNumber) }
        report.maxLength("passportNumber", draft.passportNumber, 50)
        report.maxLength("stableName", draft.stableName, 100)
        report.maxLength("ueln", draft.ueln, 15)
        if !draft.ueln.trimmingCharacters(in: .whitespaces).isEmpty, draft.ueln.range(of: uelnPattern, options: .regularExpression) == nil {
            report.warning("ueln", Messages.uelnFormat)
        }
        report.maxLength("microchipNumber", draft.microchipNumber, 20)
        if !draft.microchipNumber.trimmingCharacters(in: .whitespaces).isEmpty, draft.microchipNumber.range(of: chipPattern, options: .regularExpression) == nil {
            report.warning("microchipNumber", Messages.microchipFormat)
        }
        report.maxLength("passportIssuer", draft.passportIssuer, 150)
        report.maxLength("breed", draft.breed, 100)
        report.maxLength("color", draft.color, 50)
        report.maxLength("birthCountry", draft.birthCountry, 100)
        report.maxLength("sire", draft.sire, 100)
        report.maxLength("dam", draft.dam, 100)
        report.maxLength("damSire", draft.damSire, 100)
        report.maxLength("breeder", draft.breeder, 200)
        report.maxLength("owner", draft.owner, 200)
        report.futureDate("passportIssueDate", draft.passportIssueDate, today: today)
        report.futureDate("birthDate", draft.birthDate, today: today)
        if let weeks = draft.farrierIntervalWeeks, !(1...26).contains(weeks) {
            report.error("farrierIntervalWeeks", Messages.farrierIntervalRange)
        }
        if draft.status != .active, draft.statusDate == nil { report.error("statusDate", Messages.statusDateRequired) }
        if let statusDate = draft.statusDate, let birth = draft.birthDate, statusDate < birth {
            report.error("statusDate", Messages.statusDateBeforeBirth)
        }
        if let finance = draft.finance {
            report.money("finance.purchasePrice", finance.purchasePrice)
            report.money("finance.salePrice", finance.salePrice)
            report.money("finance.estimatedValue", finance.estimatedValue)
            report.futureDate("finance.purchaseDate", finance.purchaseDate, today: today)
            report.futureDate("finance.saleDate", finance.saleDate, today: today)
            if let purchase = finance.purchaseDate, let birth = draft.birthDate, purchase < birth {
                report.warning("finance.purchaseDate", Messages.purchaseBeforeBirth)
            }
            if let sale = finance.saleDate, let purchase = finance.purchaseDate, sale < purchase {
                report.warning("finance.saleDate", Messages.saleBeforePurchase)
            }
        }
        return report
    }

    /// Okno zmiany statusu (`HorseStatusChangeValidator`).
    public static func validateStatusChange(status: HorseStatus, statusDate: LocalDate?, salePrice: Money?) -> ValidationReport {
        var report = ValidationReport()
        if status != .active, statusDate == nil { report.error("statusDate", Messages.statusDateRequired) }
        report.money("salePrice", salePrice)
        return report
    }

    // MARK: Unikalność (EngineChecks.horseUnique)

    /// Powód konfliktu przy zapisie konia (kod `409` programu → komunikat przy polu).
    public enum UniquenessProblem: Equatable, Sendable {
        case passportTaken
        case foalNameTaken

        /// Pole, przy którym pokazać komunikat.
        public var field: String {
            switch self {
            case .passportTaken: "passportNumber"
            case .foalNameTaken: "name"
            }
        }

        public var message: String {
            switch self {
            case .passportTaken: Messages.passportNotUnique
            case .foalNameTaken: Messages.foalNameNotUnique
            }
        }
    }

    /// Numer paszportu (wielkość liter ignorowana tylko dla ASCII — `NOCASE`) musi być unikalny wśród koni poza koszem; źrebię bez
    /// paszportu rozróżnia imię (bez względu na wielkość liter, także polskich).
    public static func uniquenessProblem(name: String, passportNumber: String?, isFoal: Bool, among horses: [LocalHorse], excluding excludedId: String?) -> UniquenessProblem? {
        if let passport = clean(passportNumber) {
            let wanted = passport.asciiFolded
            if horses.contains(where: { $0.id != excludedId && $0.passportNumber?.asciiFolded == wanted }) { return .passportTaken }
        } else if isFoal {
            let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if horses.contains(where: { $0.isFoal && $0.passportNumber == nil && $0.id != excludedId && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted }) {
                return .foalNameTaken
            }
        }
        return nil
    }

    // MARK: Budowa rekordu (horseFrom)

    /// Koń z wartości formularza; `old` — koń przed zmianą (jego kwoty, zdjęcie i inne pola, których formularz nie niesie, zostają).
    public static func horse(from draft: HorseDraft, id: String, old: LocalHorse?, now: LocalDateTime) -> LocalHorse {
        let yearOnly = draft.birthYearOnly && draft.birthDate != nil
        let birth: LocalDate? = {
            guard let birth = draft.birthDate else { return nil }
            return yearOnly ? LocalDate(year: birth.year, month: 1, day: 1) : birth
        }()
        var horse = LocalHorse(
            id: id,
            createdAt: old?.createdAt ?? now,
            updatedAt: now,
            version: old?.version ?? 1,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            passportNumber: clean(draft.passportNumber),
            isFoal: draft.isFoal,
            stableName: clean(draft.stableName),
            ueln: clean(draft.ueln),
            microchipNumber: clean(draft.microchipNumber),
            passportIssuer: clean(draft.passportIssuer),
            passportIssueDate: draft.passportIssueDate,
            breed: clean(draft.breed),
            sex: draft.sex,
            color: clean(draft.color),
            birthDate: birth,
            birthYearOnly: yearOnly,
            birthCountry: clean(draft.birthCountry),
            sire: clean(draft.sire),
            dam: clean(draft.dam),
            damSire: clean(draft.damSire),
            breeder: clean(draft.breeder),
            owner: clean(draft.owner),
            markings: clean(draft.markings),
            photoAttachmentId: old?.photoAttachmentId,
            farrierIntervalWeeks: draft.farrierIntervalWeeks ?? old?.farrierIntervalWeeks ?? defaultFarrierIntervalWeeks,
            status: draft.status,
            statusDate: draft.statusDate,
            statusNote: clean(draft.statusNote),
            notes: clean(draft.notes),
            purchasePrice: old?.purchasePrice,
            purchaseDate: old?.purchaseDate,
            salePrice: old?.salePrice,
            saleDate: old?.saleDate,
            estimatedValue: old?.estimatedValue
        )
        // `finance` zastępuje wszystkie pięć wartości; brak obiektu = bez zmian.
        if let finance = draft.finance {
            horse.purchasePrice = finance.purchasePrice
            horse.purchaseDate = finance.purchaseDate
            horse.salePrice = finance.salePrice
            horse.saleDate = finance.saleDate
            horse.estimatedValue = finance.estimatedValue
        }
        return horse
    }

    // MARK: Zapis konia (createHorse / updateHorse)

    /// Wynik przygotowania zapisu konia: rekord do zapisania z ostrzeżeniami albo powód odmowy.
    public enum SaveOutcome: Equatable, Sendable {
        case saved(LocalHorse, warnings: [String: [String]])
        case invalid(ValidationReport)
        case conflict(UniquenessProblem)
    }

    /// Reguły zapisu konia w trybie samodzielnym — kolejność jak w programie: walidacja pól (400), unikalność (409), budowa rekordu,
    /// zmiana statusu widząca stary status (koń, który pada, ma cenę sprzedaży 0 bez względu na wpisaną; ostrzeżenie przy ożywieniu).
    /// `old` = `nil` dla nowego konia; `existing` — konie poza koszem (do unikalności).
    public static func prepareSave(_ draft: HorseDraft, id: String, old: LocalHorse?, existing: [LocalHorse], today: LocalDate, now: LocalDateTime) -> SaveOutcome {
        let report = validate(draft, today: today)
        if report.hasErrors { return .invalid(report) }
        if let problem = uniquenessProblem(name: draft.name, passportNumber: draft.passportNumber, isFoal: draft.isFoal, among: existing, excluding: old?.id) {
            return .conflict(problem)
        }
        var warnings = report.warnings
        var next = horse(from: draft, id: id, old: old, now: now)
        if let old {
            var beforeChange = next
            beforeChange.status = old.status
            beforeChange.statusDate = old.statusDate
            beforeChange.statusNote = old.statusNote
            let change = changeStatus(beforeChange, to: next.status, date: next.statusDate, note: next.statusNote)
            next = change.horse
            if change.revived { warnings["status", default: []].append(Messages.horseRevived) }
        }
        next.version = (old?.version ?? 0) + 1
        return .saved(next, warnings: warnings)
    }

    // MARK: Wiek i skutki zmiany statusu

    /// Liczba pełnych lat albo `nil` bez daty urodzenia (rok urodzenia bez dnia liczy się od 1 stycznia).
    public static func age(of horse: LocalHorse, on today: LocalDate) -> Int? {
        guard let birth = horse.birthDate, birth <= today else { return nil }
        let age = today.year - birth.year
        let anniversary = birth.adding(months: age * 12)
        return horse.birthYearOnly || today >= anniversary ? age : age - 1
    }

    /// Pełne miesiące od urodzenia źrebaka, który nie ma jeszcze numeru paszportu (FR-005a); inaczej `nil`.
    public static func monthsWithoutPassport(of horse: LocalHorse, on today: LocalDate) -> Int? {
        guard horse.isFoal, clean(horse.passportNumber) == nil, !horse.birthYearOnly, let birth = horse.birthDate, birth <= today else { return nil }
        let months = (today.year - birth.year) * 12 + (today.month - birth.month)
        return today >= birth.adding(months: months) ? months : months - 1
    }

    /// Cena sprzedaży tak, jak liczy ją bilans: wpisana albo 0 dla konia, który padł (bez ceny); `nil` — koń niesprzedany.
    public static func effectiveSalePrice(_ horse: LocalHorse) -> Money? {
        horse.salePrice ?? (horse.status == .deceased ? .zero : nil)
    }

    /// Wynik `changeStatus`: koń po zmianie i czy „padły” koń wrócił do statusu w stajni (ostrzeżenie).
    public struct StatusChange: Equatable, Sendable {
        public let horse: LocalHorse
        public let revived: Bool
    }

    /// Zmiana statusu (`Horse.ChangeStatus`): koń, który **staje się** padłym, dostaje cenę sprzedaży 0 i datę sprzedaży = datę statusu
    /// (zastępuje wpisane); sprzedany z ceną dostaje tę cenę i datę statusu. Nic innego nie czyści ani nie zmienia ceny.
    public static func changeStatus(_ horse: LocalHorse, to status: HorseStatus, date: LocalDate?, note: String?, salePrice: Money? = nil) -> StatusChange {
        let revived = horse.status == .deceased && HorseStatuses.isInStable(status)
        let becameDeceased = status == .deceased && horse.status != .deceased
        var changed = horse
        changed.status = status
        changed.statusDate = date
        changed.statusNote = note
        if becameDeceased {
            changed.salePrice = .zero
            changed.saleDate = date
        } else if status == .sold, let salePrice {
            changed.salePrice = salePrice
            changed.saleDate = date
        }
        return StatusChange(horse: changed, revived: revived)
    }
}
