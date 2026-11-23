// Parametry i ustawienia jazd — kopia z Androida 3.0.2 (Task 4).
// Reguły walidacji i progów z [K] 6/7 i PLAN-A Task 4.

import Foundation

// MARK: - GaitThresholds

/// Progi prędkości chodów konia (`gaitThresholdsUsed` / `gaitThresholds` z [K]).
public struct GaitThresholds: Codable, Hashable, Sendable {
    public var stopMaxKmh: Decimal
    public var walkMaxKmh: Decimal
    public var trotMaxKmh: Decimal

    public init(stopMaxKmh: Decimal, walkMaxKmh: Decimal, trotMaxKmh: Decimal) {
        self.stopMaxKmh = stopMaxKmh
        self.walkMaxKmh = walkMaxKmh
        self.trotMaxKmh = trotMaxKmh
    }
}

// MARK: - LoadParams

/// Parametry obciążenia jazdy (`loadParamsUsed` / `loadParamsUsed` z [K]).
public struct LoadParams: Codable, Hashable, Sendable {
    public var weightWalk: Decimal
    public var weightTrot: Decimal
    public var weightCanter: Decimal
    public var climbPer10m: Decimal

    public init(weightWalk: Decimal, weightTrot: Decimal, weightCanter: Decimal, climbPer10m: Decimal) {
        self.weightWalk = weightWalk
        self.weightTrot = weightTrot
        self.weightCanter = weightCanter
        self.climbPer10m = climbPer10m
    }
}

// MARK: - RideProfile

/// Profil jazdy konia — 9 pól z [K] 6.
public struct RideProfile: Codable, Hashable, Sendable {
    public var gaitStopMaxKmh: Decimal?
    public var gaitWalkMaxKmh: Decimal?
    public var gaitTrotMaxKmh: Decimal?
    public var loadWeightWalk: Decimal?
    public var loadWeightTrot: Decimal?
    public var loadWeightCanter: Decimal?
    public var loadClimbPer10m: Decimal?
    public var loadWarnPercent: Int?
    public var heavyRidePoints: Int?

    public init(
        gaitStopMaxKmh: Decimal? = nil,
        gaitWalkMaxKmh: Decimal? = nil,
        gaitTrotMaxKmh: Decimal? = nil,
        loadWeightWalk: Decimal? = nil,
        loadWeightTrot: Decimal? = nil,
        loadWeightCanter: Decimal? = nil,
        loadClimbPer10m: Decimal? = nil,
        loadWarnPercent: Int? = nil,
        heavyRidePoints: Int? = nil
    ) {
        self.gaitStopMaxKmh = gaitStopMaxKmh
        self.gaitWalkMaxKmh = gaitWalkMaxKmh
        self.gaitTrotMaxKmh = gaitTrotMaxKmh
        self.loadWeightWalk = loadWeightWalk
        self.loadWeightTrot = loadWeightTrot
        self.loadWeightCanter = loadWeightCanter
        self.loadClimbPer10m = loadClimbPer10m
        self.loadWarnPercent = loadWarnPercent
        self.heavyRidePoints = heavyRidePoints
    }
}

// MARK: - RideDefaults

/// Ustawienia domyślne jazd — kopia z [K] 7.
public struct RideDefaults: Codable, Hashable, Sendable {
    public var gaitStopMaxKmh: Decimal
    public var gaitWalkMaxKmh: Decimal
    public var gaitTrotMaxKmh: Decimal
    public var loadWeightWalk: Decimal
    public var loadWeightTrot: Decimal
    public var loadWeightCanter: Decimal
    public var loadClimbPer10m: Decimal
    public var loadWarnPercent: Int
    public var heavyRidePoints: Int
    public var recordedRideTrainingTypeId: String?
    public var version: Int

    public init(
        gaitStopMaxKmh: Decimal,
        gaitWalkMaxKmh: Decimal,
        gaitTrotMaxKmh: Decimal,
        loadWeightWalk: Decimal,
        loadWeightTrot: Decimal,
        loadWeightCanter: Decimal,
        loadClimbPer10m: Decimal,
        loadWarnPercent: Int,
        heavyRidePoints: Int,
        recordedRideTrainingTypeId: String? = nil,
        version: Int = 0
    ) {
        self.gaitStopMaxKmh = gaitStopMaxKmh
        self.gaitWalkMaxKmh = gaitWalkMaxKmh
        self.gaitTrotMaxKmh = gaitTrotMaxKmh
        self.loadWeightWalk = loadWeightWalk
        self.loadWeightTrot = loadWeightTrot
        self.loadWeightCanter = loadWeightCanter
        self.loadClimbPer10m = loadClimbPer10m
        self.loadWarnPercent = loadWarnPercent
        self.heavyRidePoints = heavyRidePoints
        self.recordedRideTrainingTypeId = recordedRideTrainingTypeId
        self.version = version
    }

