// Treść stanu jazdy dla Live Activity (Task 16) — ten sam formater co tekst powiadomienia Androida (`RideNotification.contentText`):
// „Grom · 24 min · 3,2 km · kłus”. Teksty przepisane ze `strings.xml` Androida 3.0.2 (format po `sync-strings.ps1`); zgodność z katalogiem
// aplikacji sprawdza `RideNotificationTextTests` w `AppSnapshotTests`.

import Testing
@testable import HorselyCore

@Suite struct RideStatusTextTests {
    private let texts = RideNotificationTexts(
        title: "Nagrywanie jazdy", weakGps: "Słaby sygnał GPS", paused: "pauza", gaitStop: "postój", gaitWalk: "stęp", gaitTrot: "kłus",
        gaitCanter: "galop", durationMinutes: "%1$lld min", durationHoursMinutes: "%1$lld h %2$02lld min", distanceKm: "%1$@ km",
        batteryLow: "Bateria %1$lld%% — nagrywanie trwa, podłącz telefon albo zakończ jazdę.", autoFinished: "Nagrywanie zakończone po 8 godzinach.",
        interrupted: "Nagrywanie przerwane — otwórz aplikację, aby zapisać jazdę"
    )

    private func state(seconds: Int = 24 * 60 + 10, meters: Int = 3_240, gait: Gait? = .trot, weakGps: Bool = false, paused: Bool = false) -> RideActivityState {
        RideActivityState(activeSeconds: seconds, distanceMeters: meters, gait: gait, weakGps: weakGps, paused: paused)
    }

    @Test func liveActivityTextMatchesTheAndroidNotification() {
        #expect(RideNotificationContent.contentText(horseName: "Grom", state: state(), texts: texts) == "Grom · 24 min · 3,2 km · kłus")
        #expect(RideNotificationContent.contentText(horseName: "Grom", state: state(weakGps: true), texts: texts) == "Grom · 24 min · 3,2 km · Słaby sygnał GPS")
        #expect(RideNotificationContent.contentText(horseName: "Grom", state: state(weakGps: true, paused: true), texts: texts) == "Grom · 24 min · 3,2 km · pauza")
        #expect(RideNotificationContent.contentText(horseName: "Grom", state: state(seconds: 65 * 60, meters: 12_000, gait: .walk), texts: texts) == "Grom · 1 h 05 min · 12,0 km · stęp")
        #expect(RideNotificationContent.contentText(horseName: "Grom", state: state(seconds: 0, meters: 0, gait: nil), texts: texts) == "Grom · 0 min · 0,0 km")
        #expect(RideNotificationContent.distanceAndStatus(state: state(), texts: texts) == "3,2 km · kłus")
        #expect(RideNotificationContent.duration(24 * 60 + 59, texts) == "24 min")
    }

    /// Migawka nagrywania i stan aktywności dają ten sam napis (powiadomienie Androida = Live Activity).
    @Test func snapshotAndActivityStateGiveTheSameText() {
        let snapshot = RideSnapshot(state: .paused, activeSeconds: 600, distanceMeters: 1_250, speedKmh: 12, gait: .canter, weakGps: false)
        let activity = RideActivityState(snapshot)
        #expect(activity == RideActivityState(activeSeconds: 600, distanceMeters: 1_250, gait: .canter, weakGps: false, paused: true))
        #expect(RideNotificationContent.contentText(horseName: "Grom", snapshot: snapshot, texts: texts) == "Grom · 10 min · 1,3 km · pauza")
        #expect(RideNotificationContent.contentText(horseName: "Grom", state: activity, texts: texts) == "Grom · 10 min · 1,3 km · pauza")
    }

    /// Aktualizacja Live Activity tylko przy zmianie widocznej treści: sekundy w tej samej minucie i metry w tej samej dziesiątej części km nie
    /// zmieniają napisu; minuta, 100 m, chód, słaby GPS i pauza — zmieniają.
    @Test func sameDisplayIgnoresSecondsAndMetersBelowTheShownPrecision() {
        let base = state(seconds: 24 * 60, meters: 3_160)
        #expect(base.sameDisplay(as: state(seconds: 24 * 60 + 59, meters: 3_249)))
        #expect(!base.sameDisplay(as: state(seconds: 25 * 60, meters: 3_160)))
        #expect(!base.sameDisplay(as: state(seconds: 24 * 60, meters: 3_250)))
        #expect(!base.sameDisplay(as: state(seconds: 24 * 60, meters: 3_160, gait: .canter)))
        #expect(!base.sameDisplay(as: state(seconds: 24 * 60, meters: 3_160, weakGps: true)))
        #expect(!base.sameDisplay(as: state(seconds: 24 * 60, meters: 3_160, paused: true)))
        // Przy pauzie chód jest niewidoczny — jego zmiana nie zmienia napisu.
        #expect(state(gait: .walk, paused: true).sameDisplay(as: state(gait: .trot, paused: true)))
    }
}
