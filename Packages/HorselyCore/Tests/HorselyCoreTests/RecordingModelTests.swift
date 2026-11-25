// Testy modeli nagrań jazdy — Task 5, krok 1.
// Oparte na [PLAN-A] Task 4 Step 1 i kontrakcie [K].

import Testing
import Foundation
@testable import HorselyCore

@Test func recordingDtoFromContractParsesAndRoundTrips() throws {
    // Wczytuję przykład z kontraktu [K] 4.2.
    let url = Bundle.module.url(forResource: "v3/recording", withExtension: "json")!
    let data = try Data(contentsOf: url)
    let dto = try JSONDecoder().decode(RecordingDto.self, from: data)

    // Sprawdzam kluczowe pola z przykładu [K].
    #expect(dto.id == "a3d51c8e-0b94-4e7a-9f62-1c7e4b0d8a39")
    #expect(dto.trainingId == "7b2f3a1c-5d0e-4c8a-9f21-0a6e8d4b1c33")
    #expect(dto.version == 1)
    #expect(dto.startedAt == "2026-09-01T07:02:11Z")
    #expect(dto.endedAt == "2026-09-01T08:09:11Z")
    #expect(dto.timeZone == "Europe/Warsaw")
    #expect(dto.totalSeconds == 3900)
    #expect(dto.movingSeconds == 3900)
    #expect(dto.stoppedSeconds == 0)
    #expect(dto.pausedSeconds == 120)
    #expect(dto.distanceMeters == 8500)
    #expect(dto.avgMovingSpeedKmh == Decimal(string: "7.85"))
    #expect(dto.maxSpeedKmh == Decimal(string: "24.60"))
    #expect(dto.elevationGainM == 50)
    #expect(dto.elevationLossM == 48)
    #expect(dto.minAltitudeM == 102)
    #expect(dto.maxAltitudeM == 131)
    #expect(dto.walkSeconds == 2400)
    #expect(dto.walkMeters == 3000)
    #expect(dto.trotSeconds == 1200)
    #expect(dto.trotMeters == 4000)
    #expect(dto.canterSeconds == 300)
    #expect(dto.canterMeters == 1500)
    #expect(dto.walkAvgSpeedKmh == Decimal(string: "4.50"))
    #expect(dto.trotAvgSpeedKmh == Decimal(string: "12.00"))
    #expect(dto.canterAvgSpeedKmh == Decimal(string: "18.00"))
    #expect(dto.walkAvgCadence == Decimal(string: "98.0"))
    #expect(dto.trotAvgCadence == Decimal(string: "142.0"))
    #expect(dto.canterAvgCadence == Decimal(string: "168.0"))
    #expect(dto.canterCount == 1)
    #expect(dto.longestCanterSeconds == 300)
    #expect(dto.longestCanterMeters == 1500)
    #expect(dto.loadPoints == Decimal(string: "100.0"))
    #expect(dto.weatherStatus == .fetched)
    #expect(dto.weatherTempC == Decimal(string: "17.4"))
    #expect(dto.weatherHumidityPct == 63)
    #expect(dto.weatherCode == 3)
    #expect(dto.algorithmVersion == 1)
    #expect(dto.trackFormat == "zk-track/1")
    #expect(dto.pointCount == 3900)
    #expect(dto.segments.count == 3)

    // Sprawdzam segmenty.
    #expect(dto.segments[0].seq == 1)
    #expect(dto.segments[0].gait == .walk)
    #expect(dto.segments[0].startOffsetSeconds == 0)
    #expect(dto.segments[0].endOffsetSeconds == 2400)
    #expect(dto.segments[0].distanceMeters == 3000)
    #expect(dto.segments[1].gait == .trot)
    #expect(dto.segments[1].startOffsetSeconds == 2400)
    #expect(dto.segments[1].endOffsetSeconds == 3600)
    #expect(dto.segments[2].gait == .canter)
    #expect(dto.segments[2].startOffsetSeconds == 3600)
    #expect(dto.segments[2].endOffsetSeconds == 3900)

    // Round-trip: serializacja → deserializacja.
    let encoded = try JSONEncoder().encode(dto)
    let dto2 = try JSONDecoder().decode(RecordingDto.self, from: encoded)
    #expect(dto2.id == dto.id)
    #expect(dto2.totalSeconds == dto.totalSeconds)
    #expect(dto2.segments.count == dto.segments.count)
}

@Test func inputHasNoResponseOnlyFieldsAndKeepsTrackData() {
    let dto = RecordingDto(
        id: "abc", trainingId: "def", version: 1,
        createdAt: "2026-09-01T08:00:00Z", updatedAt: "2026-09-01T08:00:00Z",
        startedAt: "2026-09-01T07:00:00Z", endedAt: "2026-09-01T08:00:00Z",
        timeZone: "Europe/Warsaw", totalSeconds: 3600, movingSeconds: 3600,
        stoppedSeconds: 0, pausedSeconds: 0, distanceMeters: 5000,
        walkSeconds: 1800, walkMeters: 2000, trotSeconds: 1200, trotMeters: 3000,
        canterSeconds: 600, canterMeters: 2000,
        loadPoints: Decimal(string: "50")!,
        gaitThresholdsUsed: ["stopMaxKmh": Decimal(string: "1.5")!],
        loadParamsUsed: ["weightWalk": Decimal(string: "1")!],
        accelerometerUsed: true, weatherStatus: .none,
        trimmedStartSeconds: 0, trimmedEndSeconds: 0, algorithmVersion: 1,
        source: ["platform": "ios"], trackFormat: "zk-track/1", pointCount: 3600,
        segments: [], trackData: "data123"
    )

    let input = dto.toInput(trackData: "newTrackData")

    // Sprawdzam, że `toInput` zwraca poprawny `RecordingInput` z podanym `trackData`.
    #expect(input.trackData == "newTrackData")
    #expect(input.startedAt == dto.startedAt)
    #expect(input.endedAt == dto.endedAt)
    #expect(input.totalSeconds == dto.totalSeconds)
}

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

@Test func exportDocumentRecordTypesMapCollections() {
    // `RecordType` ma poprawne `exportCollection` dla nowych typów.
    #expect(RecordType.trainingRecording.exportCollection == "trainingRecordings")
    #expect(RecordType.horseRideProfile.exportCollection == "horseRideProfiles")
    #expect(RecordType.rideDefaults.exportCollection == "rideDefaults")
}
