#if DEBUG
import Foundation
import HorselyCore
import HorselyKit

/// Zaślepka programu w procesie aplikacji dla testów UI (`-UITestProgram <scenariusz>`, tylko Debug; T095). Odpowiada jak program
/// 2.0.0 na trasy potrzebne parowaniu, pobraniu i kolejce, bez sieci.
///
/// - `paired`: program działa (wersja 2.0.0, jeden koń „Grom”);
/// - `offline`: komputer nie odpowiada (każde żądanie — błąd połączenia);
/// - `conflict`: jak `paired`, a zmiana notatki kończy się `409` z inną wersją z programu (konflikt);
/// - `photos`: jak `paired`, a koń „Grom” ma zdjęcie z programu (załącznik-obraz; miniatura i plik odpowiadają małym PNG).
struct DemoProgramTransport: ProgramTransport {
    enum Scenario: String {
        case paired, offline, conflict, photos
    }

    let scenario: Scenario

    static let horse = #"{"id":"11111111-1111-1111-1111-111111111111","version":3,"createdAt":"2026-01-01T10:00:00","updatedAt":"2026-01-01T10:00:00","name":"Grom","passportNumber":"PL-1","status":"Active"}"#
    static let photoId = "33333333-3333-3333-3333-333333333333"
    /// Koń „Grom” ze zdjęciem z programu.
    static let horseWithPhoto = String(horse.dropLast()) + #","photoAttachmentId":"\#(photoId)"}"#
    /// Rekord załącznika-obrazu należącego do konia (jak w eksporcie programu).
    static let photoAttachment = #"{"id":"\#(photoId)","version":1,"createdAt":"2026-10-01T10:00:00","updatedAt":"2026-10-01T10:00:00","ownerType":"Horse","ownerId":"11111111-1111-1111-1111-111111111111","horseId":"11111111-1111-1111-1111-111111111111","fileName":"grom.png","contentType":"image/png","sizeBytes":70,"sha256":"\#(String(repeating: "0", count: 64))"}"#
    /// Najmniejszy poprawny PNG (1 × 1 px) — miniatura i „pełne” zdjęcie zaślepki.
    static let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==") ?? Data()
    static let note = #"{"id":"22222222-2222-2222-2222-222222222222","version":4,"createdAt":"2026-10-01T10:00:00","updatedAt":"2026-10-04T10:00:00","horseId":"11111111-1111-1111-1111-111111111111","noteDate":"2026-10-01","title":"Kuleje (z programu)"}"#

    func send(_ request: URLRequest, to address: ServerAddress, bodyFile: URL?, download: Bool, progress: (@Sendable (Int64, Int64?) -> Void)?) async -> TransportOutcome {
        if scenario == .offline { return .failure(sentBody: false, code: .cannotConnectToHost) }
        let path = request.url.map { String($0.path.dropFirst("/api/v1/".count)) } ?? ""
        let method = request.httpMethod ?? "GET"
        func json(_ status: Int, _ text: String) -> TransportOutcome {
            .response(status: status, headers: ["content-type": "application/json"], body: Data(text.utf8), file: nil, remoteIP: "127.0.0.1")
        }
        let horse = scenario == .photos ? Self.horseWithPhoto : Self.horse
        let attachments = scenario == .photos ? "[" + Self.photoAttachment + "]" : "[]"
        switch (method, path) {
        case ("GET", "attachments/\(Self.photoId)/thumbnail") where scenario == .photos:
            return .response(status: 200, headers: ["content-type": "image/png"], body: Self.pixel, file: nil, remoteIP: "127.0.0.1")
        case ("GET", "attachments/\(Self.photoId)/content") where scenario == .photos:
            if download {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString).png")
                try? Self.pixel.write(to: file)
                return .response(status: 200, headers: ["content-type": "image/png"], body: Data(), file: file, remoteIP: "127.0.0.1")
            }
            return .response(status: 200, headers: ["content-type": "image/png"], body: Self.pixel, file: nil, remoteIP: "127.0.0.1")
        case ("GET", "system/info"):
            return json(200, #"{"appVersion":"2.0.0","apiVersion":"v1","schemaVersion":"1.5","serverTime":"2026-10-05T10:00:00Z","capabilities":["dataStamp","idempotencyKey","horseStatusInjured"],"dataStamp":"0123456789abcdef"}"#)
        case ("GET", "dictionaries"):
            return json(200, "{}")
        case ("GET", "horses"):
            return json(200, #"{"page":1,"pageSize":200,"totalCount":1,"items":["# + horse + "]}")
        case ("GET", "export"):
            let notes = scenario == .conflict ? "[" + Self.note + "]" : "[]"
            return json(200, #"{"schemaVersion":"1.5","exportedAt":"2026-10-05T10:00:00Z","appVersion":"2.0.0","scope":{"type":"full","includesAttachmentFiles":false},"data":{"horses":["# + horse + #"],"attachments":"# + attachments + #","notes":"# + notes + "}}")
        case ("GET", "trash"):
            return json(200, "[]")
        case ("PUT", _) where path.hasPrefix("notes/") && scenario == .conflict:
            return json(409, #"{"title":"Rekord zmieniono","reason":"VersionMismatch","current":"# + Self.note + "}")
        default:
            return json(404, #"{"title":"Nie znaleziono"}"#)
        }
    }

    /// Stan „sparowany” dla scenariusza: adres, klucz i — dla konfliktu — notatka z niewysłaną zmianą w kolejce.
    @MainActor
    static func seed(_ scenario: Scenario, environment: AppEnvironment) async {
        let address = ServerAddress(id: "demo", url: "http://192.168.1.20:5080/api/v1", position: 0, trustMode: .plainHttpConfirmed, isRemote: false)
        try? environment.secrets.save("hk_uitest")
        let stamp = LocalDateTime(year: 2026, month: 10, day: 1, hour: 10)!
        let now = Date()
        try? await environment.store.write { access in
            try access.saveAddress(address)
            try access.setMeta(SyncMetaKey.programVersion, "2.0.0")
            try access.setMeta(SyncMetaKey.capabilities, "dataStamp,horseStatusInjured,idempotencyKey")
            guard scenario == .conflict else { return }
            let horse = LocalHorse(id: "11111111-1111-1111-1111-111111111111", createdAt: stamp, updatedAt: stamp, version: 3, name: "Grom", passportNumber: "PL-1")
            let note = LocalNote(
                id: "22222222-2222-2222-2222-222222222222", createdAt: stamp, updatedAt: stamp, version: 3, horseId: horse.id,
                noteDate: LocalDate(year: 2026, month: 10, day: 1)!, title: "Kuleje (moja)"
            )
            try access.upsert([try StoredRecord.of(horse, syncState: .synced), try StoredRecord.of(note, syncState: .pending, baseVersion: 3)])
            try access.enqueue(OutboxOperation(
                id: "demo-op", kind: .updateRecord, localRef: note.id, payload: ApiRecordMapping.input(note), horseRefs: [HorseRef(horse)],
                summary: "Zmiana · notatka · Grom", createdAt: now, updatedAt: now, recordType: .note, recordId: note.id, baseVersion: 3
            ))
        }
    }
}
#endif
