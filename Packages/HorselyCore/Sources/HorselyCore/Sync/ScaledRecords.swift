import Foundation

// Rekordy z liczbami dziesiętnymi, które muszą zachować skalę zapisu (`18.00`, `52.2297000`) w magazynie, w kopii zapasowej
// i w pliku eksportu 1.6 — jak `BigDecimal` w Androidzie 3.0.2 (`BigDecimal.equals` rozróżnia `18.0` i `18.00`). `JSONDecoder` czyta
// liczby przez `Double`, a `JSONEncoder` nie gwarantuje skali, więc treść tych rekordów idzie przez `JSONValue.parseKeepingScale`
// i `textKeepingScale()` (`RecordCodec`). Pozostałe rekordy (kwoty `Money` z własnym kodowaniem) — bez zmian.

/// Rekord zapisywany i czytany z zachowaną skalą liczb (`RecordCodec`).
protocol ScaledJSONRecord {
    init(scaledJSON: JSONValue) throws
    func scaledJSON() -> JSONValue
}

/// Odczyt pól obiektu JSON (liczby jako `Decimal` z mantysą i wykładnikiem jak w tekście).
struct ScaledFields {
    let fields: [String: JSONValue]
    let owner: String

    init(_ json: JSONValue, owner: String) throws {
        guard case let .object(fields) = json else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "\(owner): treść nie jest obiektem"))
        }
        self.fields = fields
        self.owner = owner
    }

    func invalid(_ name: String) -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "\(owner): brak albo zła wartość pola \(name)"))
    }

    /// Wartość pola; `nil` dla braku i `null`.
    func present(_ name: String) -> JSONValue? {
        guard let value = fields[name], value != .null else { return nil }
        return value
    }

    func value(_ name: String) throws -> JSONValue {
        guard let value = present(name) else { throw invalid(name) }
        return value
    }

    func optionalString(_ name: String) throws -> String? {
        guard let value = present(name) else { return nil }
        guard case let .string(text) = value else { throw invalid(name) }
        return text
    }

    func string(_ name: String) throws -> String {
        guard let text = try optionalString(name) else { throw invalid(name) }
        return text
    }

    func optionalDecimal(_ name: String) throws -> Decimal? {
        guard let value = present(name) else { return nil }
        guard case let .number(number) = value else { throw invalid(name) }
        return number
    }

    func decimal(_ name: String) throws -> Decimal {
        guard let number = try optionalDecimal(name) else { throw invalid(name) }
        return number
    }

    func optionalInt64(_ name: String) throws -> Int64? {
        guard let number = try optionalDecimal(name) else { return nil }
        var source = number
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        guard rounded == number else { throw invalid(name) }
        return NSDecimalNumber(decimal: number).int64Value
    }

    func optionalInt(_ name: String) throws -> Int? {
        try optionalInt64(name).map { Int($0) }
    }

    func int(_ name: String) throws -> Int {
        guard let number = try optionalInt(name) else { throw invalid(name) }
        return number
    }

    func localDateTime(_ name: String) throws -> LocalDateTime {
        guard let value = LocalDateTime(try string(name)) else { throw invalid(name) }
        return value
    }

    func localDate(_ name: String) throws -> LocalDate {
        guard let value = LocalDate(try string(name)) else { throw invalid(name) }
        return value
    }

    func optionalInstant(_ name: String) throws -> Date? {
        guard let text = try optionalString(name) else { return nil }
        guard let value = InstantText.parse(text) else { throw invalid(name) }
        return value
    }
}

/// Zapis pól obiektu JSON: `nil` pomija pole, liczby zachowują skalę `Decimal`.
struct ScaledObject {
    var fields: [String: JSONValue] = [:]

    mutating func set(_ name: String, _ value: String?) {
        if let value { fields[name] = .string(value) }
    }

    mutating func set(_ name: String, _ value: Decimal?) {
        if let value { fields[name] = .number(value) }
    }

    mutating func set(_ name: String, _ value: Int?) {
        if let value { fields[name] = .number(Decimal(value)) }
    }

