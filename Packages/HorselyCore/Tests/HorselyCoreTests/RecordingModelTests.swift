// Modele nagrania jazdy, profilu konia i ustawień jazd ([K] 4.1, 4.2, 6, 7) — port `RecordingModelTest.kt` z Androida 3.0.2:
// kształt JSON (ze skalą liczb), rekordy magazynu i mapowanie odpowiedzi API na rekordy. Testy magazynu tras — R-C.

import Foundation
import Testing
@testable import HorselyCore

private func dec(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

private let trainingDate = LocalDate(year: 2026, month: 9, day: 1)!

/// Przykład z kontraktu [K] 4.2 — kopia 1:1 pliku Androida `core/src/test/resources/v3/recording.json` (z `trackData`).
private func recordingJSON() throws -> JSONValue {
    try JSONValue.parseKeepingScale(Fixtures.data("v3/recording.json"))
}

private func recording() throws -> Recording {
    try Recording(json: recordingJSON())
}

/// Liczba JSON jako tekst ze skalą (`jsonPrimitive.content` w Androidzie).
private func scaled(_ value: JSONValue?) -> String? {
    guard case let .number(number)? = value else { return nil }
    return DecimalText.text(number)
}

// MARK: - Liczby i chwile

@Test func decimalTextKeepsTheScaleOfTheJsonNumber() throws {
    for text in ["24.60", "0.0", "7", "98.0", "100.0", "-3.50", "0.05", "3900", "0"] {
        let parsed = try #require(DecimalText.parse(text))
        #expect(DecimalText.text(parsed) == text, "\(text)")
    }
    #expect(DecimalText.parse("24.60") == dec("24.6"))
    let withExponent = try #require(DecimalText.parse("1.5e2"))
    #expect(DecimalText.text(withExponent) == "150")
    #expect(DecimalText.parse("1.") == nil)
    #expect(DecimalText.parse("abc") == nil)
    #expect(try JSONValue.parseKeepingScale(#"{"b":[1.50,true,null],"a":"x\"ą"}"#).textKeepingScale() == #"{"a":"x\"ą","b":[1.50,true,null]}"#)
}

@Test func instantsReadAndWriteLikeJavaInstant() throws {
    let precise = try #require(InstantText.parse("2026-09-01T08:21:30.482113Z"))
    #expect(InstantText.format(precise) == "2026-09-01T08:21:30.482113Z")
    let whole = try #require(InstantText.parse("2026-09-01T07:02:11Z"))
    #expect(InstantText.format(whole) == "2026-09-01T07:02:11Z")
    let half = try #require(InstantText.parse("2026-09-01T07:02:11.5Z"))
    #expect(InstantText.format(half) == "2026-09-01T07:02:11.500Z")
    #expect(InstantText.parse("2026-11-10T08:00:00+01:00") == InstantText.parse("2026-11-10T07:00:00Z"))
    #expect(InstantText.parse("2026-11-10T08:00:00") == nil)
    #expect(InstantText.localDateTime(precise) == LocalDateTime(date: trainingDate, hour: 8, minute: 21, second: 30, nanosecond: 482_113_000))
    #expect(InstantText.date(LocalDateTime(year: 2026, month: 9, day: 2, hour: 10)!) == InstantText.parse("2026-09-02T10:00:00Z"))
}

// MARK: - Nagranie (`Recording`)

@Test func recordingDtoFromContractParsesAndRoundTrips() throws {
    let source = try recordingJSON()
    let parsed = try Recording(json: source)

    #expect(parsed.id == "a3d51c8e-0b94-4e7a-9f62-1c7e4b0d8a39")
    #expect(parsed.trainingId == "7b2f3a1c-5d0e-4c8a-9f21-0a6e8d4b1c33")
    #expect(parsed.version == 1)
    #expect(parsed.createdAt == InstantText.parse("2026-09-01T08:21:30.482113Z"))
    #expect(parsed.startedAt == InstantText.parse("2026-09-01T07:02:11Z"))
    #expect(parsed.timeZone == "Europe/Warsaw")
    #expect(parsed.totalSeconds == 3900)
    #expect(parsed.pausedSeconds == 120)
    #expect(parsed.avgMovingSpeedKmh == dec("7.85"))
    #expect(parsed.elevationGainM == 50)
    #expect(parsed.walkAvgCadence == dec("98.0"))
    #expect(parsed.loadPoints == dec("100.0"))
    #expect(parsed.gaitThresholdsUsed == GaitThresholds(stopMaxKmh: dec("1.5"), walkMaxKmh: dec("7"), trotMaxKmh: dec("15")))
    #expect(parsed.loadParamsUsed == LoadParams(weightWalk: dec("1"), weightTrot: dec("2"), weightCanter: dec("3"), climbPer10m: dec("1")))
    #expect(parsed.accelerometerUsed)
    #expect(parsed.weatherStatus == .fetched)
    #expect(parsed.weatherHumidityPct == 63)
    #expect(parsed.source["platform"] == .string("android"))
    #expect(parsed.trackFormat == "zk-track/1")
    #expect(parsed.pointCount == 3900)
    #expect(parsed.segments.map(\.gait) == [.walk, .trot, .canter])
    #expect(parsed.segments[1] == GaitSegment(
        seq: 2, gait: .trot, startOffsetSeconds: 2400, endOffsetSeconds: 3600, distanceMeters: 4000,
        avgSpeedKmh: dec("12.00"), maxSpeedKmh: dec("14.90"), avgCadence: dec("142.0"), elevationGainM: 12
    ))
    #expect(parsed.trackData != nil)

    // Ten sam JSON po odczycie i zapisie — liczby z zachowaną skalą (`24.60`, `98.0`, `0.0`), chwile jak w kontrakcie.
    #expect(parsed.toJSON().textKeepingScale() == source.textKeepingScale())
    #expect(scaled(parsed.toJSON()["maxSpeedKmh"]) == "24.60")

    // Odczyt przez `Codable` (treść rekordu, plik eksportu) daje te same wartości.
    #expect(try JSONDecoder().decode(Recording.self, from: Fixtures.data("v3/recording.json")) == parsed)
}

