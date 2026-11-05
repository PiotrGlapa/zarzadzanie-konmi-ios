import Foundation

/// Źródło tokenu push i wywołania systemu powiązane z powiadomieniami zdalnymi (research R2, R3).
///
/// W aplikacji — `FirebasePushTokenSource` (jedyne miejsce, które importuje Firebase); w testach pakietu — zaślepka. Dzięki temu
/// cała logika rejestracji jest testowana bez Firebase i bez `UIApplication`. Wywołania `registerForRemoteNotifications` /
/// `unregisterForRemoteNotifications` są tu, a nie wprost w rejestratorze, żeby testy nie dotykały systemu.
///
/// Zasada prywatności (FR-027): rejestrator woła źródło tokenu **tylko** w trybie z serwerem, gdy serwer ogłasza `push` i jest
/// zgoda — w trybie samodzielnym i przy serwerze bez `push` nie ma żadnego wywołania.
public protocol PushTokenSource: Sendable {
    /// Konfiguruje bibliotekę (jeden raz na proces); bez tego wywołania żadne połączenie z Google nie powstaje.
    func configureIfNeeded() async
    /// Bieżący token FCM; błąd po upływie limitu (30 s) albo gdy token jest niedostępny (np. APNs odmówił).
    func token() async throws -> String
    /// Unieważnia token (odparowanie, „Rozłącz”).
    func deleteToken() async
    /// Samoczynne pobieranie tokenu przez bibliotekę: włączone dopiero po zgodzie i obecności `push` na serwerze.
    func setAutoInit(_ enabled: Bool) async
    /// Nowe tokeny zgłaszane przez bibliotekę (odświeżenie tokenu).
    var tokenChanges: AsyncStream<String> { get }
    /// `UIApplication.registerForRemoteNotifications()` na głównym wątku.
    func registerForRemoteNotifications() async
    /// `UIApplication.unregisterForRemoteNotifications()` na głównym wątku.
    func unregisterForRemoteNotifications() async
}
