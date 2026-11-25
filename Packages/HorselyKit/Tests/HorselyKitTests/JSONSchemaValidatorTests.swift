import Foundation
import HorselyCore
import Testing
import ZIPFoundation

/// Walidator schematu z testów kopii (`JSONSchemaValidator`) musi odrzucać pliki niezgodne z `export-schema-1.6.json`: każda mutacja
/// poprawnego `export.json` (z kopii Androida 3.0.2) daje błąd właściwego słowa kluczowego.
struct JSONSchemaValidatorTests {
    /// Element ścieżki w dokumencie JSON.
    enum Step: Sendable {
        case field(String)
        case index(Int)
    }

    enum Mutation: String, CaseIterable, Sendable {
        case extraRootField
        case recordingWithoutTrackData
        case rideDefaultsNumber
        case badSha256
        case moneyNotInCents
        case latitudeAbove90
        case unknownReference

        /// Fragment komunikatu błędu, którego oczekuje mutacja.
        var expected: String {
            switch self {
            case .extraRootField: "pole spoza schematu dataSchemaVersion"
            case .recordingWithoutTrackData: "brak wymaganego pola trackData"
            case .rideDefaultsNumber: "oneOf"
            case .badSha256: "nie pasuje do"
            case .moneyNotInCents: "nie jest wielokrotnością"
            case .latitudeAbove90: "> maximum"
            case .unknownReference: "nieznane odwołanie #/$defs/brak"
            }
        }
    }

    private func resource(_ path: String) -> URL {
        let base = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        let candidates = [base.appendingPathComponent("Resources/\(path)"), base.appendingPathComponent(path)]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    /// Poprawny `export.json` 1.6 — z kopii zapisanej przez Androida 3.0.2.
    private func androidExport() throws -> JSONValue {
        let archive = try Archive(url: resource("backup-3/android-3.0.2.zkkopia"), accessMode: .read)
        let entry = try #require(archive["export.json"])
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return try JSONValue.parseKeepingScale(data)
    }

    private func schemaText() throws -> String {
        String(decoding: try Data(contentsOf: resource("contracts/export-schema-1.6.json")), as: UTF8.self)
    }

    /// Dokument z wartością `value` pod ścieżką (`nil` usuwa pole).
    private static func setting(_ value: JSONValue?, at path: ArraySlice<Step>, in node: JSONValue) -> JSONValue {
        guard let step = path.first else { return value ?? .null }
        switch (step, node) {
        case let (.field(name), .object(fields)):
            var copy = fields
            if path.count == 1 {
                copy[name] = value
            } else {
                copy[name] = setting(value, at: path.dropFirst(), in: fields[name] ?? .null)
            }
            return .object(copy)
        case let (.index(index), .array(items)):
            var copy = items
            copy[index] = setting(value, at: path.dropFirst(), in: items[index])
            return .array(copy)
        default:
            return node
        }
    }

    private func errors(schema: String, document: JSONValue) throws -> [String] {
        try JSONSchemaValidator(schema: Data(schema.utf8)).errors(Data(document.textKeepingScale().utf8))
    }

    @Test func theAndroidExportIsValid() throws {
        let found = try errors(schema: schemaText(), document: androidExport())
        #expect(found.isEmpty, "\(Array(found.prefix(5)))")
    }

    @Test(arguments: Mutation.allCases)
    func aMutatedExportIsRejected(mutation: Mutation) throws {
        var schema = try schemaText()
        var document = try androidExport()
        let data = Step.field("data")
        switch mutation {
        case .extraRootField:
            document = Self.setting(.string("3.0"), at: [.field("dataSchemaVersion")], in: document)
        case .recordingWithoutTrackData:
            document = Self.setting(nil, at: [data, .field("trainingRecordings"), .index(0), .field("trackData")], in: document)
        case .rideDefaultsNumber:
            document = Self.setting(.number(5), at: [data, .field("rideDefaults")], in: document)
        case .badSha256:
            document = Self.setting(.string("XYZ"), at: [data, .field("attachments"), .index(0), .field("sha256")], in: document)
        case .moneyNotInCents:
            let amount = try #require(DecimalText.parse("1.005"))
            document = Self.setting(.number(amount), at: [data, .field("trainings"), .index(0), .field("cost")], in: document)
        case .latitudeAbove90:
            document = Self.setting(.number(91), at: [data, .field("attachments"), .index(0), .field("latitude")], in: document)
        case .unknownReference:
            #expect(schema.contains("\"#/$defs/attachment\""))
            schema = schema.replacingOccurrences(of: "\"#/$defs/attachment\"", with: "\"#/$defs/brak\"")
        }

        let found = try errors(schema: schema, document: document)

        #expect(!found.isEmpty, "\(mutation.rawValue): walidator nie zgłosił błędu")
        #expect(found.contains { $0.contains(mutation.expected) }, "\(mutation.rawValue): \(Array(found.prefix(5)))")
    }
}
