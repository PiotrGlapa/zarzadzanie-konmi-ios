import Foundation
import Testing
@testable import HorselyCore

/// Pliki wzorcowe programu skopiowane z Androida (T014) muszą być dostępne w pakiecie testów.
struct FixturesSmokeTests {
    @Test func parityVersionIsProgram200() throws {
        let version = try Fixtures.string("parity/VERSION").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(version == "2.0.0")
    }

    @Test(arguments: ["maly", "brzegowy", "duzy"])
    func parityExportIsJson(set: String) throws {
        let object = try JSONSerialization.jsonObject(with: Fixtures.data("parity/\(set)/export.json"))
        #expect(object is [String: Any])
    }

    @Test func goldenCasesAreAvailable() throws {
        #expect(!(try Fixtures.string("golden/cases.csv")).isEmpty)
    }

    @Test func coreKnowsAppVersion() {
        #expect(HorselyCore.appVersion == "2.0.1")
    }
}
