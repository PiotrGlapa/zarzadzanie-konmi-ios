import HorselyCore
import HorselyKit
import Synchronization
import XCTest
@testable import Horsely

/// Teksty nagrywania z katalogu aplikacji (Task 15 = Android `RideNotificationTest.kt`): te same napisy co powiadomienie Androida —
/// „Grom · 24 min · 3,2 km · kłus” (na iOS: Live Activity, Task 16) i ostrzeżenia jako powiadomienia lokalne.
final class RideNotificationTextTests: XCTestCase {
    private let texts = RideNotificationTexts.app

    private func snapshot(
        activeSeconds: Int = 24 * 60 + 10, distanceMeters: Int = 3_240, gait: Gait? = .trot, weakGps: Bool = false, state: RideState = .recording
    ) -> RideSnapshot {
        RideSnapshot(state: state, activeSeconds: activeSeconds, distanceMeters: distanceMeters, speedKmh: 10.0, gait: gait, weakGps: weakGps)
    }

    private func text(_ snapshot: RideSnapshot) -> String {
        RideNotificationContent.contentText(horseName: "Grom", snapshot: snapshot, texts: texts)
    }

    /// Android: `text shows horse minutes distance and gait`.
    func testTextShowsHorseMinutesDistanceAndGait() {
        XCTAssertEqual(text(snapshot()), "Grom · 24 min · 3,2 km · kłus")
        XCTAssertEqual(text(snapshot(gait: .canter)), "Grom · 24 min · 3,2 km · galop")
        XCTAssertEqual(text(snapshot(gait: .walk)), "Grom · 24 min · 3,2 km · stęp")
        XCTAssertEqual(text(snapshot(gait: .stop)), "Grom · 24 min · 3,2 km · postój")
        XCTAssertEqual(text(snapshot(activeSeconds: 0, distanceMeters: 0, gait: nil)), "Grom · 0 min · 0,0 km")
    }

    /// Android: `long rides show hours`.
    func testLongRidesShowHours() {
        XCTAssertEqual(text(snapshot(activeSeconds: 65 * 60, distanceMeters: 12_000, gait: .walk)), "Grom · 1 h 05 min · 12,0 km · stęp")
    }

    /// Android: `weak gps replaces the gait and a pause says so`.
    func testWeakGpsReplacesTheGaitAndAPauseSaysSo() {
        XCTAssertEqual(text(snapshot(weakGps: true)), "Grom · 24 min · 3,2 km · Słaby sygnał GPS")
        XCTAssertEqual(text(snapshot(gait: nil, state: .paused)), "Grom · 24 min · 3,2 km · pauza")
    }

    /// Kilometry jak `String.format("%.1f")` Javy (połówka w górę): 3 250 m → 3,3 (printf w C dałby 3,2).
    func testDistanceRoundsHalfUpLikeJava() {
        XCTAssertEqual(text(snapshot(distanceMeters: 3_250, gait: nil)), "Grom · 24 min · 3,3 km")
        XCTAssertEqual(text(snapshot(distanceMeters: 3_249, gait: nil)), "Grom · 24 min · 3,2 km")
    }

    /// Android: `battery auto finish and interruption notifications use the agreed text` (+ słaby GPS jako powiadomienie lokalne na iOS).
    func testBatteryAutoFinishAndInterruptionNotificationsUseTheAgreedText() async {
        let poster = CollectingAlertPoster()
        let notifier = LocalRideNotifier(texts: texts, poster: poster)
        await notifier.batteryLow(percent: 15)
        await notifier.autoFinished()
        await notifier.interrupted()
        await notifier.weakGps(started: true)

        XCTAssertEqual(
            poster.alerts.map(\.body),
            [
                "Bateria 15% — nagrywanie trwa, podłącz telefon albo zakończ jazdę.",
                "Nagrywanie zakończone po 8 godzinach.",
                "Nagrywanie przerwane — otwórz aplikację, aby zapisać jazdę",
                "Słaby sygnał GPS",
            ]
        )
        XCTAssertTrue(poster.alerts.allSatisfy { $0.title == "Nagrywanie jazdy" })
        XCTAssertEqual(poster.alerts.map(\.kind), [.batteryLow, .autoFinished, .interrupted, .weakGps])
    }
}

/// Zbiera ostrzeżenia zamiast wysyłać je do `UNUserNotificationCenter`.
final class CollectingAlertPoster: RideAlertPoster {
    private let state = Mutex<[RideAlert]>([])

    var alerts: [RideAlert] { state.withLock { $0 } }

    func post(_ alert: RideAlert) async { state.withLock { $0.append(alert) } }

    func remove(_ kind: RideAlert.Kind) async {}
}
