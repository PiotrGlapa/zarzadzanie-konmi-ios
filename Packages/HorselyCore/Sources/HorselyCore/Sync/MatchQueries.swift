import Foundation

/// Zapytanie dopasowania do licznika przed i po (FR-M-SYN-06; tabela w contracts/android/outbox-operations.md): filtr API
/// i predykat lokalny na polach treści operacji (`MatchQueries.kt`). Treść musi mieć podstawione identyfikatory z programu.
///
/// Porównania: tekst — po przycięciu białych znaków (pusty = brak), kwoty — wartości dziesiętne, daty — kalendarzowe,
/// załącznik — `sha256` pliku.
public struct MatchSpec: Equatable, Sendable {
    public let path: String
    public let query: [(String, String)]
    /// Lista stronicowana (`items`, `totalCount`, `pageSize=200`); inaczej tablica.
    public let paged: Bool
    /// Elementy listy są skrócone — każdego kandydata porównuje się z pełnym rekordem z `GET <path>/{id}`.
    public let detail: Bool
    let fields: [Field]
    let sha256: String?

    public static let pageSize = 200

    public static func == (lhs: MatchSpec, rhs: MatchSpec) -> Bool {
        lhs.path == rhs.path && lhs.query.map { "\($0.0)=\($0.1)" } == rhs.query.map { "\($0.0)=\($0.1)" } && lhs.paged == rhs.paged
            && lhs.detail == rhs.detail && lhs.fields == rhs.fields && lhs.sha256 == rhs.sha256
    }

    enum Field: Equatable, Sendable {
        case text(String)
        case money(String)
        case whole(String)
        case date(String)
        case dateTime(String)
        case idSet(String)
        case sha
    }

    /// Specyfikacja dla operacji tworzącej; `nil` dla akcji na terminach, zmian i usunięć.
    public static func forOperation(_ operation: OutboxOperation, sha256: String? = nil) -> MatchSpec? {
        let p = operation.payload
        func t(_ key: String) -> String? { text(p, key) }
        func q(_ pairs: (String, String?)...) -> [(String, String)] { pairs.compactMap { key, value in value.map { (key, $0) } } }
        let visitDay = t("visitDateTime").map { String($0.prefix(10)) }
        switch operation.kind {
        case .createVetVisit:
            return MatchSpec(path: "vet-visits", query: q(("horseId", t("horseId")), ("from", visitDay), ("to", visitDay)), paged: true, detail: true,
                             fields: [.dateTime("visitDateTime"), .text("visitTypeId"), .text("contactId"), .text("reason"), .text("diagnosis"), .money("cost")], sha256: nil)
        case .createFarrierVisit:
            return MatchSpec(path: "farrier-visits", query: q(("horseId", t("horseId")), ("from", t("visitDate")), ("to", t("visitDate"))), paged: true, detail: true,
                             fields: [.date("visitDate"), .text("serviceId"), .text("contactId"), .text("hoofNotes"), .money("cost")], sha256: nil)
        case .createPhysioVisit:
            return MatchSpec(path: "physio-visits", query: q(("horseId", t("horseId")), ("from", t("visitDate")), ("to", t("visitDate"))), paged: true, detail: true,
                             fields: [.date("visitDate"), .text("contactId"), .text("reason"), .text("observations"), .money("cost")], sha256: nil)
        case .createSpecialistVisit:
            return MatchSpec(
                path: "specialist-visits",
                query: q(("horseId", t("horseId")), ("specialistTypeId", t("specialistTypeId")), ("from", t("visitDate")), ("to", t("visitDate"))),
                paged: true, detail: true,
                fields: [.date("visitDate"), .text("contactId"), .text("reason"), .text("description"), .money("cost")], sha256: nil
            )
        case .createCompetition:
            return MatchSpec(path: "competitions", query: q(("from", t("dateFrom")), ("to", t("dateFrom")), ("q", t("name"))), paged: true, detail: false,
                             fields: [.text("name"), .date("dateFrom"), .text("city")], sha256: nil)
        case .createCompetitionStart:
            return MatchSpec(path: "competitions/\(t("competitionId") ?? "")/starts", query: [], paged: false, detail: false,
                             fields: [.text("horseId"), .date("startDate"), .text("className"), .text("riderContactId"), .whole("placement"), .money("entryFee")], sha256: nil)
        case .createPurchase:
            return MatchSpec(path: "purchases", query: q(("from", t("purchaseDate")), ("to", t("purchaseDate")), ("q", t("productName"))), paged: true, detail: true,
                             fields: [.date("purchaseDate"), .text("productName"), .text("categoryId"), .money("totalAmount"), .money("deliveryCost"), .text("assignment"), .idSet("horseIds")],
                             sha256: nil)
        case .createNote:
            // Lista notatek nie ma filtra dat — czytamy całą listę konia.
            return MatchSpec(path: "notes", query: q(("horseId", t("horseId"))), paged: true, detail: false,
                             fields: [.date("noteDate"), .text("title"), .text("content")], sha256: nil)
        case .createTraining:
            return MatchSpec(
                path: "trainings",
                query: q(("horseId", t("horseId")), ("from", t("trainingDate")), ("to", t("trainingDate")), ("typeId", t("trainingTypeId"))),
                paged: true, detail: false,
                fields: [.date("trainingDate"), .text("trainingTypeId"), .whole("durationMinutes"), .whole("rating"), .text("description"), .text("riderContactId")], sha256: nil
            )
        case .createReminder:
            return MatchSpec(
                path: "reminders",
                query: q(("horseId", t("horseId")), ("kind", t("kind")), ("dueFrom", t("dueDate")), ("dueTo", t("dueDate")), ("status", "Open")),
                paged: true, detail: false, fields: [.date("dueDate"), .text("title"), .text("notes")], sha256: nil
            )
        case .createContact:
            return MatchSpec(path: "contacts", query: q(("q", t("name")), ("includeArchived", "true")), paged: true, detail: false,
                             fields: [.text("name"), .text("phone")], sha256: nil)
        case .createAttachment:
            return MatchSpec(path: "attachments", query: q(("ownerType", t("ownerType")), ("ownerId", t("ownerId"))), paged: false, detail: false,
                             fields: [.sha], sha256: sha256)
        case .createHorse:
            // Klucz dopasowania nowego konia: imię + numer paszportu (FR-SYN2-05).
            return MatchSpec(path: "horses", query: q(("q", t("name"))), paged: true, detail: false,
                             fields: [.text("name"), .text("passportNumber")], sha256: nil)
        case .completeReminder, .dismissReminder, .updateRecord, .rescheduleReminder, .deleteRecord:
            return nil
        }
    }

