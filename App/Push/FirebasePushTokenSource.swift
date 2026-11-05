import FirebaseCore
import FirebaseMessaging
import Foundation
import HorselyKit
import UIKit

/// Jedyne miejsce w projekcie, które importuje Firebase (spec 003, research R2, R3, R6): tylko moduł Messaging, bez swizzlingu
/// (`FirebaseAppDelegateProxyEnabled = NO`), bez Analytics i bez samoczynnego startu (`FirebaseMessagingAutoInitEnabled = NO`).
///
/// Biblioteka jest konfigurowana leniwie: dopiero gdy rejestrator zdecyduje, że telefon ma dostawać powiadomienia z serwera
/// (tryb z serwerem + `push` + zgoda), albo od razu przy starcie, gdy `push.active` pokazuje, że tak już było. W trybie
/// samodzielnym i przy serwerze bez `push` ta klasa nie wykonuje żadnego wywołania Firebase (FR-027).
final class FirebasePushTokenSource: PushTokenSource, @unchecked Sendable {
    enum TokenError: Error {
        case timeout
        case unavailable
    }

    /// Jedna instancja na proces: korzystają z niej rejestrator i `AppDelegate` (token APNs).
    static let shared = FirebasePushTokenSource()
    /// Limit pobrania tokenu (research R7).
    static let tokenTimeout: TimeInterval = 30

    let tokenChanges: AsyncStream<String>
    private let delegate: TokenDelegate

    private init() {
        let stream = AsyncStream<String>.makeStream()
        tokenChanges = stream.stream
        delegate = TokenDelegate(continuation: stream.continuation)
    }

    // MARK: Konfiguracja

    /// Konfiguruje Firebase raz na proces. Wołane synchronicznie z `AppDelegate` przy starcie, gdy `push.active == true`
    /// (biblioteka musi być gotowa, zanim system dostarczy token APNs).
    @MainActor
    func configureNow() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
        Messaging.messaging().delegate = delegate
    }

    func configureIfNeeded() async {
        await MainActor.run { configureNow() }
    }

    /// Token APNs z `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` — bez swizzlingu przekazywany ręcznie.
    @MainActor
    func setAPNSToken(_ token: Data) {
        configureNow()
        Messaging.messaging().apnsToken = token
    }

    // MARK: PushTokenSource

    func token() async throws -> String {
        await configureIfNeeded()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let once = OnceResult(continuation)
            Task { @MainActor in
                Messaging.messaging().token { token, error in
                    if let token, !token.isEmpty {
                        once.finish(.success(token))
                    } else {
                        once.finish(.failure(error ?? TokenError.unavailable))
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.tokenTimeout) { once.finish(.failure(TokenError.timeout)) }
        }
    }

    func deleteToken() async {
        await configureIfNeeded()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = OnceVoid(continuation)
            Task { @MainActor in
                Messaging.messaging().deleteToken { _ in once.finish() }
            }
            // Brak odpowiedzi biblioteki nie może wstrzymać odparowania.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { once.finish() }
        }
    }

    func setAutoInit(_ enabled: Bool) async {
        await configureIfNeeded()
        await MainActor.run { Messaging.messaging().isAutoInitEnabled = enabled }
    }

    func registerForRemoteNotifications() async {
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    func unregisterForRemoteNotifications() async {
        await MainActor.run { UIApplication.shared.unregisterForRemoteNotifications() }
    }
}

/// Odbiera nowe tokeny od biblioteki.
private final class TokenDelegate: NSObject, MessagingDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<String>.Continuation

    init(continuation: AsyncStream<String>.Continuation) {
        self.continuation = continuation
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let fcmToken, !fcmToken.isEmpty { continuation.yield(fcmToken) }
    }
}

/// Wznawia kontynuację dokładnie raz (wynik biblioteki albo limit czasu).
private final class OnceResult: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<String, Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<String, Error>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}

private final class OnceVoid: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func finish() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
    }
}

/// Źródło tokenu bez Firebase: przebiegi testowe, migawki i podglądy (żadnego połączenia z Google ani z systemem).
struct DisabledPushTokenSource: PushTokenSource {
    struct Unavailable: Error {}

    let tokenChanges = AsyncStream<String> { $0.finish() }

    func configureIfNeeded() async {}
    func token() async throws -> String { throw Unavailable() }
    func deleteToken() async {}
    func setAutoInit(_ enabled: Bool) async {}
    func registerForRemoteNotifications() async {}
    func unregisterForRemoteNotifications() async {}
}

/// Most między delegatem aplikacji (wywołania systemu poza SwiftUI) a rejestratorem push w środowisku aplikacji.
final class PushBridge: @unchecked Sendable {
    static let shared = PushBridge()

    private let lock = NSLock()
    private var current: PushRegistrar?

    var registrar: PushRegistrar? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}
