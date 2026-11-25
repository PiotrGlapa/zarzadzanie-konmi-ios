// Testy RideParameters i HalfUp — port 1:1 testu Androida 3.0.2 `core/src/test/.../ride/RideParametersTest.kt`
// (progi chodów i parametry obciążenia: dziedziczenie profilu konia, punkty jazdy, walidacja; PAR-01, PAR-02, PAR-05).
// Testy o nazwach z planu (`profileInheritsFieldByField`, `exampleFromPar02Gives100Points`, `walkThresholdNotAboveStopIsRejected`,
// `rangesFromPar05`) są w `RecordingModelTests.swift`.

import Testing
import Foundation
@testable import HorselyCore

private func bd(_ text: String) -> Decimal { Decimal(string: text)! }

private let defaults = RideDefaults.builtIn

/// Odpowiednik `defaults.copy(...)` z Kotlina.
private func changedDefaults(_ change: (inout RideDefaults) -> Void) -> RideDefaults {
    var copy = RideDefaults.builtIn
    change(&copy)
    return copy
}

// MARK: - HalfUp

@Test func halfUpRoundsAwayFromZero() {
    // HALF_UP „od zera" — przy remisie oddala od zera.
    #expect(HalfUp.round(Decimal(string: "2.345")!, scale: 2) == Decimal(string: "2.35"))
    #expect(HalfUp.round(Decimal(string: "-2.345")!, scale: 2) == Decimal(string: "-2.35"))
    #expect(HalfUp.round(Decimal(string: "2.5")!, scale: 0) == Decimal(string: "3"))
    #expect(HalfUp.round(Decimal(string: "-2.5")!, scale: 0) == Decimal(string: "-3"))
    #expect(HalfUp.round(Decimal(string: "2.34")!, scale: 1) == Decimal(string: "2.3"))
    #expect(HalfUp.round(Decimal(string: "2.36")!, scale: 1) == Decimal(string: "2.4"))
    #expect(HalfUp.round(Decimal(string: "0.0")!, scale: 2) == Decimal(string: "0.0"))
    #expect(HalfUp.round(Decimal(string: "-0.0")!, scale: 2) == Decimal(string: "0.0"))
}

// MARK: - RideDefaults

@Test func builtInDefaultsAreTheValuesOfPar01AndPar02() {
    #expect([defaults.gaitStopMaxKmh, defaults.gaitWalkMaxKmh, defaults.gaitTrotMaxKmh] == ["1.5", "7", "15"].map(bd))
    #expect([defaults.loadWeightWalk, defaults.loadWeightTrot, defaults.loadWeightCanter, defaults.loadClimbPer10m] == ["1", "2", "3", "1"].map(bd))
    #expect(defaults.loadWarnPercent == 30)
    #expect(defaults.heavyRidePoints == 60)
    #expect(defaults.version == 0)
    #expect(defaults.recordedRideTrainingTypeId == nil)
}

@Test func defaultsGiveTheirThresholdsAndLoad() {
    #expect(defaults.thresholds == GaitThresholds(stopMaxKmh: bd("1.5"), walkMaxKmh: bd("7"), trotMaxKmh: bd("15")))
    #expect(defaults.load == LoadParams(weightWalk: bd("1"), weightTrot: bd("2"), weightCanter: bd("3"), climbPer10m: bd("1")))
}

@Test func defaultsInputHasTheValuesWithoutTheVersion() {
    let saved = changedDefaults { $0.loadWeightTrot = bd("2.5"); $0.recordedRideTrainingTypeId = "t1"; $0.version = 4 }

    #expect(saved.toInput() == RideDefaultsInput(
        gaitStopMaxKmh: bd("1.5"), gaitWalkMaxKmh: bd("7"), gaitTrotMaxKmh: bd("15"),
        loadWeightWalk: bd("1"), loadWeightTrot: bd("2.5"), loadWeightCanter: bd("3"), loadClimbPer10m: bd("1"),
        loadWarnPercent: 30, heavyRidePoints: 60, recordedRideTrainingTypeId: "t1"
    ))
}

