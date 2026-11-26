import Foundation
import HorselyCore
import SnapshotTesting
import SwiftUI
import Synchronization
import UIKit
import XCTest
@testable import Horsely

/// Live Activity nagrywania jazdy (Task 16, FR-NAG-05): migawki widoków z `Shared/RideActivityViews.swift`, z których rozszerzenie
/// `HorselyRideActivity` składa ekran blokady i Dynamic Island. Samego widżetu (`ActivityConfiguration`) nie da się wyrenderować poza
/// systemem, więc test składa te same widoki w ramce o wymiarach ekranu blokady / wyspy iPhone'a 15 Pro (tło jak `activityBackgroundTint`,
/// czarna wyspa).
@MainActor
final class RideActivitySnapshotTests: XCTestCase {
    private let riding = RideActivityState(activeSeconds: 24 * 60 + 10, distanceMeters: 3_240, gait: .trot, weakGps: false, paused: false)
    private let weakGps = RideActivityState(activeSeconds: 24 * 60 + 10, distanceMeters: 3_240, gait: .trot, weakGps: true, paused: false)
    private let paused = RideActivityState(activeSeconds: 24 * 60 + 10, distanceMeters: 3_240, gait: nil, weakGps: false, paused: true)

    private func assertActivity(
        _ view: some View, size: CGSize, name: String, variant: SnapshotVariant, file: StaticString = #filePath, testName: String = #function,
        line: UInt = #line
    ) {
        let controller = UIHostingController(rootView: view)
        assertSnapshot(
            of: controller,
            as: .image(drawHierarchyInKeyWindow: true, precision: 0.98, perceptualPrecision: 0.98, size: size, traits: variant.traits),
            named: "\(name)-\(variant.rawValue)",
            file: file,
            testName: testName,
            line: line
        )
    }

    /// Ekran blokady: kafel aktywności (szerokość 361 pt) na tle „tapety”.
    private func lockScreen(_ state: RideActivityState) -> some View {
        ZStack {
            Color(white: 0.55)
            RideActivityLockScreenView(horseName: "Grom", state: state)
                .background(RideActivityStyle.background)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(width: 361)
        }
    }

    /// Dynamic Island, wersja kompaktowa: ikona konia | wycięcie aparatu | czas jazdy.
    private func compactIsland(_ state: RideActivityState) -> some View {
        ZStack {
            Color(white: 0.92)
            HStack(spacing: 0) {
                RideActivityHorseIcon(size: 20, color: RideActivityStyle.islandPrimary)
                Spacer(minLength: 126)
                RideActivityCompactTrailingView(state: state)
            }
            .padding(.horizontal, 14)
            .frame(width: 250, height: 37)
            .background(Color.black, in: Capsule())
        }
    }

    /// Dynamic Island, rozwinięta: koń i czas u góry, dystans z chodem i przyciski na dole.
    private func expandedIsland(_ state: RideActivityState) -> some View {
        ZStack {
            Color(white: 0.92)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    RideActivityExpandedLeadingView(horseName: "Grom")
                    Spacer()
                    RideActivityExpandedTrailingView(state: state)
                }
                RideActivityExpandedBottomView(state: state)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: 371)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        }
    }

    private let lockSize = CGSize(width: 393, height: 200)
    private let compactSize = CGSize(width: 290, height: 61)
    private let expandedSize = CGSize(width: 393, height: 200)

    /// „Nagrywanie jazdy”, „Grom · 24 min · 3,2 km · kłus”, przyciski „Pauza” i „Zakończ”.
    func testLockScreenWhileRiding() {
        for variant in [SnapshotVariant.light, .dark] {
            assertActivity(lockScreen(riding), size: lockSize, name: "ride-activity-lock", variant: variant)
        }
    }

    /// Słaby GPS: „Grom · 24 min · 3,2 km · Słaby sygnał GPS” w kolorze ostrzeżenia.
    func testLockScreenWithWeakGps() {
        assertActivity(lockScreen(weakGps), size: lockSize, name: "ride-activity-lock-weak-gps", variant: .light)
    }

    /// Pauza: „… · pauza” i przycisk „Wznów” zamiast „Pauza”.
    func testLockScreenWhilePaused() {
        assertActivity(lockScreen(paused), size: lockSize, name: "ride-activity-lock-paused", variant: .dark)
    }

    func testDynamicIslandCompact() {
        assertActivity(compactIsland(riding), size: compactSize, name: "ride-activity-island-compact", variant: .light)
    }

    func testDynamicIslandExpanded() {
        assertActivity(expandedIsland(riding), size: expandedSize, name: "ride-activity-island-expanded", variant: .light)
        assertActivity(expandedIsland(paused), size: expandedSize, name: "ride-activity-island-expanded-paused", variant: .light)
    }
}

