import Foundation
import Testing
@testable import HorselyCore

/// Model eksportu 1.5 (T016): odczyt plików wzorcowych programu, status `Injured`, nieznane pola, zapis i ponowny odczyt.
struct ExportModelTests {
    private func document(_ set: String) throws -> ExportDocument {
        try ExportDocument.parse(Fixtures.data("parity/\(set)/export.json"))
    }

    private func horses(_ document: ExportDocument) -> [LocalHorse] {
        document.records(of: .horse).compactMap { $0 as? LocalHorse }
    }

    @Test func readsTheSmallProgramExport() throws {
        let document = try document("maly")
        #expect(document.schemaVersion == "1.5")
        #expect(document.header.appVersion == "2.0.0")
        #expect(document.header.scope.type == "full")
        #expect(document.records(of: .dictionary).count == 68)
        #expect(document.records(of: .contact).count == 8)
        #expect(document.records(of: .horse).count == 2)
        #expect(document.records(of: .vetVisit).count == 2)
        #expect(document.records(of: .competition).count == 2)
        #expect(document.records(of: .competitionStart).count == 2)
        #expect(document.records(of: .purchase).count == 3)
        #expect(document.records(of: .reminder).count == 6)
        #expect(horses(document).map(\.name) == ["Grom", "Iskra"])
    }

    @Test func readsAllHorseStatusesIncludingInjured() throws {
        let statuses = Dictionary(uniqueKeysWithValues: horses(try document("brzegowy")).map { ($0.name, $0.status) })
        #expect(statuses["Błyskawica"] == .injured)
        #expect(statuses["Ósemka"] == .sold)
        #expect(statuses["Ćma"] == .deceased)
        #expect(statuses["Łabędź Ąę"] == .leased)
        #expect(statuses["Żółtko"] == .active)
    }

    @Test func aFoalHasNoPassportNumber() throws {
        let foal = try #require(horses(try document("brzegowy")).first { $0.name == "Źrebak Łatek" })
        #expect(foal.isFoal)
        #expect(foal.passportNumber == nil)
    }

    @Test func amountsAreExactDecimals() throws {
        let purchases = try document("maly").records(of: .purchase).compactMap { $0 as? LocalPurchase }
        let oats = try #require(purchases.first { $0.productName == "Owies" })
        #expect(oats.totalAmount == Money(string: "150"))
        #expect(oats.deliveryCost == Money(string: "12.5"))
        let hay = try #require(try document("brzegowy").records(of: .purchase).compactMap { $0 as? LocalPurchase }.first { $0.productName == "Siano zimowe" })
        #expect(hay.totalAmount == Money(string: "199.99"))
        #expect(hay.assignment == .multipleHorses)
        #expect(hay.horseIds.count == 3)
    }

    @Test func startsBecomeSeparateRecordsOwnedByTheirCompetition() throws {
        let document = try document("maly")
        let competitionIds = Set(document.records(of: .competition).map(\.id))
        let starts = document.records(of: .competitionStart).compactMap { $0 as? LocalCompetitionStart }
        #expect(!starts.isEmpty)
        for start in starts {
            #expect(competitionIds.contains(start.competitionId))
            #expect(start.parentId == start.competitionId)
        }
    }

    @Test func unknownFieldsAreIgnoredAndMissingDefaultsAreFilled() throws {
        let json = """
        {"schemaVersion":"1.3","data":{"horses":[{"id":"h1","createdAt":"2026-01-01T10:00:00Z","updatedAt":"2026-01-01T10:00:00Z","name":"Stary","futureField":{"a":1}}]},"extra":true}
        """
        let document = try ExportDocument.parse(json)
        let horse = try #require(horses(document).first)
        #expect(horse.name == "Stary")
        #expect(horse.status == .active)
        #expect(horse.farrierIntervalWeeks == defaultFarrierIntervalWeeks)
        #expect(horse.isFoal == false)
        #expect(horse.version == 0)
        #expect(document.header.scope.type == "full")
    }

