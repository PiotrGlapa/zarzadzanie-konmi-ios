// Testy RideParameters i HalfUp — Task 5, krok 2.
// Oparte na [PLAN-A] Task 4 Step 2/3.

import Testing
@testable import HorselyCore

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

// MARK: - RideDefaults.builtIn

@Test func builtInHasExpectedValues() {
    let defaults = RideDefaults.builtIn
    #expect(defaults.gaitStopMaxKmh == Decimal(string: "1.5"))
    #expect(defaults.gaitWalkMaxKmh == Decimal(string: "7"))
    #expect(defaults.gaitTrotMaxKmh == Decimal(string: "15"))
    #expect(defaults.loadWeightWalk == Decimal(string: "1"))
    #expect(defaults.loadWeightTrot == Decimal(string: "2"))
    #expect(defaults.loadWeightCanter == Decimal(string: "3"))
    #expect(defaults.loadClimbPer10m == Decimal(string: "1"))
    #expect(defaults.loadWarnPercent == 30)
    #expect(defaults.heavyRidePoints == 60)
    #expect(defaults.recordedRideTrainingTypeId == nil)
    #expect(defaults.version == 0)
}

// MARK: - RideParameters.resolve

@Test func resolveWithNilProfileReturnsDefaults() {
    let defaults = RideDefaults.builtIn
    let p = RideParameters.resolve(defaults, nil)

    #expect(p.thresholds.stopMaxKmh == Decimal(string: "1.5"))
    #expect(p.thresholds.walkMaxKmh == Decimal(string: "7"))
    #expect(p.thresholds.trotMaxKmh == Decimal(string: "15"))
    #expect(p.load.weightWalk == Decimal(string: "1"))
    #expect(p.load.weightTrot == Decimal(string: "2"))
    #expect(p.load.weightCanter == Decimal(string: "3"))
    #expect(p.load.climbPer10m == Decimal(string: "1"))
    #expect(p.warnPercent == 30)
    #expect(p.heavyRidePoints == 60)
    #expect(p.ownFields.isEmpty)
}

@Test func resolveWithPartialProfileOverridesOnlySetFields() {
    let defaults = RideDefaults.builtIn
    let profile = RideProfile(
        gaitWalkMaxKmh: Decimal(string: "8"),
        loadWeightTrot: Decimal(string: "3"),
        loadWarnPercent: 25
    )
    let p = RideParameters.resolve(defaults, profile)

    // Pola ustawione w profilu → nadpisane.
    #expect(p.thresholds.walkMaxKmh == Decimal(string: "8"))
    #expect(p.load.weightTrot == Decimal(string: "3"))
    #expect(p.warnPercent == 25)
    #expect(p.ownFields == ["gaitWalkMaxKmh", "loadWeightTrot", "loadWarnPercent"])

    // Pola nieustawione → z defaults.
    #expect(p.thresholds.stopMaxKmh == Decimal(string: "1.5"))
    #expect(p.thresholds.trotMaxKmh == Decimal(string: "15"))
    #expect(p.load.weightWalk == Decimal(string: "1"))
    #expect(p.load.weightCanter == Decimal(string: "3"))
    #expect(p.load.climbPer10m == Decimal(string: "1"))
    #expect(p.heavyRidePoints == 60)
}

@Test func resolveWithFullProfileOverridesAll() {
    let defaults = RideDefaults.builtIn
    let profile = RideProfile(
        gaitStopMaxKmh: Decimal(string: "2"),
        gaitWalkMaxKmh: Decimal(string: "10"),
        gaitTrotMaxKmh: Decimal(string: "20"),
        loadWeightWalk: Decimal(string: "1.5"),
        loadWeightTrot: Decimal(string: "2.5"),
        loadWeightCanter: Decimal(string: "3.5"),
        loadClimbPer10m: Decimal(string: "1.2"),
        loadWarnPercent: 40,
        heavyRidePoints: 80
    )
    let p = RideParameters.resolve(defaults, profile)

    #expect(p.thresholds.stopMaxKmh == Decimal(string: "2"))
    #expect(p.thresholds.walkMaxKmh == Decimal(string: "10"))
    #expect(p.thresholds.trotMaxKmh == Decimal(string: "20"))
    #expect(p.load.weightWalk == Decimal(string: "1.5"))
    #expect(p.load.weightTrot == Decimal(string: "2.5"))
    #expect(p.load.weightCanter == Decimal(string: "3.5"))
    #expect(p.load.climbPer10m == Decimal(string: "1.2"))
    #expect(p.warnPercent == 40)
    #expect(p.heavyRidePoints == 80)
    #expect(p.ownFields.count == 9)
}

// MARK: - RideParameters.validate

@Test func validateDefaultsReturnsNoErrors() {
    let errors = RideParameters.validate(RideDefaults.builtIn)
    #expect(errors.isEmpty)
}