    mutating func set(_ name: String, _ value: Int64?) {
        if let value { fields[name] = .number(Decimal(value)) }
    }

    var json: JSONValue { .object(fields) }
}

// MARK: - Parametry jazd

public extension RideProfile {
    /// Profil z obiektu JSON (`null` i brak pola = dziedziczy); liczby zachowują skalę.
    init(json: JSONValue) throws {
        let reader = try ScaledFields(json, owner: "Profil jazd")
        self.init(
            gaitStopMaxKmh: try reader.optionalDecimal("gaitStopMaxKmh"),
            gaitWalkMaxKmh: try reader.optionalDecimal("gaitWalkMaxKmh"),
            gaitTrotMaxKmh: try reader.optionalDecimal("gaitTrotMaxKmh"),
            loadWeightWalk: try reader.optionalDecimal("loadWeightWalk"),
            loadWeightTrot: try reader.optionalDecimal("loadWeightTrot"),
            loadWeightCanter: try reader.optionalDecimal("loadWeightCanter"),
            loadClimbPer10m: try reader.optionalDecimal("loadClimbPer10m"),
            loadWarnPercent: try reader.optionalInt("loadWarnPercent"),
            heavyRidePoints: try reader.optionalInt("heavyRidePoints")
        )
    }

    /// Profil jako obiekt JSON; pola `nil` są pomijane (jak dotychczasowa treść rekordu).
    func toJSON() -> JSONValue {
        var object = ScaledObject()
        object.set("gaitStopMaxKmh", gaitStopMaxKmh)
        object.set("gaitWalkMaxKmh", gaitWalkMaxKmh)
        object.set("gaitTrotMaxKmh", gaitTrotMaxKmh)
        object.set("loadWeightWalk", loadWeightWalk)
        object.set("loadWeightTrot", loadWeightTrot)
        object.set("loadWeightCanter", loadWeightCanter)
        object.set("loadClimbPer10m", loadClimbPer10m)
        object.set("loadWarnPercent", loadWarnPercent)
        object.set("heavyRidePoints", heavyRidePoints)
        return object.json
    }
}

public extension RideDefaults {
    /// Ustawienia jazd z obiektu JSON (`RideDefaultsDto`); liczby zachowują skalę.
    init(json: JSONValue) throws {
        let reader = try ScaledFields(json, owner: "Ustawienia jazd")
        self.init(
            gaitStopMaxKmh: try reader.decimal("gaitStopMaxKmh"),
            gaitWalkMaxKmh: try reader.decimal("gaitWalkMaxKmh"),
            gaitTrotMaxKmh: try reader.decimal("gaitTrotMaxKmh"),
            loadWeightWalk: try reader.decimal("loadWeightWalk"),
            loadWeightTrot: try reader.decimal("loadWeightTrot"),
            loadWeightCanter: try reader.decimal("loadWeightCanter"),
            loadClimbPer10m: try reader.decimal("loadClimbPer10m"),
            loadWarnPercent: try reader.int("loadWarnPercent"),
            heavyRidePoints: try reader.int("heavyRidePoints"),
            recordedRideTrainingTypeId: try reader.optionalString("recordedRideTrainingTypeId"),
            version: try reader.int("version")
        )
    }

    /// Ustawienia jako obiekt JSON; `recordedRideTrainingTypeId` `nil` jest pomijane.
    func toJSON() -> JSONValue {
        var object = ScaledObject()
        object.set("gaitStopMaxKmh", gaitStopMaxKmh)
        object.set("gaitWalkMaxKmh", gaitWalkMaxKmh)
        object.set("gaitTrotMaxKmh", gaitTrotMaxKmh)
        object.set("loadWeightWalk", loadWeightWalk)
        object.set("loadWeightTrot", loadWeightTrot)
        object.set("loadWeightCanter", loadWeightCanter)
        object.set("loadClimbPer10m", loadClimbPer10m)
        object.set("loadWarnPercent", loadWarnPercent)
        object.set("heavyRidePoints", heavyRidePoints)
        object.set("recordedRideTrainingTypeId", recordedRideTrainingTypeId)
        object.set("version", version)
        return object.json
    }
}