@Test func sameValuesCompareDecimalsByValueAndIgnoreTheVersion() {
    #expect(defaults.sameValues(changedDefaults { $0.gaitStopMaxKmh = bd("1.50"); $0.version = 7 }))
    #expect(!defaults.sameValues(changedDefaults { $0.loadWeightTrot = bd("2.5") }))
    #expect(!defaults.sameValues(changedDefaults { $0.recordedRideTrainingTypeId = "t1" }))

    #expect(RideProfile(loadWeightTrot: bd("2.5")).sameValues(RideProfile(loadWeightTrot: bd("2.50"))))
    #expect(!RideProfile(loadWeightTrot: bd("2.5")).sameValues(RideProfile()))
    #expect(!RideProfile(heavyRidePoints: 80).sameValues(RideProfile(heavyRidePoints: 81)))
}

@Test func aProfileWithoutOwnValuesIsEmpty() {
    #expect(RideProfile().isEmpty)
    #expect(!RideProfile(loadWarnPercent: 20).isEmpty)
    #expect(!RideProfile(gaitStopMaxKmh: bd("1")).isEmpty)
}

// MARK: - RideParameters.resolve

@Test func ownFieldsFollowTheOrderOfTheProfileFields() {
    let profile = RideProfile(
        gaitStopMaxKmh: bd("1"), gaitWalkMaxKmh: bd("6"), gaitTrotMaxKmh: bd("16"),
        loadWeightWalk: bd("1.2"), loadWeightTrot: bd("2.5"), loadWeightCanter: bd("4"), loadClimbPer10m: bd("2"),
        loadWarnPercent: 15, heavyRidePoints: 80
    )

    let p = RideParameters.resolve(defaults, profile)

    #expect(p.ownFields == [
        "gaitStopMaxKmh", "gaitWalkMaxKmh", "gaitTrotMaxKmh", "loadWeightWalk", "loadWeightTrot", "loadWeightCanter", "loadClimbPer10m",
        "loadWarnPercent", "heavyRidePoints"
    ])
    #expect(p.load == LoadParams(weightWalk: bd("1.2"), weightTrot: bd("2.5"), weightCanter: bd("4"), climbPer10m: bd("2")))
}

@Test func aHorseWithoutAProfileGetsTheDefaults() {
    for profile in [nil, RideProfile()] as [RideProfile?] {
        let p = RideParameters.resolve(defaults, profile)
        #expect(p.thresholds == GaitThresholds(stopMaxKmh: bd("1.5"), walkMaxKmh: bd("7"), trotMaxKmh: bd("15")))
        #expect(p.load == LoadParams(weightWalk: bd("1"), weightTrot: bd("2"), weightCanter: bd("3"), climbPer10m: bd("1")))
        #expect(p.warnPercent == 30)
        #expect(p.heavyRidePoints == 60)
        #expect(p.ownFields.isEmpty)
    }
}

@Test func savedDefaultsReplaceTheBuiltInOnesForHorsesThatInherit() {
    let saved = changedDefaults { $0.loadWeightTrot = bd("2.5"); $0.gaitWalkMaxKmh = bd("6.5"); $0.version = 3 }

    let p = RideParameters.resolve(saved, RideProfile(loadWeightCanter: bd("4")))

    #expect(p.load.weightTrot == bd("2.5"))
    #expect(p.thresholds.walkMaxKmh == bd("6.5"))
    #expect(p.load.weightCanter == bd("4"))
    #expect(p.ownFields == ["loadWeightCanter"])
}

// MARK: - RideParameters.loadPoints

