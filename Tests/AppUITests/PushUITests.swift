import XCTest

/// Powiadomienia push z serwera w interfejsie (spec 003, T043, T052, T059): tryb awaryjny z powodem, lista reguł przypisanych
/// telefonowi, informacja o kopii zapasowej na serwerze po dotknięciu wiadomości. Zaślepka serwera w procesie (`-UITestProgram push`),
/// stan push wymuszony argumentem — bez Firebase i bez zgody systemu.
final class PushUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(program: String = "push", push: String? = nil, openPush: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-UITestReset", "-UITestToday", "2026-10-05", "-UITestMode", "online", "-UITestProgram", program]
        if let push { arguments += ["-UITestPush", push] }
        if let openPush { arguments += ["-UITestOpenPush", openPush] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func openNotifications(_ app: XCUIApplication) {
        let more = app.tabBars.firstMatch.buttons.element(boundBy: 4)
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        let settings = app.buttons["more-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let notifications = app.buttons["settings-notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.tap()
    }

    @MainActor
    func testWhenApnsIsRefusedTheScreenSaysWhyAndKeepsTheLocalSettings() {
        let app = launch(push: "apnsRefused")
        openNotifications(app)
        let state = element(app, "push-state")
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        XCTAssertTrue(state.label.contains("Telefon nie może odbierać powiadomień z serwera"), "powód trybu awaryjnego: \(state.label)")
        XCTAssertTrue(element(app, "notif-enable").exists, "ustawienia lokalne zostają")
    }

    @MainActor
    func testARegisteredPhoneListsTheRulesAndHidesTheLocalSettings() {
        let app = launch(push: "registered")
        openNotifications(app)
        XCTAssertTrue(app.staticTexts["Kowal: dzień przed o 08:00"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Podsumowanie dnia o 07:30"].exists)
        XCTAssertTrue(element(app, "push-refresh").exists)
        XCTAssertFalse(element(app, "notif-enable").exists, "przy działającym push włączenie powiadomień lokalnych jest ukryte")
    }

    @MainActor
    func testWithoutRulesTheScreenWarnsThatThePhoneGetsNothing() {
        let app = launch(program: "pushNoRules", push: "registered")
        openNotifications(app)
        let rules = element(app, "push-rules")
        XCTAssertTrue(rules.waitForExistence(timeout: 15))
        XCTAssertTrue(rules.label.contains("Brak przypisanych powiadomień"), rules.label)
    }

    @MainActor
    func testTappingTheServerBackupMessageOpensTheInfoScreen() {
        let app = launch(openPush: "backup")
        XCTAssertTrue(element(app, "server-backup-info").waitForExistence(timeout: 20))
        let back = app.buttons["server-backup-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["more-settings"].waitForExistence(timeout: 5), "wraca do menu „Więcej”")
    }

    @MainActor
    func testTappingAReminderMessageForAnUnknownReminderShowsTheRemindersList() {
        let app = launch(openPush: "reminder")
        XCTAssertTrue(app.navigationBars["Terminy"].waitForExistence(timeout: 25) || app.staticTexts["Terminy"].waitForExistence(timeout: 5))
    }
}