    @Test func readsRemovalsOfAnIncrementalExport() throws {
        let json = """
        {"schemaVersion":"1.5","scope":{"type":"full","updatedSince":"a","nextUpdatedSince":"b","fullRequired":false},
         "data":{},
         "trashed":[{"type":"Horse","id":"h1"},{"type":"DictionaryItem","id":"d1"},{"type":"Nieznany","id":"x"}],
         "purged":[{"type":"Training","id":"t1"}]}
        """
        let document = try ExportDocument.parse(json)
        #expect(document.removals == [
            ExportRemoval(type: .horse, id: "h1", purged: false),
            ExportRemoval(type: .dictionary, id: "d1", purged: false),
            ExportRemoval(type: .training, id: "t1", purged: true),
        ])
        #expect(document.unknownRemovalTypes == ["Nieznany"])
        #expect(document.header.scope.nextUpdatedSince == "b")
        #expect(document.header.scope.fullRequired == false)
    }

    @Test(arguments: ["maly", "brzegowy", "duzy"])
    func writingAndReadingAgainKeepsEveryRecord(set: String) throws {
        let original = try document(set)
        let rewritten = try ExportDocument.parse(original.toJSON())
        #expect(rewritten.records.count == original.records.count)
        for type in RecordType.allCases {
            let before = original.records(of: type)
            let after = rewritten.records(of: type)
            #expect(before.count == after.count, "rodzaj \(type)")
            for (lhs, rhs) in zip(before, after) {
                #expect(try RecordCodec.encode(lhs) == RecordCodec.encode(rhs), "rodzaj \(type), id \(lhs.id)")
            }
        }
    }

    @Test func recordsRoundTripThroughTheCodec() throws {
        let original = try document("maly")
        for exported in original.records {
            let record = exported.record
            let data = try RecordCodec.encode(record)
            let decoded = try RecordCodec.decode(record.recordType, from: data)
            #expect(try RecordCodec.encode(decoded) == data)
        }
    }

    @Test func indexColumnsMatchTheDataModel() throws {
        let document = try document("maly")
        let vet = try #require(document.records(of: .vetVisit).first as? LocalVetVisit)
        #expect(vet.primaryHorseId == vet.horseId)
        #expect(vet.dateKey == vet.visitDateTime.date)
        let horse = try #require(horses(document).first)
        #expect(horse.primaryHorseId == horse.id)
        let purchase = try #require(document.records(of: .purchase).first as? LocalPurchase)
        #expect(purchase.primaryHorseId == nil)
        #expect(purchase.dateKey == purchase.purchaseDate)
    }
}

struct EnumLabelsTests {
    /// Teksty z `App/Resources/android/strings.xml` (kopia z Androida) — źródło prawdy dla `label`.
    private func androidStrings() throws -> [String: String] {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1, !FileManager.default.fileExists(atPath: url.appendingPathComponent("App/Resources/android/strings.xml").path) {
            url.deleteLastPathComponent()
        }
        let file = url.appendingPathComponent("App/Resources/android/strings.xml")
        let parser = StringsParser()
        let xml = try #require(XMLParser(contentsOf: file))
        xml.delegate = parser
        #expect(xml.parse())
        return parser.strings
    }

    private func check<E: EnumLabel & CaseIterable>(_ type: E.Type, _ strings: [String: String]) {
        for value in E.allCases {
            #expect(strings[value.labelKey] == value.label, "\(value.labelKey)")
        }
    }

    @Test func labelsMatchTheAndroidStrings() throws {
        let strings = try androidStrings()
        check(HorseStatus.self, strings)
        check(Sex.self, strings)
        check(ContactType.self, strings)
        check(ReminderKind.self, strings)
        check(ReminderStatus.self, strings)
        check(PurchaseAssignment.self, strings)
        check(ResultStatus.self, strings)
        check(MedicationMode.self, strings)
        check(Intensity.self, strings)
    }

    @Test func injuredAndDeceasedHavePolishNames() {
        #expect(HorseStatus.injured.label == "Kontuzjowany")
        #expect(HorseStatus.deceased.label == "Padł")
        #expect(ReminderKind.deworming.label == "Odrobaczanie")
    }
}

private final class StringsParser: NSObject, XMLParserDelegate {
    var strings: [String: String] = [:]
    private var name: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if elementName == "string" {
            name = attributes["name"]
            text = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if name != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "string", let name {
            strings[name] = text
            self.name = nil
        }
    }
}
