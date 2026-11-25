// Progi chodów i parametry obciążenia jazd (PAR-01, PAR-02, PAR-05; kontrakt serwera 6 i 7) — port 1:1 z Androida 3.0.2
// (`core/.../ride/RideParameters.kt`). Reguły odwzorowują serwer (`RideProfileRules`, `RideParametersResolver`, `RideLoad.points`):
// ta sama arytmetyka, te same zakresy, komunikaty i klucze błędów.

import Foundation

// MARK: - GaitThresholds

/// Progi prędkości chodów (km/h): postój do `stopMaxKmh`, stęp do `walkMaxKmh`, kłus do `trotMaxKmh`, powyżej galop. Pole `gaitThresholdsUsed` nagrania.
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

/// Wagi obciążenia (punkty za minutę chodu) i dodatek za podjazd (punkty za 10 m w górę). Pole `loadParamsUsed` nagrania.
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

/// Własne wartości konia ([K] 6): `nil` = dziedziczy z ustawień domyślnych jazd. Koń bez profilu ma wszystkie pola `nil`.
/// Nazwy i kolejność pól są wiążące — kolejność wyznacza kolejność `ownFields` w `EffectiveRideParameters`.
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

    /// Czy koń dziedziczy wszystko z ustawień domyślnych (wszystkie dziewięć pól `nil`) — taki profil serwer v3 zwraca dla konia bez własnych wartości.
    public var isEmpty: Bool { self == RideProfile() }

    /// Czy dwa profile mają te same wartości (liczby dziesiętne po wartości, nie po skali: `2.5` = `2.50`).
    public func sameValues(_ other: RideProfile) -> Bool {
        gaitStopMaxKmh == other.gaitStopMaxKmh && gaitWalkMaxKmh == other.gaitWalkMaxKmh && gaitTrotMaxKmh == other.gaitTrotMaxKmh &&
            loadWeightWalk == other.loadWeightWalk && loadWeightTrot == other.loadWeightTrot && loadWeightCanter == other.loadWeightCanter &&
            loadClimbPer10m == other.loadClimbPer10m && loadWarnPercent == other.loadWarnPercent && heavyRidePoints == other.heavyRidePoints
    }
}

// MARK: - RideDefaults

/// Ustawienia domyślne jazd całej stajni ([K] 7): dziewięć wartości (wszystkie wymagane), typ treningu dla nagranej jazdy
/// (`recordedRideTrainingTypeId`, `nil` = brak) i `version` zapisanych ustawień (`0` — jeszcze nie zapisane, wartości wbudowane).
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

    /// Progi chodów z ustawień domyślnych.
    public var thresholds: GaitThresholds {
        GaitThresholds(stopMaxKmh: gaitStopMaxKmh, walkMaxKmh: gaitWalkMaxKmh, trotMaxKmh: gaitTrotMaxKmh)
    }

    /// Wagi obciążenia i dodatek za podjazd z ustawień domyślnych.
    public var load: LoadParams {
        LoadParams(weightWalk: loadWeightWalk, weightTrot: loadWeightTrot, weightCanter: loadWeightCanter, climbPer10m: loadClimbPer10m)
    }

    /// Wartości, które ma serwer, zanim ktokolwiek zapisze ustawienia (PAR-01, PAR-02): `1,5 / 7 / 15`, wagi `1 / 2 / 3`, podjazd `1`, próg `30 %`, ciężka od `60`.
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

    /// Treść żądania zapisu ustawień domyślnych jazd z bieżących wartości (`version` zostaje w nagłówku `If-Match`).
    public func toInput() -> RideDefaultsInput {
        RideDefaultsInput(
            gaitStopMaxKmh: gaitStopMaxKmh,
            gaitWalkMaxKmh: gaitWalkMaxKmh,
            gaitTrotMaxKmh: gaitTrotMaxKmh,
            loadWeightWalk: loadWeightWalk,
            loadWeightTrot: loadWeightTrot,
            loadWeightCanter: loadWeightCanter,
            loadClimbPer10m: loadClimbPer10m,
            loadWarnPercent: loadWarnPercent,
            heavyRidePoints: heavyRidePoints,
            recordedRideTrainingTypeId: recordedRideTrainingTypeId
        )
    }

    /// Czy dwa zestawy ustawień domyślnych mają te same wartości (bez `version`; liczby dziesiętne po wartości).
    public func sameValues(_ other: RideDefaults) -> Bool {
        toInput() == other.toInput()
    }
}

