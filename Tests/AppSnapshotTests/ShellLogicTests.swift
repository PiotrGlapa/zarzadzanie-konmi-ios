import HorselyCore
import HorselyKit
import SwiftUI
import XCTest
@testable import Horsely

/// Logika powłoki bez interfejsu: adresy `horsely://`, menu „Więcej” wg trybu, argumenty uruchomienia testów.
@MainActor
final class ShellLogicTests: XCTestCase {
    private func destination(_ text: String) -> AppDestination {
        DeepLinkRouter.destination(for: URL(string: text)!)
    }

    func testKnownAddressesAreRecognized() {
        XCTAssertEqual(destination("horsely://dashboard"), .dashboard)
        XCTAssertEqual(destination("horsely://reminders"), .reminders)
        XCTAssertEqual(destination("horsely://reminders/abc-123"), .reminder(id: "abc-123"))
        XCTAssertEqual(destination("horsely://entry/new?kind=note"), .newEntry(kind: "note"))
        XCTAssertEqual(destination("horsely://entry/new?kind=farrier"), .newEntry(kind: "farrier"))
        XCTAssertEqual(destination("horsely://queue"), .queue)
    }

    func testUnknownAndForeignAddressesOpenOnlyTheDashboard() {
        XCTAssertEqual(destination("horsely://nieznany"), .dashboard)
        XCTAssertEqual(destination("horsely://entry/new?kind=usun-wszystko"), .dashboard)
        XCTAssertEqual(destination("https://example.com/reminders"), .dashboard)
        XCTAssertEqual(destination("inna://reminders"), .dashboard)
    }

    func testShortcutsMapToDestinations() {
        XCTAssertEqual(DeepLinkRouter.destination(forShortcut: "pl.glapa.horsely.shortcut.note"), .newEntry(kind: "note"))
        XCTAssertEqual(DeepLinkRouter.destination(forShortcut: "pl.glapa.horsely.shortcut.farrier"), .newEntry(kind: "farrier"))
        XCTAssertEqual(DeepLinkRouter.destination(forShortcut: "pl.glapa.horsely.shortcut.reminders"), .reminders)
        XCTAssertNil(DeepLinkRouter.destination(forShortcut: "inna"))
    }

    func testAnUnsetModeDefersTheDestinationUntilAModeIsChosen() {
        let router = DeepLinkRouter()
        router.route(.reminders, mode: .unset)
        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertNil(router.pendingDestination)
        XCTAssertEqual(router.deferredDestination, .reminders)

        router.resumeDeferred(mode: .standalone)
        XCTAssertEqual(router.selectedTab, .reminders)
        XCTAssertEqual(router.pendingDestination, .reminders)
        XCTAssertNil(router.deferredDestination)
    }

    func testRoutingSelectsTheTabOfTheDestination() {
        let router = DeepLinkRouter()
        router.handle(url: URL(string: "horsely://queue")!, mode: .online)
        XCTAssertEqual(router.selectedTab, .more)
        router.handle(url: URL(string: "horsely://reminders/x")!, mode: .online)
        XCTAssertEqual(router.selectedTab, .reminders)
    }

    // MARK: Menu „Więcej”

    private func ids(_ items: [MoreItem]) -> [MoreItem.Destination] { items.map(\.destination) }

    func testMoreMenuInTheOnlineMode() {
        let menu = MoreMenu.sections(mode: .online, queueCount: 3, conflictCount: 0)
        XCTAssertEqual(ids(menu.sections), [.competitions, .purchases, .contacts, .reports])
        XCTAssertEqual(ids(menu.phone), [.queue, .settings, .about])
        XCTAssertEqual(menu.phone.first?.count, 3)
    }

    func testConflictsAppearOnlyWhenThereAreAny() {
        let menu = MoreMenu.sections(mode: .online, queueCount: 0, conflictCount: 2)
        XCTAssertEqual(ids(menu.phone), [.conflicts, .queue, .settings, .about])
        XCTAssertEqual(menu.phone.first?.count, 2)
    }

    func testMoreMenuInTheStandaloneMode() {
        let menu = MoreMenu.sections(mode: .standalone, queueCount: 5, conflictCount: 5)
        XCTAssertEqual(ids(menu.sections), [.competitions, .purchases, .contacts, .reports])
        XCTAssertEqual(ids(menu.phone), [.trash, .dictionaries, .backup, .settings, .about])
    }

    func testMoreMenuBeforeAModeIsChosen() {
        let menu = MoreMenu.sections(mode: .unset, queueCount: 0, conflictCount: 0)
        XCTAssertEqual(ids(menu.phone), [.settings, .about])
    }

    // MARK: Argumenty uruchomienia

    func testLaunchOptionsAreReadFromArguments() {
        let options = LaunchOptions(arguments: ["Horsely", "-UITestFixture", "zrzuty", "-UITestToday", "2026-10-05", "-UITestMode", "standalone"])
        XCTAssertEqual(options.fixture, "zrzuty")
        XCTAssertEqual(options.today, LocalDate(year: 2026, month: 10, day: 5))
        XCTAssertEqual(options.mode, .standalone)
        XCTAssertTrue(options.isTestRun)
        XCTAssertFalse(LaunchOptions(arguments: ["Horsely"]).isTestRun)
        XCTAssertNil(LaunchOptions(arguments: ["-UITestToday", "nie-data"]).today)
    }

    // MARK: Środowisko

    func testEnvironmentPersistsTheModeAndTheTheme() throws {
        let suite = "horsely.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let environment = AppEnvironment.testing(settings: settings)
        XCTAssertEqual(environment.workMode, .unset)
        environment.workMode = .standalone
        environment.theme = .dark
        XCTAssertEqual(settings.workMode, .standalone)
        XCTAssertEqual(settings.theme, .dark)
        XCTAssertEqual(environment.theme.colorScheme, .dark)
        XCTAssertNil(ThemeSetting.system.colorScheme)
    }
}
