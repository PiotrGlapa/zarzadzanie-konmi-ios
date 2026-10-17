import XCTest
@testable import Horsely

/// Szkielet testów aplikacji (T001): test jest hostowany w aplikacji, więc `Bundle.main` to pakiet Horsely.
/// Testy migawkowe i zgodności tekstów dochodzą w fazie 2 (T018, T019, T037).
final class BundleSmokeTests: XCTestCase {
    func testBundleVersionAndDisplayName() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "2.0.2")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Horsely")
    }

    func testIdentityMatchesBundle() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, AppIdentity.bundleID)
        XCTAssertEqual(AppIdentity.appGroup, "group.pl.glapa.horsely")
    }
}
