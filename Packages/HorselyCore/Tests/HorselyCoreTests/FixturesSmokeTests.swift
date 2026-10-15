import Foundation
import Testing
@testable import HorselyCore

/// Pliki wzorcowe programu skopiowane z Androida (T014) muszą być dostępne w pakiecie testów.
struct FixturesSmokeTests {
    private func fixture(_ path: String) -> URL {
        Bundle.module.resourceURL!.appendingPathComponent("Resources/\(path)")
    }

    @Test func parityVersionIsProgram200() throws {
        let version = try String(contentsOf: fixture("parity/VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(version == "2.0.0")
    }

    @Test(arguments: ["maly", "brzegowy", "duzy"])
    func parityExportIsJson(set: String) throws {
        let data = try Data(contentsOf: fixture("parity/\(set)/export.json"))
        let object = try JSONSerialization.jsonObject(with: data)
        #expect(object is [String: Any])
    }

    @Test func goldenCasesAreAvailable() throws {
        let cases = try String(contentsOf: fixture("golden/cases.csv"), encoding: .utf8)
        #expect(!cases.isEmpty)
    }

    @Test func coreKnowsAppVersion() {
        #expect(HorselyCore.appVersion == "2.0.1")
    }
}
