import HorselyCore
import HorselyKit
import SwiftUI
import XCTest
@testable import Horsely

/// TYMCZASOWA DIAGNOSTYKA (Task 17 I1): która czynność zmienia wysokość dużego tytułu w kolejnych migawkach. Klasa biegnie pierwsza
/// (kolejność alfabetyczna); po każdym kroku migawka wzorcowego ekranu z dużym tytułem, pomiar w `__Snapshots__/diag.txt`.
@MainActor
final class AAAProbeSnapshotTests: XCTestCase {
    private var probe: some View {
        NavigationStack {
            ScrollView { Text("Treść").frame(maxWidth: .infinity) }
                .navigationTitle("Pulpit")
                .navigationBarTitleDisplayMode(.large)
        }
    }

    private func measure(_ step: String) {
        assertScreen(probe, name: "probe-\(step)", variant: .light)
    }

    func testLeakSteps() async throws {
        measure("0-start")
        try await Task.sleep(for: .seconds(3))
        measure("1-after-3s")

        assertScreen(Text("Trwa nagrywanie — Grom · 24 min · 3,2 km").font(.subheadline.weight(.semibold)), name: "step-2-text", variant: .light)
        measure("2-text")

        let startedAt = Date(timeIntervalSince1970: 1_791_201_900)
        let snapshot = RideSnapshot(state: .recording, activeSeconds: 24 * 60 + 10, distanceMeters: 3_240, speedKmh: 9.4, gait: .trot, weakGps: false)
        let ride = ActiveRide(sessionId: "s1", horseName: "Grom", startedAt: startedAt, snapshot: snapshot)
        assertScreen(RideBanner(content: RideStartPolicy.banner(ride)!) {}, name: "step-3-banner", variant: .light)
        measure("3-banner")

        let env = makeEnvironment(mode: .standalone, variant: .light)
        _ = try await SnapshotEntries.seed(env)
        let grom = try XCTUnwrap(env.horseDirectory.horses.first { $0.name == "Grom" })
        let params = RideParameters.resolve(RideDefaults.builtIn, nil)
        let start = Int64(startedAt.timeIntervalSince1970 * 1000)
        let id = try await env.rideSessions.start(horse: HorseRef(id: grom.id, name: grom.name, passportNumber: nil), params: params, startedAtMillis: start)
        try await env.rideSessions.flush(sessionId: id, points: [], snapshot: snapshot, pauses: [])
        measure("4-ride-in-store")

        let observer = Task { await env.observeActiveRide() }
        try await Task.sleep(for: .seconds(1.5))
        measure("5-observer-running")

        await assertSettledScreen(TrainingsSectionView().environment(env), name: "step-6-trainings-ride", variant: .light)
        observer.cancel()
        measure("6-trainings-ride")

        let plain = makeEnvironment(mode: .standalone, variant: .light)
        await assertSettledScreen(TrainingsSectionView().environment(plain), name: "step-7-trainings-plain", variant: .light)
        measure("7-trainings-plain")

        let unset = makeEnvironment(mode: .unset, variant: .light)
        assertScreen(RootView().environment(unset), name: "step-8-welcome", variant: .light)
        measure("8-welcome")

        let more = makeEnvironment(mode: .standalone, variant: .light)
        more.router.selectedTab = .more
        assertScreen(RootView().environment(more), name: "step-9-more", variant: .light)
        measure("9-more")
    }
}
