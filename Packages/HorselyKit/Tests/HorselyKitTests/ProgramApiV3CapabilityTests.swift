import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// K12: `apiV3` jest wyliczane w produkcji — parowanie i synchronizacja zapisują możliwości przez `ProgramCapabilities.of(info)`.
/// `system/info` jak w pliku `v3/system-info.json` (kopia 1:1 z Androida).
struct ProgramApiV3CapabilityTests {
    private static let systemInfoV3 = """
        {
          "appVersion": "2.0.0+java.3.0.0",
          "apiVersion": "v1",
          "schemaVersion": "1.5",
          "serverTime": "2026-11-14T10:00:00",
          "capabilities": ["updatedSince", "ifMatchDelete", "idempotencyKey", "horsePhotoField", "dataStamp",
                           "horseStatusInjured", "reportExport", "trainingAttachments", "trainingRecordings"],
          "dataStamp": "9f2c4a7e1b3d5a60",
          "buildVersion": "3.0.0",
          "apiVersions": ["1", "3"],
          "dataSchemaVersion": "3.0"
        }
        """

    @Test func syncServiceStoresApiV3AfterSystemInfo() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let program = FakeProgram()
        program.on("GET", "system/info", .json(200, Self.systemInfoV3))
        let (client, _) = program.client()
        let service = SyncService(client: client, store: store)

        guard case let .success(info) = await client.systemInfo() else {
            Issue.record("system/info nie został odczytany")
            return
        }
        let change = try await service.record(info)

        #expect(!change.before.apiV3)
        #expect(change.after.apiV3)
        #expect(change.forcesFullSync)
        let stored = ProgramCapabilities(serialized: try await store.meta(SyncMetaKey.capabilities))
        #expect(stored.apiV3)
        #expect(stored.trainingRecordings)
        #expect(await service.capabilities().apiV3)
        #expect(try await store.meta(SyncMetaKey.forceFull) == "true")
    }

    @Test func pairingResultHasApiV3AndNextRequestsGoToV3() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let program = FakeProgram()
        program.on("GET", "system/info", .json(200, Self.systemInfoV3))
        program.on("GET", "dictionaries", .json(200, "{}"))
        program.on("GET", "horses", .json(200, #"{"items":[],"totalCount":0}"#))
        let (client, _) = program.client()
        let service = PairingService(store: store, client: client, secrets: InMemorySecretStore())
        let address = CheckedAddress(baseUrl: program.baseUrl, host: program.host, port: 5080, isLocal: true, isHttps: false)

        let outcome = await service.verify(PairingRequest(url: address, key: "hk_test"))

        guard case let .success(result) = outcome else {
            Issue.record("parowanie nie powiodło się")
            return
        }
        #expect(result.capabilities.apiV3)
        let infoRequest = program.requests("GET", "system/info").first
        #expect(infoRequest?.url == program.baseUrl + "/system/info")
        let dictionariesRequest = program.requests("GET", "dictionaries").first
        #expect(dictionariesRequest?.url.contains("/api/v3/dictionaries") == true)
    }
}
