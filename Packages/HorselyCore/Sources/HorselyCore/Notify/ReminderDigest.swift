import Foundation

/// Zaplanowane powiadomienie lokalne: identyfikator (`daily-RRRR-MM-DD` / `due-<id terminu>`), chwila (czas lokalny telefonu),
/// treść, wersja bez imion i tytułów (ekran blokady przy „Ukryj szczegóły”) i adres `horsely://` po dotknięciu.
public struct PlannedNotice: Equatable, Sendable {
    public let identifier: String
    public let fireAt: LocalDateTime
    public let text: String
    public let publicText: String
    public let deepLink: String

    public init(identifier: String, fireAt: LocalDateTime, text: String, publicText: String, deepLink: String) {
        self.identifier = identifier
        self.fireAt = fireAt
        self.text = text
        self.publicText = publicText
        self.deepLink = deepLink
    }
}

/// Ustawienia powiadomień (Ustawienia → Powiadomienia).
public struct NotificationPlanSettings: Equatable, Sendable {
    public var hour: Int
    public var minute: Int
    public var onDueDate: Bool

    public init(hour: Int = 8, minute: Int = 0, onDueDate: Bool = false) {
        self.hour = hour
        self.minute = minute
        self.onDueDate = onDueDate
    }

    /// Godzina z ustawień w zapisie `HH:mm` (nieczytelna — 08:00).
    public init(time: String, onDueDate: Bool) {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let valid = parts.count == 2 && (0 ... 23).contains(parts[0]) && (0 ... 59).contains(parts[1])
        self.init(hour: valid ? parts[0] : 8, minute: valid ? parts[1] : 0, onDueDate: onDueDate)
    }
}

/// Powiadomienia o terminach budowane lokalnie, bez sieci (FR-M-POW-01…04, `ReminderDigest.kt`): dzienne podsumowanie
/// i powiadomienia w dniu terminu. iOS nie budzi aplikacji codziennie, więc plan obejmuje 14 kolejnych podsumowań (każde liczone
/// na swój dzień) i najbliższe terminy — razem nie więcej niż 60 (limit systemu 64). Terminy koni sprzedanych i padłych są
/// pomijane; koń kontuzjowany jest w stajni jak aktywny.
public enum ReminderDigest {
    /// Po tylu dniach bez odświeżenia podsumowanie dopisuje, z kiedy są dane.
    public static let staleAfterDays = 7
    public static let summaryDays = 14
    public static let limit = 60

    public static let dashboardLink = "horsely://dashboard"
    public static let dueDayPublicText = "Termin na dziś"

    public static func reminderLink(_ id: String) -> String { "horsely://reminders/\(id)" }

    /// Otwarte terminy koni w stajni (aktywnych i kontuzjowanych).
    public static func relevant(_ reminders: [LocalReminder], horses: [LocalHorse]) -> [LocalReminder] {
        let inStable = Set(horses.filter { HorseStatuses.isInStable($0.status) }.map(\.id))
        return reminders.filter { $0.status == .open && inStable.contains($0.horseId) }
    }

    /// „X przeterminowanych, Y na dziś i jutro” (z dopiskiem o starych danych) albo `nil`, gdy nie ma czego zgłosić.
    public static func dailySummary(_ open: [LocalReminder], day: LocalDate, fetchedAt: LocalDateTime?, at moment: LocalDateTime) -> String? {
        let overdue = open.filter { $0.dueDate < day }.count
        let soon = open.filter { $0.dueDate == day || $0.dueDate == day.adding(days: 1) }.count
        if overdue == 0 && soon == 0 { return nil }
        var parts: [String] = []
        if overdue > 0 { parts.append("\(overdue) przeterminowanych") }
        if soon > 0 { parts.append("\(soon) na dziś i jutro") }
        let summary = parts.joined(separator: ", ")
        guard let note = staleNote(fetchedAt: fetchedAt, at: moment) else { return summary }
        return "\(summary)\n\(note)"
    }

