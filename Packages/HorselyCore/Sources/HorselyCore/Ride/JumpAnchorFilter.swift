import Foundation

// Reguła kotwicy dystansu — port `JumpAnchorFilter.kt` z Androida 3.0.2. Używa jej nagrywanie na żywo (`RideRecorder`) i końcowe
// statystyki jazdy (zadanie 18), więc dystans na żywo i końcowy są zgodne.

/// Wynik `JumpAnchorFilter.accept` dla punktu o dobrej dokładności.
enum JumpAnchorResult: Equatable {
    /// Punkt policzony: `meters` od kotwicy w `seconds` s; punkt jest nową kotwicą.
    case counted(meters: Double, seconds: Double)

    /// Punkt jest nową kotwicą BEZ dystansu przez lukę (start, po pauzie, po trwałym przesunięciu współrzędnych).
    case anchored

    /// Skok powyżej 70 km/h: punkt nie wpływa na dystans ani prędkość, kotwica bez zmian.
    case rejected
}

/// Wspólna reguła kotwicy dystansu. Filtr dostaje tylko punkty o dobrej dokładności, w kolejności czasu.
///
/// Kotwica to ostatni policzony punkt. Skok > `maxJumpKmh` względem kotwicy odrzuca punkt z dystansu i prędkości (w śladzie zostaje),
/// ale kotwica nie stoi w miejscu na zawsze:
/// - punkt spójny z kotwicą (prędkość ≤ 70 km/h) jest liczony (`.counted`), a licznik odrzuceń skokowych zerowany — pojedynczy skok
///   odrzuca tylko jeden punkt;
/// - punkt spójny z POPRZEDNIO ODRZUCONYM punktem (prędkość między nimi ≤ 70 km/h) albo będący `maxConsecutiveJumps`-tym kolejnym
///   odrzuceniem skokowym przesuwa kotwicę na siebie BEZ doliczania dystansu przez lukę (`.anchored`);
/// - `reset()` (pauza, po której odcinek nie liczy się do dystansu) kasuje kotwicę, ostatnio odrzucony punkt i licznik.
/// Dzięki temu trwałe przesunięcie współrzędnych (np. zimny start GPS) kosztuje jeden–dwa punkty, a nie minuty dystansu.
struct JumpAnchorFilter {
    /// Prędkość (km/h) powyżej której skok między punktami uznaje się za błąd GPS.
    static let maxJumpKmh = 70.0

    /// Tyle kolejnych odrzuceń skokowych przesuwa kotwicę (trwałe przesunięcie współrzędnych).
    static let maxConsecutiveJumps = 3

    private static let kmhPerMs = 3.6

    /// Bieżąca kotwica albo `nil` (start, po `reset()`).
    private(set) var anchor: TrackPoint?

    private var lastRejected: TrackPoint?
    private var consecutiveJumps = 0

    init() {}

    mutating func reset() {
        anchor = nil
        lastRejected = nil
        consecutiveJumps = 0
    }

    mutating func accept(_ p: TrackPoint) -> JumpAnchorResult {
        guard let prev = anchor else {
            anchorAt(p)
            return .anchored
        }
        let seconds = Double(p.tMillis - prev.tMillis) / 1000.0
        let meters = haversineMeters(prev.lat, prev.lon, p.lat, p.lon)
        if seconds > 0.0 && meters / seconds * Self.kmhPerMs <= Self.maxJumpKmh {
            lastRejected = nil
            consecutiveJumps = 0
            anchor = p
            return .counted(meters: meters, seconds: seconds)
        }
        consecutiveJumps += 1
        var consistentWithRejected = false
        if let rejected = lastRejected {
            consistentWithRejected = isConsistent(from: rejected, to: p)
        }
        if consecutiveJumps >= Self.maxConsecutiveJumps || consistentWithRejected {
            anchorAt(p)
            return .anchored
        }
        lastRejected = p
        return .rejected
    }

    private mutating func anchorAt(_ p: TrackPoint) {
        anchor = p
        lastRejected = nil
        consecutiveJumps = 0
    }

    /// Czy przejście z `from` do `to` ma prędkość najwyżej 70 km/h (punkty spójne ze sobą).
    private func isConsistent(from: TrackPoint, to: TrackPoint) -> Bool {
        let seconds = Double(to.tMillis - from.tMillis) / 1000.0
        return seconds > 0.0 && haversineMeters(from.lat, from.lon, to.lat, to.lon) / seconds * Self.kmhPerMs <= Self.maxJumpKmh
    }
}
