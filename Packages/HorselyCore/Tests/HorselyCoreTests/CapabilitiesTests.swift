import Testing
import Foundation
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

    /// `system/info` z wersją 3.0.0 — plik `v3/system-info.json` to kopia 1:1 przykładu z Androida ([K] 1).
    @Test func systemInfo300IsParsed() throws {
        let info = try JSONDecoder().decode(ProgramInfo.self, from: Fixtures.data("v3/system-info.json"))
        #expect(info.appVersion == "2.0.0+java.3.0.0")
        #expect(info.apiVersion == "v1")
        #expect(info.schemaVersion == "1.5")
        #expect(info.serverTime == "2026-11-14T10:00:00")
        #expect(info.dataStamp == "9f2c4a7e1b3d5a60")
        #expect(info.apiVersions == ["1", "3"])
        #expect(info.dataSchemaVersion == "3.0")
        #expect(info.capabilities == ["updatedSince", "ifMatchDelete", "idempotencyKey", "horsePhotoField", "dataStamp", "horseStatusInjured", "reportExport", "trainingAttachments", "trainingRecordings"])
        let caps = ProgramCapabilities.of(info)
        #expect(caps.apiV3)
        #expect(caps.trainingAttachments)
        #expect(caps.trainingRecordings)
        #expect(!caps.names.contains("reportExport"))
    }

    /// Produkcyjna ścieżka (`ProgramInfo.programCapabilities`, używana przez parowanie i synchronizację) też wylicza `apiV3`.
    @Test func programCapabilitiesOfDecodedSystemInfoHaveApiV3() throws {
        let info = try JSONDecoder().decode(ProgramInfo.self, from: Fixtures.data("v3/system-info.json"))
        #expect(info.programCapabilities.apiV3)
        #expect(info.programCapabilities == ProgramCapabilities.of(info))
        #expect(ProgramCapabilities(serialized: info.programCapabilities.serialized).apiV3)
    }

    /// Program bez `apiVersions` (2.x) nie dostaje `apiV3` także przez `programCapabilities`.
    @Test func programCapabilitiesOfServer2xHaveNoApiV3() {
        let info = ProgramInfo(appVersion: "2.1.0", capabilities: ["updatedSince", "dataStamp"], apiVersions: ["1"])
        #expect(!info.programCapabilities.apiV3)
        #expect(info.programCapabilities.updatedSince)
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