    /// Wartości wbudowane (gdy serwer nie ma jeszcze zapisanych ustawień; `version: 0`).
    public static let builtIn = RideDefaults(
        gaitStopMaxKmh: Decimal(string: "1.5")!,
        gaitWalkMaxKmh: Decimal(string: "7")!,
        gaitTrotMaxKmh: Decimal(string: "15")!,
        loadWeightWalk: Decimal(string: "1")!,
        loadWeightTrot: Decimal(string: "2")!,
        loadWeightCanter: Decimal(string: "3")!,
        loadClimbPer10m: Decimal(string: "1")!,
        loadWarnPercent: 30,
        heavyRidePoints: 60,
        recordedRideTrainingTypeId: nil,
        version: 0
    )
}

// MARK: - EffectiveRideParameters

/// Scalone parametry jazd: profil konia scalony z ustawieniami domyślnymi.
public struct EffectiveRideParameters: Hashable, Sendable {
    public var thresholds: GaitThresholds
    public var load: LoadParams
    public var warnPercent: Int
    public var heavyRidePoints: Int
    /// Nazwy pól `RideProfile`, które konien ustawił sam (w kolejności pól profilu).
    public var ownFields: [String]

    public init(
        thresholds: GaitThresholds,
        load: LoadParams,
        warnPercent: Int,
        heavyRidePoints: Int,
        ownFields: [String]
    ) {
        self.thresholds = thresholds
        self.load = load
        self.warnPercent = warnPercent
        self.heavyRidePoints = heavyRidePoints
        self.ownFields = ownFields
    }
}

// MARK: - RideParameters (obiekt statyczny)

/// Obiekt z funkcjami do rozwiązywania, walidacji i obliczania parametrów jazd.
public enum RideParameters {
    /// Nazwy pól `RideProfile` w kolejności definicji — używane do `ownFields`.
    private static let profileFieldNames: [String] = [
        "gaitStopMaxKmh", "gaitWalkMaxKmh", "gaitTrotMaxKmh",
        "loadWeightWalk", "loadWeightTrot", "loadWeightCanter",
        "loadClimbPer10m", "loadWarnPercent", "heavyRidePoints"
    ]

    /// Rozwiązuje skuteczne parametry jazd z ustawień domyślnych i opcjonalnego profilu konia.
    /// Pola profilu, które nie są `nil`, zastępują wartości domyślne.
    public static func resolve(_ defaults: RideDefaults, _ profile: RideProfile?) -> EffectiveRideParameters {
        var ownFields: [String] = []

        let stopMax = profile?.gaitStopMaxKmh ?? defaults.gaitStopMaxKmh
        let walkMax = profile?.gaitWalkMaxKmh ?? defaults.gaitWalkMaxKmh
        let trotMax = profile?.gaitTrotMaxKmh ?? defaults.gaitTrotMaxKmh

        let weightWalk = profile?.loadWeightWalk ?? defaults.loadWeightWalk
        let weightTrot = profile?.loadWeightTrot ?? defaults.loadWeightTrot
        let weightCanter = profile?.loadWeightCanter ?? defaults.loadWeightCanter
        let climbPer10m = profile?.loadClimbPer10m ?? defaults.loadClimbPer10m

        let warnPercent = profile?.loadWarnPercent ?? defaults.loadWarnPercent
        let heavyRidePoints = profile?.heavyRidePoints ?? defaults.heavyRidePoints

        if profile != nil {
            if profile?.gaitStopMaxKmh != nil { ownFields.append("gaitStopMaxKmh") }
            if profile?.gaitWalkMaxKmh != nil { ownFields.append("gaitWalkMaxKmh") }
            if profile?.gaitTrotMaxKmh != nil { ownFields.append("gaitTrotMaxKmh") }
            if profile?.loadWeightWalk != nil { ownFields.append("loadWeightWalk") }
            if profile?.loadWeightTrot != nil { ownFields.append("loadWeightTrot") }
            if profile?.loadWeightCanter != nil { ownFields.append("loadWeightCanter") }
            if profile?.loadClimbPer10m != nil { ownFields.append("loadClimbPer10m") }
            if profile?.loadWarnPercent != nil { ownFields.append("loadWarnPercent") }
            if profile?.heavyRidePoints != nil { ownFields.append("heavyRidePoints") }
        }

        return EffectiveRideParameters(
            thresholds: GaitThresholds(stopMaxKmh: stopMax, walkMaxKmh: walkMax, trotMaxKmh: trotMax),
            load: LoadParams(weightWalk: weightWalk, weightTrot: weightTrot, weightCanter: weightCanter, climbPer10m: climbPer10m),
            warnPercent: warnPercent,
            heavyRidePoints: heavyRidePoints,
            ownFields: ownFields
        )
    }

