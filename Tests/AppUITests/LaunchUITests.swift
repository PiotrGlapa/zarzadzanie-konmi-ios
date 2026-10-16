import XCTest

/// Szkielet testów UI (T001): aplikacja uruchamia się (tryb samodzielny) i pokazuje pasek pięciu kart.
final class LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesWithFiveTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestMode", "standalone", "-UITestToday", "2026-10-05"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.firstMatch.buttons.count, 5)
    }
}
