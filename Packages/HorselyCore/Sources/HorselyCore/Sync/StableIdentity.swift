import Foundation

/// Wynik rozpoznania „tej samej stajni” po ponownym parowaniu (FR-M-POL-08).
public enum StableIdentity: Equatable, Sendable {
    /// Kolejka może ruszać.
    case match
    /// Komputer nie wygląda na tę samą stajnię: `missingHorses` koni z kolejki nie znaleziono (dla kolejki bez koni — 0).
    /// Operacje `heldOperationIds` przechodzą do `Held`.
    case mismatch(missingHorses: Int, heldOperationIds: Set<String>)
}

/// Rozpoznanie stajni (contracts/android/outbox-operations.md, `StableIdentityCheck.kt`): aplikacja nie zna identyfikatora
/// instalacji programu, więc porównuje konie.
///
/// 1. Zbiór `horseRefs` operacji w stanach `Pending`, `NeedsFix`, `Unknown`.
/// 2. Konie z programu (`GET /horses?status=all`, wszystkie strony).
/// 3. Zgodność: każdy `HorseRef` istnieje z tym samym `id`, `name` i `passportNumber` (źrebak bez paszportu: brak = brak).
///    Pusty zbiór → zgodny co najmniej jeden koń z pamięci.
public enum StableIdentityCheck {
    public static let considered: Set<OutboxState> = [.pending, .needsFix, .unknown]

    public static func check(operations: [OutboxOperation], programHorses: [HorseRef], cachedHorses: [HorseRef]) -> StableIdentity {
        let relevant = operations.filter { considered.contains($0.state) }
        if relevant.isEmpty { return .match }
        let held = Set(relevant.map(\.id))
        let known = Set(programHorses.map(\.identity))
        let refs = Set(relevant.flatMap(\.horseRefs).map(\.identity))
        if refs.isEmpty {
            // Kolejka bez koni (np. nowy kontakt): wystarczy, że choć jeden koń z pamięci jest w programie.
            if cachedHorses.isEmpty { return .match }
            return cachedHorses.contains { known.contains($0.identity) } ? .match : .mismatch(missingHorses: 0, heldOperationIds: held)
        }
        let missing = refs.subtracting(known)
        return missing.isEmpty ? .match : .mismatch(missingHorses: missing.count, heldOperationIds: held)
    }
}