    /// „Grom — kowal, dziś”, „…, jutro”, „…, termin minął 3 dni temu”, „…, termin za 4 dni”.
    public static func line(_ reminder: LocalReminder, horseName: String?, today: LocalDate) -> String {
        var subject: [String] = []
        if let horseName, !horseName.trimmingCharacters(in: .whitespaces).isEmpty { subject.append(horseName) }
        subject.append(kindName(reminder))
        return "\(subject.joined(separator: " — ")), \(dueText(reminder.dueDate, today: today))"
    }

    /// Plan powiadomień od chwili `now`: podsumowania na 14 dni (od dziś, jeśli godzina jeszcze nie minęła) i — przy włączonym
    /// „w dniu terminu” — po jednym na każdy otwarty termin od dziś, najbliższe pierwsze, aż do limitu 60.
    public static func plan(
        reminders: [LocalReminder], horses: [LocalHorse], settings: NotificationPlanSettings, now: LocalDateTime, fetchedAt: LocalDateTime?
    ) -> [PlannedNotice] {
        let open = relevant(reminders, horses: horses)
        let names = Dictionary(horses.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var notices: [PlannedNotice] = []
        for offset in 0 ..< summaryDays {
            let day = now.date.adding(days: offset)
            guard let fireAt = LocalDateTime(date: day, hour: settings.hour, minute: settings.minute), fireAt > now,
                  let text = dailySummary(open, day: day, fetchedAt: fetchedAt, at: fireAt) else { continue }
            notices.append(PlannedNotice(identifier: "daily-\(day)", fireAt: fireAt, text: text, publicText: text, deepLink: dashboardLink))
        }
        guard settings.onDueDate else { return notices }
        let upcoming = open.filter { $0.dueDate >= now.date }
            .sorted { ($0.dueDate, $0.title, $0.id) < ($1.dueDate, $1.title, $1.id) }
        for reminder in upcoming where notices.count < limit {
            guard let fireAt = LocalDateTime(date: reminder.dueDate, hour: settings.hour, minute: settings.minute), fireAt > now else { continue }
            notices.append(PlannedNotice(
                identifier: "due-\(reminder.id)", fireAt: fireAt, text: line(reminder, horseName: names[reminder.horseId], today: reminder.dueDate),
                publicText: dueDayPublicText, deepLink: reminderLink(reminder.id)
            ))
        }
        return Array(notices.prefix(limit))
    }

    static func dueText(_ due: LocalDate, today: LocalDate) -> String {
        let days = due.days(since: today)
        switch days {
        case 0: return "dziś"
        case 1: return "jutro"
        case let days where days > 1: return "termin za \(days) \(dniForm(days))"
        case -1: return "termin minął wczoraj"
        default: return "termin minął \(-days) \(dniForm(-days)) temu"
        }
    }

    static func dniForm(_ days: Int) -> String { days == 1 ? "dzień" : "dni" }

    static func kindName(_ reminder: LocalReminder) -> String {
        switch reminder.kind {
        case .vet: "weterynarz"
        case .vaccination: "szczepienie"
        case .deworming: "odrobaczanie"
        case .farrier: "kowal"
        case .physio: "fizjoterapia"
        case .specialist: "specjalista"
        case .competition: "zawody"
        case .other: reminder.title
        }
    }

    /// Dopisek dla danych starszych niż 7 dni w chwili powiadomienia (brak daty pobrania — bez dopisku).
    static func staleNote(fetchedAt: LocalDateTime?, at moment: LocalDateTime) -> String? {
        guard let fetchedAt, minutes(moment) - minutes(fetchedAt) > staleAfterDays * 24 * 60 else { return nil }
        return "Dane z \(Formats.dataStamp(fetchedAt)) — połącz się z komputerem, aby je odświeżyć"
    }

    static func minutes(_ value: LocalDateTime) -> Int {
        value.date.dayNumber * 24 * 60 + value.hour * 60 + value.minute
    }
}
