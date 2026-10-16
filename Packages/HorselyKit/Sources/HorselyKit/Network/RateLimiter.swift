import Foundation

/// Ogranicznik tempa (okno przesuwne): najwyżej `maxRequests` żądań w oknie `window` sekund. Limit programu to 100 żądań / 10 s
/// na klucz; aplikacja zostawia zapas — 80 / 10 s (contracts/android/pairing-and-connection.md, research R8). Czas oczekiwania
/// nie wlicza się do limitów połączenia i odpowiedzi.
public actor RateLimiter {
    public static let defaultMaxRequests = 80
    public static let defaultWindow: TimeInterval = 10

    private let maxRequests: Int
    private let window: TimeInterval
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var stamps: [Date] = []

    public init(
        maxRequests: Int = RateLimiter.defaultMaxRequests, window: TimeInterval = RateLimiter.defaultWindow, now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.maxRequests = max(1, maxRequests)
        self.window = max(0.001, window)
        self.now = now
        self.sleep = sleep
    }

    /// Czeka, aż żądanie zmieści się w limicie, i rezerwuje miejsce.
    public func acquire() async {
        while true {
            let moment = now()
            stamps.removeAll { moment.timeIntervalSince($0) >= window }
            if stamps.count < maxRequests {
                stamps.append(moment)
                return
            }
            let wait = window - moment.timeIntervalSince(stamps[0])
            await sleep(max(wait, 0.001))
        }
    }
}
