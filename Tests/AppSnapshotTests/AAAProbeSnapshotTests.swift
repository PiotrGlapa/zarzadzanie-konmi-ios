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

    private func titled(_ title: String, large: Bool) -> some View {
        NavigationStack {
            ScrollView { Text("Treść").frame(maxWidth: .infinity) }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(large ? .large : .inline)
        }
    }

    func testLeakSteps() async throws {
        measure("0-start")
        assertScreen(Text("Więcej jazdę ŁÓŻ żółć").font(.title2.weight(.semibold)), name: "step-1-body-diacritics", variant: .light)
        measure("1-body-diacritics")
        assertScreen(titled("Konie", large: false), name: "step-2-inline-ascii", variant: .light)
        measure("2-inline-ascii")
        assertScreen(titled("Więcej", large: true), name: "step-3-large-e-ogonek", variant: .light)
        measure("3-large-e-ogonek")
        assertScreen(titled("Nagraj jazdę", large: false), name: "step-4-inline-e-ogonek", variant: .light)
        measure("4-inline-e-ogonek")
        assertScreen(titled("Żółw", large: false), name: "step-5-inline-z-dot", variant: .light)
        measure("5-inline-z-dot")
        let env = makeEnvironment(mode: .standalone, variant: .light)
        assertScreen(start(RideStartModel(preview: .wearHint, environment: env, horses: [])), name: "step-6-wear", variant: .light)
        measure("6-wear")
    }
}
