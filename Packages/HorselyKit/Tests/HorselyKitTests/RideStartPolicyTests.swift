import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Start nagrywania, pasek NAG-01 i odzyskiwanie (Task 17 = Android 3.0.2 `RideStartFlowTest.kt`, `RideRecordingScreenTest.kt` — część
/// paska i dialogu — oraz `RideRecoveryTest.kt`). Logika z `RideStartPolicy` i `RideRecovery` bez interfejsu; odzyskiwanie na PRAWDZIWYM
/// `RideSessionStore` (plik bazy w katalogu tymczasowym) i prawdziwym kontrolerze z zaślepkami źródeł (`ControllerHarness`).
struct RideStartPolicyTests {
    private let params: EffectiveRideParameters = RideParameters.resolve(RideDefaults.builtIn, nil)
    private let grom = HorseRef(id: "h1", name: "Grom", passportNumber: nil)
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    // MARK: Wymagane testy Task 17

    /// Android: `start from horse tab preselects horse` — koń z karty jest wybrany (z „Zmień” zamiast listy), ale tylko koń ze stajni.
    @Test func startFromHorseTabPreselectsHorse() {
        let stable = ["h1", "h2"]
        #expect(RideStartPolicy.initialSelection(preselectedHorseId: "h2", horseIds: stable) == RideHorseSelection(horseId: "h2", fromCard: true))
        #expect(RideStartPolicy.initialSelection(preselectedHorseId: nil, horseIds: stable) == RideHorseSelection(horseId: nil, fromCard: false))
        // Koń sprzedany (spoza stajni) nie jest wybierany — lista wyboru.
        #expect(RideStartPolicy.initialSelection(preselectedHorseId: "h9", horseIds: stable) == RideHorseSelection(horseId: nil, fromCard: false))
        // Pierwszy krok bez trwającej i niezakończonej jazdy to wybór konia.
        #expect(RideStartPolicy.gate(.none) == .horse)
    }

    /// Android: `wear hint skipped after do not show again` + `wear hint stays visible when the box is not ticked` + `wear hint text is
    /// the verbatim instruction with the do not show again box`.
    @Test func wearHintSkippedAfterDoNotShowAgain() {
        let suite = "horsely.ride-start.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.rideWearHintHidden == false, "domyślnie instrukcja jest pokazywana")

        #expect(RideStartPolicy.next(after: .horse, wearHintHidden: settings.rideWearHintHidden, location: .whenInUse) == .wearHint)
        let content = RideStartPolicy.content(for: .wearHint)
        #expect(content.titleKey == "ride_wear_title")
        #expect(content.textKey == "ride_wear_text", "NAG-03 dosłownie z katalogu")
        #expect(content.doNotShowAgainKey == "ride_wear_dont_show")
        #expect(content.buttonKey == "common_next")

        // „Nie pokazuj więcej” zapisane przy „Dalej” — następny start pomija instrukcję.
        settings.rideWearHintHidden = true
        #expect(SettingsStore(defaults: defaults).rideWearHintHidden, "ustawienie przetrwa nowy obiekt ustawień")
        #expect(RideStartPolicy.next(after: .horse, wearHintHidden: settings.rideWearHintHidden, location: .whenInUse) == .starting)
        #expect(RideStartPolicy.next(after: .horse, wearHintHidden: true, location: .notDetermined) == .location)
    }

    /// Android: `location denied shows explanation with settings button` — odmowa i przybliżona lokalizacja (FR-NAG-09) dają
    /// „Bez dostępu do dokładnej lokalizacji nie da się nagrać jazdy.” z „Otwórz ustawienia”; powrót z ustawień ze zgodą prowadzi do startu.
    @Test func locationDeniedShowsExplanationWithSettingsButton() {
        #expect(RideStartPolicy.next(after: .wearHint, wearHintHidden: false, location: .notDetermined) == .location)
        #expect(RideStartPolicy.content(for: .location).buttonKey == "ride_allow")
        for refused in [LocationAuthorization.denied, .reducedAccuracy] {
            #expect(RideStartPolicy.afterLocationAnswer(refused) == .locationDenied)
            #expect(RideStartPolicy.next(after: .wearHint, wearHintHidden: false, location: refused) == .locationDenied)
        }
        let denied = RideStartPolicy.content(for: .locationDenied)
        #expect(denied.titleKey == "ride_location_denied")
        #expect(denied.titleIsError)
        #expect(denied.buttonKey == "ride_open_settings")
        // Powrót z ustawień: zgoda nadana → start, wciąż bez dokładnej → dalej wyjaśnienie.
        #expect(RideStartPolicy.next(after: .locationDenied, wearHintHidden: false, location: .whenInUse) == .starting)
        #expect(RideStartPolicy.next(after: .locationDenied, wearHintHidden: false, location: .reducedAccuracy) == .locationDenied)
        // Kontroler odmówił startu (zgoda cofnięta między krokiem a startem) — to samo wyjaśnienie.
        #expect(RideStartPolicy.step(for: .reducedAccuracy) == .locationDenied)
        #expect(RideStartPolicy.step(for: .locationDenied) == .locationDenied)
        #expect(RideStartPolicy.step(for: .locationNotDetermined) == .location)
        #expect(RideStartPolicy.step(for: .alreadyRecording) == .opened)
        #expect(RideStartPolicy.step(for: .locationUnavailable) == nil)
    }

    /// Android: `banner visible while recording and opens recording screen` + `banner tells a paused and an interrupted ride apart`. Pasek
    /// obserwuje migawkę z TEGO SAMEGO sklepu, do którego pisze kontroler (jedna instancja `RideSessionStore`).
    @Test func bannerVisibleWhileRecording() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let store = try h.openStore()
        let controller = h.controller(store)
        #expect(RideStartPolicy.banner(nil) == nil)
        #expect(try #require(await awaitRide(store) { $0 == nil }) == nil, "bez jazdy nie ma paska")

        let id = try await controller.start(horse: grom, params: params)
        for s in 1...6 {
            h.clock.millis = Self.start + Int64(s) * 1_000
            await h.emit(fix(s), to: controller)
            await controller.tick()
        }
        let recording = try #require(await awaitRide(store) { $0?.snapshot.state == .recording && ($0?.snapshot.distanceMeters ?? 0) > 0 } ?? nil)
        #expect(recording.sessionId == id)
        let banner = try #require(RideStartPolicy.banner(recording))
        #expect(banner.textKey == "ride_banner")
        #expect(banner.horseName == "Grom")
        #expect(banner.activeSeconds == recording.snapshot.activeSeconds)
        #expect(banner.distanceMeters == recording.snapshot.distanceMeters)
        #expect(banner.openLabelKey == "ride_banner_open")

        #expect(await controller.pause())
        let paused = try #require(await awaitRide(store) { $0?.snapshot.state == .paused } ?? nil)
        #expect(RideStartPolicy.banner(paused)?.textKey == "ride_banner_paused")

        await controller.interrupt()
        let interrupted = try #require(await awaitRide(store) { $0?.snapshot.state == .interrupted } ?? nil)
        #expect(RideStartPolicy.banner(interrupted)?.textKey == "ride_banner_interrupted")

        // Zakończona jazda (czeka na zapis) nie ma paska — sklep jej nie podaje.
        try await store.setState(sessionId: id, state: .finished)
        #expect(try #require(await awaitRide(store) { $0 == nil }) == nil)
    }

    /// Android: `recovery dialog shows horse time distance and offers save and discard` + `recovery dialog uses the phone time zone`.
    @Test func recoveryAlertShowsHorseTimeDistance() {
        // 2026-10-05 12:05 UTC = 14:05 w Warszawie (czas letni).
        let startedAt = Date(timeIntervalSince1970: 1_791_201_900)
        let ride = UnfinishedRide(sessionId: "s1", horseName: "Grom", startedAt: startedAt, distanceMeters: 6_100, state: .interrupted)
        let content = RideStartPolicy.recovery(ride, timeZone: warsaw)
        #expect(content == RideRecoveryContent(sessionId: "s1", horseName: "Grom", startTime: "14:05", distanceMeters: 6_100))
        #expect(RideStartPolicy.recovery(ride, timeZone: TimeZone(identifier: "UTC")!).startTime == "12:05")
        #expect(content.titleKey == "ride_recovery_title")
        #expect(content.saveKey == "ride_recovery_save")
        #expect(content.discardKey == "ride_recovery_discard")
        #expect(content.discardTitleKey == "ride_recovery_discard_title")
        #expect(content.discardConfirmKey == "ride_recovery_discard_confirm")
        // Treść z szablonu `ride_recovery_text` (format po sync-strings.ps1) i dystans jak w pasku.
        let distance = RideNotificationContent.distance(content.distanceMeters, .stringsXml)
        let text = String(format: "Masz niezakończone nagranie (%1$@, %2$@, %3$@).", content.horseName, content.startTime, distance)
        #expect(text == "Masz niezakończone nagranie (Grom, 14:05, 6,1 km).")
    }

    // MARK: Odzyskiwanie po starcie aplikacji (przeniesione z przeglądu Task 15)

    /// Otwarcie aplikacji przez użytkownika z jazdą `.recording` w bazie: `prepareRelaunch(.foreground)` oznacza ją `.interrupted`
    /// ASYNCHRONICZNIE. Odzyskiwanie czeka na to zadanie — pytanie dostaje stan po decyzji (przerwana), nie nieaktualne „nagrywanie”.
    @Test func foregroundLaunchWithStaleRideAsksAfterThePendingRelaunch() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let id = try await recordAndKill(h, seconds: 8)

        h.clock.millis = Self.start + 600_000
        let store = try h.openStore()
        let restarted = h.controller(store, locations: FakeLocationSource(), motion: FakeMotionSource())
        let recovery = RideRecovery(store: store, controller: restarted)
        #expect(restarted.prepareRelaunch(launch: .foreground) != nil)
        // Bez `await` na zadanie startowe — `check()` czeka na nie sama.
        let check = await recovery.check()
        guard case let .pending(ride) = check else {
            Issue.record("oczekiwano pytania o niezakończoną jazdę, jest \(check)")
            return
        }
        #expect(ride.sessionId == id)
        #expect(ride.state == .interrupted, "stan po decyzji startowej, nie nieaktualne nagrywanie")
        #expect(ride.horseName == "Grom")
        #expect(ride.distanceMeters > 0)
        #expect(!restarted.isRunning)
        // Drugie sprawdzenie (np. ekran startu) daje to samo — bez drugiego, innego pytania.
        #expect(await recovery.pending() == ride)
    }

    /// Ponowne uruchomienie w tle (klucz `location`) wznawia jazdę — to nie jest jazda do odzyskania: bez pytania, pasek i ekran nagrywania.
    @Test func backgroundResumedRideIsNotOfferedForRecovery() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let id = try await recordAndKill(h, seconds: 8)

        h.clock.millis = Self.start + 120_000
        let store = try h.openStore()
        let restarted = h.controller(store, locations: FakeLocationSource(), motion: FakeMotionSource())
        let recovery = RideRecovery(store: store, controller: restarted)
        #expect(restarted.prepareRelaunch(launch: .backgroundLocation) != nil)
        #expect(await recovery.check() == .recording(sessionId: id))
        #expect(await recovery.pending() == nil)
        let gateCheck = await recovery.check()
        #expect(RideStartPolicy.gate(gateCheck) == .opened, "start nagrywania otwiera trwającą jazdę zamiast drugiej sesji")
        #expect(await restarted.finish() == id)
    }

    /// Android: `save closes an interrupted ride and leaves it ready for the finish screen` — koniec jazdy to ostatnia aktywność z trasy.
    @Test func saveClosesTheRideAtItsLastActivity() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let id = try await recordAndKill(h, seconds: 8)
        h.clock.millis = Self.start + 3_600_000
        let store = try h.openStore()
        let controller = h.controller(store, locations: FakeLocationSource(), motion: FakeMotionSource())
        controller.prepareRelaunch(launch: .foreground)
        let alerts = AlertRecorder()
        let recovery = RideRecovery(store: store, controller: controller, notifier: LocalRideNotifier(texts: .stringsXml, poster: alerts))
        let ride = try #require(await recovery.pending())

        #expect(try await recovery.save(ride) == id)
        let loaded = try await store.load(sessionId: id)
        #expect(loaded.session.state == .finished)
        let last = try #require(loaded.track.points.last?.tMillis)
        #expect(loaded.session.endedAt == Date(timeIntervalSince1970: TimeInterval(last) / 1000), "koniec = ostatni punkt, nie chwila zapisu")
        #expect(alerts.removed == [.interrupted])
        // Zakończona, niezapisana jazda nadal czeka (ekran zakończenia — Task 21), więc kolejny start zapyta o nią, a nie założy drugiej.
        #expect(await recovery.pending()?.state == .finished)
    }

    /// `finish()` zwraca id także po nieudanym zapisie końcowym (sesja `.interrupted` bez ostatnich punktów) — ekran po „Zakończ” zamyka ją
    /// tak jak „Zapisz” z odzyskiwania, z tym, co już jest w bazie.
    @Test func closeAfterFinishClosesAnInterruptedRide() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let id = try await recordAndKill(h, seconds: 8)
        let store = try h.openStore()
        try await store.setState(sessionId: id, state: .interrupted)
        let recovery = RideRecovery(store: store, controller: h.controller(store, locations: FakeLocationSource(), motion: FakeMotionSource()), log: h.logs.append)

        await recovery.closeAfterFinish(sessionId: id)
        let loaded = try await store.load(sessionId: id)
        #expect(loaded.session.state == .finished)
        #expect(loaded.session.endedAt == Date(timeIntervalSince1970: TimeInterval(loaded.track.lastActivityMillis) / 1000))
        #expect(h.logs.lines.contains { $0.hasPrefix("Zakończenie jazdy: zapis końcowy się nie udał") })
        // Jazda zakończona poprawnie — bez zmian i bez wpisu.
        await recovery.closeAfterFinish(sessionId: id)
        #expect(h.logs.lines.filter { $0.hasPrefix("Zakończenie jazdy") }.count == 1)
    }

    /// Android: `discard removes the session and the media files of the ride`.
    @Test func discardRemovesTheSessionAndItsMedia() async throws {
        let h = ControllerHarness()
        defer { h.cleanUp() }
        let id = try await recordAndKill(h, seconds: 8)
        let store = try h.openStore()
        try await store.addMedia(sessionId: id, uri: "ride-media/a.jpg", contentType: "image/jpeg", capturedAt: Date(timeIntervalSince1970: 1_790_000_005), lat: 52, lon: 21)
        let deleted = LogLines()
        let recovery = RideRecovery(
            store: store, controller: h.controller(store, locations: FakeLocationSource(), motion: FakeMotionSource()),
            deleteMedia: { uris in for uri in uris { deleted.append(uri) } }
        )
        let ride = try #require(await recovery.pending())

        try await recovery.discard(sessionId: ride.sessionId)
        #expect(try await store.unfinished() == nil)
        #expect(deleted.lines == ["ride-media/a.jpg"])
        #expect(await recovery.check() == .none)
    }

    // MARK: Ekran nagrywania (czysta logika)

    /// Android: `the clock ticks between flushes and stops while paused` + `an hour long ride shows hours in the clock`.
    @Test func clockTicksBetweenSnapshotsOnlyWhileRecording() {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let recording = RideSnapshot(state: .recording, activeSeconds: 100, distanceMeters: 0, speedKmh: nil, gait: nil, weakGps: false)
        #expect(RideStartPolicy.displayedSeconds(snapshot: recording, snapshotAt: at, now: at.addingTimeInterval(3.7)) == 103)
        #expect(RideStartPolicy.displayedSeconds(snapshot: recording, snapshotAt: at, now: at.addingTimeInterval(60)) == 110, "najwyżej 10 s ponad migawkę")
        var paused = recording
        paused.state = .paused
        #expect(RideStartPolicy.displayedSeconds(snapshot: paused, snapshotAt: at, now: at.addingTimeInterval(5)) == 100)
        #expect(RideStartPolicy.clock(24 * 60 + 10) == "24:10")
        #expect(RideStartPolicy.clock(3_725) == "1:02:05")
        #expect(RideStartPolicy.clock(-5) == "00:00")
        #expect(RideStartPolicy.speed(9.44, template: "%1$@ km/h") == "9,4 km/h")
        #expect(RideStartPolicy.speed(9.45, template: "%1$@ km/h") == "9,5 km/h")
    }

    /// Android: `UnfinishedRide.needsRecovery` — jazda nagrywana w tym procesie nie jest odzyskiwana, przerwana i zakończona są.
    @Test func onlyARideNotRecordedByThisProcessNeedsRecovery() {
        #expect(!RideStartPolicy.needsRecovery(state: .recording, controllerRunning: true))
        #expect(!RideStartPolicy.needsRecovery(state: .paused, controllerRunning: true))
        #expect(RideStartPolicy.needsRecovery(state: .recording, controllerRunning: false))
        #expect(RideStartPolicy.needsRecovery(state: .interrupted, controllerRunning: true))
        #expect(RideStartPolicy.needsRecovery(state: .finished, controllerRunning: false))
    }

    // MARK: Pomocnicze

    private static let start: Int64 = 1_790_000_000_000

    private func fix(_ step: Int) -> LocationSample {
        LocationSample(lat: 52.0 + Double(step) * 0.0001, lon: 21.0, altM: 100.0, speedMs: 2.2, hAccM: 5.0)
    }

    /// Jazda z `seconds` sekundami punktów (zapisana co 5 s), potem „zabicie procesu” — kontroler porzucony bez `finish`.
    private func recordAndKill(_ h: ControllerHarness, seconds: Int) async throws -> String {
        h.clock.millis = Self.start
        let first = h.controller(try h.openStore())
        let id = try await first.start(horse: grom, params: params)
        for s in 1...seconds {
            h.clock.millis = Self.start + Int64(s) * 1_000
            await h.emit(fix(s), to: first)
            await first.tick()
        }
        return id
    }

    /// Pierwsza wartość strumienia paska spełniająca warunek (`.some(nil)` — brak jazdy) albo `nil` po 20 s.
    private func awaitRide(_ store: RideSessionStore, _ predicate: @escaping @Sendable (ActiveRide?) -> Bool) async -> ActiveRide?? {
        await withTaskGroup(of: ActiveRide??.self) { group in
            group.addTask {
                for await ride in store.observeActiveRide() where predicate(ride) { return .some(ride) }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
