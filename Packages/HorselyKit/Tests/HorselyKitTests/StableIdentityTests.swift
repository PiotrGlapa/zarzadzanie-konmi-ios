import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Rozpoznanie tej samej stajni po ponownym parowaniu (T077, FR-M-POL-08; przypadki z `StableIdentityCheckTest`).
struct StableIdentityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let grom = HorseRef(id: "h1", name: "Grom", passportNumber: "PL-1")
    private let foal = HorseRef(id: "h2", name: "Iskra", passportNumber: nil)

    private func op(_ id: String, horses: [HorseRef], state: OutboxState = .pending) -> OutboxOperation {
        OutboxOperation(id: id, kind: .createNote, localRef: id, payload: .object([:]), horseRefs: horses, summary: "Notatka", state: state, createdAt: now, updatedAt: now)
    }

    @Test func refsThatAllExistWithTheSameIdNameAndPassportMatch() {
        #expect(StableIdentityCheck.check(operations: [op("a", horses: [grom])], programHorses: [grom, foal], cachedHorses: []) == .match)
    }

    @Test func aFoalWithoutAPassportMatchesOnlyByNullAndName() {
        #expect(StableIdentityCheck.check(operations: [op("a", horses: [foal])], programHorses: [foal], cachedHorses: []) == .match)
        let withEmptyPassport = HorseRef(id: "h2", name: "Iskra", passportNumber: "  ")
        #expect(StableIdentityCheck.check(operations: [op("a", horses: [withEmptyPassport])], programHorses: [foal], cachedHorses: []) == .match)
        let withPassport = HorseRef(id: "h2", name: "Iskra", passportNumber: "PL-9")
        #expect(StableIdentityCheck.check(operations: [op("a", horses: [foal])], programHorses: [withPassport], cachedHorses: []) != .match)
    }

    @Test func oneMissingHorseHoldsAllOperationsInTheQueue() {
        let result = StableIdentityCheck.check(operations: [op("a", horses: [grom]), op("b", horses: [foal])], programHorses: [grom], cachedHorses: [])
        #expect(result == .mismatch(missingHorses: 1, heldOperationIds: ["a", "b"]))
    }

    @Test func theSameIdWithAnotherNameOrPassportIsADifferentHorse() {
        let renamed = HorseRef(id: "h1", name: "Piorun", passportNumber: "PL-1")
        #expect(StableIdentityCheck.check(operations: [op("a", horses: [grom])], programHorses: [renamed], cachedHorses: []) == .mismatch(missingHorses: 1, heldOperationIds: ["a"]))
    }

    @Test func aQueueWithoutHorsesComparesTheCachedHorses() {
        #expect(StableIdentityCheck.check(operations: [op("a", horses: [])], programHorses: [grom], cachedHorses: [grom]) == .match)
        #expect(StableIdentityCheck.check(operations: [op("a", horses: [])], programHorses: [foal], cachedHorses: [grom]) == .mismatch(missingHorses: 0, heldOperationIds: ["a"]))
        #expect(StableIdentityCheck.check(operations: [op("a", horses: [])], programHorses: [foal], cachedHorses: []) == .match)
    }

    @Test func anEmptyQueueAlwaysMatchesAndOnlyUnsentStatesCount() {
        #expect(StableIdentityCheck.check(operations: [], programHorses: [], cachedHorses: [grom]) == .match)
        #expect(StableIdentityCheck.check(operations: [op("a", horses: [grom], state: .conflict)], programHorses: [], cachedHorses: []) == .match)
    }

    @Test func holdingAndReleasingChangeOnlyTheRightStates() async throws {
        let store = RecordStore(database: try AppDatabase.inMemory())
        let program = FakeProgram()
        program.on("GET", "horses", .json(200, #"{"items":[{"id":"h9","name":"Obcy","passportNumber":"X"}],"totalCount":1}"#))
        let (client, _) = program.client()
        try await store.writeQuietly { access in
            try access.enqueue(self.op("a", horses: [self.grom]))
            try access.enqueue(self.op("b", horses: [self.grom], state: .conflict))
        }
        let service = PairingService(store: store, client: client, secrets: InMemorySecretStore())
        let result = await service.checkStable(now: now)
        #expect(result == .mismatch(missingHorses: 1, heldOperationIds: ["a"]))
        #expect(try await store.read { try $0.operation("a")?.state } == .held)
        #expect(try await store.read { try $0.operation("b")?.state } == .conflict)
        try await service.release(now: now)
        #expect(try await store.read { try $0.operation("a")?.state } == .pending)
    }
}
