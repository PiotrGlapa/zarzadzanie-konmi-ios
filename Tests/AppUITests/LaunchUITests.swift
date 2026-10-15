import XCTest

/// Szkielet testów UI (T001): aplikacja uruchamia się i pokazuje pasek pięciu kart.
/// Przepływy użytkownika dochodzą z historiami US1–US9.
final class LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesWithFiveTabs() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.firstMatch.buttons.count, 5)
    }
}
