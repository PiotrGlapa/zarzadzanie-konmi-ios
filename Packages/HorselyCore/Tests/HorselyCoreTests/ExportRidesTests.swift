import Foundation
import Testing
@testable import HorselyCore

/// Jazdy w pliku eksportu 1.6 (`ExportDocumentTest.kt` Androida 3.0.2, część „schemat 1.6”): nagranie bierze konia i datę z treningu,
/// profil — wersję konia, `rideDefaults` to obiekt albo `null`, trasa jedzie obok rekordu jako bajty z base64.
struct ExportRidesTests {
    private let horse = #"{"id":"h1","createdAt":"2026-01-01T10:00:00","updatedAt":"2026-08-01T10:00:00","version":7,"name":"Grom","status":"Active","farrierIntervalWeeks":6,"birthYearOnly":false}"#
    private let training = #"{"id":"7b2f3a1c-5d0e-4c8a-9f21-0a6e8d4b1c33","createdAt":"2026-09-01T10:00:00","updatedAt":"2026-09-01T10:00:00","version":1,"horseId":"h1","trainingDate":"2026-09-01","trainingTypeId":"tt"}"#
    private let defaults = #"{"gaitStopMaxKmh":1.5,"gaitWalkMaxKmh":7,"gaitTrotMaxKmh":15,"loadWeightWalk":1,"loadWeightTrot":2,"loadWeightCanter":3,"loadClimbPer10m":1,"loadWarnPercent":25,"heavyRidePoints":60,"version":2}"#
    private let trackBase64 = "H4sIAAAAAAAAA6tWKkktLlGyUlAqS8wpTVWqBQBIvF1MFgAAAA=="

    private func recording() throws -> String {
        String(decoding: try Fixtures.data("v3/recording.json"), as: UTF8.self)
    }

    private func v16(_ data: String) -> String {
        #"{"schemaVersion":"1.6","exportedAt":"2026-11-14T10:30:00Z","appVersion":"3.0.0","scope":{"type":"full"},"data":{"# + data + "}}"
    }

    @Test func aRecordingAndAProfileAreResolvedFromTheirTrainingAndHorseAndOrphansAreDropped() throws {
        let original = try recording()
        let orphan = original
            .replacingOccurrences(of: "7b2f3a1c-5d0e-4c8a-9f21-0a6e8d4b1c33", with: "aaaaaaaa-0000-4000-8000-000000000000")
            .replacingOccurrences(of: "a3d51c8e-0b94-4e7a-9f62-1c7e4b0d8a39", with: "orphan-recording")
        let text = v16(
            #""trainingRecordings":["# + original + "," + orphan + #"],"horseRideProfiles":[{"horseId":"h1","loadWarnPercent":20},{"horseId":"duch","loadWarnPercent":20}],"horses":["#
                + horse + #"],"trainings":["# + training + "]"
        )

        let document = try ExportDocument.parse(text)

        let recordings = document.records(of: .trainingRecording).compactMap { $0 as? LocalTrainingRecording }
        #expect(recordings.count == 1)
        let read = try #require(recordings.first)
        #expect(read.horseId == "h1")
        #expect(read.trainingDate == LocalDate(year: 2026, month: 9, day: 1))
        #expect(document.records.first { $0.record is LocalTrainingRecording }?.dateKey == read.trainingDate)
        let profiles = document.records(of: .horseRideProfile).compactMap { $0 as? LocalHorseRideProfile }
        #expect(profiles.count == 1)
        let profile = try #require(profiles.first)
        #expect(profile.id == "h1")
        #expect(profile.version == 7, "profil niesie wersję konia")
        #expect(profile.updatedAt == LocalDateTime(year: 2026, month: 8, day: 1, hour: 10))
        #expect(profile.profile.loadWarnPercent == 20)
    }