@Test func pointsAreRoundedToATenthHalfUpAndAMissingClimbCountsAsZero() {
    let load = defaults.load

    #expect(RideParameters.loadPoints(walkSeconds: 3, trotSeconds: 0, canterSeconds: 0, elevationGainM: nil, load: load) == bd("0.1"), "0,05 → 0,1")
    #expect(RideParameters.loadPoints(walkSeconds: 2, trotSeconds: 0, canterSeconds: 0, elevationGainM: nil, load: load) == bd("0.0"), "0,033 → 0,0")
    #expect(RideParameters.loadPoints(walkSeconds: 0, trotSeconds: 2, canterSeconds: 0, elevationGainM: nil, load: load) == bd("0.1"), "0,067 → 0,1")
    #expect(RideParameters.loadPoints(walkSeconds: 0, trotSeconds: 0, canterSeconds: 0, elevationGainM: 15, load: load) == bd("1.5"), "15 m podjazdu = 1,5 pkt")
    #expect(RideParameters.loadPoints(walkSeconds: 0, trotSeconds: 0, canterSeconds: 0, elevationGainM: nil, load: load) == bd("0.0"))
    #expect(
        RideParameters.loadPoints(walkSeconds: 600, trotSeconds: 0, canterSeconds: 0, elevationGainM: 0, load: load)
            == RideParameters.loadPoints(walkSeconds: 600, trotSeconds: 0, canterSeconds: 0, elevationGainM: nil, load: load)
    )
}

@Test func pointsAreDividedOnceSoATieOfComponentsRoundsHalfUp() {
    // Audyt K7: 2 s · 1 + 2 s · 0,5 = 3 / 60 = 0,05 dokładnie → 0,1. Dzielenie każdego składnika osobno dałoby 0,0499… → 0,0.
    let load = LoadParams(weightWalk: bd("1"), weightTrot: bd("0.5"), weightCanter: bd("3"), climbPer10m: bd("1"))

    #expect(RideParameters.loadPoints(walkSeconds: 2, trotSeconds: 2, canterSeconds: 0, elevationGainM: nil, load: load) == bd("0.1"))
}

@Test func pointsUseTheWeightsOfTheHorse() {
    let heavyTrot = RideParameters.resolve(defaults, RideProfile(loadWeightTrot: bd("2.5"), loadClimbPer10m: bd("0.5")))

    #expect(RideParameters.loadPoints(walkSeconds: 2400, trotSeconds: 1200, canterSeconds: 300, elevationGainM: 50, load: heavyTrot.load) == bd("107.5"))
}

// MARK: - RideParameters.exampleText

@Test func exampleTextShowsTheDefaultExample() {
    #expect(RideParameters.exampleText(defaults.load) == "Jazda 40 min stępa, 20 min kłusa, 5 min galopu, 50 m podjazdu = 40 + 40 + 15 + 5 = 100 pkt")
}

@Test func exampleTextFollowsTheCurrentWeightsWithADecimalComma() {
    let load = LoadParams(weightWalk: bd("1"), weightTrot: bd("2.5"), weightCanter: bd("2.25"), climbPer10m: bd("1"))

    #expect(RideParameters.exampleText(load) == "Jazda 40 min stępa, 20 min kłusa, 5 min galopu, 50 m podjazdu = 40 + 50 + 11,25 + 5 = 106,3 pkt")
}

// MARK: - RideParameters.validate

@Test func thresholdsAreCheckedOnTheMergedValues() {
    let stopAboveInheritedWalk = RideParameters.validate(RideProfile(gaitStopMaxKmh: bd("8")), defaults)
    #expect(stopAboveInheritedWalk.dictionary == ["rideProfile.gaitWalkMaxKmh": "Próg stępa musi być większy niż próg postoju."])

    let trotNotAboveWalk = RideParameters.validate(RideProfile(gaitTrotMaxKmh: bd("7")), defaults)
    #expect(trotNotAboveWalk.dictionary == ["rideProfile.gaitTrotMaxKmh": "Próg kłusa musi być większy niż próg stępa."])

    let ownThresholdsInOrder = RideProfile(gaitStopMaxKmh: bd("2"), gaitWalkMaxKmh: bd("9"), gaitTrotMaxKmh: bd("18"))
    #expect(RideParameters.validate(ownThresholdsInOrder, defaults).isEmpty)
}

@Test func anEmptyProfileAndTheBuiltInDefaultsAreValid() {
    #expect(RideParameters.validate(RideProfile(), defaults).isEmpty)
    #expect(RideParameters.validate(defaults).isEmpty)
}

