import Foundation
import HorselyCore

// Odzyskiwanie jazdy po zabiciu procesu, przesunięciu albo nieudanym zakończeniu (Task 17 = Android 3.0.2 `RideRecovery` z
// `RideRecoveryDialog.kt`, NAG-09, decyzja A13; SPECYFIKACJA_MOBILE_IOS.md 9.3). Wspólne dla pytania przy starcie aplikacji
// (`RideRecoveryAlert`) i ekranu startu nagrywania.

/// Co jest w bazie sesji z punktu widzenia interfejsu.
public enum RideRecoveryCheck: Sendable, Hashable {
    /// Nie ma niezakończonej sesji.
    case none
    /// Kontroler w tym procesie nagrywa tę jazdę (także wznowioną po ponownym uruchomieniu w tle) — bez pytania, pasek i ekran nagrywania.
    case recording(sessionId: String)
    /// Sesja czeka na „Zapisz / Odrzuć” (przerwana, zakończona i niezapisana albo pozostawiona przez poprzedni proces).
    case pending(UnfinishedRide)
}

extension Track {
    /// Ostatnia chwila trasy (epoka, ms): ostatni punkt albo koniec ostatniej pauzy, nie wcześniej niż start (Android
    /// `Track.lastActivityMillis`). Koniec jazdy odzyskanej po zabiciu procesu — nie chwila zapisu, bo czas od przerwania do „Zapisz”
    /// doliczałby się do jazdy.
    public var lastActivityMillis: Int64 {
        max(startedAtMillis, points.map(\.tMillis).max() ?? 0, pauses.map(\.endMillis).max() ?? 0)
    }
}

/// Odczyt, zapis i odrzucenie niezakończonej jazdy. Wszystkie odczyty czekają najpierw na decyzję podjętą przy starcie aplikacji
/// (`RideRecordingController.awaitPendingRelaunch()`): przy uruchomieniu na pierwszym planie nieświeża sesja `.recording`/`.paused` dostaje
/// `.interrupted` ASYNCHRONICZNIE, a przy uruchomieniu w tle jazda jest właśnie wznawiana — bez czekania pytanie pokazałoby stan sprzed
/// decyzji (albo zapytało o jazdę, która za chwilę nagrywa dalej).
public struct RideRecovery: Sendable {
    private let store: RideSessionStore
    private let controller: RideRecordingController
    private let notifier: (any RideNotifier)?
    private let deleteMedia: @Sendable ([String]) -> Void
    private let log: @Sendable (String) -> Void

    /// - Parameters:
    ///   - store: JEDYNY sklep sesji aplikacji (ten sam co kontroler i pasek NAG-01)
    ///   - notifier: zdejmuje powiadomienie „Nagrywanie przerwane — …” po zapisaniu albo odrzuceniu
    ///   - deleteMedia: usuwa pliki zdjęć i filmów odrzuconej jazdy (adresy z sesji; obce adresy pomija)
    ///   - log: dziennik diagnostyczny — bez współrzędnych i nazwy konia
    public init(
        store: RideSessionStore, controller: RideRecordingController, notifier: (any RideNotifier)? = nil,
        deleteMedia: @escaping @Sendable ([String]) -> Void = { _ in }, log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.store = store
        self.controller = controller
        self.notifier = notifier
        self.deleteMedia = deleteMedia
        self.log = log
    }

    /// Stan sesji po decyzji startowej. Uszkodzony wiersz nie wywraca aplikacji: błąd odczytu trafia do dziennika (nazwa typu) i liczy się jak
    /// brak sesji.
    public func check() async -> RideRecoveryCheck {
        await controller.awaitPendingRelaunch()
        let ride: UnfinishedRide?
        do {
            ride = try await store.unfinished()
        } catch {
            log("Odczyt niezakończonej jazdy nie powiódł się (\(String(describing: type(of: error))))")
            return .none
        }
        guard let ride else { return .none }
        let running = controller.isRunning && controller.activeSessionId == ride.sessionId
        guard RideStartPolicy.needsRecovery(state: ride.state, controllerRunning: running) else { return .recording(sessionId: ride.sessionId) }
        if ride.damaged { log("Zapis niezakończonej jazdy jest uszkodzony — odzyskano go częściowo") }
        return .pending(ride)
    }

    /// Jazda do pytania „Zapisz / Odrzuć” albo `nil`.
    public func pending() async -> UnfinishedRide? {
        if case let .pending(ride) = await check() { return ride }
        return nil
    }

    /// „Zapisz”: zamyka jazdę do zapisu (stan `.finished`, koniec = ostatnia aktywność z trasy) i zwraca id sesji dla ekranu zakończenia.
    /// Uszkodzony wiersz nie pozwala wczytać trasy — wtedy koniec to chwila zapisu.
    public func save(_ ride: UnfinishedRide) async throws -> String {
        if ride.state != .finished { try await close(sessionId: ride.sessionId) }
        await notifier?.clearInterrupted()
        return ride.sessionId
    }

    /// Po „Zakończ”: `RideRecordingController.finish()` zwraca id także wtedy, gdy ostatni zapis się nie udał (sesja ma wtedy `.interrupted`,
    /// bez ostatnich punktów). Taka jazda jest zamykana tak samo jak odzyskana („Zapisz”) — z tym, co już jest w bazie; gdy i to się nie uda,
    /// zostaje `.interrupted` i przy następnym starcie aplikacji wraca pytanie „Zapisz / Odrzuć”.
    public func closeAfterFinish(sessionId: String) async {
        do {
            let state = try await store.load(sessionId: sessionId).session.state
            guard state != .finished else { return }
            try await close(sessionId: sessionId)
            log("Zakończenie jazdy: zapis końcowy się nie udał — jazda zamknięta z dotychczas zapisanymi punktami")
        } catch {
            log("Zakończenie jazdy: nie zamknięto jazdy do zapisu (\(String(describing: type(of: error))))")
        }
    }

    private func close(sessionId: String) async throws {
        let end: Int64?
        do {
            end = try await store.load(sessionId: sessionId).track.lastActivityMillis
        } catch {
            log("Nie wyliczono końca odzyskiwanej jazdy z trasy (\(String(describing: type(of: error))))")
            end = nil
        }
        try await store.setState(sessionId: sessionId, state: .finished, endedAtMillis: end)
    }

    /// „Odrzuć” (po drugim pytaniu): usuwa sesję, jej punkty i pliki zrobione w trakcie jazdy. Kolejność: najpierw adresy plików (wiersz
    /// sesji to jedyne odwołanie do nich), potem sesja, na końcu pliki — zabicie procesu w trakcie zostawia sesję i pytanie przy starcie,
    /// a nie osierocone zdjęcia. Działa także dla uszkodzonego wiersza.
    public func discard(sessionId: String) async throws {
        let uris: [String]
        do {
            uris = try await store.mediaUris(sessionId: sessionId)
        } catch {
            log("Nie wczytano plików odrzucanej jazdy (\(String(describing: type(of: error))))")
            uris = []
        }
        try await store.discard(sessionId: sessionId)
        deleteMedia(uris)
        await notifier?.clearInterrupted()
    }
}
