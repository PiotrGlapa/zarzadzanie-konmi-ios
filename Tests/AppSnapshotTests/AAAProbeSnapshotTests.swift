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

    private func start(_ model: RideStartModel) -> some View {
        NavigationStack { RideStartView(model: model, onClose: {}, onRecording: {}, onFinish: { _ in }) }
    }

    func testLeakSteps() async throws {
        measure("0-start")
        let env = makeEnvironment(mode: .standalone, variant: .light)
        let horses = try await SnapshotHorses.seed(env)
        assertScreen(start(RideStartModel(preview: .wearHint, environment: env, horses: [])), name: "step-1-wear", variant: .light)
        measure("1-wear")
        assertScreen(start(RideStartModel(preview: .locationDenied, environment: env, horses: [])), name: "step-2-denied", variant: .light)
        measure("2-denied")
        assertScreen(start(RideStartModel(preview: .location, environment: env, horses: horses)), name: "step-3-location", variant: .light)
        measure("3-location")
        assertScreen(start(RideStartModel(preview: .horse, environment: env, horses: horses, horseId: horses.first?.id, fromCard: true)), name: "step-4-horse", variant: .light)
        measure("4-horse")

        let startedAt = Date(timeIntervalSince1970: 1_791_201_900)
        let snapshot = RideSnapshot(state: .recording, activeSeconds: 24 * 60 + 10, distanceMeters: 3_240, speedKmh: 9.4, gait: .trot, weakGps: false)
        let ride = ActiveRide(sessionId: "s1", horseName: "Grom", startedAt: startedAt, snapshot: snapshot)
        assertScreen(NavigationStack { RideRecordingScreen(ride: ride, loading: false, seconds: 1_450, track: nil) }, name: "step-5-recording", variant: .light)
        measure("5-recording")

        assertScreen(TabView { Text("A").tabItem { Label("A", systemImage: "star") } }, name: "step-6-tabview", variant: .light)
        measure("6-tabview")

        let more = makeEnvironment(mode: .standalone, variant: .light)
        assertScreen(MoreView().environment(more), name: "step-7-more", variant: .light)
        measure("7-more")

        more.router.selectedTab = .more
        assertScreen(RootView().environment(more), name: "step-8-root-more", variant: .light)
        measure("8-root-more")
    }
}
