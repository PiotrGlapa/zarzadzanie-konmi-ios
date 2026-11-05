import Foundation
import HorselyCore
import Testing
@testable import HorselyKit

/// Zgodność zaślepki i klienta push z kopią OpenAPI serwera (spec 003, T019, konstytucja V/VI). Kopia pochodzi z repozytorium UI
/// (`api/openapi.json`, commit dd7f142). Odpowiedzi `200` są tam opisane tylko jako `object` — kształt pól bierzemy z kontraktu
/// serwera (odstępstwo w plan.md „Complexity Tracking”), więc test sprawdza ścieżki, metody i ciało `DeviceRegistration`.
struct PushOpenApiContractTests {
    private func openApi() throws -> JSONValue {
        let base = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        let candidates = [base.appendingPathComponent("Resources/openapi-server-push.json"), base.appendingPathComponent("openapi-server-push.json")]
        let url = try #require(candidates.first { FileManager.default.fileExists(atPath: $0.path) }, "brak kopii OpenAPI w zasobach testów")
        return try JSONValue.parse(Data(contentsOf: url))
    }

    /// Pary metoda + ścieżka, których używa `PushApi` (ścieżki względem `/api/v1/`).
    private let used: [(method: String, path: String)] = [
        ("put", "/api/v1/push/device"), ("get", "/api/v1/push/device"), ("delete", "/api/v1/push/device"), ("get", "/api/v1/push/rules"),
    ]

    @Test func everyCallOfPushApiExistsInTheServerOpenApi() throws {
        let paths = try #require(openApi()["paths"]?.objectValue)
        for (method, path) in used {
            #expect(paths[path]?[method] != nil, "w OpenAPI serwera brak \(method.uppercased()) \(path)")
        }
    }

    @Test func theStubServesExactlyTheCallsPushApiMakes() async throws {
        let program = FakeProgram()
        program.pushCapability = true
        let (client, _) = program.client()
        let api = PushApi(client: client)
        _ = await api.registerDevice(token: try #require(DeviceRegistration(token: "abcdefghijkl")))
        _ = await api.device()
        _ = await api.unregisterDevice()
        _ = await api.rules()
        let seen = program.requests.map { "\($0.method.lowercased()) /api/v1/\($0.path)" }
        #expect(seen == used.map { "\($0.method) \($0.path)" })
        // Każde wywołanie obsłużyła zaślepka (a nie domyślne 404).
        #expect(program.registeredPushToken == nil, "po DELETE zaślepka nie trzyma tokenu")
    }

    @Test func theRegistrationBodyHasOnlyTheFieldsOfTheOpenApiSchema() async throws {
        let schema = try #require(openApi()["components"]?["schemas"]?["DeviceRegistration"]?["properties"]?.objectValue)
        let program = FakeProgram()
        program.pushCapability = true
        let (client, _) = program.client()
        _ = await PushApi(client: client).registerDevice(token: try #require(DeviceRegistration(token: "abcdefghijkl")))
        let body = try #require(program.requests("PUT", "push/device").first?.json?.objectValue)
        #expect(Set(body.keys) == Set(schema.keys), "ciało PUT ma pola inne niż schemat DeviceRegistration")
    }
}