@Test func recordingFieldsFollowTheOrderOfTheContract() throws {
    #expect(Array(Recording.fieldNames.prefix(9)) == ["id", "trainingId", "version", "createdAt", "updatedAt", "startedAt", "endedAt", "timeZone", "totalSeconds"])
    #expect(Array(Recording.fieldNames.suffix(4)) == ["trackFormat", "pointCount", "segments", "trackData"])

    // Kolejność pól pierwszego poziomu w przykładzie kontraktu = `fieldNames`; nagranie zapisuje dokładnie te pola.
    let text = try Fixtures.string("v3/recording.json")
    let contractOrder = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
        guard line.hasPrefix("  \""), !line.hasPrefix("   ") else { return nil }
        return line.dropFirst(3).split(separator: "\"").first.map(String.init)
    }
    #expect(contractOrder == Recording.fieldNames)
    let json = try recording().toJSON()
    let written = try #require(json.objectValue)
    #expect(Set(written.keys) == Set(Recording.fieldNames))
}

@Test func inputHasNoResponseOnlyFieldsAndKeepsTrackData() throws {
    var source = try recording()
    source.trackData = nil
    let input = source.toInput(trackData: "QUJD")

    for name in ["id", "trainingId", "version", "createdAt", "updatedAt"] {
        #expect(input[name] == nil, "\(name)")
    }
    #expect(input["trackData"] == .string("QUJD"))
    #expect(input["segments"]?.arrayValue?.count == 3)
    #expect(input["trackFormat"] == .string("zk-track/1"))
    #expect(input["weatherStatus"] == .string("Fetched"))
    #expect(input["startedAt"] == .string("2026-09-01T07:02:11Z"))
    #expect(scaled(input["maxSpeedKmh"]) == "24.60")
    #expect(scaled(input["gaitThresholdsUsed"]?["walkMaxKmh"]) == "7")
}

@Test func inputOverridesTheTrackDataTheRecordingCarries() throws {
    #expect(try recording().toInput(trackData: "NOWE")["trackData"] == .string("NOWE"))
}

@Test func optionalValuesMissingInTheResponseStayNull() throws {
    let json = try recordingJSON()
    var fields = try #require(json.objectValue)
    for name in ["avgMovingSpeedKmh", "maxSpeedKmh", "elevationGainM", "walkAvgCadence", "weatherTempC", "weatherCode", "trackData"] {
        fields.removeValue(forKey: name)
    }

    let parsed = try Recording(json: .object(fields))

    #expect(parsed.avgMovingSpeedKmh == nil)
    #expect(parsed.elevationGainM == nil)
    #expect(parsed.walkAvgCadence == nil)
    #expect(parsed.weatherTempC == nil)
    #expect(parsed.weatherCode == nil)
    #expect(parsed.trackData == nil)
    let input = parsed.toInput(trackData: "X")
    #expect(input["avgMovingSpeedKmh"] == nil)
    #expect(input["weatherCode"] == nil)
}