// MARK: - RideDefaultsInput

/// Treść `PUT /settings/ride-defaults` ([K] 7): jak `RideDefaults`, ale bez `version` (wersję niesie `If-Match`).
/// `recordedRideTrainingTypeId` `nil` = brak wybranego rodzaju treningu.
public struct RideDefaultsInput: Codable, Hashable, Sendable {
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
        recordedRideTrainingTypeId: String? = nil
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
    }
}

// MARK: - EffectiveRideParameters

/// Parametry jazd konia tak, jak obowiązują teraz: wartość z profilu konia, a gdzie jej brak — z ustawień domyślnych.
/// `ownFields` — nazwy pól `RideProfile`, które koń ustawił sam, w kolejności pól profilu (np. „Grom: własne wagi — kłus 2,5”).
public struct EffectiveRideParameters: Hashable, Sendable {
    public var thresholds: GaitThresholds
    public var load: LoadParams
    public var warnPercent: Int
    public var heavyRidePoints: Int
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

// MARK: - RideFieldErrors

/// Błędy walidacji parametrów jazd: klucz pola → komunikat, w kolejności sprawdzania (odpowiednik `LinkedHashMap` z Androida).
/// Porównanie (`==`) jak w Kotlinie: po parach klucz–komunikat, bez względu na kolejność.
public struct RideFieldErrors: Hashable, Sendable, ExpressibleByDictionaryLiteral {
    /// Klucze w kolejności dodania.
    public private(set) var keys: [String] = []
    private var messages: [String: String] = [:]

    public init() {}

    public init(dictionaryLiteral elements: (String, String)...) {
        for (key, message) in elements { self[key] = message }
    }

