import Testing
@testable import HorselyCore

/// Decyzja A10 (`VideoPolicyTest.kt` Androida 3.0.2): film do 720p (krótszy bok), gdy większy albo cięższy niż 100 MB; mniejszy idzie bez zmian.
struct VideoPolicyTests {
    private let mb: Int64 = 1024 * 1024

    @Test func video4KIsTranscoded() {
        // 3840×2160: krótszy bok 2160 > 720, rozmiar niewielki.
        #expect(VideoPolicy.decide(shortSidePx: 2160, sizeBytes: 40 * mb, sendOriginal: false) == .transcode)
        // Pionowe 4K ma krótszy bok 2160 tak samo — liczy się krótszy, nie szerokość.
        #expect(VideoPolicy.decide(shortSidePx: 2160, sizeBytes: 5 * mb, sendOriginal: false) == .transcode)
        // 1080p także jest większe niż 720p.
        #expect(VideoPolicy.decide(shortSidePx: 1080, sizeBytes: 5 * mb, sendOriginal: false) == .transcode)
    }

    @Test func video720UnderLimitIsKept() {
        #expect(VideoPolicy.decide(shortSidePx: 720, sizeBytes: 30 * mb, sendOriginal: false) == .keepOriginal)
        #expect(VideoPolicy.decide(shortSidePx: 480, sizeBytes: 1, sendOriginal: false) == .keepOriginal)
        #expect(VideoPolicy.decide(shortSidePx: 720, sizeBytes: 100 * mb - 1, sendOriginal: false) == .keepOriginal)
    }

    @Test func a720pVideoOf100MBOrMoreIsStillTranscoded() {
        #expect(VideoPolicy.decide(shortSidePx: 720, sizeBytes: 100 * mb, sendOriginal: false) == .transcode)
        #expect(VideoPolicy.decide(shortSidePx: 480, sizeBytes: 250 * mb, sendOriginal: false) == .transcode)
    }

    @Test func originalToggleOnlyBelow100MB() {
        #expect(VideoPolicy.canSendOriginal(sizeBytes: 99 * mb))
        #expect(VideoPolicy.canSendOriginal(sizeBytes: 100 * mb - 1))
        #expect(!VideoPolicy.canSendOriginal(sizeBytes: 100 * mb))
        #expect(!VideoPolicy.canSendOriginal(sizeBytes: 300 * mb))

        // Poniżej 100 MB „Wyślij oryginał” zostawia 4K bez zmian…
        #expect(VideoPolicy.decide(shortSidePx: 2160, sizeBytes: 60 * mb, sendOriginal: true) == .keepOriginal)
        // …a od 100 MB przełącznik nie działa — plik i tak trzeba zmniejszyć.
        #expect(VideoPolicy.decide(shortSidePx: 2160, sizeBytes: 100 * mb, sendOriginal: true) == .transcode)
        #expect(VideoPolicy.decide(shortSidePx: 2160, sizeBytes: 400 * mb, sendOriginal: true) == .transcode)
    }

    @Test func transcodedUnderLimitIsAccepted() {
        #expect(VideoPolicy.afterTranscode(sizeBytes: 80 * mb, durationSeconds: 240) == .keepOriginal)
        #expect(VideoPolicy.afterTranscode(sizeBytes: 100 * mb - 1, durationSeconds: 300) == .keepOriginal)
    }

    @Test func transcodedOverLimitIsRejectedWithMaxLength() {
        // Komunikat jest literalny — niezależny od czasu filmu.
        #expect(
            VideoPolicy.afterTranscode(sizeBytes: 130 * mb, durationSeconds: 480)
                == .reject("Film jest za długi — nawet po zmniejszeniu do 720p ma 130 MB (najwięcej 100 MB). Najdłuższy film to ok. 5 min.")
        )
    }

    @Test func rejectionMessageRoundsTheSizeUpAndAlwaysSaysFiveMinutes() {
        #expect(
            VideoPolicy.afterTranscode(sizeBytes: 100 * mb + 1, durationSeconds: 0)
                == .reject("Film jest za długi — nawet po zmniejszeniu do 720p ma 101 MB (najwięcej 100 MB). Najdłuższy film to ok. 5 min.")
        )
        guard case let .reject(message) = VideoPolicy.afterTranscode(sizeBytes: 5000 * mb, durationSeconds: 600) else {
            Issue.record("film 5000 MB po przekodowaniu musi być odrzucony")
            return
        }
        #expect(message.hasSuffix("ma 5000 MB (najwięcej 100 MB). Najdłuższy film to ok. 5 min."))
    }

    @Test func largeVideoPassesTheFileCheckOnlyWhenAllowed() {
        // Film > 100 MB zostanie zmniejszony przed wysłaniem (A10), więc przy dodawaniu nie jest odrzucany; inne pliki — tak.
        #expect(FilePolicy.check(fileName: "jazda.mov", mimeType: "video/quicktime", sizeBytes: 300 * mb, allowLargeVideo: true) == .allowed(fileName: "jazda.mov", contentType: "video/quicktime"))
        #expect(!FilePolicy.check(fileName: "jazda.mov", mimeType: "video/quicktime", sizeBytes: 300 * mb).isAllowed)
        #expect(!FilePolicy.check(fileName: "skan.pdf", mimeType: "application/pdf", sizeBytes: 300 * mb, allowLargeVideo: true).isAllowed)
        // Import (aplikacja i rozszerzenie udostępniania) używa tej samej decyzji.
        #expect(FilePolicy.checkImport(fileName: "jazda.mp4", mimeType: "video/mp4", sizeBytes: 300 * mb) == .allowed(fileName: "jazda.mp4", contentType: "video/mp4"))
        #expect(!FilePolicy.checkImport(fileName: "skan.pdf", mimeType: "application/pdf", sizeBytes: 300 * mb).isAllowed)
        #expect(FilePolicy.isVideo("video/mp4"))
        #expect(!FilePolicy.isVideo("image/jpeg"))
    }
}