@Test func segmentWithoutCadenceAndClimbReadsAsNull() throws {
    let text = #"{"seq":1,"gait":"Stop","startOffsetSeconds":0,"endOffsetSeconds":30,"distanceMeters":0,"avgSpeedKmh":0.00,"maxSpeedKmh":0.40,"avgCadence":null,"elevationGainM":null}"#

    let segment = try JSONDecoder().decode(GaitSegment.self, from: Data(text.utf8))

    #expect(segment.gait == .stop)
    #expect(segment.avgCadence == nil)
    #expect(segment.elevationGainM == nil)
    #expect(try GaitSegment(json: JSONValue.parseKeepingScale(text), path: "segment") == segment)
}

// MARK: - Rekord magazynu nagrania

@Test func localRecordKeepsNoTrackDataAndTakesTheHorseAndTheDateOfTheTraining() throws {
    let local = try recording().toRecord(horseId: "h1", trainingDate: trainingDate)

    #expect(local.recording.trackData == nil)
    #expect(local.recordType == .trainingRecording)
    #expect(local.id == "a3d51c8e-0b94-4e7a-9f62-1c7e4b0d8a39")
    #expect(local.parentId == "7b2f3a1c-5d0e-4c8a-9f21-0a6e8d4b1c33")
    #expect(local.horseId == "h1")
    #expect(local.primaryHorseId == "h1")
    #expect(local.horseIds == ["h1"])
    #expect(local.dateKey == trainingDate)
    #expect(local.version == 1)
    #expect(local.createdAt == LocalDateTime(date: trainingDate, hour: 8, minute: 21, second: 30, nanosecond: 482_113_000))

    let body = try RecordCodec.encodeString(local)
    #expect(!body.contains("trackData"), "treść rekordu nie niesie trasy (decyzja A4)")
    let decoded = try RecordCodec.decode(.trainingRecording, from: body)
    #expect(decoded as? LocalTrainingRecording == local)
    #expect(decoded.parentId == "7b2f3a1c-5d0e-4c8a-9f21-0a6e8d4b1c33")
    #expect(decoded.dateKey == trainingDate)
    #expect(local.toApi() == local.recording)
    #expect(local.toApi(trackData: "QUJD").trackData == "QUJD")
}

@Test func auditOfALocalRecordingChangesTheVersionAndTheUpdateTimeOnly() throws {
    let local = try recording().toRecord(horseId: "h1", trainingDate: trainingDate)
    let at = LocalDateTime(year: 2026, month: 9, day: 2, hour: 10)!

    let updated = local.withAudit(version: 4, updatedAt: at)

    #expect(updated.version == 4)
    #expect(updated.recording.version == 4)
    #expect(updated.updatedAt == at)
    #expect(updated.createdAt == local.createdAt)
    var expected = local.recording
    expected.version = 4
    expected.updatedAt = try #require(InstantText.parse("2026-09-02T10:00:00Z"))
    #expect(updated.recording == expected)
}

// MARK: - Odpowiedzi API → rekordy

@Test func apiDecodesARecordingOfATraining() throws {
    let body = try recordingJSON()

    let local = try #require(ApiRecordMapping.decodeRecording(body, horseId: "h1", trainingDate: trainingDate))

    #expect(local.recording.trackData == nil)
    #expect(local.horseId == "h1")
    #expect(local.recording.segments.count == 3)
    #expect(ApiRecordMapping.decodeRecording(.object(["id": .string("x")]), horseId: "h1", trainingDate: trainingDate) == nil)

    // Ogólne `record` nie zna treningu: nagranie czyta tylko wtedy, gdy wołający dopisał `horseId` i `trainingDate`.
    #expect(ApiRecordMapping.record(.trainingRecording, from: body) == nil)
    var withTraining = try #require(body.objectValue)
    withTraining["horseId"] = .string("h1")
    withTraining["trainingDate"] = .string("2026-09-01")
    let viaRecord = try #require(ApiRecordMapping.record(.trainingRecording, from: .object(withTraining)) as? LocalTrainingRecording)
    #expect(viaRecord == local)
}

