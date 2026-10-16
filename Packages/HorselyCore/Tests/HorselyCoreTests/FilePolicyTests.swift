import Testing
@testable import HorselyCore

/// Typy i rozmiar plików przed dodaniem do kolejki (T112, FR-M-ZAL-02; `FilePolicyTest.kt`).
struct FilePolicyTests {
    private let mb: Int64 = 1024 * 1024

    private func allowed(_ name: String, _ mime: String?, _ size: Int64 = 1024) -> (fileName: String, contentType: String)? {
        if case let .allowed(fileName, contentType) = FilePolicy.check(fileName: name, mimeType: mime, sizeBytes: size) { return (fileName, contentType) }
        return nil
    }

    private func rejected(_ name: String, _ mime: String?, _ size: Int64 = 1024) -> String? {
        if case let .rejected(reason) = FilePolicy.check(fileName: name, mimeType: mime, sizeBytes: size) { return reason }
        return nil
    }

    @Test func allAllowedTypesPassWithTheirCanonicalContentType() {
        #expect(allowed("foto.jpg", "image/jpeg")?.contentType == "image/jpeg")
        #expect(allowed("foto.jpeg", "image/jpeg")?.contentType == "image/jpeg")
        #expect(allowed("a.png", "image/png")?.contentType == "image/png")
        #expect(allowed("a.heic", "image/heic")?.contentType == "image/heic")
        #expect(allowed("a.webp", "image/webp")?.contentType == "image/webp")
        #expect(allowed("a.pdf", "application/pdf")?.contentType == "application/pdf")
        #expect(allowed("a.docx", nil)?.contentType == "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
        #expect(allowed("a.xlsx", nil)?.contentType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        #expect(allowed("a.txt", "text/plain")?.contentType == "text/plain")
        #expect(allowed("a.mp4", "video/mp4")?.contentType == "video/mp4")
        #expect(allowed("a.mov", "video/quicktime")?.contentType == "video/quicktime")
    }

    @Test func theExtensionIsComparedWithoutRegardToCase() {
        #expect(allowed("FOTO.JPG", "image/jpeg") != nil)
        #expect(allowed("Raport.PdF", "application/pdf") != nil)
    }

    @Test func exactlyOneHundredMegabytesIsAllowedAndOneByteMoreIsNot() {
        #expect(allowed("film.mp4", "video/mp4", 100 * mb) != nil)
        #expect(rejected("film.mp4", "video/mp4", 100 * mb + 1)?.contains("100 MB") == true)
    }

    @Test func otherTypesAreRejectedWithAMessageListingTheAllowedOnes() {
        let reason = rejected("program.exe", "application/x-msdownload") ?? ""
        #expect(reason.contains("JPG") && reason.contains("PDF") && reason.contains("MOV"))
        #expect(rejected("archiwum.zip", "application/zip") != nil)
        #expect(rejected("skrypt.js", "text/javascript") != nil)
        #expect(rejected("bez-rozszerzenia", "application/octet-stream") != nil)
    }

    @Test func aGenericOrMissingMimeTypeDoesNotRejectAnAllowedExtension() {
        #expect(allowed("a.jpg", nil) != nil)
        #expect(allowed("a.pdf", "application/octet-stream") != nil)
        #expect(allowed("a.png", "") != nil)
        #expect(allowed("a.jpg", "image/jpeg; charset=binary") != nil)
    }

    @Test func aMimeTypeOfAnotherKindThanTheExtensionIsRejected() {
        #expect(rejected("a.jpg", "application/x-msdownload") != nil)
        #expect(rejected("a.pdf", "application/zip") != nil)
    }

    @Test func heifAndOtherAliasesAreAccepted() {
        #expect(allowed("a.heic", "image/heif") != nil)
        #expect(allowed("a.mov", "video/x-quicktime") != nil)
    }

    @Test func aFileWithoutExtensionIsAcceptedWhenTheMimeTypeIsAllowedAndGetsTheExtension() {
        #expect(allowed("IMG_1234", "image/jpeg")?.fileName == "IMG_1234.jpg")
        #expect(allowed("a.pdf", "application/pdf")?.fileName == "a.pdf")
    }

    @Test func anEmptyFileIsRejected() {
        #expect(rejected("a.jpg", "image/jpeg", 0)?.contains("pusty") == true)
    }

    @Test func pathSegmentsAndOddCharactersNeverReachTheFileName() {
        #expect(allowed("../../etc/zdjecie.jpg", "image/jpeg")?.fileName == "zdjecie.jpg")
        #expect(allowed("C:\\Users\\x\\zdjecie.jpg", "image/jpeg")?.fileName == "zdjecie.jpg")
        #expect(allowed("zdj\u{0007}ecie.jpg", "image/jpeg")?.fileName == "zdjecie.jpg")
    }

    @Test func imagesAreRecognisedForThePreparationStep() {
        #expect(FilePolicy.isImage("image/jpeg"))
        #expect(FilePolicy.isImage("image/heic"))
        #expect(!FilePolicy.isImage("application/pdf"))
        #expect(!FilePolicy.isImage("video/mp4"))
    }
}
