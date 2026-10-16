import Foundation
import HorselyCore
import HorselyKit
import XCTest
@testable import Horsely

/// Prywatność (T136, konstytucja II): `Info.plist` prosi tylko o aparat, sieć lokalną i Face ID — bez lokalizacji, kontaktów,
/// pełnej biblioteki zdjęć i `NSAllowsArbitraryLoads`; w trybie samodzielnym aplikacja nie łączy się z siecią (transport zapisuje
/// każde żądanie).
@MainActor
final class InfoPlistPolicyTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    func testOnlyTheNeededPermissionsAreRequested() {
        for key in ["NSCameraUsageDescription", "NSLocalNetworkUsageDescription", "NSFaceIDUsageDescription"] {
            XCTAssertFalse((info[key] as? String ?? "").isEmpty, "brak \(key)")
        }
        XCTAssertEqual(info["NSFaceIDUsageDescription"] as? String, "Odblokowanie aplikacji z danymi stajni")
        let forbidden = [
            "NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription", "NSLocationAlwaysUsageDescription",
            "NSLocationUsageDescription", "NSContactsUsageDescription", "NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription",
            "NSMicrophoneUsageDescription", "NSCalendarsUsageDescription", "NSBluetoothAlwaysUsageDescription",
        ]
        for key in forbidden { XCTAssertNil(info[key], "niedozwolona zgoda \(key)") }
    }

    func testArbitraryLoadsAreNotAllowed() {
        let transport = info["NSAppTransportSecurity"] as? [String: Any] ?? [:]
        XCTAssertNotEqual(transport["NSAllowsArbitraryLoads"] as? Bool, true)
        XCTAssertNotEqual(transport["NSAllowsArbitraryLoadsInWebContent"] as? Bool, true)
        XCTAssertNotEqual(transport["NSAllowsArbitraryLoadsForMedia"] as? Bool, true)
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
        let file = try env.attachments.prepare(data: Data("notatka".utf8), fileName: "a.txt", mimeType: "text/plain")
        try await env.attachments.add(AttachmentOwner(type: .horse, id: horse.id, horseId: horse.id), [PendingAttachment(file: file)])
        try await env.backup.write(to: root.appendingPathComponent("kopia.zkkopia"), password: nil, attachmentsCacheMb: 200)
        await env.processSharedInbox()
        XCTAssertEqual(recorder.count, 0, "tryb samodzielny nie łączy się z siecią")
    }
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