@Test func horseWithARideProfileParsesAndTheProfileIsItsOwnRecord() throws {
    let horse = try JSONValue.parse(
        #"{"id":"h1","version":7,"createdAt":"2026-01-01T10:00:00Z","updatedAt":"2026-08-01T10:00:00Z","name":"Grom","rideProfile":{"gaitStopMaxKmh":null,"gaitWalkMaxKmh":null,"gaitTrotMaxKmh":null,"loadWeightWalk":null,"loadWeightTrot":2.5,"loadWeightCanter":null,"loadClimbPer10m":null,"loadWarnPercent":20,"heavyRidePoints":null}}"#
    )

    // Koń zostaje koniem — profil nie trafia do jego rekordu (decyzja A4).
    let horseRecord = try #require(ApiRecordMapping.record(.horse, from: horse) as? LocalHorse)
    #expect(horseRecord.name == "Grom")
    let horseBody = try RecordCodec.encodeString(horseRecord)
    #expect(!horseBody.contains("rideProfile"))

    let profile = try #require(ApiRecordMapping.rideProfileRecord(fromHorse: horse))
    #expect(profile.profile == RideProfile(loadWeightTrot: dec("2.5"), loadWarnPercent: 20))
    #expect(profile.id == "h1")
    #expect(profile.horseId == "h1")
    #expect(profile.primaryHorseId == "h1")
    #expect(profile.recordType == .horseRideProfile)
    #expect(profile.version == 7)
    #expect(profile.updatedAt == LocalDateTime(year: 2026, month: 8, day: 1, hour: 10))
    #expect(try RecordCodec.decode(.horseRideProfile, from: RecordCodec.encode(profile)) as? LocalHorseRideProfile == profile)
    #expect((ApiRecordMapping.record(.horseRideProfile, from: horse) as? LocalHorseRideProfile)?.profile == profile.profile)
}

