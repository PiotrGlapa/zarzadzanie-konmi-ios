import Foundation
import Testing
@testable import HorselyCore

/// Reguły konia (T038): walidacja pól z komunikatami programu, unikalność paszportu i imienia źrebaka bez paszportu, przejścia
/// statusu (w tym „Kontuzjowany” i „Padł”), wiek i miesiące bez paszportu; scenariusze z plików wzorcowych programu 2.0.0.
struct HorseRulesTests {
    private let today = LocalDate(year: 2026, month: 10, day: 15)!
    private let stamp = LocalDateTime(year: 2026, month: 10, day: 1, hour: 8)!

    private func date(_ year: Int, _ month: Int, _ day: Int) -> LocalDate { LocalDate(year: year, month: month, day: day)! }

    private func validDraft() -> HorseDraft {
        var draft = HorseDraft()
        draft.name = "Grom"
        draft.passportNumber = "PL-GROM"
        return draft
    }

    private func horse(_ name: String, passport: String? = nil, foal: Bool = false, status: HorseStatus = .active, id: String? = nil) -> LocalHorse {
        LocalHorse(id: id ?? name, createdAt: stamp, updatedAt: stamp, version: 1, name: name, passportNumber: passport, isFoal: foal, status: status)
    }

    // MARK: Walidacja

    @Test func aValidDraftHasNoErrors() {
        let report = HorseRules.validate(validDraft(), today: today)
        #expect(!report.hasErrors)
        #expect(report.warnings.isEmpty)
    }

    @Test func nameIsRequiredAndLimited() {
        var draft = validDraft()
        draft.name = "   "
        #expect(HorseRules.validate(draft, today: today).errors["name"] == [Messages.required])
        draft.name = String(repeating: "a", count: 101)
        #expect(HorseRules.validate(draft, today: today).errors["name"] == ["Maksymalna długość to 100 znaków."])
    }

    @Test func passportIsRequiredUnlessTheHorseIsAFoal() {
        var draft = validDraft()
        draft.passportNumber = ""
        #expect(HorseRules.validate(draft, today: today).errors["passportNumber"] == ["Pole jest wymagane."])
        draft.isFoal = true
        #expect(HorseRules.validate(draft, today: today).errors["passportNumber"] == nil)
    }

    @Test func farrierIntervalMustBeBetweenOneAndTwentySixWeeks() {
        var draft = validDraft()
        for weeks in [0, 27, -1] {
            draft.farrierIntervalWeeks = weeks
            #expect(HorseRules.validate(draft, today: today).errors["farrierIntervalWeeks"] == ["Interwał kowalski musi mieścić się w zakresie 1–26 tygodni."])
        }
        for weeks in [1, 6, 26] {
            draft.farrierIntervalWeeks = weeks
            #expect(HorseRules.validate(draft, today: today).errors["farrierIntervalWeeks"] == nil)
        }
    }

    @Test func datesCannotBeInTheFuture() {
        var draft = validDraft()
        draft.birthDate = date(2026, 10, 16)
        draft.passportIssueDate = date(2027, 1, 1)
        let errors = HorseRules.validate(draft, today: today).errors
        #expect(errors["birthDate"] == ["Data nie może być z przyszłości."])
        #expect(errors["passportIssueDate"] == ["Data nie może być z przyszłości."])
        draft.birthDate = today
        #expect(HorseRules.validate(draft, today: today).errors["birthDate"] == nil)
    }

    @Test func uelnAndMicrochipFormatsOnlyWarn() {
        var draft = validDraft()
        draft.ueln = "ABC"
        draft.microchipNumber = "12345"
        let report = HorseRules.validate(draft, today: today)
        #expect(!report.hasErrors)
        #expect(report.warnings["ueln"] == [Messages.uelnFormat])
        #expect(report.warnings["microchipNumber"] == [Messages.microchipFormat])
        draft.ueln = "616000123456789"
        draft.microchipNumber = "616000123456789"
        #expect(HorseRules.validate(draft, today: today).warnings.isEmpty)
    }

    @Test func aStatusOtherThanActiveNeedsADate() {
        var draft = validDraft()
        for status in [HorseStatus.injured, .sold, .deceased, .leased] {
            draft.status = status
            draft.statusDate = nil
            #expect(HorseRules.validate(draft, today: today).errors["statusDate"] == ["Podaj datę zmiany statusu."], "\(status)")
        }
        draft.status = .injured
        draft.statusDate = today
        #expect(HorseRules.validate(draft, today: today).errors["statusDate"] == nil)
        draft.status = .active
        draft.statusDate = nil
        #expect(HorseRules.validate(draft, today: today).errors["statusDate"] == nil)
    }

