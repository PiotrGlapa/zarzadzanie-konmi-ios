import Foundation
import HorselyCore
#if os(iOS)
import CoreMotion
#endif

// Akcelerometr nagrywania jazdy (Task 15, odpowiednik `AccelerometerSource.kt` i `AccelWindowBuffer` z Androida 3.0.2): próbki ok. 50 Hz
// dla `CadenceAnalyzer`, okna 5 s składa `AccelWindowBuffer`. Surowe próbki nie są zapisywane — tylko rytm i intensywność okna.

/// Źródło próbek akcelerometru; w testach zaślepka. `samples()` zaczyna odbiór (strumień kończy się od razu, gdy telefon nie ma czujnika —
/// jazda toczy się dalej bez rytmu), `stop()` go kończy (bezpieczne bez wcześniejszego startu).
public protocol MotionSource: Sendable {
    func samples() -> AsyncStream<AccelSample>
    func stop()
}

/// Wektor Core Motion w g (`CMAcceleration`) w postaci niezależnej od systemu (testy na macOS).
public struct MotionVector: Sendable, Hashable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Zamiana próbki `CMDeviceMotion` na wejście `CadenceAnalyzer` (ruling z Task 12). Analizator potrzebuje przyspieszenia **z grawitacją**
/// w m/s² (tak podaje je akcelerometr Androida), a `CMDeviceMotion.userAcceleration` grawitacji NIE zawiera — dlatego próbka to
/// `userAcceleration + gravity` po osiach (oba w g), zamienione na m/s² przez `AccelSample.fromG`. Samo `userAcceleration` dałoby moduł
/// wektora bez składowej stałej, czyli wyprostowany sinus: rytm dwa razy za wysoki i zawyżona intensywność. Typ wymusza podanie obu
/// składowych osobno.
public enum DeviceMotionConversion {
    /// - Parameters:
    ///   - timestamp: `CMLogItem.timestamp` (s od uruchomienia telefonu) — zamieniany na ns
    ///   - userAcceleration: `CMDeviceMotion.userAcceleration` (g)
    ///   - gravity: `CMDeviceMotion.gravity` (g)
    public static func sample(timestamp: TimeInterval, userAcceleration: MotionVector, gravity: MotionVector) -> AccelSample {
        AccelSample.fromG(
            tNanos: Int64((timestamp * 1_000_000_000).rounded()),
            x: userAcceleration.x + gravity.x,
            y: userAcceleration.y + gravity.y,
            z: userAcceleration.z + gravity.z
        )
    }
}

/// Składa próbki w okna 5 s (port `AccelWindowBuffer` z Androida): `add` oddaje okno, gdy rozpiętość próbek (od pierwszej do bieżącej)
/// sięgnie `windowNanos`, i zaczyna nowe. Okno 5 s wystarcza `CadenceAnalyzer` (potrzebuje ≥ 3 s). Po pauzie wołać `clear()` — okno nie
/// może obejmować przerwy.
public struct AccelWindowBuffer: Sendable {
    public static let windowNanos: Int64 = 5_000_000_000

    private let windowNanos: Int64
    private var samples: [AccelSample] = []

    public init(windowNanos: Int64 = AccelWindowBuffer.windowNanos) {
        self.windowNanos = windowNanos
    }

    public mutating func add(_ sample: AccelSample) -> [AccelSample]? {
        samples.append(sample)
        guard let first = samples.first, sample.tNanos - first.tNanos >= windowNanos else { return nil }
        let window = samples
        samples.removeAll(keepingCapacity: true)
        return window
    }

    public mutating func clear() {
        samples.removeAll()
    }
}

#if os(iOS)
/// `CMMotionManager` z `deviceMotionUpdateInterval = 1/50` (ok. 50 Hz — tyle, ile przepróbkowuje `CadenceAnalyzer`). Działa w tle,
/// dopóki aplikacja żyje dzięki nagrywaniu lokalizacji; nie wymaga zgody (to nie `CMMotionActivityManager`).
public final class CoreMotionSource: MotionSource, @unchecked Sendable {
    private let lock = NSLock()
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "pl.glapa.horsely.ride.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var continuation: AsyncStream<AccelSample>.Continuation?

    public init() {}

    public func samples() -> AsyncStream<AccelSample> {
        stop()
        let (stream, continuation) = AsyncStream<AccelSample>.makeStream(bufferingPolicy: .bufferingNewest(1_000))
        let started = lock.withLock { () -> Bool in
            guard manager.isDeviceMotionAvailable else { return false }
            manager.deviceMotionUpdateInterval = 1.0 / 50.0
            manager.startDeviceMotionUpdates(to: queue) { motion, _ in
                guard let motion else { return }
                let user = motion.userAcceleration
                let gravity = motion.gravity
                continuation.yield(
                    DeviceMotionConversion.sample(
                        timestamp: motion.timestamp,
                        userAcceleration: MotionVector(x: user.x, y: user.y, z: user.z),
                        gravity: MotionVector(x: gravity.x, y: gravity.y, z: gravity.z)
                    )
                )
            }
            self.continuation = continuation
            return true
        }
        if !started { continuation.finish() }
        return stream
    }

    public func stop() {
        let continuation = lock.withLock { () -> AsyncStream<AccelSample>.Continuation? in
            if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.finish()
    }
}
#endif