    /// Waliduje profil względem ustawień domyślnych. Zwraca mapę `pole → komunikat_błędu`.
    public static func validate(_ profile: RideProfile, _ defaults: RideDefaults) -> [String: String] {
        var errors: [String: String] = [:]

        // Próg stępa musi być większy niż próg postoju.
        if let walkMax = profile.gaitWalkMaxKmh {
            let stopMax = profile.gaitStopMaxKmh ?? defaults.gaitStopMaxKmh
            if walkMax <= stopMax {
                errors["gaitWalkMaxKmh"] = "Próg stępa musi być większy niż próg postoju."
            }
        }

        // Próg kłusa musi być większy niż próg stępa.
        if let trotMax = profile.gaitTrotMaxKmh {
            let walkMax = profile.gaitWalkMaxKmh ?? defaults.gaitWalkMaxKmh
            if trotMax <= walkMax {
                errors["gaitTrotMaxKmh"] = "Próg kłusa musi być większy niż próg stępa."
            }
        }

        // Zakresy: prędkości 0,5–40 km/h.
        for (key, value) in [
            ("gaitStopMaxKmh", profile.gaitStopMaxKmh),
            ("gaitWalkMaxKmh", profile.gaitWalkMaxKmh),
            ("gaitTrotMaxKmh", profile.gaitTrotMaxKmh)
        ] {
            if let value = value {
                if value < Decimal(string: "0.5")! || value > Decimal(string: "40")! {
                    errors[key] = "Wpisz wartość od 0,5 do 40."
                }
            }
        }

        // Wagi: 0,1–10.
        for key in ["loadWeightWalk", "loadWeightTrot", "loadWeightCanter", "loadClimbPer10m"] {
            let value: Decimal? = {
                switch key {
                case "loadWeightWalk": return profile.loadWeightWalk
                case "loadWeightTrot": return profile.loadWeightTrot
                case "loadWeightCanter": return profile.loadWeightCanter
                case "loadClimbPer10m": return profile.loadClimbPer10m
                default: return nil
                }
            }()
            if let value = value {
                if value < Decimal(string: "0.1")! || value > Decimal(string: "10")! {
                    errors[key] = "Wpisz wartość od 0,1 do 10."
                }
            }
        }

        // loadWarnPercent: 5–200.
        if let warn = profile.loadWarnPercent {
            if warn < 5 || warn > 200 {
                errors["loadWarnPercent"] = "Wpisz wartość od 5 do 200."
            }
        }

        // heavyRidePoints: 1–10000.
        if let heavy = profile.heavyRidePoints {
            if heavy < 1 || heavy > 10000 {
                errors["heavyRidePoints"] = "Wpisz wartość od 1 do 10000."
            }
        }

        return errors
    }

    /// Waliduje profil z ustawieniami domyślnymi (bez przekazywania profilu).
    public static func validate(_ defaults: RideDefaults) -> [String: String] {
        return validate(RideProfile(), defaults)
    }

    /// Oblicza punkty obciążenia jazdy:
    /// `punkty = walkMinutes · weightWalk + trotMinutes · weightTrot + canterMinutes · weightCanter + elevationGainM / 10 · climbPer10m`.
    /// Wynik zaokrąglony do 0,1 HALF_UP.
    public static func loadPoints(
        walkSeconds: Int,
        trotSeconds: Int,
        canterSeconds: Int,
        elevationGainM: Int?,
        load: LoadParams
    ) -> Decimal {
        let walkMinutes = Decimal(walkSeconds) / Decimal(60)
        let trotMinutes = Decimal(trotSeconds) / Decimal(60)
        let canterMinutes = Decimal(canterSeconds) / Decimal(60)

        let elevation = Decimal(elevationGainM ?? 0) / Decimal(10) * load.climbPer10m

        var raw = walkMinutes * load.weightWalk + trotMinutes * load.weightTrot + canterMinutes * load.weightCanter + elevation
        return HalfUp.round(raw, scale: 1)
    }

    /// Tekst przykładowy obciążenia jazdy dla podanych parametrów.
    /// Format: „Jazda 40 min stępa, 20 min kłusa, 5 min galopu, 50 m podjazdu = 40 + 40 + 15 + 5 = 100 pkt”
    public static func exampleText(_ load: LoadParams) -> String {
        // Przykładowe wartości: 40 min stępa, 20 min kłusa, 5 min galopu, 50 m podjazdu.
        let walkMinutes = 40
        let trotMinutes = 20
        let canterMinutes = 5
        let elevationM = 50

        let walkPts = Decimal(walkMinutes) * load.weightWalk
        let trotPts = Decimal(trotMinutes) * load.weightTrot
        let canterPts = Decimal(canterMinutes) * load.weightCanter
        let elevPts = Decimal(elevationM) / Decimal(10) * load.climbPer10m

        let total = HalfUp.round(walkPts + trotPts + canterPts + elevPts, scale: 0)

        let walkPtsStr = formatDecimal(walkPts)
        let trotPtsStr = formatDecimal(trotPts)
        let canterPtsStr = formatDecimal(canterPts)
        let elevPtsStr = formatDecimal(elevPts)
        let totalStr = formatDecimal(total)

        return "Jazda \(walkMinutes) min stępa, \(trotMinutes) min kłusa, \(canterMinutes) min galopu, \(elevationM) m podjazdu = \(walkPtsStr) + \(trotPtsStr) + \(canterPtsStr) + \(elevPtsStr) = \(totalStr) pkt"
    }

    private static func formatDecimal(_ value: Decimal) -> String {
        // Zaokrąglenie do 0 miejsc dla tekstu przykładowego.
        let rounded = HalfUp.round(value, scale: 0)
        return rounded.description
    }
}