    @Test func theStatusDateCannotPrecedeTheBirth() {
        var draft = validDraft()
        draft.birthDate = date(2020, 5, 1)
        draft.status = .sold
        draft.statusDate = date(2019, 1, 1)
        #expect(HorseRules.validate(draft, today: today).errors["statusDate"] == [Messages.statusDateBeforeBirth])
    }

    @Test func financeAmountsAreValidatedAndTheirOddDatesOnlyWarn() {
        var draft = validDraft()
        draft.birthDate = date(2020, 1, 1)
        draft.finance = HorseFinanceDraft(
            purchasePrice: Money(string: "-1"), purchaseDate: date(2019, 1, 1), salePrice: Money(string: "10.123"), saleDate: date(2018, 1, 1),
            estimatedValue: Money(string: "10000000.01")
        )
        let report = HorseRules.validate(draft, today: today)
        #expect(report.errors["finance.purchasePrice"] == [Messages.moneyInvalid])
        #expect(report.errors["finance.salePrice"] == [Messages.moneyInvalid])
        #expect(report.errors["finance.estimatedValue"] == [Messages.moneyInvalid])
        #expect(report.warnings["finance.purchaseDate"] == [Messages.purchaseBeforeBirth])
        #expect(report.warnings["finance.saleDate"] == [Messages.saleBeforePurchase])
        draft.finance = HorseFinanceDraft(purchasePrice: Money(string: "10000000"), salePrice: Money(string: "0"), estimatedValue: Money(string: "1.5"))
        #expect(!HorseRules.validate(draft, today: today).hasErrors)
    }

    // MARK: Unikalność

    @Test func aPassportMustBeUniqueIgnoringOnlyAsciiCase() {
        let horses = [horse("Grom", passport: "PL-Grom"), horse("Łania", passport: "ŁANIA-1")]
        #expect(HorseRules.uniquenessProblem(name: "X", passportNumber: "pl-grom", isFoal: false, among: horses, excluding: nil) == .passportTaken)
        #expect(HorseRules.uniquenessProblem(name: "X", passportNumber: " PL-GROM ", isFoal: false, among: horses, excluding: nil) == .passportTaken)
        // NOCASE SQLite nie składa liter spoza ASCII: „Ł” ≠ „ł”.
        #expect(HorseRules.uniquenessProblem(name: "X", passportNumber: "łania-1", isFoal: false, among: horses, excluding: nil) == nil)
        // Edycja tego samego konia nie jest konfliktem.
        #expect(HorseRules.uniquenessProblem(name: "Grom", passportNumber: "PL-Grom", isFoal: false, among: horses, excluding: "Grom") == nil)
    }

    @Test func aFoalWithoutPassportNeedsAUniqueNameIgnoringCase() {
        let horses = [horse("Źrebak Łatek", foal: true), horse("Dorosły", passport: "PL-1")]
        #expect(HorseRules.uniquenessProblem(name: "źrebak ŁATEK", passportNumber: nil, isFoal: true, among: horses, excluding: nil) == .foalNameTaken)
        #expect(HorseRules.uniquenessProblem(name: "Dorosły", passportNumber: "", isFoal: true, among: horses, excluding: nil) == nil)
        #expect(HorseRules.uniquenessProblem(name: "Nowy", passportNumber: nil, isFoal: true, among: horses, excluding: nil) == nil)
        #expect(HorseRules.uniquenessProblem(name: "Źrebak Łatek", passportNumber: nil, isFoal: true, among: horses, excluding: "Źrebak Łatek") == nil)
        // Imię sprawdza się tylko dla źrebięcia bez paszportu.
        #expect(HorseRules.uniquenessProblem(name: "Źrebak Łatek", passportNumber: nil, isFoal: false, among: horses, excluding: nil) == nil)
    }

    @Test func uniquenessMessagesMatchTheProgram() {
        #expect(HorseRules.UniquenessProblem.passportTaken.message == "Koń z tym numerem paszportu już istnieje.")
        #expect(HorseRules.UniquenessProblem.foalNameTaken.message == "Źrebak bez paszportu o tym imieniu już istnieje — nadaj inne imię albo wpisz numer paszportu.")
        #expect(HorseRules.UniquenessProblem.passportTaken.field == "passportNumber")
        #expect(HorseRules.UniquenessProblem.foalNameTaken.field == "name")
    }

    // MARK: Status