/// Intencje przycisków i dane aktywności (bez widoków).
final class RideActivityIntentTests: XCTestCase {
    /// „Pauza” / „Wznów” / „Zakończ” z Live Activity trafiają do odbiorcy zarejestrowanego w `RideActivityActions.shared` (w aplikacji —
    /// kontroler nagrywania); „Zakończ” otwiera aplikację i zostawia id sesji dla ekranu zakończenia (Task 21).
    func testIntentsReachTheRegisteredHandler() async throws {
        let handler = RecordingRideActions()
        RideActivityActions.shared.register(handler)
        defer { RideActivityActions.shared.register(RideBridge.shared.controller) }

        _ = try await PauseRideIntent().perform()
        _ = try await ResumeRideIntent().perform()
        _ = try await FinishRideIntent().perform()

        XCTAssertEqual(handler.calls, [.pause, .resume, .finish])
        XCTAssertEqual(RideActivityActions.shared.takeFinishedSessionId(), "sesja-1")
        XCTAssertTrue(FinishRideIntent.openAppWhenRun, "„Zakończ” otwiera aplikację na ekranie zakończenia")
        XCTAssertFalse(PauseRideIntent.openAppWhenRun)
        XCTAssertFalse(ResumeRideIntent.openAppWhenRun)
    }

    /// Poprawka I2: przycisk bez zarejestrowanego kontrolera nie jest cichym sukcesem — intencja kończy się, ale akcja trafia do dziennika
    /// diagnostycznego (bez nazwy konia).
    func testIntentWithoutAHandlerIsLogged() async throws {
        let lines = LoggedLines()
        RideActivityActions.shared.register(nil)
        RideActivityActions.shared.setLog(lines.append)
        defer {
            RideActivityActions.shared.setLog(nil)
            RideActivityActions.shared.register(RideBridge.shared.controller)
        }

        _ = try await PauseRideIntent().perform()
        _ = try await FinishRideIntent().perform()

        XCTAssertEqual(lines.all, [
            "Live Activity: przycisk „Pauza” bez kontrolera nagrywania — pominięto",
            "Live Activity: przycisk „Zakończ” bez kontrolera nagrywania — pominięto",
        ])
        XCTAssertNil(RideActivityActions.shared.takeFinishedSessionId())
    }

    /// Napisy z katalogu (`strings.xml` Androida): przyciski powiadomienia nagrywania i treść stanu.
    func testTextsComeFromTheCatalog() {
        XCTAssertEqual(RideActivityButtonTexts.app, RideActivityButtonTexts(pause: "Pauza", resume: "Wznów", finish: "Zakończ"))
        let state = RideActivityState(activeSeconds: 24 * 60, distanceMeters: 3_240, gait: .trot, weakGps: false, paused: false)
        XCTAssertEqual(RideNotificationContent.contentText(horseName: "Grom", state: state, texts: .app), "Grom · 24 min · 3,2 km · kłus")
        var weak = state
        weak.weakGps = true
        XCTAssertEqual(RideNotificationContent.contentText(horseName: "Grom", state: weak, texts: .app), "Grom · 24 min · 3,2 km · Słaby sygnał GPS")
    }

    /// Stan aktywności (wysyłany do systemu i widoczny na ekranie blokady) ma tylko czas, dystans, chód, słaby GPS i pauzę — bez
    /// współrzędnych (konstytucja 3.0.0); przekład stanu w obie strony jest bezstratny.
    func testContentStateHasNoCoordinates() throws {
        let state = RideActivityState(activeSeconds: 600, distanceMeters: 1_250, gait: .canter, weakGps: true, paused: false)
        let content = RideActivityAttributes.ContentState(state)
        XCTAssertEqual(content.gait, "Canter")
        XCTAssertEqual(content.rideState, state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(content)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["activeSeconds", "distanceMeters", "gait", "weakGps", "paused"])
        let attributes = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(RideActivityAttributes(horseName: "Grom"))) as? [String: Any])
        XCTAssertEqual(Set(attributes.keys), ["horseName"])
    }
}

/// Zapisuje akcje zamiast nagrywać jazdę.
private final class RecordingRideActions: RideActivityActionHandler {
    private let state = Mutex<[RideActivityAction]>([])

    var calls: [RideActivityAction] { state.withLock { $0 } }

    func pauseRide() async -> Bool {
        state.withLock { $0.append(.pause) }
        return true
    }

    func resumeRide() async -> Bool {
        state.withLock { $0.append(.resume) }
        return true
    }

    func finishRide() async -> String? {
        state.withLock { $0.append(.finish) }
        return "sesja-1"
    }
}

/// Wpisy dziennika z rejestru akcji.
private final class LoggedLines: Sendable {
    private let state = Mutex<[String]>([])

    var all: [String] { state.withLock { $0 } }

    var append: @Sendable (String) -> Void { { [self] line in self.state.withLock { $0.append(line) } } }
}