@Test func validateEmptyProfileWithDefaultsReturnsNoErrors() {
    let empty = RideProfile()
    let errors = RideParameters.validate(empty, RideDefaults.builtIn)
    #expect(errors.isEmpty)
}

@Test func validateWalkBelowStopReturnsError() {
    let profile = RideProfile(gaitWalkMaxKmh: Decimal(string: "1.0"))
    let errors = RideParameters.validate(profile, RideDefaults.builtIn)
    #expect(errors.keys.contains("gaitWalkMaxKmh"))
    #expect(errors["gaitWalkMaxKmh"] == "Próg stępa musi być większy niż próg postoju.")
}

@Test func validateTrotBelowWalkReturnsError() {
    let profile = RideProfile(gaitTrotMaxKmh: Decimal(string: "5"))
    let errors = RideParameters.validate(profile, RideDefaults.builtIn)
    #expect(errors.keys.contains("gaitTrotMaxKmh"))
    #expect(errors["gaitTrotMaxKmh"] == "Próg kłusa musi być większy niż próg stępa.")
}

@Test func validateTrotBelowWalkUsesProfileWalkThreshold() {
    // Gdy profil ma ustawiony both walk i trot, używa profile walk, nie defaults.
    let profile = RideProfile(
        gaitWalkMaxKmh: Decimal(string: "10"),
        gaitTrotMaxKmh: Decimal(string: "5")
    )
    let errors = RideParameters.validate(profile, RideDefaults.builtIn)
    #expect(errors.keys.contains("gaitTrotMaxKmh"))
    #expect(errors["gaitTrotMaxKmh"] == "Próg kłusa musi być większy niż próg stępa.")
}

// MARK: - RideParameters.loadPoints

@Test func loadPointsZeroSeconds() {
    let load = LoadParams(
        weightWalk: Decimal(string: "1")!,
        weightTrot: Decimal(string: "2")!,
        weightCanter: Decimal(string: "3")!,
        climbPer10m: Decimal(string: "1")!
    )
    #expect(RideParameters.loadPoints(
        walkSeconds: 0, trotSeconds: 0, canterSeconds: 0,
        elevationGainM: 0, load: load
    ) == Decimal(string: "0"))
}

@Test func loadPointsWithElevation() {
    let load = LoadParams(
        weightWalk: Decimal(string: "1")!,
        weightTrot: Decimal(string: "2")!,
        weightCanter: Decimal(string: "3")!,
        climbPer10m: Decimal(string: "1")!
    )
    // 600s stępa (10 min) + 100m podjazdu (10 * 1 = 10 pkt)
    // = 10 * 1 + 10 = 20 pkt
    let result = RideParameters.loadPoints(
        walkSeconds: 600, trotSeconds: 0, canterSeconds: 0,
        elevationGainM: 100, load: load
    )
    #expect(result == Decimal(string: "20.0"))
}

@Test func loadPointsRoundsHalfUp() {
    let load = LoadParams(
        weightWalk: Decimal(string: "1")!,
        weightTrot: Decimal(string: "2")!,
        weightCanter: Decimal(string: "3")!,
        climbPer10m: Decimal(string: "1")!
    )
    // 180s stępa = 3 min * 1 = 3 pkt
    // 180s kłusa = 3 min * 2 = 6 pkt
    // 0.5 pkt → zaokrąglenie do 1 pkt
    // = 3 + 6 + 0.5 = 9.5 → 10 pkt
    let result = RideParameters.loadPoints(
        walkSeconds: 180, trotSeconds: 180, canterSeconds: 0,
        elevationGainM: 5, load: load
    )
    #expect(result == Decimal(string: "10.0"))
}

// MARK: - RideParameters.exampleText

@Test func exampleTextReturnsFormattedString() {
    let load = LoadParams(
        weightWalk: Decimal(string: "1")!,
        weightTrot: Decimal(string: "2")!,
        weightCanter: Decimal(string: "3")!,
        climbPer10m: Decimal(string: "1")!
    )
    let text = RideParameters.exampleText(load)
    #expect(text.contains("Jazda"))
    #expect(text.contains("min stępa"))
    #expect(text.contains("min kłusa"))
    #expect(text.contains("min galopu"))
    #expect(text.contains("pkt"))
}

@Test func exampleTextContainsCorrectCalculation() {
    let load = LoadParams(
        weightWalk: Decimal(string: "1")!,
        weightTrot: Decimal(string: "2")!,
        weightCanter: Decimal(string: "3")!,
        climbPer10m: Decimal(string: "1")!
    )
    let text = RideParameters.exampleText(load)
    // 40 * 1 = 40, 20 * 2 = 40, 5 * 3 = 15, 50/10 * 1 = 5
    // = 40 + 40 + 15 + 5 = 100
    #expect(text.contains("40 + 40 + 15 + 5 = 100 pkt"))
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
    #expect(Set([s1, s2]).count == 1)
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