// MARK: - Rekordy magazynu

extension LocalTrainingRecording: ScaledJSONRecord {
    init(scaledJSON: JSONValue) throws {
        let reader = try ScaledFields(scaledJSON, owner: "Nagranie jazdy")
        self.init(recording: try Recording(json: reader.value("recording")), horseId: try reader.string("horseId"), trainingDate: try reader.localDate("trainingDate"))
    }

    func scaledJSON() -> JSONValue {
        .object(["recording": recording.toJSON(), "horseId": .string(horseId), "trainingDate": .string(trainingDate.description)])
    }
}

extension LocalHorseRideProfile: ScaledJSONRecord {
    init(scaledJSON: JSONValue) throws {
        let reader = try ScaledFields(scaledJSON, owner: "Profil jazd konia")
        self.init(
            horseId: try reader.string("horseId"), profile: try RideProfile(json: reader.present("profile") ?? .object([:])),
            createdAt: try reader.localDateTime("createdAt"), updatedAt: try reader.localDateTime("updatedAt"), version: try reader.optionalInt("version") ?? 0
        )
    }

    func scaledJSON() -> JSONValue {
        .object([
            "horseId": .string(horseId), "profile": profile.toJSON(), "createdAt": .string(createdAt.description),
            "updatedAt": .string(updatedAt.description), "version": .number(Decimal(version)),
        ])
    }
}

extension LocalRideDefaults: ScaledJSONRecord {
    init(scaledJSON: JSONValue) throws {
        let reader = try ScaledFields(scaledJSON, owner: "Ustawienia jazd")
        self.init(defaults: try RideDefaults(json: reader.value("defaults")), createdAt: try reader.localDateTime("createdAt"), updatedAt: try reader.localDateTime("updatedAt"))
    }

    func scaledJSON() -> JSONValue {
        .object(["defaults": defaults.toJSON(), "createdAt": .string(createdAt.description), "updatedAt": .string(updatedAt.description)])
    }
}

extension LocalAttachment: ScaledJSONRecord {
    init(scaledJSON: JSONValue) throws {
        let reader = try ScaledFields(scaledJSON, owner: "Załącznik")
        guard let ownerType = AttachmentOwnerType(rawValue: try reader.string("ownerType")) else { throw reader.invalid("ownerType") }
        guard let sizeBytes = try reader.optionalInt64("sizeBytes") else { throw reader.invalid("sizeBytes") }
        self.init(
            id: try reader.string("id"), createdAt: try reader.localDateTime("createdAt"), updatedAt: try reader.localDateTime("updatedAt"),
            version: try reader.optionalInt("version") ?? 0, ownerType: ownerType, ownerId: try reader.string("ownerId"),
            horseId: try reader.optionalString("horseId"), fileName: try reader.string("fileName"), contentType: try reader.string("contentType"),
            sizeBytes: sizeBytes, sha256: try reader.string("sha256"), description: try reader.optionalString("description"),
            capturedAt: try reader.optionalInstant("capturedAt"), latitude: try reader.optionalDecimal("latitude"),
            longitude: try reader.optionalDecimal("longitude")
        )
    }

    func scaledJSON() -> JSONValue {
        var object = ScaledObject()
        object.set("id", id)
        object.set("createdAt", createdAt.description)
        object.set("updatedAt", updatedAt.description)
        object.set("version", version)
        object.set("ownerType", ownerType.rawValue)
        object.set("ownerId", ownerId)
        object.set("horseId", horseId)
        object.set("fileName", fileName)
        object.set("contentType", contentType)
        object.set("sizeBytes", sizeBytes)
        object.set("sha256", sha256)
        object.set("description", description)
        object.set("capturedAt", capturedAt.map(InstantText.format))
        object.set("latitude", latitude)
        object.set("longitude", longitude)
        return object.json
    }
}
