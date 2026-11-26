import Foundation
import HorselyCore

/// Live Activity nagrywanej jazdy (Task 16, FR-NAG-05): ekran blokady i Dynamic Island. Kontroler nagrywania (`RideRecordingController`)
/// zaczyna ją przy starcie albo wznowieniu jazdy, aktualizuje przy zmianie widocznej treści (pełne minuty, dziesiąte części km, chód, słaby
/// GPS, pauza) i kończy przy zakończeniu, przerwaniu albo porzuceniu jazdy. Implementację z ActivityKit ma aplikacja
/// (`LiveRideActivityPresenter`); pakiet i testy nie znają ActivityKit. Wołane z aktora kontrolera po kolei (każde wywołanie jest
/// oczekiwane), więc kolejność start → aktualizacje → koniec jest zachowana.
public protocol RideActivityPresenter: Sendable {
    /// Pokazuje aktywność jazdy. `resuming` — wznowienie tej samej jazdy po ponownym uruchomieniu aplikacji w tle: wtedy aktywność
    /// z poprzedniego procesu (z tym samym koniem) jest przejmowana, bo nowej nie da się zacząć w tle. Przy nowej jazdzie wszystkie
    /// istniejące aktywności są kończone i powstaje nowa (atrybut `horseName` jest niezmienny). Decyzja: `RideActivityAdoption`.
    /// Nazwa konia trafia tylko na ekran telefonu, nigdy do dziennika.
    func start(horseName: String, state: RideActivityState, resuming: Bool) async
    /// Nowa treść aktywności.
    func update(_ state: RideActivityState) async
    /// Zdejmuje aktywność jazdy (także pozostałą po poprzednim procesie); bez aktywności nic nie robi.
    func end() async
}

/// Bez Live Activity (testy, podgląd).
public struct NoRideActivityPresenter: RideActivityPresenter {
    public init() {}

    public func start(horseName: String, state: RideActivityState, resuming: Bool) async {}
    public func update(_ state: RideActivityState) async {}
    public func end() async {}
}