@Test func horseWithoutARideProfileHasNoProfileRecord() throws {
    let v1 = try JSONValue.parse(#"{"id":"h1","version":1,"createdAt":"2026-01-01T10:00:00Z","updatedAt":"2026-01-01T10:00:00Z","name":"Stary"}"#)

    #expect(ApiRecordMapping.rideProfileRecord(fromHorse: v1) == nil)
    #expect(ApiRecordMapping.record(.horseRideProfile, from: v1) == nil)
    let explicitNull = try JSONValue.parse(#"{"id":"h1","version":1,"createdAt":"2026-01-01T10:00:00Z","updatedAt":"2026-01-01T10:00:00Z","name":"Stary","rideProfile":null}"#)
    #expect(ApiRecordMapping.rideProfileRecord(fromHorse: explicitNull) == nil)
}

@Test func horseInputOmitsTheRideProfileUnlessItIsSet() throws {
    let stamp = LocalDateTime(year: 2026, month: 1, day: 1, hour: 10)!
    let horse = LocalHorse(id: "h1", createdAt: stamp, updatedAt: stamp, version: 2, name: "Grom")

    #expect(ApiRecordMapping.input(horse)["rideProfile"] == nil, "pominięty profil = bez zmian po stronie serwera")
    #expect(ApiRecordMapping.input(horse, rideProfile: RideProfile())["rideProfile"] == .object([:]), "pusty obiekt = wszystko dziedziczy")
    let own = ApiRecordMapping.input(horse, rideProfile: RideProfile(loadWeightTrot: dec("2.5"), heavyRidePoints: 80))["rideProfile"]
    let expected = try JSONValue.parse(#"{"loadWeightTrot":2.5,"heavyRidePoints":80}"#)
    #expect(own == expected)
}

@Test func trainingWithARecordingSummaryParses() throws {
    let training = try JSONValue.parse(
        #"{"id":"t1","version":3,"createdAt":"2026-09-01T07:00:00Z","updatedAt":"2026-09-01T09:10:00Z","horseId":"h1","trainingDate":"2026-09-01","trainingTypeId":"tt","recordingSummary":{"recordingId":"a3d51c8e-0b94-4e7a-9f62-1c7e4b0d8a39","distanceMeters":8500,"totalSeconds":3900,"version":1}}"#
    )

    #expect(ApiRecordMapping.recordingSummary(ofTraining: training) == RecordingSummary(recordingId: "a3d51c8e-0b94-4e7a-9f62-1c7e4b0d8a39", distanceMeters: 8500, totalSeconds: 3900, version: 1))
    // Trening zostaje treningiem — podsumowanie jest tylko w odpowiedzi API (decyzja A4).
    let record = try #require(ApiRecordMapping.record(.training, from: training) as? LocalTraining)
    let trainingBody = try RecordCodec.encodeString(record)
    #expect(!trainingBody.contains("recordingSummary"))

    let old = try JSONValue.parse(#"{"id":"t1","version":3,"createdAt":"2026-09-01T07:00:00Z","updatedAt":"2026-09-01T09:10:00Z","horseId":"h1","trainingDate":"2026-09-01","trainingTypeId":"tt","recordingSummary":null}"#)
    #expect(ApiRecordMapping.recordingSummary(ofTraining: old) == nil)
}

// MARK: - Ustawienia domyślne jazd

@Test func rideDefaultsParseFromTheContractAndAreOneRecord() throws {
    let text = #"{"gaitStopMaxKmh":1.5,"gaitWalkMaxKmh":7,"gaitTrotMaxKmh":15,"loadWeightWalk":1,"loadWeightTrot":2,"loadWeightCanter":3,"loadClimbPer10m":1,"loadWarnPercent":30,"heavyRidePoints":60,"recordedRideTrainingTypeId":"d2c6b0f4-9a1e-4f58-8b37-6e1a0c9d2f75","version":0}"#

    let defaults = try JSONDecoder().decode(RideDefaults.self, from: Data(text.utf8))

    var expected = RideDefaults.builtIn
    expected.recordedRideTrainingTypeId = "d2c6b0f4-9a1e-4f58-8b37-6e1a0c9d2f75"
    #expect(defaults == expected)
    let local = defaults.toRecord()
    #expect(local.id == "ride-defaults")
    #expect(local.id == LocalRideDefaults.ID)
    #expect(local.recordType == .rideDefaults)
    #expect(local.version == 0)
    #expect(local.primaryHorseId == nil)
    #expect(local.toApi() == defaults)
    #expect(try RecordCodec.decode(.rideDefaults, from: RecordCodec.encode(local)) as? LocalRideDefaults == local)
    #expect(try ApiRecordMapping.record(.rideDefaults, from: JSONValue.parse(text)) as? LocalRideDefaults == local)

    var changed = defaults
    changed.loadWeightTrot = dec("2.5")
    changed.version = 1
    let saved = changed.toRecord()
    #expect(saved.version == 1)
    #expect(saved.withAudit(version: 2, updatedAt: LocalDateTime(year: 2026, month: 9, day: 2, hour: 10)!).defaults.version == 2)
}

@Test func rideDefaultsWithoutTheTrainingTypeKeepItNull() throws {
    let body = String(decoding: try JSONEncoder().encode(RideDefaults.builtIn), as: UTF8.self)

    #expect(!body.contains("recordedRideTrainingTypeId"))
    #expect(try JSONDecoder().decode(RideDefaults.self, from: Data(body.utf8)) == RideDefaults.builtIn)
}

// MARK: - Rodzaje rekordów

@Test func exportDocumentRecordTypesMapCollections() {
    #expect(RecordType.trainingRecording.exportCollection == "trainingRecordings")
    #expect(RecordType.horseRideProfile.exportCollection == "horseRideProfiles")
    #expect(RecordType.rideDefaults.exportCollection == nil, "ustawienia jazd to obiekt `rideDefaults`, nie kolekcja")
    #expect(RecordType.fromRemovalType("TrainingRecording") == .trainingRecording)
    #expect(RecordType.fromRemovalType("HorseRideProfile") == .horseRideProfile)
    #expect(RecordType.fromRemovalType("RideDefaults") == .rideDefaults)
    #expect(RecordType.fromRemovalType("trainingRecordings") == nil)
}

// MARK: - Parametry jazd (R-A)

@Test func profileInheritsFieldByField() {
    // Test z [PLAN-A]: resolve z profilem częściowym.
    let defaults = RideDefaults.builtIn
    let profile = RideProfile(gaitWalkMaxKmh: Decimal(string: "8"), loadWarnPercent: 20)
    let p = RideParameters.resolve(defaults, profile)

    #expect(p.thresholds.walkMaxKmh == Decimal(string: "8"))
    #expect(p.thresholds.trotMaxKmh == Decimal(string: "15"))
    #expect(p.thresholds.stopMaxKmh == Decimal(string: "1.5"))
    #expect(p.warnPercent == 20)
    #expect(p.heavyRidePoints == 60)
    #expect(p.ownFields == ["gaitWalkMaxKmh", "loadWarnPercent"])
}

@Test func exampleFromPar02Gives100Points() {
    // [PLAN-A] Task 4 / Android `example from PAR-02 gives 100 points`: 40 min stępa, 20 min kłusa, 5 min galopu, 50 m podjazdu.
    #expect(RideParameters.loadPoints(walkSeconds: 2400, trotSeconds: 1200, canterSeconds: 300, elevationGainM: 50, load: RideDefaults.builtIn.load)
        == Decimal(string: "100.0")!)
}

@Test func walkThresholdNotAboveStopIsRejected() {
    // Android `walk threshold not above stop is rejected`: równość zbioru kluczy z przedrostkiem `rideProfile.`.
    let errors = RideParameters.validate(RideProfile(gaitWalkMaxKmh: Decimal(string: "1.5")!), RideDefaults.builtIn)
    #expect(Set(errors.keys) == ["rideProfile.gaitWalkMaxKmh"])
}

@Test func rangesFromPar05() {
    // Android `ranges from PAR-05 in a profile`: prędkości 0,5–40, wagi 0,1–10, podjazd 0–10, próg 5–200, ciężka 1–10 000.
    func keys(_ profile: RideProfile) -> Set<String> { Set(RideParameters.validate(profile, RideDefaults.builtIn).keys) }
    func bd(_ text: String) -> Decimal { Decimal(string: text)! }

    // poza zakresem
    #expect(keys(RideProfile(gaitStopMaxKmh: bd("0.4"))) == ["rideProfile.gaitStopMaxKmh"])
    #expect(keys(RideProfile(gaitTrotMaxKmh: bd("41"))) == ["rideProfile.gaitTrotMaxKmh"])
    #expect(keys(RideProfile(loadWeightWalk: bd("0.05"))) == ["rideProfile.loadWeightWalk"])
    #expect(keys(RideProfile(loadWeightTrot: bd("11"))) == ["rideProfile.loadWeightTrot"])
    #expect(keys(RideProfile(loadWeightCanter: bd("10.1"))) == ["rideProfile.loadWeightCanter"])
    #expect(keys(RideProfile(loadClimbPer10m: bd("10.1"))) == ["rideProfile.loadClimbPer10m"])
    #expect(keys(RideProfile(loadClimbPer10m: bd("-0.1"))) == ["rideProfile.loadClimbPer10m"])
    #expect(keys(RideProfile(loadWarnPercent: 4)) == ["rideProfile.loadWarnPercent"])
    #expect(keys(RideProfile(loadWarnPercent: 201)) == ["rideProfile.loadWarnPercent"])
    #expect(keys(RideProfile(heavyRidePoints: 0)) == ["rideProfile.heavyRidePoints"])
    #expect(keys(RideProfile(heavyRidePoints: 10001)) == ["rideProfile.heavyRidePoints"])

    // granice przechodzą
    #expect(keys(RideProfile(gaitStopMaxKmh: bd("0.5"))).isEmpty)
    #expect(keys(RideProfile(gaitTrotMaxKmh: bd("40"))).isEmpty)
    #expect(keys(RideProfile(gaitStopMaxKmh: bd("0.5"), gaitWalkMaxKmh: bd("1"), gaitTrotMaxKmh: bd("40"))).isEmpty)
    #expect(keys(RideProfile(loadWeightWalk: bd("0.1"), loadWeightTrot: bd("10"), loadWeightCanter: bd("10"))).isEmpty)
    #expect(keys(RideProfile(loadClimbPer10m: bd("0"))).isEmpty)
    #expect(keys(RideProfile(loadClimbPer10m: bd("10"))).isEmpty)
    #expect(keys(RideProfile(loadWarnPercent: 5)).isEmpty)
    #expect(keys(RideProfile(loadWarnPercent: 200)).isEmpty)
    #expect(keys(RideProfile(heavyRidePoints: 1)).isEmpty)
    #expect(keys(RideProfile(heavyRidePoints: 10000)).isEmpty)
}
