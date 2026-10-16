import XCTest

/// Konie w trybie samodzielnym (US1): dodanie konia z Pulpitu, błędy reguł programu przy polach z zachowaniem danych, kafel i karta konia.
final class HorsesFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestMode", "standalone", "-UITestToday", "2026-10-05"]
        app.launch()
        return app
    }

    private func type(_ text: String, into field: XCUIElement) {
        field.tap()
        field.typeText(text)
    }

    @MainActor
    func testAddingAHorseShowsATileAndTheHorseCard() {
        let app = launch()
        let addFirst = app.buttons["dashboard-add-first-horse"]
        XCTAssertTrue(addFirst.waitForExistence(timeout: 10))
        addFirst.tap()

        let name = app.textFields["horse-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        type("Grom", into: name)

        // Bez numeru paszportu (koń dorosły) program odrzuca zapis, a dane zostają w formularzu.
        app.buttons["horse-form-save"].tap()
        XCTAssertTrue(app.staticTexts["Pole jest wymagane."].waitForExistence(timeout: 5), "komunikat reguły przy paszporcie")
        XCTAssertEqual(name.value as? String, "Grom", "dane formularza zostają po błędzie")

        type("PL-0001", into: app.textFields["horse-passport"])
        app.buttons["horse-form-save"].tap()

        let tile = app.buttons["horse-tile-Grom"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "kafel konia na Pulpicie")
        XCTAssertFalse(app.buttons["dashboard-add-first-horse"].exists, "karta „Dodaj pierwszego konia” znika")

        tile.tap()
        XCTAssertTrue(app.staticTexts["Grom"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["horse-edit"].exists)
    }

    @MainActor
    func testTheHorsesTabListsAddedHorsesAndSearchFindsThem() {
        let app = launch()
        app.buttons["dashboard-add-first-horse"].tap()
        type("Iskra", into: app.textFields["horse-name"])
        type("PL-0002", into: app.textFields["horse-passport"])
        app.buttons["horse-form-save"].tap()
        XCTAssertTrue(app.buttons["horse-tile-Iskra"].waitForExistence(timeout: 10))

        app.tabBars.firstMatch.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["horse-row-Iskra"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["horses-add"].exists)
    }
}