@Test func rangeMessagesArePolish() {
    let errors = RideParameters.validate(
        RideProfile(gaitStopMaxKmh: bd("0.4"), loadWeightTrot: bd("11"), loadClimbPer10m: bd("11"), loadWarnPercent: 4, heavyRidePoints: 0),
        defaults
    )

    #expect(errors["rideProfile.gaitStopMaxKmh"] == "Wpisz wartość od 0,5 do 40 km/h.")
    #expect(errors["rideProfile.loadWeightTrot"] == "Wpisz wartość od 0,1 do 10.")
    #expect(errors["rideProfile.loadClimbPer10m"] == "Wpisz wartość od 0 do 10.")
    #expect(errors["rideProfile.loadWarnPercent"] == "Wpisz wartość od 5 do 200.")
    #expect(errors["rideProfile.heavyRidePoints"] == "Wpisz wartość od 1 do 10 000.")
}

@Test func aRangeErrorWinsOverTheOrderErrorOfTheSameField() {
    let errors = RideParameters.validate(RideProfile(gaitWalkMaxKmh: bd("0.4")), defaults)

    #expect(errors.dictionary == ["rideProfile.gaitWalkMaxKmh": "Wpisz wartość od 0,5 do 40 km/h."])
}

@Test func defaultsAreValidatedWithoutTheProfilePrefix() {
    #expect(
        RideParameters.validate(changedDefaults { $0.gaitWalkMaxKmh = bd("1.5") }).dictionary
            == ["gaitWalkMaxKmh": "Próg stępa musi być większy niż próg postoju."]
    )
    #expect(Set(RideParameters.validate(changedDefaults { $0.gaitTrotMaxKmh = bd("7") }).keys) == ["gaitTrotMaxKmh"])
    #expect(
        Set(RideParameters.validate(changedDefaults { $0.loadWeightWalk = bd("0.05"); $0.heavyRidePoints = 10001; $0.loadWarnPercent = 3 }).keys)
            == ["loadWeightWalk", "heavyRidePoints", "loadWarnPercent"]
    )
    #expect(RideParameters.validate(changedDefaults {
        $0.gaitStopMaxKmh = bd("0.5"); $0.gaitWalkMaxKmh = bd("0.6"); $0.gaitTrotMaxKmh = bd("40"); $0.loadClimbPer10m = bd("0")
    }).isEmpty)
}

@Test func theKeysOfTheProfileAreTheNamesOfTheContract() {
    let all = RideProfile(
        gaitStopMaxKmh: bd("0.1"), gaitWalkMaxKmh: bd("0.1"), gaitTrotMaxKmh: bd("0.1"),
        loadWeightWalk: bd("0"), loadWeightTrot: bd("0"), loadWeightCanter: bd("0"), loadClimbPer10m: bd("-1"),
        loadWarnPercent: 0, heavyRidePoints: 0
    )
    let names = [
        "gaitStopMaxKmh", "gaitWalkMaxKmh", "gaitTrotMaxKmh", "loadWeightWalk", "loadWeightTrot", "loadWeightCanter", "loadClimbPer10m",
        "loadWarnPercent", "heavyRidePoints"
    ]

    let errors = RideParameters.validate(all, defaults)

    #expect(Set(errors.keys) == Set(names.map { "rideProfile.\($0)" }))
    // Kolejność kluczy jak `LinkedHashMap` w Androidzie: kolejność pól profilu.
    #expect(errors.keys == names.map { "rideProfile.\($0)" })
    #expect(errors.values.allSatisfy { $0.hasSuffix(".") })
}

// MARK: - RecordingSummary

@Test func recordingSummaryHashable() {
    let s1 = RecordingSummary(recordingId: "abc", distanceMeters: 5000, totalSeconds: 3600, version: 1)
    let s2 = RecordingSummary(recordingId: "abc", distanceMeters: 5000, totalSeconds: 3600, version: 1)
    let s3 = RecordingSummary(recordingId: "def", distanceMeters: 5000, totalSeconds: 3600, version: 1)

    #expect(s1 == s2)
    #expect(s1 != s3)
    #expect(Set([s1, s2, s3]).count == 2)
}

