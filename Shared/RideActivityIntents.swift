import AppIntents
import Foundation
import HorselyCore

// Przyciski Live Activity (Task 16, FR-NAG-05) — odpowiedniki „Pauza” / „Wznów” / „Zakończ” z powiadomienia nagrywania Androida.
// `LiveActivityIntent` wykonuje się w procesie APLIKACJI (system uruchamia ją w tle, gdy nie działa); typy są też w rozszerzeniu
// widżetów, bo widok aktywności tworzy z nich przyciski. Do kontrolera nagrywania docierają przez `RideActivityActions.shared`, który
// rejestruje aplikacja — w procesie rozszerzenia rejestr jest pusty i `perform()` nic nie robi.

/// „Pauza” — wstrzymuje nagrywanie (odbiór GPS zatrzymany, sesja w tle zostaje dla „Wznów”).
struct PauseRideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "ride_notification_pause"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await RideActivityActions.shared.perform(.pause)
        return .result()
    }
}

/// „Wznów” — wznawia nagrywanie po pauzie.
struct ResumeRideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "ride_notification_resume"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await RideActivityActions.shared.perform(.resume)
        return .result()
    }
}

/// „Zakończ” — kończy jazdę i otwiera aplikację (`openAppWhenRun`) na ekranie zakończenia. Ekran zakończenia (formularz po jeździe) to
/// Task 21: odbiera id zakończonej sesji z `RideActivityActions.shared.takeFinishedSessionId()` po wejściu aplikacji na pierwszy plan.
struct FinishRideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "ride_notification_finish"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        await RideActivityActions.shared.perform(.finish)
        return .result()
    }
}
