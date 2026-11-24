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
    #expect(p.ownFields == ["gaitWalkMaxKmh", "loadWarnPercent"])
}

@Test func exampleFromPar02Gives100Points() {
    // [PLAN-A] Task 4: 40 min stępa, 20 min kłusa, 5 min galopu, 50 m podjazdu, wagi 1/2/3, climb 1.
    // = 40 + 40 + 15 + 5 = 100 pkt
    let load = LoadParams(
        weightWalk: Decimal(string: "1")!,
        weightTrot: Decimal(string: "2")!,
        weightCanter: Decimal(string: "3")!,
        climbPer10m: Decimal(string: "1")!
    )
    let result = RideParameters.loadPoints(
        walkSeconds: 2400,
        trotSeconds: 1200,
        canterSeconds: 300,
        elevationGainM: 50,
        load: load
    )
    #expect(result == Decimal(string: "100.0"))
}

@Test func walkThresholdNotAboveStopIsRejected() {
    // Próg stępa <= próg postoju → błąd.
    let profile = RideProfile(gaitWalkMaxKmh: Decimal(string: "1.5"))
    let errors = RideParameters.validate(profile, RideDefaults.builtIn)
    #expect(errors.keys.contains("gaitWalkMaxKmh"))
}

@Test func rangesFromPar05() {
    // Zakresy z [K] 6: prędkości 0,5–40, wagi 0,1–10, warn 5–200, heavy 1–10000.
    // Granice przechodzą.
    let boundary = RideProfile(
        gaitStopMaxKmh: Decimal(string: "0.5"),
        gaitWalkMaxKmh: Decimal(string: "40"),
        gaitTrotMaxKmh: Decimal(string: "40"),
        loadWeightWalk: Decimal(string: "0.1"),
        loadWeightTrot: Decimal(string: "10"),
        loadWeightCanter: Decimal(string: "10"),
        loadClimbPer10m: Decimal(string: "10"),
        loadWarnPercent: 5,
        heavyRidePoints: 1
    )
    #expect(RideParameters.validate(boundary, RideDefaults.builtIn).isEmpty)

    let boundary2 = RideProfile(
        gaitStopMaxKmh: Decimal(string: "39.5"),
        gaitWalkMaxKmh: Decimal(string: "40"),
        gaitTrotMaxKmh: Decimal(string: "40"),
        loadWeightWalk: Decimal(string: "10"),
        loadWeightTrot: Decimal(string: "10"),
        loadWeightCanter: Decimal(string: "10"),
        loadClimbPer10m: Decimal(string: "10"),
        loadWarnPercent: 200,
        heavyRidePoints: 10000
    )
    #expect(RideParameters.validate(boundary2, RideDefaults.builtIn).isEmpty)

    // Wartości poza zakresem → błąd.
    let under = RideProfile(gaitStopMaxKmh: Decimal(string: "0.4"))
    var errors = RideParameters.validate(under, RideDefaults.builtIn)
    #expect(errors.keys.contains("gaitStopMaxKmh"))

    let over = RideProfile(gaitStopMaxKmh: Decimal(string: "41"))
    errors = RideParameters.validate(over, RideDefaults.builtIn)
    #expect(errors.keys.contains("gaitStopMaxKmh"))

    let weightUnder = RideProfile(loadWeightWalk: Decimal(string: "0.05"))
    errors = RideParameters.validate(weightUnder, RideDefaults.builtIn)
    #expect(errors.keys.contains("loadWeightWalk"))

    let weightOver = RideProfile(loadWeightWalk: Decimal(string: "11"))
    errors = RideParameters.validate(weightOver, RideDefaults.builtIn)
    #expect(errors.keys.contains("loadWeightWalk"))

    let climbOver = RideProfile(loadClimbPer10m: Decimal(string: "10.1"))
    errors = RideParameters.validate(climbOver, RideDefaults.builtIn)
    #expect(errors.keys.contains("loadClimbPer10m"))

    let warnUnder = RideProfile(loadWarnPercent: 4)
    errors = RideParameters.validate(warnUnder, RideDefaults.builtIn)
    #expect(errors.keys.contains("loadWarnPercent"))

    let warnOver = RideProfile(loadWarnPercent: 201)
    errors = RideParameters.validate(warnOver, RideDefaults.builtIn)
    #expect(errors.keys.contains("loadWarnPercent"))

    let heavyUnder = RideProfile(heavyRidePoints: 0)
    errors = RideParameters.validate(heavyUnder, RideDefaults.builtIn)
    #expect(errors.keys.contains("heavyRidePoints"))

    let heavyOver = RideProfile(heavyRidePoints: 10001)
    errors = RideParameters.validate(heavyOver, RideDefaults.builtIn)
    #expect(errors.keys.contains("heavyRidePoints"))
}

@Test func exportDocumentRecordTypesMapCollections() {
    // `RecordType` ma poprawne `exportCollection` dla nowych typów.
    #expect(RecordType.trainingRecording.exportCollection == "trainingRecordings")
    #expect(RecordType.horseRideProfile.exportCollection == "horseRideProfiles")
    #expect(RecordType.rideDefaults.exportCollection == "rideDefaults")
}
