import Foundation

// Odległości na kuli — port `Geo.kt` z Androida 3.0.2. Ta sama funkcja liczy dystans na żywo (`RideRecorder`) i w statystykach
// końcowych jazdy (zadanie 18), więc oba wyniki są zgodne.

/// Promień Ziemi (m) przyjęty w obliczeniach odległości (haversine).
public let earthRadiusMeters: Double = 6_371_000.0

/// Odległość po kuli (haversine, `earthRadiusMeters`) w metrach między punktami podanymi w stopniach.
///
/// Zamiana stopni na radiany jak `Math.toRadians` z JDK 9+ (mnożenie przez stałą `π/180`), a `min(1.0, sqrt(a))` zachowuje się jak
/// w Kotlinie: NaN daje NaN (Swiftowe `min` zwróciłoby 1.0, czyli fałszywą, ogromną odległość zamiast „brak wyniku").
public func haversineMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let phi1 = toRadians(lat1)
    let phi2 = toRadians(lat2)
    let dPhi = toRadians(lat2 - lat1)
    let dLambda = toRadians(lon2 - lon1)
    let a = sin(dPhi / 2.0) * sin(dPhi / 2.0) + cos(phi1) * cos(phi2) * sin(dLambda / 2.0) * sin(dLambda / 2.0)
    let root = a.squareRoot()
    let clamped = root.isNaN ? root : (root < 1.0 ? root : 1.0)
    return 2.0 * earthRadiusMeters * asin(clamped)
}

private func toRadians(_ degrees: Double) -> Double {
    degrees * 0.017453292519943295
}
