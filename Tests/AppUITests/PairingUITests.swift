import XCTest

/// Parowanie i połączenie z programem (T095) z zaślepką programu w procesie aplikacji (`-UITestProgram`): wpis ręczny i wynik
/// parowania, komunikat „Komputer nie odpowiada” zwijany do ikonki, konflikt rozstrzygnięty „Przyjmij z programu”.
final class PairingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testManualPairingShowsTheProgramAndOpensTheDashboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestToday", "2026-10-05", "-UITestProgram", "paired"]
        app.launch()

        XCTAssertTrue(app.buttons["mode-online"].waitForExistence(timeout: 10))
        app.buttons["mode-next"].tap()
        XCTAssertTrue(app.buttons["pairing-manual"].waitForExistence(timeout: 5), "wybór: kod QR albo wpis ręczny")
        app.buttons["pairing-manual"].tap()

        let address = app.textFields["pairing-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("http://192.168.1.20:5080")
        let key = app.secureTextFields["pairing-key"]
        key.tap()
        key.typeText("hk_uitest")
        app.buttons["pairing-connect"].tap()

        // `http` — ostrzeżenie o braku szyfrowania przed połączeniem.
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "ostrzeżenie o połączeniu bez szyfrowania")
        alert.buttons.element(boundBy: 0).tap()

        let version = app.staticTexts["pairing-result-version"]
        XCTAssertTrue(version.waitForExistence(timeout: 10), "wynik parowania")
        XCTAssertTrue(version.label.contains("2.0.0"))
        XCTAssertTrue(app.staticTexts["pairing-result-horses"].label.contains("1"))
        app.buttons["pairing-continue"].tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "Pulpit po parowaniu")
    }

    @MainActor
    func testAnUnreachableComputerIsReportedAndCollapsesToTheIcon() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestToday", "2026-10-05", "-UITestMode", "online", "-UITestProgram", "offline"]
        app.launch()

        let overlay = app.otherElements["connection-overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 15), "komunikat „Komputer nie odpowiada”")
        let icon = app.buttons["connection-icon"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5), "ikonka w pasku tytułu")
        // Po 3 s komunikat zwija się do samej ikonki.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: overlay)
        wait(for: [gone], timeout: 15)
        XCTAssertTrue(icon.exists)
    }

    @MainActor
    func testAConflictIsResolvedByAcceptingTheProgramVersion() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestToday", "2026-10-05", "-UITestMode", "online", "-UITestProgram", "conflict"]
        app.launch()

        let card = app.buttons["dashboard-conflicts"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "karta „Konflikty do rozstrzygnięcia” na Pulpicie")
        card.tap()
        let row = app.buttons["conflict-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let accept = app.buttons["conflict-accept-theirs"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.tap()
        XCTAssertTrue(app.staticTexts["conflicts-empty"].waitForExistence(timeout: 10), "brak konfliktów po rozstrzygnięciu")
    }
}