    /// Adres zapytania (bez stronicowania); wartości kodowane procentowo.
    public func url(page: Int? = nil) -> String {
        var items = query
        if paged, let page {
            items.append(("page", String(page)))
            items.append(("pageSize", String(Self.pageSize)))
        }
        guard !items.isEmpty else { return path }
        return path + "?" + items.map { "\($0.0)=\(Self.encode($0.1))" }.joined(separator: "&")
    }

    public static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Czy rekord z programu pasuje do treści operacji.
    public func matches(payload: JSONValue, record: JSONValue) -> Bool {
        fields.allSatisfy { field in
            switch field {
            case let .text(key): return Self.text(payload, key) == Self.text(record, key)
            case let .money(key), let .whole(key):
                let a = Self.text(payload, key).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
                let b = Self.text(record, key).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
                if case .whole = field { return a.map { NSDecimalNumber(decimal: $0).intValue } == b.map { NSDecimalNumber(decimal: $0).intValue } }
                return a == b
            case let .date(key):
                return Self.text(payload, key).map { String($0.prefix(10)) }.flatMap(LocalDate.init) == Self.text(record, key).map { String($0.prefix(10)) }.flatMap(LocalDate.init)
            case let .dateTime(key):
                return Self.text(payload, key).flatMap(LocalDateTime.init) == Self.text(record, key).flatMap(LocalDateTime.init)
            case let .idSet(key):
                return Set(payload[key]?.arrayValue?.compactMap(\.stringValue) ?? []) == Set(record[key]?.arrayValue?.compactMap(\.stringValue) ?? [])
            case .sha:
                guard let sha256, let theirs = Self.text(record, "sha256") else { return false }
                return theirs.caseInsensitiveCompare(sha256) == .orderedSame
            }
        }
    }

    /// Liczba pasujących i `id` najnowszego (wg `createdAt`, przy równych — `id`, UUIDv7 rośnie z czasem).
    public func count(payload: JSONValue, records: [JSONValue]) -> (count: Int, newestId: String?) {
        let matching = records.filter { matches(payload: payload, record: $0) }
        let newest = matching.max { (Self.text($0, "createdAt") ?? "", Self.text($0, "id") ?? "") < (Self.text($1, "createdAt") ?? "", Self.text($1, "id") ?? "") }
        return (matching.count, newest.flatMap { Self.text($0, "id") })
    }

    static func text(_ object: JSONValue, _ key: String) -> String? {
        guard let value = object[key], !value.isNull, let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
