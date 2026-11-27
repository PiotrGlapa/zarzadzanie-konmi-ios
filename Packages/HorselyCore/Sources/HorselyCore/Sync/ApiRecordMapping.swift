import Foundation

/// Rekordy magazynu (kształt eksportu) ↔ treści API programu (`ApiMapping.kt`, `ApiRecords.kt`). Różnice kształtu:
/// koń — kwoty w obiekcie `finance`; trening — trener i koszt w obiekcie `coaching`; leki wizyty bez pól audytu; start — zawody
/// w adresie, nie w treści. Pola tylko do odczytu (nazwy, liczniki, `isOverdue`) są pomijane przy odczycie.
public enum ApiRecordMapping {
    static let audit: Set<String> = ["id", "createdAt", "updatedAt", "version"]
    static let financeKeys = ["purchasePrice", "purchaseDate", "salePrice", "saleDate", "estimatedValue"]
    static let coachingKeys = ["trainerContactId", "cost", "originalAmount", "originalCurrency"]
    static let medicationKeys: Set<String> = ["name", "dosage", "startDate", "endDate", "administration", "notes"]
    /// Pola rekordów, które program ustala sam (terminy: stan i źródło; nie wysyłamy ich w treści żądania).
    static let readOnly: [RecordType: Set<String>] = [
        .reminder: ["status", "sourceType", "sourceId", "completedByType", "completedById", "completedAt"],
        .dictionary: ["isSystem", "systemKey"],
    ]

    // MARK: API → rekord

    /// Odpowiedź API (`GET`, `PUT`, `POST`, `current` z `409`) jako rekord magazynu; `nil`, gdy treść nie jest rekordem tego rodzaju.
    /// Profil jazd konia czyta się z odpowiedzi konia (`rideProfile`), nagranie — tylko gdy wołający dopisał `horseId` i `trainingDate`.
    /// - Parameter parentId: zawody startu, gdy odpowiedź ich nie niesie.
    public static func record(_ type: RecordType, from json: JSONValue, parentId: String? = nil) -> (any LocalRecord)? {
        guard case var .object(fields) = json else { return nil }
        switch type {
        case .trainingRecording:
            guard let horseId = fields["horseId"]?.stringValue, let date = fields["trainingDate"]?.stringValue, let trainingDate = LocalDate(date) else {
                return nil
            }
            return decodeRecording(json, horseId: horseId, trainingDate: trainingDate)
        case .horseRideProfile:
            return rideProfileRecord(fromHorse: json)
        case .rideDefaults:
            guard let data = try? json.data(), let defaults = try? JSONDecoder().decode(RideDefaults.self, from: data) else { return nil }
            return defaults.toRecord()
        case .horse:
            if case let .object(finance)? = fields.removeValue(forKey: "finance") {
                for key in financeKeys where fields[key] == nil { fields[key] = finance[key] ?? .null }
            }
        case .training:
            if case let .object(coaching)? = fields.removeValue(forKey: "coaching") {
                for key in coachingKeys where fields[key] == nil { fields[key] = coaching[key] ?? .null }
            }
        case .vetVisit:
            if case let .array(items)? = fields["medications"] {
                let created = fields["createdAt"] ?? .null
                let updated = fields["updatedAt"] ?? .null
                fields["medications"] = .array(items.enumerated().map { index, item in
                    guard case var .object(medication) = item else { return item }
                    if medication["id"] == nil || medication["id"] == .null { medication["id"] = .string(UUID().uuidString.lowercased()) }
                    if medication["createdAt"] == nil { medication["createdAt"] = created }
                    if medication["updatedAt"] == nil { medication["updatedAt"] = updated }
                    if medication["sortOrder"] == nil { medication["sortOrder"] = .number(Decimal(index)) }
                    return .object(medication)
                })
            }
        case .attachment:
            // Załącznik z programu może nie mieć `updatedAt` ani `version` (DTO ma tylko `createdAt`) — jak `Attachment.toRecord(version = 1,
            // updatedAt = createdAt)` Androida; wersja 0 psułaby eksport (schemat 1.6 wymaga `version >= 1`).
            if fields["updatedAt"] == nil || fields["updatedAt"] == .null { fields["updatedAt"] = fields["createdAt"] ?? .null }
            if fields["version"] == nil || fields["version"] == .null { fields["version"] = .number(1) }
        case .competitionStart:
            if let parentId, fields["competitionId"] == nil || fields["competitionId"] == .null { fields["competitionId"] = .string(parentId) }
        default:
            break
        }
        // Załącznik: współrzędne zachowują skalę zapisu (`52.2297000`), a `JSONEncoder` jej nie gwarantuje — treść idzie tekstem ze skalą.
        let body = JSONValue.object(fields)
        guard let data = type == .attachment ? Data(body.textKeepingScale().utf8) : (try? body.data()) else { return nil }
        return try? RecordCodec.decode(type, from: data)
    }

    /// Nagranie jazdy z odpowiedzi serwera; koń i data treningu (kolumny magazynu) pochodzą z treningu, bo `RecordingDto` ich nie niesie.
    /// Punkty trasy (`trackData`) nie wchodzą do rekordu. `nil`, gdy treść nie jest nagraniem.
    public static func decodeRecording(_ json: JSONValue, horseId: String, trainingDate: LocalDate) -> LocalTrainingRecording? {
        guard let recording = try? Recording(json: json) else { return nil }
        return recording.toRecord(horseId: horseId, trainingDate: trainingDate)
    }

