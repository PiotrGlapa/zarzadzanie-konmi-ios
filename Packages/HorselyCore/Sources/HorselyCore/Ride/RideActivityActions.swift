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

/// Wynik akcji z przycisku Live Activity.
public enum RideActivityActionOutcome: Sendable, Equatable {
    /// Akcja wykonana.
    case performed
    /// Brak zarejestrowanego kontrolera (proces rozszerzenia albo aplikacja przed rejestracją).
    case noHandler
    /// Kontroler jest, ale nie ma jazdy, której akcja dotyczy (już zakończona, już wstrzymana, nie wstrzymana).
    case noRide
}

/// Odbiorca akcji Live Activity — w aplikacji kontroler nagrywania jazdy.
public protocol RideActivityActionHandler: Sendable {
    /// `false`, gdy nie było czego wstrzymać.
    func pauseRide() async -> Bool
    /// `false`, gdy nie było czego wznowić.
    func resumeRide() async -> Bool
    /// Kończy jazdę; id zakończonej sesji (ekran zakończenia) albo `nil`, gdy nic się nie nagrywało.
    func finishRide() async -> String?
}

/// Rejestr odbiorcy akcji Live Activity (jeden na proces).
public final class RideActivityActions: Sendable {
    public static let shared = RideActivityActions()

    private struct State: Sendable {
        var handler: (any RideActivityActionHandler)?
        var finishedSessionId: String?
        var log: (@Sendable (String) -> Void)?
    }

    private let state = Mutex(State())

    public init() {}

    /// Aplikacja rejestruje kontroler nagrywania (`HorselyApp.init`); `nil` usuwa odbiorcę.
    public func register(_ handler: (any RideActivityActionHandler)?) {
        state.withLock { $0.handler = handler }
    }

    /// Dziennik diagnostyczny dla akcji, które nic nie zrobiły (aplikacja ustawia go przy starcie, niezależnie od odbiorcy). Wpisy bez nazwy
    /// konia i współrzędnych — tylko rodzaj akcji i powód.
    public func setLog(_ log: (@Sendable (String) -> Void)?) {
        state.withLock { $0.log = log }
    }

    /// Wykonuje akcję u zarejestrowanego odbiorcy. Akcja, która nic nie zrobiła (brak odbiorcy albo brak jazdy), nie jest cichym sukcesem:
    /// trafia do dziennika diagnostycznego, a wynik mówi, co się stało.
    @discardableResult
    public func perform(_ action: RideActivityAction) async -> RideActivityActionOutcome {
        let (handler, log) = state.withLock { ($0.handler, $0.log) }
        guard let handler else {
            log?("Live Activity: przycisk „\(Self.describe(action))” bez kontrolera nagrywania — pominięto")
            return .noHandler
        }
        let performed: Bool
        switch action {
        case .pause:
            performed = await handler.pauseRide()
        case .resume:
            performed = await handler.resumeRide()
        case .finish:
            let id = await handler.finishRide()
            if let id { state.withLock { $0.finishedSessionId = id } }
            performed = id != nil
        }
        if performed { return .performed }
        log?("Live Activity: przycisk „\(Self.describe(action))” bez trwającej jazdy — pominięto")
        return .noRide
    }

    private static func describe(_ action: RideActivityAction) -> String {
        switch action {
        case .pause: "Pauza"
        case .resume: "Wznów"
        case .finish: "Zakończ"
        }
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

/// Czy przy starcie jazdy przejąć istniejącą Live Activity (czysta decyzja dla `LiveRideActivityPresenter`, który dotyka ActivityKit).
public enum RideActivityAdoption {
    /// Indeks aktywności do przejęcia albo `nil` — wtedy wszystkie istniejące są kończone i powstaje nowa. Przejmujemy tylko przy wznowieniu
    /// jazdy po ponownym uruchomieniu w tle (nowej aktywności nie da się wtedy zacząć) i tylko aktywność z tym samym koniem (`horseName`
    /// jest niezmienny); nowa jazda zawsze dostaje nową aktywność, żeby nie pokazywać konia z poprzedniej.
    public static func adoptedIndex(existingHorseNames: [String], horseName: String, resuming: Bool) -> Int? {
        guard resuming else { return nil }
        return existingHorseNames.firstIndex(of: horseName)
    }
}
