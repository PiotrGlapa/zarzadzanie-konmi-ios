import Testing
@testable import HorselyCore

/// Możliwość `push` w `capabilities` programu 2.0 (spec 003, T006).
struct CapabilitiesTests {
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
}
