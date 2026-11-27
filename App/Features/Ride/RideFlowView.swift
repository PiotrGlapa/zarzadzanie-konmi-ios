import HorselyCore
import HorselyKit
import SwiftUI

/// Ekrany nagrywania na pełnym ekranie nad kartami (Task 17; Android: trasy `ride/start?horseId=`, `ride/recording`, `ride/finish/{id}`).
/// Trasę trzyma `DeepLinkRouter.ride`; zmiana trasy podmienia ekran bez zamykania okna.
struct RideFlowView: View {
    let environment: AppEnvironment
    let route: RideFlowRoute

    var body: some View {
        NavigationStack {
            switch route {
            case let .start(horseId):
                RideStartView(
                    model: RideStartModel(environment: environment, preselectedHorseId: horseId),
                    onClose: close,
                    onRecording: { environment.router.ride = .recording },
                    onFinish: { environment.router.openRideFinish(sessionId: $0) }
                )
            case .recording:
                RideRecordingView(
                    model: RideRecordingModel(environment: environment),
                    onClose: close,
                    onFinish: { environment.router.openRideFinish(sessionId: $0) }
                )
            case let .finish(sessionId):
                RideFinishPendingView(sessionId: sessionId, onClose: close)
            }
        }
        .id(route)
        .environment(environment)
        .tint(HorselyColor.primary)
        .preferredColorScheme(environment.theme.colorScheme)
    }

    private func close() {
        environment.router.ride = nil
    }
}

/// HAK DLA TASK 21: miejsce ekranu zakończenia jazdy (Android `RideFinishFlow` — formularz treningu z jazdy, przycinanie, zapis). Do czasu
/// Task 21 pokazuje tylko podsumowanie zakończonej jazdy (koń, czas, dystans) i pozwala wrócić; jazda zostaje w bazie w stanie `.finished`
/// (niezapisana), więc nic nie ginie: następny start aplikacji albo „Nagraj jazdę” zapyta „Zapisz / Odrzuć”. Wchodzi się tu z „Zakończ”
/// na ekranie nagrywania, z „Zakończ” na Live Activity (`RideActivityActions` → `DeepLinkRouter.openRideFinish`) i z „Zapisz”
/// w odzyskiwaniu. Teksty wyłącznie z katalogu (`ride_finish_*`).
struct RideFinishPendingView: View {
    @Environment(AppEnvironment.self) private var environment
    let sessionId: String
    let onClose: () -> Void

    @State private var session: RideSessionInfo?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.screenEdge) {
                if let session {
                    InfoCard {
                        VStack(alignment: .leading, spacing: Spacing.between) {
                            Text(session.horse.name).font(.headline).foregroundStyle(HorselyColor.onBackground)
                            row("ride_time", RideText.duration(session.activeSeconds))
                            row("ride_distance", RideText.distance(session.distanceMeters))
                        }
                    }
                } else if failed {
                    Text("ride_finish_load_failed").font(.body).foregroundStyle(HorselyColor.error)
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("ride_finish_loading").font(.body)
                    }
                }
            }
            .padding(Spacing.screenEdge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HorselyColor.background)
        .navigationTitle("ride_finish_form_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { RideBackButton(action: onClose) }
        }
        .task {
            do {
                session = try await environment.rideSessions.load(sessionId: sessionId).session
            } catch {
                environment.log.log(RideRecordingController.logCategory, "Odczyt zakończonej jazdy nie powiódł się (\(String(describing: type(of: error))))")
                failed = true
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(HorselyColor.onSurfaceVariant)
            Spacer()
            Text(value).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
        }
        .accessibilityElement(children: .combine)
    }
}
