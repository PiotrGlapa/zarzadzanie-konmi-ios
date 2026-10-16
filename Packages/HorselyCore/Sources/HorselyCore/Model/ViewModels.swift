import Foundation

/// Strona wyniku listy (`totalAmount`/`totalCost` tylko w listach zakupów i treningów — sumy dla całego filtra).
public struct Page<Item: Equatable & Sendable>: Equatable, Sendable {
    public var items: [Item]
    public var page: Int
    public var pageSize: Int
    public var totalCount: Int
    public var totalAmount: Money?
    public var totalCost: Money?

    public init(items: [Item] = [], page: Int = 1, pageSize: Int = 50, totalCount: Int = 0, totalAmount: Money? = nil, totalCost: Money? = nil) {
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.totalCount = totalCount
        self.totalAmount = totalAmount
        self.totalCost = totalCost
    }
}

/// Termin w kształcie odpowiedzi programu: rekord z nazwą konia i rodzaju specjalisty oraz `isOverdue` względem dziś.
public struct ReminderItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var version: Int
    public var createdAt: LocalDateTime
    public var updatedAt: LocalDateTime
    public var horseId: String
    public var kind: ReminderKind
    public var dueDate: LocalDate
    public var title: String
    public var specialistTypeId: String?
    public var notes: String?
    public var status: ReminderStatus
    public var sourceType: String?
    public var sourceId: String?
    public var completedByType: String?
    public var completedById: String?
    public var completedAt: LocalDateTime?
    public var isOverdue: Bool
    public var horseName: String?
    public var specialistTypeName: String?

    public init(reminder: LocalReminder, isOverdue: Bool, horseName: String?, specialistTypeName: String?) {
        id = reminder.id
        version = reminder.version
        createdAt = reminder.createdAt
        updatedAt = reminder.updatedAt
        horseId = reminder.horseId
        kind = reminder.kind
        dueDate = reminder.dueDate
        title = reminder.title
        specialistTypeId = reminder.specialistTypeId
        notes = reminder.notes
        status = reminder.status
        sourceType = reminder.sourceType
        sourceId = reminder.sourceId
        completedByType = reminder.completedByType
        completedById = reminder.completedById
        completedAt = reminder.completedAt
        self.isOverdue = isOverdue
        self.horseName = horseName
        self.specialistTypeName = specialistTypeName
    }
}

/// Kafel konia na Pulpicie: koń w stajni z najbliższym otwartym terminem.
public struct DashboardHorse: Codable, Equatable, Sendable, Identifiable {
    public var horseId: String
    public var name: String
    public var nextReminderId: String?
    public var nextReminderDate: LocalDate?
    public var nextReminderTitle: String?
    public var isNextReminderOverdue: Bool
    public var photoAttachmentId: String?
    public var monthsWithoutPassport: Int?
    public var status: HorseStatus

    public var id: String { horseId }

    public init(
        horseId: String, name: String, nextReminderId: String?, nextReminderDate: LocalDate?, nextReminderTitle: String?, isNextReminderOverdue: Bool,
        photoAttachmentId: String?, monthsWithoutPassport: Int?, status: HorseStatus
    ) {
        self.horseId = horseId
        self.name = name
        self.nextReminderId = nextReminderId
        self.nextReminderDate = nextReminderDate
        self.nextReminderTitle = nextReminderTitle
        self.isNextReminderOverdue = isNextReminderOverdue
        self.photoAttachmentId = photoAttachmentId
        self.monthsWithoutPassport = monthsWithoutPassport
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case horseId, name, nextReminderId, nextReminderDate, nextReminderTitle, isNextReminderOverdue, photoAttachmentId, monthsWithoutPassport, status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        horseId = try c.decode(String.self, forKey: .horseId)
        name = try c.decode(String.self, forKey: .name)
        nextReminderId = try c.decodeIfPresent(String.self, forKey: .nextReminderId)
        nextReminderDate = try c.decodeIfPresent(LocalDate.self, forKey: .nextReminderDate)
        nextReminderTitle = try c.decodeIfPresent(String.self, forKey: .nextReminderTitle)
        isNextReminderOverdue = try c.decodeIfPresent(Bool.self, forKey: .isNextReminderOverdue) ?? false
        photoAttachmentId = try c.decodeIfPresent(String.self, forKey: .photoAttachmentId)
        monthsWithoutPassport = try c.decodeIfPresent(Int.self, forKey: .monthsWithoutPassport)
        status = try c.decodeIfPresent(HorseStatus.self, forKey: .status) ?? .active
    }
}

public enum TimelineEntryType: String, Codable, Sendable, CaseIterable {
    case vetVisit = "VetVisit"
    case farrierVisit = "FarrierVisit"
    case physioVisit = "PhysioVisit"
    case specialistVisit = "SpecialistVisit"
    case competitionStart = "CompetitionStart"
    case purchase = "Purchase"
    case note = "Note"

