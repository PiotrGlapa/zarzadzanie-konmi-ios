import XCTest

/// Ustawienia i szybkie akcje (T130, FR-M-UST-00, FR-023): kolejność pozycji w obu trybach, brak „Połączenie z programem”
/// w trybie samodzielnym, szybka akcja „Terminy” otwiera kartę Terminy.
final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openSettings(_ app: XCUIApplication) {
        let more = app.tabBars.firstMatch.buttons.element(boundBy: 4)
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        let settings = app.buttons["more-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
    }

    /// Pozycje widoczne w ustawieniach, od góry.
    private func items(_ app: XCUIApplication, _ identifiers: [String]) -> [String] {
        identifiers
            .compactMap { id -> (String, CGFloat)? in
                let element = app.buttons[id]
                guard element.waitForExistence(timeout: 2) else { return nil }
                return (id, element.frame.minY)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private let all = ["settings-connection", "settings-work-mode", "settings-notifications", "settings-app-lock", "settings-data", "settings-appearance"]

    @MainActor
    func testTheOnlineSettingsStartWithTheConnection() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestToday", "2026-10-05", "-UITestMode", "online", "-UITestProgram", "paired"]
        app.launch()
        openSettings(app)
        XCTAssertEqual(items(app, all), all)
    }

    @MainActor
    func testTheStandaloneSettingsHaveNoConnection() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestToday", "2026-10-05", "-UITestMode", "standalone"]
        app.launch()
        openSettings(app)
        XCTAssertEqual(items(app, all), Array(all.dropFirst()))
        XCTAssertFalse(app.buttons["settings-connection"].exists)

        app.buttons["settings-appearance"].tap()
        XCTAssertTrue(app.otherElements["appearance-theme"].waitForExistence(timeout: 5) || app.buttons["Ciemny"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTheRemindersQuickActionOpensTheRemindersTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestToday", "2026-10-05", "-UITestMode", "standalone", "-UITestShortcut", "pl.glapa.horsely.shortcut.reminders"]
        app.launch()
        let reminders = app.tabBars.firstMatch.buttons.element(boundBy: 2)
        XCTAssertTrue(reminders.waitForExistence(timeout: 20))
        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: reminders)
        waitForExpectations(timeout: 10)
    }
}
