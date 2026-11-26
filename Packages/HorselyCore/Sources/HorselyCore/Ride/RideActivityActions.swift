import Foundation
import Synchronization

// Przyciski Live Activity (Task 16): „Pauza”, „Wznów” i „Zakończ” to `LiveActivityIntent` (`Shared/RideActivityIntents.swift`), które
// system wykonuje w procesie APLIKACJI. Intencje kompilują się też w rozszerzeniu widżetów, które nie ma kontrolera nagrywania — dlatego
// docierają do niego przez ten rejestr: aplikacja przy starcie rejestruje JEDYNY `RideRecordingController` (HorselyKit), a w procesie
// rozszerzenia rejestr jest pusty i akcja nic nie robi.

/// Akcja z przycisku Live Activity.
public enum RideActivityAction: String, Sendable, CaseIterable {
    case pause
    case resume
    case finish
}

/// Odbiorca akcji Live Activity — w aplikacji kontroler nagrywania jazdy.
public protocol RideActivityActionHandler: Sendable {
    func pauseRide() async
    func resumeRide() async
    /// Kończy jazdę; id zakończonej sesji (ekran zakończenia) albo `nil`, gdy nic się nie nagrywało.
    func finishRide() async -> String?
}

/// Rejestr odbiorcy akcji Live Activity (jeden na proces).
public final class RideActivityActions: Sendable {
    public static let shared = RideActivityActions()

    private struct State: Sendable {
        var handler: (any RideActivityActionHandler)?
        var finishedSessionId: String?
    }

    private let state = Mutex(State())

    public init() {}

    /// Aplikacja rejestruje kontroler nagrywania (`HorselyApp.init`); `nil` usuwa odbiorcę.
    public func register(_ handler: (any RideActivityActionHandler)?) {
        state.withLock { $0.handler = handler }
    }

    /// Wykonuje akcję u zarejestrowanego odbiorcy. `false`, gdy odbiorcy nie ma (proces rozszerzenia widżetów).
    @discardableResult
    public func perform(_ action: RideActivityAction) async -> Bool {
        guard let handler = state.withLock({ $0.handler }) else { return false }
        switch action {
        case .pause:
            await handler.pauseRide()
        case .resume:
            await handler.resumeRide()
        case .finish:
            if let id = await handler.finishRide() {
                state.withLock { $0.finishedSessionId = id }
            }
        }
        return true
    }

    /// Hak dla ekranu zakończenia jazdy (Task 21): „Zakończ” z Live Activity otwiera aplikację (`openAppWhenRun`) i zostawia tu id zakończonej
    /// sesji; interfejs po wejściu na pierwszy plan odbiera je raz (kolejne wywołanie zwraca `nil`) i pokazuje formularz po jeździe.
    public func takeFinishedSessionId() -> String? {
        state.withLock { current in
            defer { current.finishedSessionId = nil }
            return current.finishedSessionId
        }
    }
}
