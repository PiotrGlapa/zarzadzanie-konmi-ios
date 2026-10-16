import Foundation

/// Możliwości programu 2.0.0 ogłaszane w `GET /system/info` (`capabilities`); nazwy są umową z programem
/// (contracts/android/program-2.0-integration.md §1). Program 1.5.0–1.6.x i tryb samodzielny nie mają żadnej — `none`.
/// Nieznane nazwy są pomijane.
public struct ProgramCapabilities: Hashable, Sendable, CustomStringConvertible {
    public static let updatedSinceName = "updatedSince"
    public static let dataStampName = "dataStamp"
    public static let ifMatchDeleteName = "ifMatchDelete"
    public static let idempotencyKeyName = "idempotencyKey"
    public static let horsePhotoFieldName = "horsePhotoField"
    public static let horseStatusInjuredName = "horseStatusInjured"

    private static let known: Set<String> = [
        updatedSinceName, dataStampName, ifMatchDeleteName, idempotencyKeyName, horsePhotoFieldName, horseStatusInjuredName,
    ]

    /// Program bez listy możliwości (1.5.0–1.6.x) i tryb samodzielny.
    public static let none = ProgramCapabilities(names: [])

    public let names: Set<String>

    /// Z listy z `system/info`; nieznane nazwy są pomijane.
    public init(names: some Sequence<String>) {
        self.names = Set(names).intersection(Self.known)
    }

    /// Odczyt zapisu z `local_meta` (`serialized`); brak albo pusty napis → `none`.
    public init(serialized text: String?) {
        let items = (text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        self.init(names: items)
    }

    /// Pobieranie zmian: `GET /export?scope=full&updatedSince=…`.
    public var updatedSince: Bool { names.contains(Self.updatedSinceName) }
    /// Stempel danych w `system/info` — odświeżenie bez zmian kończy się bez `/export`.
    public var dataStamp: Bool { names.contains(Self.dataStampName) }
    /// `If-Match` przy `DELETE` i przywracaniu z kosza.
    public var ifMatchDelete: Bool { names.contains(Self.ifMatchDeleteName) }
    /// `Idempotency-Key` przy `POST` tworzących.
    public var idempotencyKey: Bool { names.contains(Self.idempotencyKeyName) }
    /// `photoAttachmentId` w `PUT /horses/{id}`.
    public var horsePhotoField: Bool { names.contains(Self.horsePhotoFieldName) }
    /// Status konia „Kontuzjowany” (klient deklaruje cechę nagłówkiem `X-Client-Features`).
    public var horseStatusInjured: Bool { names.contains(Self.horseStatusInjuredName) }

    /// Zapis do `local_meta`: nazwy rozdzielone przecinkami, w stałej kolejności.
    public var serialized: String { names.sorted().joined(separator: ",") }

    public var description: String { "ProgramCapabilities(\(serialized))" }
}

/// Zmiana możliwości wykryta przy odczycie `system/info`.
public struct CapabilitiesChange: Equatable, Sendable {
    public let before: ProgramCapabilities
    public let after: ProgramCapabilities

    public init(before: ProgramCapabilities, after: ProgramCapabilities) {
        self.before = before
        self.after = after
    }

    public var changed: Bool { before != after }

    /// Następne pobranie musi być pełne: inna treść pobrania (`updatedSince`) albo inny status koni.
    public var forcesFullSync: Bool {
        before.updatedSince != after.updatedSince || before.horseStatusInjured != after.horseStatusInjured
    }

    /// Zmienił się odstęp pracy w tle (15 min ze stemplem danych, inaczej 60 min).
    public var refreshIntervalChanged: Bool { before.dataStamp != after.dataStamp }
}

/// Cechy klienta w nagłówku `X-Client-Features` (contracts/android/program-2.0-integration.md §2): `horse-status-injured`
/// w każdym żądaniu, gdy program ogłosił `horseStatusInjured`. Program 1.6.1 nie dostaje żadnego nowego nagłówka.
public enum ClientFeatures {
    public static let header = "X-Client-Features"
    public static let horseStatusInjured = "horse-status-injured"

    public static func value(for capabilities: ProgramCapabilities) -> String? {
        capabilities.horseStatusInjured ? horseStatusInjured : nil
    }
}

/// Informacje o programie z `GET /system/info`.
public struct ProgramInfo: Decodable, Equatable, Sendable {
    public let appVersion: String
    public let apiVersion: String?
    public let schemaVersion: String?
    public let serverTime: String?
    /// Od 2.0; brak u programu 1.5.0–1.6.x.
    public let capabilities: [String]
    public let dataStamp: String?

    public init(appVersion: String, apiVersion: String? = "v1", schemaVersion: String? = nil, serverTime: String? = nil, capabilities: [String] = [], dataStamp: String? = nil) {
        self.appVersion = appVersion
        self.apiVersion = apiVersion
        self.schemaVersion = schemaVersion
        self.serverTime = serverTime
        self.capabilities = capabilities
        self.dataStamp = dataStamp
    }

    private enum CodingKeys: String, CodingKey { case appVersion, apiVersion, schemaVersion, serverTime, capabilities, dataStamp }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        apiVersion = try c.decodeIfPresent(String.self, forKey: .apiVersion)
        schemaVersion = try c.decodeIfPresent(String.self, forKey: .schemaVersion)
        serverTime = try c.decodeIfPresent(String.self, forKey: .serverTime)
        capabilities = (try? c.decodeIfPresent([String].self, forKey: .capabilities)) ?? []
        dataStamp = try c.decodeIfPresent(String.self, forKey: .dataStamp)
    }

    public var programCapabilities: ProgramCapabilities { ProgramCapabilities(names: capabilities) }
}
