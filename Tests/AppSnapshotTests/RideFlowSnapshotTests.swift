import HorselyCore
import HorselyKit
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Horsely

/// Start nagrywania, ekran jazdy, pasek NAG-01 i pytanie o odzyskanie (Task 17 = Android 3.0.2 `RideStartFlowTest`, `RideRecordingScreenTest`):
/// migawki na stałych danych (koń „Grom”, 24:10, 3,24 km, kłus; bez żywego zegara), jasny / ciemny / tekst 200 % według konwencji
/// `SnapshotSupport`, oraz teksty z katalogu podstawione tak jak na ekranie.
///
/// STAN GLOBALNY UIKIT (poprawka I1 Task 17, pomiary CI 45923274989…45927554186): pierwszy pasek nawigacji, który w procesie ułoży tytuł
/// z polską literą z ogonkiem/kreską („Więcej”, „Nagraj jazdę”), na stałe podnosi wysokość widoku dużego tytułu UIKit z 52 do 57,67 pt
/// (etykieta „Pulpit” tej samej czcionki: 40,67 → 46,33 pt; przy 200 %: 73 → 82,67 pt) — dla WSZYSTKICH późniejszych ekranów z dużym tytułem
/// w tym procesie (tytuł niżej o 17 px przy 3x). Robią to ekrany startu i nagrywania z tej klasy oraz `RootView` z kartami (`ShellSnapshotTests`
/// `testMore…`/`testTabBar…`, tak było przed Task 17). Kod paska NAG-01 i obserwacja jazdy NIE zmieniają układu (sonda: pasek, sesja w sklepie,
/// `observeActiveRide`, dział Treningi z paskiem — 52 pt). Stanu nie da się wyzerować, więc:
/// - klasa nazywa się `TrainingsRideFlowSnapshotTests`, żeby XCTest (kolejność alfabetyczna klas) uruchamiał ją PO klasach z wzorcami dużego
///   tytułu nagranymi przed tym stanem (Pulpit, działy) — inaczej ekrany startu z tej klasy przesunęłyby ich tytuły;
/// - migawki z dużym tytułem tej klasy (Pulpit i dział Treningi z paskiem) najpierw same wprowadzają proces w ten stan
///   (`primeNavigationTitleMetrics`), więc są takie same niezależnie od tego, co biegło wcześniej — i odpowiadają działającej aplikacji, w której pasek kart z „Więcej”
///   jest widoczny od startu (jak `shell-dashboard`).
/// Wzorce plików zostają w `__Snapshots__/RideFlowSnapshotTests/` (katalog wynika z nazwy pliku).
@MainActor
final class TrainingsRideFlowSnapshotTests: XCTestCase {
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    /// Ułożenie (bez porównania) paska nawigacji z tytułem „Więcej” tą samą drogą co migawka — patrz opis klasy.
    private func primeNavigationTitleMetrics() async {
        let controller = UIHostingController(
            rootView: NavigationStack { Color.clear.navigationTitle("Więcej").navigationBarTitleDisplayMode(.large) }
        )
        let strategy = Snapshotting<UIViewController, UIImage>.image(drawHierarchyInKeyWindow: true, size: Self.snapshotSize, traits: SnapshotVariant.light.traits)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            strategy.snapshot(controller).run { _ in continuation.resume() }
        }
    }

    /// 2026-10-05 12:05 UTC = 14:05 w Warszawie.
    private let startedAt = Date(timeIntervalSince1970: 1_791_201_900)

    private func ride(_ state: RideState, weakGps: Bool = false, gait: Gait? = .trot, speed: Double? = 9.4) -> ActiveRide {
        ActiveRide(
            sessionId: "s1", horseName: "Grom", startedAt: startedAt,
            snapshot: RideSnapshot(state: state, activeSeconds: 24 * 60 + 10, distanceMeters: 3_240, speedKmh: speed, gait: gait, weakGps: weakGps)
        )
    }

    /// Stały ślad: pętla wokół ujeżdżalni (punkty wyliczone, bez prawdziwego miejsca).
    private var track: Track {
        let start = Int64(startedAt.timeIntervalSince1970 * 1000)
        let points = (0..<60).map { i -> TrackPoint in
            let angle = Double(i) / 60 * 2 * .pi
            return TrackPoint(
                tMillis: start + Int64(i) * 20_000, lat: 52.0 + 0.0012 * sin(angle), lon: 21.0 + 0.0025 * cos(angle) + 0.0004 * Double(i) / 60,
                altM: 100, speedMs: 2.6, hAccM: 5, cadence: nil, intensity: nil
            )
        }
        return Track(startedAtMillis: start, points: points, pauses: [])
    }

    private func recording(_ ride: ActiveRide?, loading: Bool = false) -> some View {
        NavigationStack { RideRecordingScreen(ride: ride, loading: loading, seconds: ride?.snapshot.activeSeconds ?? 0, track: ride == nil ? nil : track) }
    }

    // MARK: Ekran nagrywania

    /// Android: `recording screen shows time distance speed gait and the small map`.
    func testRecordingScreen() {
        for variant in SnapshotVariant.allCases {
            assertScreen(recording(ride(.recording)), name: "ride-recording", variant: variant)
        }
    }

    /// Android: `a paused ride offers resume instead of pause`, `weak gps is announced and missing speed shows a dash`, `an interrupted ride
    /// cannot be paused or photographed and says so`, `without a ride the screen says there is no recording`.
    func testRecordingScreenStates() {
        for variant in [SnapshotVariant.light, .dark] {
            assertScreen(recording(ride(.paused, gait: nil, speed: nil)), name: "ride-recording-paused", variant: variant)
        }
        assertScreen(recording(ride(.recording, weakGps: true, gait: nil, speed: nil)), name: "ride-recording-weak-gps", variant: .light)
        assertScreen(recording(ride(.interrupted, gait: nil, speed: nil)), name: "ride-recording-interrupted", variant: .light)
        assertScreen(recording(nil), name: "ride-recording-none", variant: .light)
    }

    // MARK: Pasek NAG-01

    /// Android: `banner tells a paused and an interrupted ride apart`.
    func testBanners() {
        let banners = VStack(spacing: Spacing.between) {
            ForEach([RideState.recording, .paused, .interrupted], id: \.self) { state in
                RideBanner(content: RideStartPolicy.banner(self.ride(state))!) {}
            }
            Spacer()
        }
        .padding(Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HorselyColor.background)
        for variant in SnapshotVariant.allCases {
            assertScreen(banners, name: "ride-banners", variant: variant)
        }
    }

    /// Android: `the dashboard shows the banner above everything and opens the recording` — pasek obserwuje sesję w sklepie sesji.
    func testBannerOnTheDashboard() async throws {
        await primeNavigationTitleMetrics()
        for variant in [SnapshotVariant.light, .dark] {
            let env = try await environmentWithRide(variant)
            let observer = Task { await env.observeActiveRide() }
            defer { observer.cancel() }
            await assertSettledScreen(DashboardView().environment(env), name: "dashboard-ride-banner", variant: variant)
        }
    }

    /// Android: `the trainings section shows the banner and the record button next to the plus`.
    func testBannerInTheTrainingsSectionWithTheRecordButton() async throws {
        await primeNavigationTitleMetrics()
        let env = try await environmentWithRide(.light)
        let observer = Task { await env.observeActiveRide() }
        defer { observer.cancel() }
        await assertSettledScreen(TrainingsSectionView().environment(env), name: "section-trainings-ride", variant: .light)
    }

    // MARK: Start nagrywania

    private func start(_ model: RideStartModel) -> some View {
        NavigationStack { RideStartView(model: model, onClose: {}, onRecording: {}, onFinish: { _ in }) }
    }

    /// Android: `wear hint text is the verbatim instruction with the do not show again box` (NAG-03 dosłownie).
    func testWearHintStep() {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            assertScreen(start(RideStartModel(preview: .wearHint, environment: env, horses: [])), name: "ride-start-wear-hint", variant: variant)
        }
    }

    /// Android: `location denied shows explanation with settings button`.
    func testLocationDeniedStep() {
        for variant in SnapshotVariant.allCases {
            let env = makeEnvironment(mode: .standalone, variant: variant)
            assertScreen(start(RideStartModel(preview: .locationDenied, environment: env, horses: [])), name: "ride-start-location-denied", variant: variant)
        }
    }

    /// Krok „Dokładna lokalizacja” przed pytaniem systemu i koń z karty konia z „Zmień” (Android: `start from horse tab preselects horse`).
    func testLocationAndHorseFromCardSteps() async throws {
        let env = makeEnvironment(mode: .standalone, variant: .light)
        let horses = try await SnapshotHorses.seed(env)
        let grom = try XCTUnwrap(horses.first { $0.name == "Grom" })
        assertScreen(start(RideStartModel(preview: .location, environment: env, horses: horses)), name: "ride-start-location", variant: .light)
        assertScreen(
            start(RideStartModel(preview: .horse, environment: env, horses: horses, horseId: grom.id, fromCard: true)), name: "ride-start-horse-from-card",
            variant: .light
        )
    }

    // MARK: Odzyskiwanie

    // Pytanie „Zapisz / Odrzuć” to systemowy alert (`UIAlertController`) prezentowany poza widokiem — SnapshotTesting go nie rysuje (próba
    // zrzutu całego okna dała pusty obraz). Treść sprawdza `testRecoveryAndBannerTextsFromTheCatalog`, logikę — `RideStartPolicyTests`.

    /// Teksty pytania i paska z katalogu, podstawione jak na ekranie (godzina w strefie telefonu, dystans jak w Live Activity).
    func testRecoveryAndBannerTextsFromTheCatalog() {
        let pending = UnfinishedRide(sessionId: "s1", horseName: "Grom", startedAt: startedAt, distanceMeters: 6_100, state: .interrupted)
        XCTAssertEqual(RideText.recovery(RideStartPolicy.recovery(pending, timeZone: warsaw)), "Masz niezakończone nagranie (Grom, 14:05, 6,1 km).")
        XCTAssertEqual(tr("ride_recovery_title"), "Niezakończone nagranie")
        XCTAssertEqual(RideText.banner(RideStartPolicy.banner(ride(.recording))!), "Trwa nagrywanie — Grom · 24 min · 3,2 km")
        XCTAssertEqual(RideText.banner(RideStartPolicy.banner(ride(.paused))!), "Nagrywanie wstrzymane — Grom · 24 min · 3,2 km")
        XCTAssertEqual(RideText.banner(RideStartPolicy.banner(ride(.interrupted))!), "Nagrywanie przerwane — Grom · 24 min · 3,2 km")
        XCTAssertEqual(RideText.speed(9.4), "9,4 km/h")
        // NAG-03 dosłownie (wymaganie Androida 3.0.2, `[WYM]` NAG-03).
        XCTAssertEqual(
            tr("ride_wear_text"),
            "Włóż telefon do kieszeni kurtki albo uchwytu na ramieniu, ekranem do ciała. Nie wkładaj go do torby przy siodle ani nie trzymaj w ręce — wtedy chody będą liczone błędnie."
        )
        XCTAssertEqual(tr("ride_location_denied"), "Bez dostępu do dokładnej lokalizacji nie da się nagrać jazdy.")
        XCTAssertEqual(tr("ride_open_settings"), "Otwórz ustawienia")
        XCTAssertEqual(tr("ride_wear_dont_show"), "Nie pokazuj więcej")
    }

    /// `ride-media/` — adresy względne; obce adresy (poza katalogiem, z `..`) są pomijane przy usuwaniu.
    func testRideMediaAddressesStayInsideTheDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-ride-media-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = RideMediaFiles(root: root)
        let file = try files.newFile(extension: "jpg")
        XCTAssertTrue(file.uri.hasPrefix("ride-media/"))
        try Data([1, 2, 3]).write(to: file.url)
        XCTAssertEqual(files.url(for: file.uri), file.url)
        XCTAssertNil(files.url(for: "ride-media/../Files/x.jpg"))
        XCTAssertNil(files.url(for: "Files/x.jpg"))
        files.delete(["ride-media/../x", file.uri])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    // MARK: Pomocnicze

    /// Środowisko z końmi i trwającą jazdą „Grom” zapisaną w JEDYNYM sklepie sesji (migawka 24:10, 3,24 km).
    private func environmentWithRide(_ variant: SnapshotVariant) async throws -> AppEnvironment {
        let env = makeEnvironment(mode: .standalone, variant: variant)
        _ = try await SnapshotEntries.seed(env)
        let grom = try XCTUnwrap(env.horseDirectory.horses.first { $0.name == "Grom" })
        let params = RideParameters.resolve(RideDefaults.builtIn, nil)
        let start = Int64(startedAt.timeIntervalSince1970 * 1000)
        let id = try await env.rideSessions.start(horse: HorseRef(id: grom.id, name: grom.name, passportNumber: nil), params: params, startedAtMillis: start)
        try await env.rideSessions.flush(sessionId: id, points: [], snapshot: ride(.recording).snapshot, pauses: [])
        return env
    }
}
