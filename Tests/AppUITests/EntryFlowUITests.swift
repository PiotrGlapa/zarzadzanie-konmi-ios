import XCTest

/// Dodawanie wpisu (US2): „+” → rodzaj → koń → formularz z dzisiejszą datą → „Zapisano” z „Cofnij”; błąd reguły przy polu
/// z zachowaniem danych.
final class EntryFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchWithHorse() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestMode", "standalone", "-UITestToday", "2026-10-05"]
        app.launch()
        app.buttons["dashboard-add-first-horse"].tap()
        let name = app.textFields["horse-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Grom")
        let passport = app.textFields["horse-passport"]
        passport.tap()
        passport.typeText("PL-0001")
        app.buttons["horse-form-save"].tap()
        XCTAssertTrue(app.buttons["horse-tile-Grom"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testAddingANoteShowsSavedWithUndoAndItAppearsOnTheDashboard() {
        let app = launchWithHorse()
        app.buttons["add-entry-button"].tap()
        let kind = app.buttons["new-entry-kind-note"]
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        kind.tap()
        let horse = app.buttons["new-entry-horse-Grom"]
        XCTAssertTrue(horse.waitForExistence(timeout: 5))
        horse.tap()

        let title = app.textFields["entry-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        // Bez tytułu reguła odrzuca zapis, a formularz zostaje z wybranym koniem i datą.
        app.buttons["entry-form-save"].tap()
        XCTAssertTrue(app.staticTexts["Pole jest wymagane."].waitForExistence(timeout: 5), "komunikat reguły przy tytule")
        XCTAssertTrue(title.exists, "formularz zostaje po błędzie")

        title.tap()
        title.typeText("Kuleje na lewą przednią")
        app.buttons["entry-form-save"].tap()

        XCTAssertTrue(app.staticTexts["Zapisano"].waitForExistence(timeout: 10), "komunikat „Zapisano”")
        XCTAssertTrue(app.buttons["Cofnij"].exists, "akcja „Cofnij”")
        XCTAssertTrue(app.staticTexts["Kuleje na lewą przednią"].waitForExistence(timeout: 10), "wpis w „Ostatnich wpisach”")

        app.buttons["Cofnij"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Kuleje na lewą przednią"])
        waitForExpectations(timeout: 10)
    }

    @MainActor
    func testTheNewEntryKindListOffersEveryKindAndAReminder() {
        let app = launchWithHorse()
        app.buttons["add-entry-button"].tap()
        for kind in ["vet", "farrier", "physio", "specialist", "note", "purchase", "start", "training", "reminder"] {
            XCTAssertTrue(app.buttons["new-entry-kind-\(kind)"].waitForExistence(timeout: 5), "rodzaj \(kind)")
        }
    }

    @MainActor
    func testTheRemindersTabShowsAReminderAddedFromTheTab() {
        let app = launchWithHorse()
        app.tabBars.firstMatch.buttons.element(boundBy: 2).tap()
        app.buttons["add-entry-button"].tap()
        let horse = app.buttons["new-entry-horse-Grom"]
        XCTAssertTrue(horse.waitForExistence(timeout: 5))
        horse.tap()
        let title = app.textFields["reminder-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Szczepienie na grypę")
        app.buttons["reminder-form-save"].tap()
        XCTAssertTrue(app.buttons["reminder-row-Szczepienie na grypę"].waitForExistence(timeout: 10), "termin na liście")
    }
}