    @Test func aHorseInTheStableIsActiveOrInjured() {
        #expect(HorseStatuses.isInStable(.active))
        #expect(HorseStatuses.isInStable(.injured))
        for status in [HorseStatus.sold, .deceased, .leased] { #expect(!HorseStatuses.isInStable(status)) }
    }

    @Test func statusChangeToInjuredNeedsAStatusDate() {
        #expect(HorseRules.validateStatusChange(status: .injured, statusDate: nil, salePrice: nil).errors["statusDate"] != nil)
        #expect(!HorseRules.validateStatusChange(status: .injured, statusDate: today, salePrice: nil).hasErrors)
        #expect(!HorseRules.validateStatusChange(status: .active, statusDate: nil, salePrice: nil).hasErrors)
    }

    @Test func aHorseBecomingDeceasedGetsASalePriceOfZero() {
        var old = horse("Gaj", passport: "PL-GAJ")
        old.salePrice = Money(string: "5000")
        let change = HorseRules.changeStatus(old, to: .deceased, date: date(2026, 9, 20), note: nil)
        #expect(change.horse.status == .deceased)
        #expect(change.horse.salePrice == .zero)
        #expect(change.horse.saleDate == date(2026, 9, 20))
        #expect(!change.revived)
    }

    @Test func aSoldHorseWithAPriceGetsThePriceAndTheStatusDate() {
        let change = HorseRules.changeStatus(horse("Gaj", passport: "P"), to: .sold, date: date(2026, 9, 20), note: "Nowy właściciel", salePrice: Money(string: "12000.50"))
        #expect(change.horse.salePrice == Money(string: "12000.5"))
        #expect(change.horse.saleDate == date(2026, 9, 20))
        #expect(change.horse.statusNote == "Nowy właściciel")
    }

    @Test func goingToInjuredOrBackToActiveChangesNothingElse() {
        var old = horse("Gaj", passport: "P")
        old.salePrice = Money(string: "10")
        let injured = HorseRules.changeStatus(old, to: .injured, date: today, note: "Kulawizna")
        #expect(injured.horse.status == .injured)
        #expect(injured.horse.salePrice == Money(string: "10"))
        #expect(!injured.revived)
        let back = HorseRules.changeStatus(injured.horse, to: .active, date: nil, note: nil)
        #expect(back.horse.status == .active)
        #expect(!back.revived)
    }

    @Test func aDeceasedHorseBroughtBackToTheStableIsRevived() {
        let deceased = horse("Stary", passport: "P", status: .deceased)
        #expect(HorseRules.changeStatus(deceased, to: .active, date: nil, note: nil).revived)
        #expect(HorseRules.changeStatus(deceased, to: .injured, date: today, note: nil).revived)
        #expect(!HorseRules.changeStatus(deceased, to: .sold, date: today, note: nil).revived)
    }

    @Test func effectiveSalePriceTreatsADeceasedHorseWithoutPriceAsZero() {
        #expect(HorseRules.effectiveSalePrice(horse("A", passport: "P")) == nil)
        #expect(HorseRules.effectiveSalePrice(horse("A", passport: "P", status: .deceased)) == .zero)
        var sold = horse("A", passport: "P", status: .sold)
        sold.salePrice = Money(string: "99")
        #expect(HorseRules.effectiveSalePrice(sold) == Money(string: "99"))
    }

    // MARK: Wiek i źrebięta

    @Test func ageCountsFullYears() {
        var grom = horse("Grom", passport: "P")
        #expect(HorseRules.age(of: grom, on: today) == nil)
        grom.birthDate = date(2019, 10, 15)
        #expect(HorseRules.age(of: grom, on: today) == 7)
        grom.birthDate = date(2019, 10, 16)
        #expect(HorseRules.age(of: grom, on: today) == 6)
        grom.birthDate = date(2019, 12, 1)
        grom.birthYearOnly = true
        #expect(HorseRules.age(of: grom, on: today) == 7)
        grom.birthDate = date(2027, 1, 1)
        #expect(HorseRules.age(of: grom, on: today) == nil)
    }

    @Test func monthsWithoutAPassportAreFullMonthsSinceBirth() {
        var foal = horse("Żuczek", foal: true)
        foal.birthDate = date(2025, 10, 15)
        #expect(HorseRules.monthsWithoutPassport(of: foal, on: today) == 12)
        foal.birthDate = date(2025, 10, 16)
        #expect(HorseRules.monthsWithoutPassport(of: foal, on: today) == 11)
        foal.birthDate = date(2026, 10, 1)
        #expect(HorseRules.monthsWithoutPassport(of: foal, on: today) == 0)
        foal.passportNumber = "PL-1"
        #expect(HorseRules.monthsWithoutPassport(of: foal, on: today) == nil)
        foal.passportNumber = nil
        foal.birthYearOnly = true
        #expect(HorseRules.monthsWithoutPassport(of: foal, on: today) == nil)
        var adult = horse("Dorosły", passport: nil)
        adult.birthDate = date(2020, 1, 1)
        #expect(HorseRules.monthsWithoutPassport(of: adult, on: today) == nil)
    }

    // MARK: Zapis

    @Test func savingBuildsACleanRecordAndKeepsWhatTheFormDoesNotCarry() {
        var old = horse("Grom", passport: "PL-GROM", id: "h1")
        old.photoAttachmentId = "photo-1"
        old.purchasePrice = Money(string: "4000")
        old.version = 3
        var draft = HorseDraft(horse: old)
        draft.name = "  Grom  "
        draft.stableName = "   "
        draft.notes = "Uwagi"
        let outcome = HorseRules.prepareSave(draft, id: "h1", old: old, existing: [old], today: today, now: stamp)
        guard case let .saved(saved, warnings) = outcome else { Issue.record("oczekiwano zapisu: \(outcome)"); return }
        #expect(saved.name == "Grom")
        #expect(saved.stableName == nil)
        #expect(saved.notes == "Uwagi")
        #expect(saved.photoAttachmentId == "photo-1")
        #expect(saved.purchasePrice == Money(string: "4000"))
        #expect(saved.version == 4)
        #expect(warnings.isEmpty)
    }

    @Test func aBirthYearOnlyIsStoredAsTheFirstOfJanuary() {
        var draft = validDraft()
        draft.birthDate = date(2019, 6, 20)
        draft.birthYearOnly = true
        guard case let .saved(saved, _) = HorseRules.prepareSave(draft, id: "n", old: nil, existing: [], today: today, now: stamp) else { Issue.record("zapis"); return }
        #expect(saved.birthDate == date(2019, 1, 1))
        #expect(saved.birthYearOnly)
        #expect(saved.version == 1)
    }

    @Test func savingRefusesInvalidAndDuplicatedHorses() {
        var draft = validDraft()
        draft.passportNumber = ""
        if case let .invalid(report) = HorseRules.prepareSave(draft, id: "n", old: nil, existing: [], today: today, now: stamp) {
            #expect(report.errors["passportNumber"] == [Messages.required])
        } else { Issue.record("oczekiwano odmowy") }

        draft.passportNumber = "pl-grom"
        let existing = [horse("Grom", passport: "PL-GROM")]
        #expect(HorseRules.prepareSave(draft, id: "n", old: nil, existing: existing, today: today, now: stamp) == .conflict(.passportTaken))
    }

    @Test func aRevivedHorseGetsAWarning() {
        let deceased = horse("Gaj", passport: "PL-GAJ", status: .deceased, id: "g")
        var draft = HorseDraft(horse: deceased)
        draft.status = .active
        draft.statusDate = nil
        guard case let .saved(saved, warnings) = HorseRules.prepareSave(draft, id: "g", old: deceased, existing: [deceased], today: today, now: stamp) else { Issue.record("zapis"); return }
        #expect(saved.status == .active)
        #expect(warnings["status"] == [Messages.horseRevived])
    }
}

/// Scenariusze programu 2.0.0 (`parity/brzegowy/scenarios/kon-*.json`): ta sama operacja daje ten sam wynik co odpowiedź programu.
struct HorseScenarioParityTests {
    private struct Scenario {
        let name: String
        let clock: LocalDateTime
        let before: ExportDocument
        let method: String
        let id: String?
        let body: [String: Any]
        let status: Int
        let response: [String: Any]
    }