@Test func recordingSummaryCodable() throws {
    let summary = RecordingSummary(recordingId: "abc", distanceMeters: 5000, totalSeconds: 3600, version: 1)
    let encoded = try JSONEncoder().encode(summary)
    let decoded = try JSONDecoder().decode(RecordingSummary.self, from: encoded)

    #expect(decoded.recordingId == summary.recordingId)
    #expect(decoded.distanceMeters == summary.distanceMeters)
    #expect(decoded.totalSeconds == summary.totalSeconds)
    #expect(decoded.version == summary.version)
}

// MARK: - GaitSegment

@Test func gaitSegmentHashable() {
    let s1 = GaitSegment(seq: 1, gait: .walk, startOffsetSeconds: 0, endOffsetSeconds: 600,
                          distanceMeters: 1000, avgSpeedKmh: Decimal(string: "5")!, maxSpeedKmh: Decimal(string: "7")!)
    let s2 = GaitSegment(seq: 1, gait: .walk, startOffsetSeconds: 0, endOffsetSeconds: 600,
                          distanceMeters: 1000, avgSpeedKmh: Decimal(string: "5")!, maxSpeedKmh: Decimal(string: "7")!)

    #expect(s1 == s2)
    #expect(Set<GaitSegment>([s1, s2]).count == 1)
}

@Test func gaitSegmentCodable() throws {
    let segment = GaitSegment(seq: 1, gait: .trot, startOffsetSeconds: 600, endOffsetSeconds: 1200,
                              distanceMeters: 2000, avgSpeedKmh: Decimal(string: "12")!, maxSpeedKmh: Decimal(string: "15")!,
                              avgCadence: Decimal(string: "140"), elevationGainM: 10)
    let encoded = try JSONEncoder().encode(segment)
    let decoded = try JSONDecoder().decode(GaitSegment.self, from: encoded)

    #expect(decoded.seq == 1)
    #expect(decoded.gait == .trot)
    #expect(decoded.avgCadence == Decimal(string: "140"))
    #expect(decoded.elevationGainM == 10)
}

// MARK: - Gait

@Test func gaitAllCases() {
    #expect(Gait.allCases.count == 4)
    #expect(Gait.allCases.contains(.stop))
    #expect(Gait.allCases.contains(.walk))
    #expect(Gait.allCases.contains(.trot))
    #expect(Gait.allCases.contains(.canter))
}

@Test func gaitRawValues() {
    #expect(Gait.stop.rawValue == "Stop")
    #expect(Gait.walk.rawValue == "Walk")
    #expect(Gait.trot.rawValue == "Trot")
    #expect(Gait.canter.rawValue == "Canter")
}

@Test func gaitFromRawValue() {
    #expect(Gait(rawValue: "Stop") == .stop)
    #expect(Gait(rawValue: "Walk") == .walk)
    #expect(Gait(rawValue: "Trot") == .trot)
    #expect(Gait(rawValue: "Canter") == .canter)
}

// MARK: - WeatherStatus

@Test func weatherStatusAllCases() {
    #expect(WeatherStatus.allCases.count == 5)
    #expect(WeatherStatus.allCases.contains(.none))
    #expect(WeatherStatus.allCases.contains(.pending))
    #expect(WeatherStatus.allCases.contains(.fetched))
    #expect(WeatherStatus.allCases.contains(.disabled))
    #expect(WeatherStatus.allCases.contains(.failed))
}

@Test func weatherStatusRawValues() {
    #expect(WeatherStatus.none.rawValue == "None")
    #expect(WeatherStatus.pending.rawValue == "Pending")
    #expect(WeatherStatus.fetched.rawValue == "Fetched")
    #expect(WeatherStatus.disabled.rawValue == "Disabled")
    #expect(WeatherStatus.failed.rawValue == "Failed")
}