    /// Komunikat pola albo `nil`. Przypisanie istniejącego klucza zastępuje komunikat bez zmiany kolejności.
    public subscript(key: String) -> String? {
        get { messages[key] }
        set {
            if let newValue {
                if messages.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if messages.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    /// Dodaje komunikat tylko wtedy, gdy pole nie ma jeszcze błędu (`putIfAbsent`).
    mutating func putIfAbsent(_ key: String, _ message: String) {
        if messages[key] == nil { self[key] = message }
    }

    /// Komunikaty w kolejności kluczy.
    public var values: [String] { keys.compactMap { messages[$0] } }
    public var isEmpty: Bool { keys.isEmpty }
    public var count: Int { keys.count }
    /// Błędy jako słownik (bez kolejności).
    public var dictionary: [String: String] { messages }

    public static func == (lhs: RideFieldErrors, rhs: RideFieldErrors) -> Bool {
        lhs.messages == rhs.messages
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(messages)
    }
}

// MARK: - RideParameters

/// Rozwiązywanie, walidacja i obliczanie parametrów jazd.
public enum RideParameters {
    private static let sixty = Decimal(60)
    private static let six = Decimal(6)

    private static let speedMin = Decimal(string: "0.5")!
    private static let speedMax = Decimal(40)
    private static let weightMin = Decimal(string: "0.1")!
    private static let weightMax = Decimal(10)
    private static let climbMin = Decimal(0)
    private static let climbMax = Decimal(10)
    private static let warnMin = 5
    private static let warnMax = 200
    private static let heavyMin = 1
    private static let heavyMax = 10_000

    private static let speedRange = "Wpisz wartość od 0,5 do 40 km/h."
    private static let weightRange = "Wpisz wartość od 0,1 do 10."
    private static let climbRange = "Wpisz wartość od 0 do 10."
    private static let warnRange = "Wpisz wartość od 5 do 200."
    private static let heavyRange = "Wpisz wartość od 1 do 10 000."
    private static let walkOrder = "Próg stępa musi być większy niż próg postoju."
    private static let trotOrder = "Próg kłusa musi być większy niż próg stępa."

    // Jazda z przykładu PAR-02: 40 min stępa, 20 min kłusa, 5 min galopu, 50 m podjazdu.
    private static let exampleWalkMinutes = 40
    private static let exampleTrotMinutes = 20
    private static let exampleCanterMinutes = 5
    private static let exampleClimbM = 50

    /// Parametry konia: pole po polu wartość z `profile` (gdy ją ma) albo z `defaults`.
    public static func resolve(_ defaults: RideDefaults, _ profile: RideProfile?) -> EffectiveRideParameters {
        var own: [String] = []
        func pick<T>(_ name: String, _ fromProfile: T?, _ fromDefaults: T) -> T {
            guard let fromProfile else { return fromDefaults }
            own.append(name)
            return fromProfile
        }

        let p = profile ?? RideProfile()
        let thresholds = GaitThresholds(
            stopMaxKmh: pick("gaitStopMaxKmh", p.gaitStopMaxKmh, defaults.gaitStopMaxKmh),
            walkMaxKmh: pick("gaitWalkMaxKmh", p.gaitWalkMaxKmh, defaults.gaitWalkMaxKmh),
            trotMaxKmh: pick("gaitTrotMaxKmh", p.gaitTrotMaxKmh, defaults.gaitTrotMaxKmh)
        )
        let load = LoadParams(
            weightWalk: pick("loadWeightWalk", p.loadWeightWalk, defaults.loadWeightWalk),
            weightTrot: pick("loadWeightTrot", p.loadWeightTrot, defaults.loadWeightTrot),
            weightCanter: pick("loadWeightCanter", p.loadWeightCanter, defaults.loadWeightCanter),
            climbPer10m: pick("loadClimbPer10m", p.loadClimbPer10m, defaults.loadClimbPer10m)
        )
        let warn = pick("loadWarnPercent", p.loadWarnPercent, defaults.loadWarnPercent)
        let heavy = pick("heavyRidePoints", p.heavyRidePoints, defaults.heavyRidePoints)
        return EffectiveRideParameters(thresholds: thresholds, load: load, warnPercent: warn, heavyRidePoints: heavy, ownFields: own)
    }

    /// Błędy profilu konia: klucz `rideProfile.<pole>` → komunikat (puste = poprawny). Zakres sprawdza każdą wpisaną wartość
    /// (`nil` dziedziczy, więc nigdy nie jest błędem), kolejność progów `postój < stęp < kłus` — po scaleniu z `defaults` ([K] 6).
    /// Błąd zakresu ma pierwszeństwo przed błędem kolejności tego samego pola; błąd kolejności ma klucz progu wyższego
    /// (`gaitWalkMaxKmh` gdy stęp nie jest powyżej postoju, `gaitTrotMaxKmh` gdy kłus nie jest powyżej stępa) — jak w serwerze.
    public static func validate(_ profile: RideProfile, _ defaults: RideDefaults) -> RideFieldErrors {
        let merged = resolve(defaults, profile).thresholds
        return validateValues(
            prefix: "rideProfile.",
            stop: profile.gaitStopMaxKmh, walk: profile.gaitWalkMaxKmh, trot: profile.gaitTrotMaxKmh,
            weightWalk: profile.loadWeightWalk, weightTrot: profile.loadWeightTrot, weightCanter: profile.loadWeightCanter,
            climb: profile.loadClimbPer10m,
            warn: profile.loadWarnPercent, heavy: profile.heavyRidePoints,
            merged: merged
        )
    }

    /// Błędy ustawień domyślnych jazd: klucze bez przedrostka (`gaitWalkMaxKmh`), wszystkie wartości wymagane i w zakresie, progi rosnące.
    public static func validate(_ defaults: RideDefaults) -> RideFieldErrors {
        validateValues(
            prefix: "",
            stop: defaults.gaitStopMaxKmh, walk: defaults.gaitWalkMaxKmh, trot: defaults.gaitTrotMaxKmh,
            weightWalk: defaults.loadWeightWalk, weightTrot: defaults.loadWeightTrot, weightCanter: defaults.loadWeightCanter,
            climb: defaults.loadClimbPer10m,
            warn: defaults.loadWarnPercent, heavy: defaults.heavyRidePoints,
            merged: defaults.thresholds
        )
    }

    private static func validateValues(
        prefix: String,
        stop: Decimal?,
        walk: Decimal?,
        trot: Decimal?,
        weightWalk: Decimal?,
        weightTrot: Decimal?,
        weightCanter: Decimal?,
        climb: Decimal?,
        warn: Int?,
        heavy: Int?,
        merged: GaitThresholds
    ) -> RideFieldErrors {
        var errors = RideFieldErrors()
        func decimal(_ name: String, _ value: Decimal?, _ min: Decimal, _ max: Decimal, _ message: String) {
            if let value, value < min || value > max { errors[prefix + name] = message }
        }
        func whole(_ name: String, _ value: Int?, _ min: Int, _ max: Int, _ message: String) {
            if let value, value < min || value > max { errors[prefix + name] = message }
        }
        decimal("gaitStopMaxKmh", stop, speedMin, speedMax, speedRange)
        decimal("gaitWalkMaxKmh", walk, speedMin, speedMax, speedRange)
        decimal("gaitTrotMaxKmh", trot, speedMin, speedMax, speedRange)
        decimal("loadWeightWalk", weightWalk, weightMin, weightMax, weightRange)
        decimal("loadWeightTrot", weightTrot, weightMin, weightMax, weightRange)
        decimal("loadWeightCanter", weightCanter, weightMin, weightMax, weightRange)
        decimal("loadClimbPer10m", climb, climbMin, climbMax, climbRange)
        whole("loadWarnPercent", warn, warnMin, warnMax, warnRange)
        whole("heavyRidePoints", heavy, heavyMin, heavyMax, heavyRange)
        if merged.stopMaxKmh >= merged.walkMaxKmh { errors.putIfAbsent(prefix + "gaitWalkMaxKmh", walkOrder) }
        if merged.walkMaxKmh >= merged.trotMaxKmh { errors.putIfAbsent(prefix + "gaitTrotMaxKmh", trotOrder) }
        return errors
    }

    /// Punkty jazdy ([K] 8.1 p. 2): `walk/60·wagaStępa + trot/60·wagaKłusa + canter/60·wagaGalopu + (przewyższenie ?? 0)/10·podjazd`,
    /// zaokrąglone do 0,1 w górę od połowy (`HALF_UP`) na jazdę. Postój daje 0; brak przewyższenia liczy się jako 0.
    /// Wszystko mnożone przez 60 i dzielone raz na końcu, żeby zaokrąglał się tylko wynik (jak w serwerze).
    public static func loadPoints(
        walkSeconds: Int,
        trotSeconds: Int,
        canterSeconds: Int,
        elevationGainM: Int?,
        load: LoadParams
    ) -> Decimal {
        let walk: Decimal = Decimal(walkSeconds) * load.weightWalk
        let trot: Decimal = Decimal(trotSeconds) * load.weightTrot
        let canter: Decimal = Decimal(canterSeconds) * load.weightCanter
        let climb: Decimal = Decimal(elevationGainM ?? 0) * load.climbPer10m * six
        let exactTimesSixty: Decimal = walk + trot + canter + climb
        return HalfUp.round(exactTimesSixty / sixty, scale: 1)
    }

    /// Przykład liczony na żywo z wpisanych wag (PAR-02): „Jazda 40 min stępa, 20 min kłusa, 5 min galopu, 50 m podjazdu =
    /// 40 + 40 + 15 + 5 = 100 pkt” dla wartości domyślnych; liczby z przecinkiem dziesiętnym, bez zbędnych zer.
    public static func exampleText(_ load: LoadParams) -> String {
        let walk = Decimal(exampleWalkMinutes) * load.weightWalk
        let trot = Decimal(exampleTrotMinutes) * load.weightTrot
        let canter = Decimal(exampleCanterMinutes) * load.weightCanter
        let climb = Decimal(exampleClimbM) / Decimal(10) * load.climbPer10m
        let total = loadPoints(
            walkSeconds: exampleWalkMinutes * 60,
            trotSeconds: exampleTrotMinutes * 60,
            canterSeconds: exampleCanterMinutes * 60,
            elevationGainM: exampleClimbM,
            load: load
        )
        return "Jazda \(exampleWalkMinutes) min stępa, \(exampleTrotMinutes) min kłusa, \(exampleCanterMinutes) min galopu, \(exampleClimbM) m podjazdu = "
            + "\(number(walk)) + \(number(trot)) + \(number(canter)) + \(number(climb)) = \(number(total)) pkt"
    }

    /// Liczba bez zbędnych zer po przecinku, z przecinkiem dziesiętnym (`stripTrailingZeros().toPlainString()` z Androida).
    static func number(_ value: Decimal) -> String {
        var text = NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return text.replacingOccurrences(of: ".", with: ",")
    }
}
