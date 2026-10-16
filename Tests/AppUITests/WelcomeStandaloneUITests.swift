import XCTest

/// Wybór trybu pracy przy pierwszym uruchomieniu (T040, FR-TRB-02): domyślnie „Tak, połącz z programem”, „Nie, używaj samodzielnie”
/// → Pulpit z podpowiedzią „Dodaj pierwszego konia”, a po ponownym uruchomieniu od razu Pulpit.
final class WelcomeStandaloneUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func firstLaunch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset", "-UITestToday", "2026-10-05"]
        return app
    }

    @MainActor
    func testStandaloneChoiceOpensTheEmptyDashboardAndIsRemembered() {
        // Prośba systemu o zgodę na powiadomienia (język symulatora: angielski) — przyjmujemy ją.
        addUIInterruptionMonitor(withDescription: "Powiadomienia") { alert in
            for label in ["Allow", "Zezwól", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        let app = firstLaunch()
        app.launch()

        let online = app.buttons["mode-online"]
        XCTAssertTrue(online.waitForExistence(timeout: 10), "ekran wyboru trybu")
        XCTAssertTrue(online.isSelected, "domyślnie zaznaczone „Tak, połącz z programem”")
        XCTAssertFalse(app.buttons["mode-restore"].exists, "„Odtwórz z kopii” tylko po wyborze trybu samodzielnego")

        app.buttons["mode-standalone"].tap()
        XCTAssertTrue(app.buttons["mode-standalone"].isSelected)
        XCTAssertTrue(app.buttons["mode-restore"].exists)

        app.buttons["mode-next"].tap()
        let notifications = app.buttons["notifications-next"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5), "wyjaśnienie zgody na powiadomienia")
        notifications.tap()
        app.tap() // pozwala monitorowi obsłużyć okno systemowe, jeśli się pojawiło

        let addFirst = app.buttons["dashboard-add-first-horse"]
        XCTAssertTrue(addFirst.waitForExistence(timeout: 15), "Pulpit z podpowiedzią „Dodaj pierwszego konia”")
        XCTAssertTrue(app.tabBars.firstMatch.exists)

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-UITestToday", "2026-10-05"] // bez -UITestReset: tryb jest zapamiętany
        relaunched.launch()
        XCTAssertTrue(relaunched.buttons["dashboard-add-first-horse"].waitForExistence(timeout: 15), "po ponownym uruchomieniu od razu Pulpit")
        XCTAssertFalse(relaunched.buttons["mode-next"].exists)
    }

    @MainActor
    func testOnlineChoiceLeadsToPairingAndBackToTheChoice() {
        let app = firstLaunch()
        app.launch()
        XCTAssertTrue(app.buttons["mode-next"].waitForExistence(timeout: 10))
        app.buttons["mode-next"].tap() // domyślnie „Tak, połącz z programem”
        let back = app.buttons["pairing-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["mode-online"].waitForExistence(timeout: 5), "przerwane parowanie wraca do wyboru trybu")
    }
}
