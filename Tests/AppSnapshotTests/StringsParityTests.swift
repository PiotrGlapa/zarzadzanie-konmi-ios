import Foundation
import XCTest
@testable import Horsely

/// Zgodność tekstów z Androidem (T019, SC-008): każdy klucz `strings.xml` i `plurals.xml` istnieje w `Localizable.xcstrings`
/// z tą samą treścią po konwersji formatów, a skompilowany katalog w pakiecie aplikacji zwraca te teksty.
final class StringsParityTests: XCTestCase {
    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1, !FileManager.default.fileExists(atPath: url.appendingPathComponent("App/Resources/Localizable.xcstrings").path) {
            url.deleteLastPathComponent()
        }
        return url
    }

    private struct AndroidStrings {
        var strings: [String: String] = [:]
        var plurals: [String: [String: String]] = [:]
    }

    private func loadAndroid() throws -> AndroidStrings {
        var result = AndroidStrings()
        for name in ["strings.xml", "plurals.xml"] {
            let url = repositoryRoot.appendingPathComponent("App/Resources/android/\(name)")
            let parser = AndroidResourceParser()
            let xml = try XCTUnwrap(XMLParser(contentsOf: url), "Brak pliku \(url.path)")
            xml.delegate = parser
            XCTAssertTrue(xml.parse(), "Błąd odczytu \(name): \(String(describing: xml.parserError))")
            result.strings.merge(parser.strings) { current, _ in current }
            result.plurals.merge(parser.plurals) { current, _ in current }
        }
        // Odwołania @string/nazwa.
        for (key, value) in result.strings where value.hasPrefix("@string/") {
            result.strings[key] = result.strings[String(value.dropFirst("@string/".count))] ?? value
        }
        return result
    }

    /// Ta sama konwersja co w `scripts/sync-strings.ps1`: `%1$s` → `%1$@`, `%d` → `%lld`.
    private func convert(_ text: String) -> String {
        let pattern = try! NSRegularExpression(pattern: "%%|%(\\d+\\$)?([-+0 #]*)(\\d*)(\\.\\d+)?([sdf])")
        let range = NSRange(text.startIndex..., in: text)
        var result = ""
        var last = text.startIndex
        for match in pattern.matches(in: text, range: range) {
            let full = Range(match.range, in: text)!
            result += text[last..<full.lowerBound]
            let token = String(text[full])
            if token == "%%" {
                result += token
            } else {
                func group(_ index: Int) -> String { Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
                let converted: String
                switch group(5) {
                case "s": converted = "%\(group(1))\(group(2))\(group(3))\(group(4))@"
                case "d": converted = "%\(group(1))\(group(2))\(group(3))\(group(4))lld"
                default: converted = token
                }
                result += converted
            }
            last = full.upperBound
        }
        return result + text[last...]
    }

    private struct Catalog {
        var strings: [String: String] = [:]
        var plurals: [String: [String: String]] = [:]
    }

    private func loadCatalog() throws -> Catalog {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("App/Resources/Localizable.xcstrings"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["sourceLanguage"] as? String, "pl")
        let entries = try XCTUnwrap(root["strings"] as? [String: [String: Any]])
        var catalog = Catalog()
        for (key, entry) in entries {
            let localization = try XCTUnwrap(((entry["localizations"] as? [String: Any])?["pl"]) as? [String: Any], key)
            if let unit = (localization["stringUnit"] as? [String: Any])?["value"] as? String {
                catalog.strings[key] = unit
            } else if let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] {
                catalog.plurals[key] = plural.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
            }
        }
        return catalog
    }

    func testEveryAndroidStringExistsWithTheSameText() throws {
        let android = try loadAndroid()
        let catalog = try loadCatalog()
        XCTAssertGreaterThan(android.strings.count, 1000)
        XCTAssertEqual(Set(android.strings.keys), Set(catalog.strings.keys), "Różne zbiory kluczy tekstów")
        for (key, text) in android.strings {
            XCTAssertEqual(catalog.strings[key], convert(text), "Tekst „\(key)”")
        }
    }

    func testEveryAndroidPluralExistsWithAllPolishForms() throws {
        let android = try loadAndroid()
        let catalog = try loadCatalog()
        XCTAssertEqual(Set(android.plurals.keys), Set(catalog.plurals.keys), "Różne zbiory kluczy liczb mnogich")
        for (key, forms) in android.plurals {
            XCTAssertEqual(Set(forms.keys), ["one", "few", "many", "other"], "Formy „\(key)”")
            for (quantity, text) in forms {
                XCTAssertEqual(catalog.plurals[key]?[quantity], convert(text), "Liczba mnoga „\(key)” (\(quantity))")
            }
        }
    }

    func testTheOldProgramNameDoesNotAppearInTexts() throws {
        let catalog = try loadCatalog()
        let texts = Array(catalog.strings.values) + catalog.plurals.values.flatMap(\.values)
        for text in texts {
            XCTAssertFalse(text.lowercased().contains("zarządzanie końmi"), "Stara nazwa programu w tekście: \(text)")
        }
    }

    func testTheCompiledBundleReturnsAndroidTexts() {
        XCTAssertEqual(tr("common_save"), "Zapisz")
        XCTAssertEqual(tr("nav_dashboard"), "Pulpit")
        XCTAssertEqual(tr("horse_status_injured"), "Kontuzjowany")
        XCTAssertEqual(tr("app_name"), "Horsely")
        XCTAssertEqual(tr("dictionary_picker_inactive", "Skoki"), "Skoki (nieaktywna)")
        XCTAssertEqual(tr("rating_content", 3), "Ocena: 3 z 5")
    }

    func testPluralFormsFollowPolishRules() {
        // Polska liczba mnoga: one (1), few (2–4, 22–24…), many (0, 5–21, 25…), other (ułamki — tu nie używane).
        XCTAssertEqual(trPlural("pairing_horses_count", 1), "1 koń")
        XCTAssertEqual(trPlural("pairing_horses_count", 2), "2 konie")
        XCTAssertEqual(trPlural("pairing_horses_count", 5), "5 koni")
        XCTAssertEqual(trPlural("pairing_horses_count", 22), "22 konie")
        XCTAssertEqual(trPlural("pairing_horses_count", 12), "12 koni")
    }
}

private final class AndroidResourceParser: NSObject, XMLParserDelegate {
    var strings: [String: String] = [:]
    var plurals: [String: [String: String]] = [:]

    private var stringName: String?
    private var pluralName: String?
    private var quantity: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "string":
            stringName = attributes["name"]
            text = ""
        case "plurals":
            pluralName = attributes["name"]
            if let pluralName { plurals[pluralName] = [:] }
        case "item":
            quantity = attributes["quantity"]
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if stringName != nil || quantity != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "string":
            if let stringName { strings[stringName] = unescape(text) }
            stringName = nil
        case "item":
            if let pluralName, let quantity { plurals[pluralName]?[quantity] = unescape(text) }
            quantity = nil
        case "plurals":
            pluralName = nil
        default:
            break
        }
    }

    /// Znaki specjalne Androida: `\n`, `\'`, `\"`, `\\`.
    private func unescape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