    public var recordType: RecordType {
        switch self {
        case .vetVisit: .vetVisit
        case .farrierVisit: .farrierVisit
        case .physioVisit: .physioVisit
        case .specialistVisit: .specialistVisit
        case .competitionStart: .competitionStart
        case .purchase: .purchase
        case .note: .note
        }
    }

    public var ownerType: AttachmentOwnerType {
        switch self {
        case .vetVisit: .vetVisit
        case .farrierVisit: .farrierVisit
        case .physioVisit: .physioVisit
        case .specialistVisit: .specialistVisit
        case .competitionStart: .competitionStart
        case .purchase: .purchase
        case .note: .note
        }
    }
}

/// Wpis osi czasu konia (bez treningów — te mają własną listę); `cost` bez przeliczeń.
public struct TimelineItem: Codable, Equatable, Sendable, Identifiable {
    public var entryType: TimelineEntryType
    public var id: String
    public var date: LocalDate
    public var title: String
    public var summary: String?
    public var cost: Money?
    public var attachmentCount: Int
    public var horseId: String?
    public var horseName: String?

    public init(
        entryType: TimelineEntryType, id: String, date: LocalDate, title: String, summary: String?, cost: Money?, attachmentCount: Int = 0,
        horseId: String? = nil, horseName: String? = nil
    ) {
        self.entryType = entryType
        self.id = id
        self.date = date
        self.title = title
        self.summary = summary
        self.cost = cost
        self.attachmentCount = attachmentCount
        self.horseId = horseId
        self.horseName = horseName
    }

    private enum CodingKeys: String, CodingKey { case entryType, id, date, title, summary, cost, attachmentCount, horseId, horseName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryType = try c.decode(TimelineEntryType.self, forKey: .entryType)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(LocalDate.self, forKey: .date)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        cost = try c.decodeIfPresent(Money.self, forKey: .cost)
        attachmentCount = try c.decodeIfPresent(Int.self, forKey: .attachmentCount) ?? 0
        horseId = try c.decodeIfPresent(String.self, forKey: .horseId)
        horseName = try c.decodeIfPresent(String.self, forKey: .horseName)
    }
}

/// Dane Pulpitu wyświetlane 1:1 (zasada I).
public struct Dashboard: Codable, Equatable, Sendable {
    public var overdue: [ReminderItem]
    public var upcoming: [ReminderItem]
    public var laterThisMonth: [ReminderItem]
    public var horses: [DashboardHorse]
    public var recentEntries: [TimelineItem]
    public var costsThisMonth: Money
    public var costsPreviousMonth: Money
    public var horizonDays: Int

    public init(
        overdue: [ReminderItem] = [], upcoming: [ReminderItem] = [], laterThisMonth: [ReminderItem] = [], horses: [DashboardHorse] = [],
        recentEntries: [TimelineItem] = [], costsThisMonth: Money = .zero, costsPreviousMonth: Money = .zero, horizonDays: Int = 7
    ) {
        self.overdue = overdue
        self.upcoming = upcoming
        self.laterThisMonth = laterThisMonth
        self.horses = horses
        self.recentEntries = recentEntries
        self.costsThisMonth = costsThisMonth
        self.costsPreviousMonth = costsPreviousMonth
        self.horizonDays = horizonDays
    }
}

/// Filtr osi czasu: `horseId` `nil` = wpisy wszystkich koni (Pulpit).
public struct TimelineFilter: Sendable {
    public var horseId: String?
    public var types: Set<TimelineEntryType>
    public var from: LocalDate?
    public var to: LocalDate?
    public var page: Int
    public var pageSize: Int

    public init(horseId: String? = nil, types: Set<TimelineEntryType> = [], from: LocalDate? = nil, to: LocalDate? = nil, page: Int = 1, pageSize: Int = 50) {
        self.horseId = horseId
        self.types = types
        self.from = from
        self.to = to
        self.page = page
        self.pageSize = pageSize
    }
}

/// Ustawienia programu, od których zależą reguły.
public struct RuleSettings: Sendable {
    /// Odstęp kowalski nowego konia bez własnego.
    public var defaultFarrierIntervalWeeks: Int
    /// Ile dni naprzód obejmuje „Nadchodzące” na Pulpicie.
    public var upcomingHorizonDays: Int

    public init(defaultFarrierIntervalWeeks: Int = 6, upcomingHorizonDays: Int = 7) {
        self.defaultFarrierIntervalWeeks = defaultFarrierIntervalWeeks
        self.upcomingHorizonDays = upcomingHorizonDays
    }
}
