import ActivityKit
import Foundation
import HorselyCore
import HorselyKit

/// Live Activity jazdy przez ActivityKit (Task 16): `RideRecordingController` woła start, aktualizacje i koniec po kolei. Bez przechowywanego
/// stanu — za każdym razem bierze aktywności z `Activity.activities`; po ponownym uruchomieniu aplikacji w tle przejmuje aktywność tej samej
/// jazdy z poprzedniego procesu (nowej w tle nie da się zacząć), przy nowej jazdzie kończy stare i zaczyna nową (`RideActivityAdoption`). Dziennik dostaje tylko nazwę typu błędu — nigdy nazwy konia.
struct LiveRideActivityPresenter: RideActivityPresenter {
    let log: @Sendable (String) -> Void

    func start(horseName: String, state: RideActivityState, resuming: Bool) async {
        let content = ActivityContent(state: RideActivityAttributes.ContentState(state), staleDate: nil)
        let existing = Activity<RideActivityAttributes>.activities
        // Przejęcie tylko przy wznowieniu tej samej jazdy (ten sam koń); pozostałe aktywności — z poprzednich jazd — znikają.
        let adopted = RideActivityAdoption.adoptedIndex(
            existingHorseNames: existing.map(\.attributes.horseName), horseName: horseName, resuming: resuming
        )
        for (index, other) in existing.enumerated() where index != adopted {
            await other.end(nil, dismissalPolicy: .immediate)
        }
        if let adopted {
            await existing[adopted].update(content)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log("Live Activity wyłączone w ustawieniach — jazda bez aktywności na ekranie blokady")
            return
        }
        do {
            _ = try Activity<RideActivityAttributes>.request(attributes: RideActivityAttributes(horseName: horseName), content: content, pushType: nil)
        } catch {
            log("Live Activity: start nie powiódł się (\(String(describing: type(of: error))))")
        }
    }

    func update(_ state: RideActivityState) async {
        let content = ActivityContent(state: RideActivityAttributes.ContentState(state), staleDate: nil)
        for activity in Activity<RideActivityAttributes>.activities {
            await activity.update(content)
        }
    }

    func end() async {
        for activity in Activity<RideActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
