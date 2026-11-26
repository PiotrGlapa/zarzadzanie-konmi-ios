import Foundation
import HorselyCore
import HorselyKit
import XCTest
@testable import Horsely

/// Prywatność (T136, konstytucja II 3.0.0): `Info.plist` prosi tylko o aparat, sieć lokalną, Face ID oraz — dla nagrywania jazdy —
/// lokalizację „Podczas używania”, mikrofon (dźwięk filmu) i dodawanie do galerii; bez lokalizacji „Zawsze”, kontaktów, pełnej biblioteki
/// zdjęć i `NSAllowsArbitraryLoads`; w trybie samodzielnym aplikacja nie łączy się z siecią (transport zapisuje każde żądanie).
@MainActor
final class InfoPlistPolicyTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    func testOnlyTheNeededPermissionsAreRequested() {
        let needed = [
            "NSCameraUsageDescription", "NSLocalNetworkUsageDescription", "NSFaceIDUsageDescription", "NSLocationWhenInUseUsageDescription",
            "NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription",
        ]
        for key in needed {
            XCTAssertFalse((info[key] as? String ?? "").isEmpty, "brak \(key)")
        }
        XCTAssertEqual(info["NSFaceIDUsageDescription"] as? String, "Odblokowanie aplikacji z danymi stajni")
        let forbidden = [
            "NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationAlwaysUsageDescription", "NSLocationUsageDescription",
            "NSLocationTemporaryUsageDescriptionDictionary", "NSContactsUsageDescription", "NSPhotoLibraryUsageDescription",
            "NSCalendarsUsageDescription", "NSBluetoothAlwaysUsageDescription", "NSMotionUsageDescription",
        ]
        for key in forbidden { XCTAssertNil(info[key], "niedozwolona zgoda \(key)") }
    }

    /// Nagrywanie jazdy (Task 15, FR-NAG-07, [ZAK] 6): lokalizacja wyłącznie „Podczas używania” — opis zgody z tekstu Androida
    /// `ride_location_text` (ten sam, który widzi użytkownik przed pytaniem systemu), tryb tła `location`; nigdy klucza „Zawsze”.
    func testLocationWhenInUseOnly() {
        XCTAssertEqual(info["NSLocationWhenInUseUsageDescription"] as? String, tr("ride_location_text"))
        XCTAssertEqual(
            info["NSLocationWhenInUseUsageDescription"] as? String,
            "Aplikacja zapisuje trasę z GPS tylko wtedy, gdy nagrywasz jazdę. Zezwól na dokładną lokalizację „podczas używania aplikacji”."
        )
        let modes = info["UIBackgroundModes"] as? [String] ?? []
        XCTAssertTrue(modes.contains("location"), "brak trybu tła location")
        XCTAssertNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"], "lokalizacja „Zawsze” jest zabroniona")
        XCTAssertNil(info["NSLocationAlwaysUsageDescription"], "lokalizacja „Zawsze” jest zabroniona")
    }

    /// Push z serwera (spec 003, FR-027, FR-030b, research R1/R3): Firebase bez swizzlingu i bez samoczynnego startu,
    /// tło „remote-notification”; rozszerzenie udostępniania nie ma śladu Firebase.
    func testPushConfigurationIsPrivacyFriendly() throws {
        XCTAssertEqual(info["FirebaseAppDelegateProxyEnabled"] as? Bool, false)
        XCTAssertEqual(info["FirebaseMessagingAutoInitEnabled"] as? Bool, false)
        XCTAssertEqual(info["FIREBASE_ANALYTICS_COLLECTION_ENABLED"] as? Bool, false)
        let modes = info["UIBackgroundModes"] as? [String] ?? []
        for mode in ["fetch", "processing", "remote-notification"] { XCTAssertTrue(modes.contains(mode), "brak trybu tła \(mode)") }

        var root = URL(fileURLWithPath: #filePath)
        while root.pathComponents.count > 1, !FileManager.default.fileExists(atPath: root.appendingPathComponent("ShareExtension/Info.plist").path) {
            root.deleteLastPathComponent()
        }
        let data = try Data(contentsOf: root.appendingPathComponent("ShareExtension/Info.plist"))
        let share = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        XCTAssertFalse(share.keys.contains { $0.localizedCaseInsensitiveContains("firebase") }, "rozszerzenie nie może mieć kluczy Firebase")
        XCTAssertFalse((share["UIBackgroundModes"] as? [String] ?? []).contains("remote-notification"))
    }

    /// Live Activity nagrywania jazdy (Task 16, FR-NAG-05, SPECYFIKACJA 9.5): `NSSupportsLiveActivities` w aplikacji, rozszerzenie
    /// `HorselyRideActivity` to rozszerzenie WidgetKit bez Firebase i bez trybów tła.
    func testLiveActivitiesAreSupported() throws {
        XCTAssertEqual(info["NSSupportsLiveActivities"] as? Bool, true)
        var root = URL(fileURLWithPath: #filePath)
        while root.pathComponents.count > 1, !FileManager.default.fileExists(atPath: root.appendingPathComponent("RideActivity/Info.plist").path) {
            root.deleteLastPathComponent()
        }
        let data = try Data(contentsOf: root.appendingPathComponent("RideActivity/Info.plist"))
        let widget = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        let extensionInfo = try XCTUnwrap(widget["NSExtension"] as? [String: Any])
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
        XCTAssertFalse(widget.keys.contains { $0.localizedCaseInsensitiveContains("firebase") })
        XCTAssertNil(widget["UIBackgroundModes"])
    }

    func testArbitraryLoadsAreNotAllowed() {
        let transport = info["NSAppTransportSecurity"] as? [String: Any] ?? [:]
        XCTAssertNotEqual(transport["NSAllowsArbitraryLoads"] as? Bool, true)
        XCTAssertNotEqual(transport["NSAllowsArbitraryLoadsInWebContent"] as? Bool, true)
        XCTAssertNotEqual(transport["NSAllowsArbitraryLoadsForMedia"] as? Bool, true)
    }

    /// Prywatność (spec 003, FR-027, SC-006): w trybie samodzielnym i przy serwerze bez `push` źródło tokenu (Firebase) nie dostaje
    /// żadnego wywołania, a `registerForRemoteNotifications` nie jest wołane.
    func testStandaloneAndNoPushServerNeverTouchThePushTokenSource() async throws {
        for mode in [WorkMode.standalone, .online] {
            let tokens = CountingPushTokenSource()
            let suite = "horsely.nopush.\(UUID().uuidString)"
            let settings = SettingsStore(defaults: UserDefaults(suiteName: suite))
            settings.workMode = mode
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-nopush-\(UUID().uuidString)", isDirectory: true)
            let env = AppEnvironment(
                settings: settings, dates: FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 5)!),
                log: DiagnosticLog(directory: root.appendingPathComponent("Logs")), store: RecordStore(database: try AppDatabase.inMemory()),
                files: try LocalFileStore(root: root.appendingPathComponent("Files")), transport: RecordingTransport(), probe: AlwaysReachable(),
                pushTokens: tokens
            )
            await env.prepareStore()
            await env.startOnline()
            await env.pushRegistrar.reconcile(.launch)
            await env.pushRegistrar.reconcile(.foreground)
            await env.pushRegistrar.reconcile(.background)
            await env.pushEnteredForeground()
            await env.cleanUpStalePush()
            XCTAssertEqual(tokens.callCount, 0, "tryb \(mode): źródło tokenu nie może być wołane")
        }
    }

    /// Typowe czynności trybu samodzielnego: dane, wpisy, raporty, załączniki, kopia — zero żądań sieciowych.
    func testStandaloneWorkMakesNoNetworkRequests() async throws {
        let recorder = RecordingTransport()
        let suite = "horsely.offline.\(UUID().uuidString)"
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite))
        settings.workMode = .standalone
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-offline-\(UUID().uuidString)", isDirectory: true)
        let env = AppEnvironment(
            settings: settings, dates: FixedDateProvider(today: LocalDate(year: 2026, month: 10, day: 5)!),
            log: DiagnosticLog(directory: root.appendingPathComponent("Logs")), store: RecordStore(database: try AppDatabase.inMemory()),
            files: try LocalFileStore(root: root.appendingPathComponent("Files")), transport: recorder, probe: AlwaysReachable()
        )
        await env.prepareStore()
        await env.startOnline()
        _ = try await SnapshotEntries.seed(env)
        await env.refresh(force: true)
        _ = await env.sendQueue()
        _ = try await env.reports.costs(CostFilter())
        _ = try await env.reports.horseBalance(statuses: [], horseIds: [])
        let horse = try XCTUnwrap(env.horseDirectory.horses.first)
        let file = try await env.attachments.prepare(data: Data("notatka".utf8), fileName: "a.txt", mimeType: "text/plain")
        try await env.attachments.add(AttachmentOwner(type: .horse, id: horse.id, horseId: horse.id), [PendingAttachment(file: file)])
        try await env.backup.write(to: root.appendingPathComponent("kopia.zkkopia"), password: nil, attachmentsCacheMb: 200)
        await env.processSharedInbox()
        XCTAssertEqual(recorder.count, 0, "tryb samodzielny nie łączy się z siecią")
    }
}

/// Źródło tokenu liczące wywołania (żadne nie powinno wystąpić bez push).
final class CountingPushTokenSource: PushTokenSource, @unchecked Sendable {
    struct Unavailable: Error {}

    private let lock = NSLock()
    private var calls = 0
    let tokenChanges = AsyncStream<String> { $0.finish() }

    var callCount: Int { lock.withLock { calls } }

    private func count() { lock.withLock { calls += 1 } }

    func configureIfNeeded() async { count() }
    func token() async throws -> String { count(); throw Unavailable() }
    func deleteToken() async { count() }
    func setAutoInit(_ enabled: Bool) async { count() }
    func registerForRemoteNotifications() async { count() }
    func unregisterForRemoteNotifications() async { count() }
}

/// Transport zapisujący każde żądanie (i odpowiadający błędem sieci).
final class RecordingTransport: ProgramTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    var count: Int { lock.withLock { requests.count } }

    func send(_ request: URLRequest, to address: ServerAddress, bodyFile: URL?, download: Bool, progress: (@Sendable (Int64, Int64?) -> Void)?) async -> TransportOutcome {
        lock.withLock { requests.append(request) }
        return .failure(sentBody: false, code: .notConnectedToInternet)
    }
}
