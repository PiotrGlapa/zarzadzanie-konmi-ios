import Testing
@testable import HorselyCore

/// Możliwość `push` w `capabilities` programu 2.0 (spec 003, T006) oraz nowe możliwości 3.0.
struct CapabilitiesTests {
    // MARK: - Push (istniejące)

    @Test func pushIsRecognisedAndPushAdminAndUnknownNamesAreSkipped() {
        let capabilities = ProgramCapabilities(names: ["dataStamp", "push", "pushAdmin", "cosNowego"])
        #expect(capabilities.push)
        #expect(capabilities.dataStamp)
        #expect(!capabilities.names.contains("pushAdmin"))
        #expect(capabilities.serialized == "dataStamp,push")
        #expect(ProgramCapabilities(serialized: capabilities.serialized) == capabilities)
        #expect(!ProgramCapabilities(names: ["pushAdmin"]).push)
        #expect(!ProgramCapabilities.none.push)
    }

    @Test func aChangeReportsWhenPushAppearsOrVanishes() {
        let without = ProgramCapabilities(names: ["dataStamp"])
        let with = ProgramCapabilities(names: ["dataStamp", "push"])
        let appeared = CapabilitiesChange(before: without, after: with)
        #expect(appeared.pushAppeared && !appeared.pushVanished)
        let vanished = CapabilitiesChange(before: with, after: without)
        #expect(vanished.pushVanished && !vanished.pushAppeared)
        let same = CapabilitiesChange(before: with, after: with)
        #expect(!same.pushAppeared && !same.pushVanished)
        let unrelated = CapabilitiesChange(before: without, after: ProgramCapabilities(names: ["dataStamp", "updatedSince"]))
        #expect(!unrelated.pushAppeared && !unrelated.pushVanished)
    }

    @Test func pushDoesNotForceAFullDownloadOrChangeTheRefreshInterval() {
        let change = CapabilitiesChange(before: ProgramCapabilities(names: ["dataStamp"]), after: ProgramCapabilities(names: ["dataStamp", "push"]))
        #expect(change.changed)
        #expect(!change.forcesFullSync)
        #expect(!change.refreshIntervalChanged)
    }

    // MARK: - Task 3: Wersje API i nowe możliwości

    /// `system/info` z wersją 3.0.0 — parsuje `apiVersions`, `dataSchemaVersion` i wszystkie trzy nowe możliwości.
    @Test func systemInfo300IsParsed() throws {
        // Przykład z [K] 1 — plik system-info.json w v3/
        let json = """
            {
                "appVersion": "3.0.0",
                "apiVersion": "v3",
                "schemaVersion": "1.6",
                "serverTime": "2026-11-22T10:00:00Z",
                "capabilities": ["updatedSince", "dataStamp", "ifMatchDelete", "idempotencyKey", "horsePhotoField", "horseStatusInjured", "push", "trainingAttachments", "trainingRecordings"],
                "dataStamp": "2026-11-22T09:00:00Z",
                "apiVersions": ["1", "3"],
                "dataSchemaVersion": "3.0"
            }
            """
        let decoder = JSONDecoder()
        let info = try decoder.decode(ProgramInfo.self, from: json.data(using: .utf8)!)
        #expect(info.appVersion == "3.0.0")
        #expect(info.apiVersions == ["1", "3"])
        #expect(info.dataSchemaVersion == "3.0")
        let caps = ProgramCapabilities.of(info)
        #expect(caps.apiV3)
        #expect(caps.trainingAttachments)
        #expect(caps.trainingRecordings)
    }

    /// Serwer 2.x nie ma `apiVersions` → `apiV3` jest false.
    @Test func server2xHasNoV3() {
        let info2x = ProgramInfo(
            appVersion: "2.1.0",
            apiVersion: "v1",
            schemaVersion: "1.5",
            capabilities: ["updatedSince", "dataStamp", "push"],
            apiVersions: [],
            dataSchemaVersion: nil
        )
        let caps = ProgramCapabilities.of(info2x)
        #expect(!caps.apiV3)
        #expect(caps.updatedSince)
        #expect(caps.dataStamp)
    }

    /// `apiV3` przetrwaje serializację i ponowny odczyt.
    @Test func apiV3SurvivesSerializeParse() {
        let caps = ProgramCapabilities(names: ["trainingAttachments", "trainingRecordings", "apiV3"])
        #expect(caps.apiV3)
        let serialized = caps.serialized
        let parsed = ProgramCapabilities(serialized: serialized)
        #expect(parsed.apiV3)
        #expect(parsed.trainingAttachments)
        #expect(parsed.trainingRecordings)
    }

    /// Zmiana `apiV3` z false na true wymusza pełne pobranie.
    @Test func switchingToV3ForcesFullSync() {
        let caps2x = ProgramCapabilities(names: ["updatedSince", "dataStamp"])
        #expect(!caps2x.apiV3)
        let capsV3 = ProgramCapabilities(names: ["updatedSince", "dataStamp", "apiV3"])
        #expect(capsV3.apiV3)
        let change = CapabilitiesChange(before: caps2x, after: capsV3)
        #expect(change.changed)
        #expect(change.forcesFullSync)
    }
}