    @Test func rideDefaultsAreReadAsAnObjectAndNullMeansNone() throws {
        let some = try ExportDocument.parse(v16(#""rideDefaults":"# + defaults)).records(of: .rideDefaults)
        let none = try ExportDocument.parse(v16(#""rideDefaults":null"#)).records(of: .rideDefaults)

        let read = try #require(some.first as? LocalRideDefaults)
        #expect(some.count == 1)
        #expect(read.defaults.loadWarnPercent == 25)
        #expect(read.version == 2)
        #expect(read.id == LocalRideDefaults.ID)
        #expect(none.isEmpty)
    }

    @Test func theTrackOfARecordingTravelsAsBase64BytesNextToTheRecord() throws {
        let original = try recording()
        let document = try ExportDocument.parse(v16(#""horses":["# + horse + #"],"trainings":["# + training + #"],"trainingRecordings":["# + original + "]"))

        let exported = try #require(document.records.first { $0.record is LocalTrainingRecording })
        let track = try #require(exported.track)
        #expect(track.recordingId == "a3d51c8e-0b94-4e7a-9f62-1c7e4b0d8a39")
        #expect(track.version == 1)
        #expect(track.format == "zk-track/1")
        #expect(track.data == Data(base64Encoded: trackBase64))
        #expect((exported.record as? LocalTrainingRecording)?.recording.trackData == nil)
    }

    @Test func anEmptyTrackDataMeansNoTrackAndABrokenOneFailsOnlyWhenNotLenient() throws {
        let empty = try recording().replacingOccurrences(of: trackBase64, with: "")
        let broken = try recording().replacingOccurrences(of: trackBase64, with: "%%%nie-base64%%%")
        let withEmpty = v16(#""horses":["# + horse + #"],"trainings":["# + training + #"],"trainingRecordings":["# + empty + "]")
        let withBroken = v16(#""horses":["# + horse + #"],"trainings":["# + training + #"],"trainingRecordings":["# + broken + "]")

        #expect(try ExportDocument.parse(withEmpty).records.first { $0.record is LocalTrainingRecording }?.track == nil)
        #expect(throws: DecodingError.self) { _ = try ExportDocument.parse(withBroken) }
        let lenient = try ExportDocument.parse(withBroken, lenientTracks: true)
        let exported = try #require(lenient.records.first { $0.record is LocalTrainingRecording })
        #expect(exported.track == nil, "pobieranie z programu: nagranie wchodzi bez trasy")
    }

    @Test func a16DocumentWrittenAgainKeepsRidesAndTracks() throws {
        let original = try recording()
        let text = v16(
            #""horses":["# + horse + #"],"trainings":["# + training + #"],"trainingRecordings":["# + original
                + #"],"horseRideProfiles":[{"horseId":"h1","loadWarnPercent":20}],"rideDefaults":"# + defaults
        )
        let document = try ExportDocument.parse(text)

        let written = try document.toJSON()
        let again = try ExportDocument.parse(written)

        #expect(document.records.map { AnyHashable($0.record) } == again.records.map { AnyHashable($0.record) })
        #expect(document.records.compactMap(\.track) == again.records.compactMap(\.track))
        let data = try #require(try JSONValue.parseKeepingScale(written)["data"])
        let profiles = try #require(data["horseRideProfiles"]?.arrayValue)
        #expect(profiles.count == 1)
        #expect(profiles.first?["gaitStopMaxKmh"] == .null, "profil niesie wszystkie 9 pól, brak = null")
        #expect(data["trainingRecordings"]?.arrayValue?.first?["trackData"] == .string(trackBase64))
    }

    @Test func a16DocumentWithoutRidesWritesEmptyRideCollectionsAndA15DocumentNone() throws {
        let written = try ExportDocument.parse(v16(#""notes":[]"#)).toJSON()
        let data = try #require(try JSONValue.parseKeepingScale(written)["data"])
        #expect(data["trainingRecordings"] == .array([]))
        #expect(data["horseRideProfiles"] == .array([]))
        #expect(data["rideDefaults"] == .null)

        let old = try ExportDocument.parse(v16(#""notes":[]"#).replacingOccurrences(of: #""schemaVersion":"1.6""#, with: #""schemaVersion":"1.5""#)).toJSON()
        let oldData = try #require(try JSONValue.parseKeepingScale(old)["data"])
        #expect(oldData["trainingRecordings"] == nil && oldData["horseRideProfiles"] == nil && oldData["rideDefaults"] == nil, "schemat 1.5 nie zna jazd")
    }
}
