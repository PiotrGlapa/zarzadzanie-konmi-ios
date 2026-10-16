import Foundation

/// Rekord w kształcie eksportu programu. Właściwości `recordType`, `primaryHorseId`, `dateKey`, `parentId` i `horseIds` są wyliczane
/// (nie trafiają do JSON) i zasilają kolumny indeksowane magazynu (data-model.md §1–2).
public protocol LocalRecord: Codable, Hashable, Sendable {
    var id: String { get }
    var createdAt: LocalDateTime { get }
    var updatedAt: LocalDateTime { get }
    var version: Int { get }

    var recordType: RecordType { get }

    /// Koń, do którego należy rekord (zakup wielu koni: `nil`, konie w `horseIds`).
    var primaryHorseId: String? { get }

    /// Data porządkująca rekord w listach i raportach.
    var dateKey: LocalDate? { get }

    /// Rekord nadrzędny: zawody dla startu, właściciel dla załącznika, źródło dla terminu.
    var parentId: String? { get }

    /// Wszystkie konie rekordu (tabela `record_horse`).
    var horseIds: [String] { get }

    /// Ten sam rekord z nowym znacznikiem audytu — używane przy zapisie lokalnym.
    func withAudit(version: Int, updatedAt: LocalDateTime) -> Self

    /// Ten sam rekord z czasem utworzenia (nowy rekord wstawiany przez reguły).
    func withCreated(at time: LocalDateTime) -> Self
}

public extension LocalRecord {
    var primaryHorseId: String? { nil }
    var dateKey: LocalDate? { nil }
    var parentId: String? { nil }
    var horseIds: [String] { primaryHorseId.map { [$0] } ?? [] }
}

/// Zapis i odczyt rekordów jako JSON w kształcie eksportu (kolumna `body` magazynu, plik kopii zapasowej).
public enum RecordCodec {
    public static func decode(_ type: RecordType, from data: Data) throws -> any LocalRecord {
        switch type {
        case .dictionary: try JSONDecoder().decode(LocalDictionaryItem.self, from: data)
        case .contact: try JSONDecoder().decode(LocalContact.self, from: data)
        case .horse: try JSONDecoder().decode(LocalHorse.self, from: data)
        case .vetVisit: try JSONDecoder().decode(LocalVetVisit.self, from: data)
        case .farrierVisit: try JSONDecoder().decode(LocalFarrierVisit.self, from: data)
        case .physioVisit: try JSONDecoder().decode(LocalPhysioVisit.self, from: data)
        case .specialistVisit: try JSONDecoder().decode(LocalSpecialistVisit.self, from: data)
        case .competition: try JSONDecoder().decode(LocalCompetition.self, from: data)
        case .competitionStart: try JSONDecoder().decode(LocalCompetitionStart.self, from: data)
        case .purchase: try JSONDecoder().decode(LocalPurchase.self, from: data)
        case .note: try JSONDecoder().decode(LocalNote.self, from: data)
        case .training: try JSONDecoder().decode(LocalTraining.self, from: data)
        case .reminder: try JSONDecoder().decode(LocalReminder.self, from: data)
        case .attachment: try JSONDecoder().decode(LocalAttachment.self, from: data)
        }
    }

    public static func decode(_ type: RecordType, from json: String) throws -> any LocalRecord {
        try decode(type, from: Data(json.utf8))
    }

    public static func encode(_ record: some LocalRecord) throws -> Data {
        try makeEncoder().encode(record)
    }

    public static func encodeString(_ record: some LocalRecord) throws -> String {
        String(decoding: try encode(record), as: UTF8.self)
    }

    /// Kodowanie wspólnego kodera (używane przez dokument eksportu i kopię zapasową).
    static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// Konie i załączniki jako elementy list SwiftUI (`ForEach`, `List`).
extension LocalHorse: Identifiable {}
extension LocalAttachment: Identifiable {}
extension LocalContact: Identifiable {}
extension LocalDictionaryItem: Identifiable {}
extension LocalCompetition: Identifiable {}
extension LocalReminder: Identifiable {}
extension LocalTraining: Identifiable {}
extension LocalPurchase: Identifiable {}
extension LocalCompetitionStart: Identifiable {}
extension LocalVetVisit: Identifiable {}
extension LocalFarrierVisit: Identifiable {}
extension LocalPhysioVisit: Identifiable {}
extension LocalSpecialistVisit: Identifiable {}
extension LocalNote: Identifiable {}
