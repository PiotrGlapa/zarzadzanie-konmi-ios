import Foundation
import HorselyKit

// Teksty nagrywania jazdy (`RideNotificationTexts.app`) są w `Shared/RideActivityAttributes.swift` — wspólne z rozszerzeniem Live Activity.

/// Kontroler nagrywania dla delegata aplikacji (`applicationWillTerminate`), który nie ma dostępu do środowiska — jak `PushBridge`.
final class RideBridge: @unchecked Sendable {
    static let shared = RideBridge()

    private let lock = NSLock()
    private var current: RideRecordingController?

    var controller: RideRecordingController? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}