    private func scenarios() throws -> [Scenario] {
        let directory = Fixtures.url("parity/brzegowy/scenarios")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("kon-") && $0.hasSuffix(".json") }.sorted()
        return try files.compactMap { file in
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(file))) as! [String: Any]
            let operation = object["operation"] as! [String: Any]
            let path = operation["path"] as! String
            let method = operation["method"] as! String
            guard ["POST", "PUT"].contains(method), path.hasPrefix("/api/v1/horses"), operation["body"] is [String: Any] else { return nil }
            let before = try ExportDocument.parse(JSONSerialization.data(withJSONObject: object["before"]!))
            let response = object["response"] as! [String: Any]
            return Scenario(
                name: object["name"] as! String, clock: LocalDateTime(object["clock"] as! String)!, before: before, method: method,
                id: method == "PUT" ? String(path.split(separator: "/").last!) : nil, body: operation["body"] as! [String: Any],
                status: response["status"] as! Int, response: response["body"] as! [String: Any]
            )
        }
    }

    private func money(_ value: Any?) -> Money? {
        guard let number = value as? NSNumber else { return nil }
        return Money(string: number.stringValue)
    }

    private func date(_ value: Any?) -> LocalDate? { (value as? String).flatMap { LocalDate($0) } }

    private func draft(from body: [String: Any]) -> HorseDraft {
        var draft = HorseDraft()
        draft.name = body["name"] as? String ?? ""
        draft.passportNumber = body["passportNumber"] as? String ?? ""
        draft.isFoal = body["isFoal"] as? Bool ?? false
        draft.stableName = body["stableName"] as? String ?? ""
        draft.sex = (body["sex"] as? String).flatMap(Sex.init(rawValue:))
        draft.birthDate = date(body["birthDate"])
        draft.birthYearOnly = body["birthYearOnly"] as? Bool ?? false
        draft.farrierIntervalWeeks = body["farrierIntervalWeeks"] as? Int ?? defaultFarrierIntervalWeeks
        draft.status = (body["status"] as? String).flatMap(HorseStatus.init(rawValue:)) ?? .active
        draft.statusDate = date(body["statusDate"])
        draft.statusNote = body["statusNote"] as? String ?? ""
        if let finance = body["finance"] as? [String: Any] {
            draft.finance = HorseFinanceDraft(
                purchasePrice: money(finance["purchasePrice"]), purchaseDate: date(finance["purchaseDate"]), salePrice: money(finance["salePrice"]),
                saleDate: date(finance["saleDate"]), estimatedValue: money(finance["estimatedValue"])
            )
        }
        return draft
    }

    @Test func horseScenariosGiveTheSameResultAsTheProgram() throws {
        let all = try scenarios()
        #expect(all.count >= 8, "za mało scenariuszy koni: \(all.count)")
        for scenario in all {
            let horses = scenario.before.records(of: .horse).compactMap { $0 as? LocalHorse }
            let old = scenario.id.flatMap { id in horses.first { $0.id == id } }
            let outcome = HorseRules.prepareSave(
                draft(from: scenario.body), id: scenario.id ?? "nowy", old: old, existing: horses, today: scenario.clock.date, now: scenario.clock
            )
            switch (scenario.status, outcome) {
            case let (400, .invalid(report)):
                let expected = scenario.response["errors"] as! [String: [String]]
                #expect(report.errors == expected, "\(scenario.name): błędy walidacji")
            case let (409, .conflict(problem)):
                #expect(problem.message == scenario.response["detail"] as? String, "\(scenario.name): komunikat konfliktu")
            case let (200, .saved(horse, _)), let (201, .saved(horse, _)):
                let response = scenario.response
                #expect(horse.name == response["name"] as? String, "\(scenario.name): imię")
                #expect(horse.passportNumber == response["passportNumber"] as? String, "\(scenario.name): paszport")
                #expect(horse.sex?.rawValue == response["sex"] as? String, "\(scenario.name): płeć")
                #expect(horse.status.rawValue == response["status"] as? String, "\(scenario.name): status")
                #expect(horse.statusDate == date(response["statusDate"]), "\(scenario.name): data statusu")
                #expect(horse.statusNote == response["statusNote"] as? String, "\(scenario.name): notatka statusu")
                #expect(horse.version == response["version"] as? Int, "\(scenario.name): wersja")
                #expect(horse.birthDate == date(response["birthDate"]), "\(scenario.name): data urodzenia")
                #expect(horse.farrierIntervalWeeks == response["farrierIntervalWeeks"] as? Int, "\(scenario.name): interwał kowala")
                let finance = response["finance"] as! [String: Any]
                #expect(horse.purchasePrice == money(finance["purchasePrice"]), "\(scenario.name): cena zakupu")
                #expect(horse.purchaseDate == date(finance["purchaseDate"]), "\(scenario.name): data zakupu")
                #expect(horse.salePrice == money(finance["salePrice"]), "\(scenario.name): cena sprzedaży")
                #expect(horse.saleDate == date(finance["saleDate"]), "\(scenario.name): data sprzedaży")
                #expect(horse.estimatedValue == money(finance["estimatedValue"]), "\(scenario.name): wartość")
            default:
                Issue.record("\(scenario.name): oczekiwano odpowiedzi \(scenario.status), jest \(outcome)")
            }
        }
    }
}