    /// Własne parametry jazd konia jako osobny rekord (`toRideProfileRecord` z Androida); `nil`, gdy odpowiedź konia nie niesie
    /// `rideProfile` (serwer 2.x, `/api/v1`). Wersja i czasy — konia.
    public static func rideProfileRecord(fromHorse json: JSONValue) -> LocalHorseRideProfile? {
        guard case let .object(fields) = json, let horseId = fields["id"]?.stringValue,
              let profileJSON = fields["rideProfile"], case .object = profileJSON,
              let data = try? profileJSON.data(), let profile = try? JSONDecoder().decode(RideProfile.self, from: data),
              let createdText = fields["createdAt"]?.stringValue, let createdAt = LocalDateTime(createdText),
              let updatedText = fields["updatedAt"]?.stringValue, let updatedAt = LocalDateTime(updatedText) else { return nil }
        return LocalHorseRideProfile(horseId: horseId, profile: profile, createdAt: createdAt, updatedAt: updatedAt, version: fields["version"]?.intValue ?? 0)
    }

    /// `recordingSummary` treningu z odpowiedzi `/api/v3` (pole tylko modelu API — rekord treningu go nie ma, decyzja A4);
    /// `nil` dla treningu bez nagrania i odpowiedzi `/api/v1`.
    public static func recordingSummary(ofTraining json: JSONValue) -> RecordingSummary? {
        guard let summary = json["recordingSummary"], case .object = summary, let data = try? summary.data() else { return nil }
        return try? JSONDecoder().decode(RecordingSummary.self, from: data)
    }

    // MARK: Rekord → treść żądania

    /// Treść `POST`/`PUT` z rekordu magazynu. Koń: `includeFinance = false` pomija kwoty (zmiana innych pól nie rusza kwot),
    /// `includePhoto` — `photoAttachmentId` tylko dla programu z możliwością `horsePhotoField` i tylko w `PUT`,
    /// `rideProfile` — profil jazd (`/api/v3`); `nil` pomija pole (bez zmian po stronie serwera), pusty profil = wszystko dziedziczy.
    public static func input(_ record: some LocalRecord, includeFinance: Bool = true, includePhoto: Bool = false, rideProfile: RideProfile? = nil) -> JSONValue {
        guard let data = try? RecordCodec.encode(record), case var .object(fields)? = try? JSONValue.parse(data) else { return .object([:]) }
        for key in audit { fields.removeValue(forKey: key) }
        for key in readOnly[record.recordType] ?? [] { fields.removeValue(forKey: key) }
        switch record.recordType {
        case .horse:
            var finance: [String: JSONValue] = [:]
            for key in financeKeys { finance[key] = fields.removeValue(forKey: key) ?? .null }
            if includeFinance { fields["finance"] = .object(finance) }
            if !includePhoto { fields.removeValue(forKey: "photoAttachmentId") }
            if let rideProfile, let data = try? JSONEncoder().encode(rideProfile), let profile = try? JSONValue.parse(data) {
                fields["rideProfile"] = profile
            }
        case .training:
            var coaching: [String: JSONValue] = [:]
            for key in coachingKeys { coaching[key] = fields.removeValue(forKey: key) ?? .null }
            fields["coaching"] = .object(coaching)
        case .vetVisit:
            if case let .array(items)? = fields["medications"] {
                fields["medications"] = .array(items.map { item in
                    guard case let .object(medication) = item else { return item }
                    return .object(medication.filter { medicationKeys.contains($0.key) })
                })
            }
        default:
            break
        }
        return .object(fields)
    }

    /// Zakup: konie w treści tylko dla przypisania do koni (`General` bez listy).
    public static func horseIds(of payload: JSONValue) -> [String] {
        payload["horseIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }
}

/// Ścieżki zasobów programu (`/api/v1/…`) dla rekordów, które aplikacja zmienia i usuwa (`RecordPaths.kt`). Start zawodów leży
/// pod zawodami — potrzebny jest ich `id` (pole `competitionId` w treści operacji).
public enum RecordPaths {
    static let collections: [RecordType: String] = [
        .horse: "horses", .contact: "contacts", .vetVisit: "vet-visits", .farrierVisit: "farrier-visits", .physioVisit: "physio-visits",
        .specialistVisit: "specialist-visits", .competition: "competitions", .purchase: "purchases", .note: "notes", .training: "trainings",
        .reminder: "reminders", .attachment: "attachments",
    ]

    /// Ścieżka rekordu; `nil` dla rodzaju bez zapisu w API albo startu bez zawodów.
    public static func item(_ type: RecordType, id: String, parentId: String? = nil) -> String? {
        if type == .competitionStart { return parentId.map { "competitions/\($0)/starts/\(id)" } }
        return collections[type].map { "\($0)/\(id)" }
    }

    public static func create(_ type: RecordType, parentId: String? = nil) -> String? {
        if type == .competitionStart { return parentId.map { "competitions/\($0)/starts" } }
        return collections[type]
    }

    /// Czy aplikacja zapisuje ten rodzaj rekordu w programie (słowniki — nie, zakres 1.x).
    public static func supports(_ type: RecordType) -> Bool { type != .dictionary }
}
