import Foundation

/// Pulpit i oś czasu z danych lokalnych (port `DashboardQuery`, `TimelineQuery`): odpowiedzi w modelach API, identyczne z odpowiedzią
/// programu na tych samych danych (pliki wzorcowe `parity`).
public struct LocalViews {
    public static let recentEntries = 10
    private static let summaryLength = 160

    private let source: RecordSource
    private let settings: RuleSettings

    public init(source: RecordSource, settings: RuleSettings = RuleSettings()) {
        self.source = source
        self.settings = settings
    }

    // MARK: Terminy

    /// Terminy z nazwą konia i rodzaju specjalisty, `isOverdue` względem dziś.
    public func reminderItems(_ reminders: [LocalReminder], today: LocalDate) throws -> [ReminderItem] {
        let horses = try CostCalculator.names(source, .horse)
        let types = try CostCalculator.names(source, .dictionary)
        return reminders.map { reminder in
            ReminderItem(
                reminder: reminder, isOverdue: reminder.status == .open && reminder.dueDate < today,
                horseName: horses[reminder.horseId] ?? "", specialistTypeName: reminder.specialistTypeId.flatMap { types[$0] }
            )
        }
    }

    // MARK: Pulpit

    public func dashboard(today: LocalDate) throws -> Dashboard {
        let horizon = settings.upcomingHorizonDays
        let horizonEnd = today.adding(days: horizon)
        let monthEnd = LocalDate(year: today.year, month: today.month, day: LocalDate.daysIn(month: today.month, year: today.year))!
        let horses = try source.records(.horse, as: LocalHorse.self).filter { HorseStatuses.isInStable($0.status) }
        let stableIds = Set(horses.map(\.id))
        let open = try source.records(.reminder, as: LocalReminder.self)
            .filter { $0.status == .open && stableIds.contains($0.horseId) }
            .sorted { ($0.dueDate, $0.id) < ($1.dueDate, $1.id) }
        let models = try reminderItems(open, today: today)
        var nearest: [String: ReminderItem] = [:]
        for model in models where nearest[model.horseId] == nil { nearest[model.horseId] = model }
        let tiles = horses.sorted { PolishNames.compare($0.name, $1.name) == .orderedAscending }.map { horse -> DashboardHorse in
            let reminder = nearest[horse.id]
            return DashboardHorse(
                horseId: horse.id, name: horse.name, nextReminderId: reminder?.id, nextReminderDate: reminder?.dueDate, nextReminderTitle: reminder?.title,
                isNextReminderOverdue: reminder?.isOverdue ?? false, photoAttachmentId: horse.photoAttachmentId,
                monthsWithoutPassport: HorseRules.monthsWithoutPassport(of: horse, on: today), status: horse.status
            )
        }
        let monthStart = today.firstOfMonth
        let costs = try CostCalculator.entries(source: source, from: monthStart.adding(months: -1), to: monthEnd).entries
        let recent = try timeline(TimelineFilter(page: 1, pageSize: Self.recentEntries + 5)).items
            .filter { $0.horseId != nil }
            .prefix(Self.recentEntries)
            .map { item -> TimelineItem in
                var copy = item
                copy.horseName = (try? source.find(.horse, id: item.horseId!, as: LocalHorse.self))?.name ?? ""
                return copy
            }
        return Dashboard(
            overdue: models.filter { $0.dueDate < today },
            upcoming: models.filter { $0.dueDate >= today && $0.dueDate <= horizonEnd },
            laterThisMonth: models.filter { $0.dueDate > horizonEnd && $0.dueDate <= monthEnd },
            horses: tiles,
            recentEntries: Array(recent),
            costsThisMonth: costs.filter { $0.date >= monthStart }.reduce(Money.zero) { $0 + $1.cost },
            costsPreviousMonth: costs.filter { $0.date < monthStart }.reduce(Money.zero) { $0 + $1.cost },
            horizonDays: horizon
        )
    }

    // MARK: Oś czasu

    public func timeline(_ filter: TimelineFilter) throws -> Page<TimelineItem> {
        let types = filter.types.isEmpty ? Set(TimelineEntryType.allCases) : filter.types
        let dictionary = try CostCalculator.names(source, .dictionary)
        var rows: [TimelineItem] = []
        // Dla wszystkich koni wystarczą najnowsze wpisy każdego rodzaju; dla jednego konia cała oś jest mała.
        let limit = filter.horseId == nil ? (filter.page - 1) * filter.pageSize + filter.pageSize : Int.max
        for type in types { rows += try load(type, filter, dictionary, limit: limit) }
        let ordered = rows.sorted { lhs, rhs in lhs.date == rhs.date ? lhs.id > rhs.id : lhs.date > rhs.date }
        let total = filter.horseId == nil ? try types.reduce(0) { $0 + (try load($1, filter, [:], limit: Int.max).count) } : ordered.count
        let pageItems = ordered.dropFirst((filter.page - 1) * filter.pageSize).prefix(filter.pageSize)

        var attachments: [String: [LocalAttachment]] = [:]
        for attachment in try source.records(.attachment, as: LocalAttachment.self) { attachments[attachment.ownerId, default: []].append(attachment) }
        let items = pageItems.map { item -> TimelineItem in
            var copy = item
            copy.attachmentCount = (attachments[item.id] ?? []).filter { $0.ownerType == item.entryType.ownerType }.count
            return copy
        }
        return Page(items: items, page: filter.page, pageSize: filter.pageSize, totalCount: total)
    }

    private func load(_ type: TimelineEntryType, _ filter: TimelineFilter, _ dictionary: [String: String], limit: Int) throws -> [TimelineItem] {
        // Najnowsze `limit` wierszy rodzaju (zapytanie zwraca rosnąco po dacie).
        let stored = try source.query(type.recordType, horseId: filter.horseId, from: filter.from, to: filter.to)
        let newest = stored.count > limit ? Array(stored.suffix(limit)) : stored
        return try newest.compactMap { row -> TimelineItem? in
            guard let date = row.dateKey else { return nil }
            switch row.record {
            case let record as LocalVetVisit:
                return item(type, record.id, date, dictionary[record.visitTypeId] ?? "Weterynarz", join(record.vaccineOrProduct, record.reason, record.diagnosis), record.cost, record.horseId)
            case let record as LocalFarrierVisit:
                return item(type, record.id, date, dictionary[record.serviceId] ?? "Kowal", record.hoofNotes, record.cost, record.horseId)
            case let record as LocalPhysioVisit:
                return item(type, record.id, date, "Fizjoterapia", join(record.reason, record.observations), record.cost, record.horseId)
            case let record as LocalSpecialistVisit:
                return item(type, record.id, date, dictionary[record.specialistTypeId] ?? "Specjaliści", join(record.reason, record.description), record.cost, record.horseId)
            case let record as LocalCompetitionStart:
                guard let competition = try source.find(.competition, id: record.competitionId, as: LocalCompetition.self) else { return nil }
                let placement = record.placement.map { "\($0). miejsce" }
                let cost: Money? = (record.entryFee == nil && record.otherCosts == nil) ? nil : (record.entryFee ?? .zero) + (record.otherCosts ?? .zero)
                return item(type, record.id, date, competition.name, join(record.className, placement, record.description), cost, record.horseId)
            case let record as LocalPurchase:
                // Program dzieli tu bez imion koni (reszta groszowa trafia do konia o najniższym id) — odtwarzamy to dla zgodności.
                let horses = record.horseIds.map { HorseName(id: $0, name: "") }
                let full = record.totalAmount + record.deliveryCost
                let cost: Money
                if let horseId = filter.horseId {
                    cost = PurchaseSplit.allocate(full, assignment: record.assignment, horses: horses).filter { $0.horseId == horseId }.reduce(Money.zero) { $0 + $1.amount }
                } else {
                    cost = full
                }
                return item(type, record.id, date, record.productName, join(dictionary[record.categoryId], record.notes), cost, filter.horseId ?? record.horseIds.sorted().first)
            case let record as LocalNote:
                return item(type, record.id, date, record.title, record.content, nil, record.horseId)
            default:
                return nil
            }
        }
    }

    private func item(_ type: TimelineEntryType, _ id: String, _ date: LocalDate, _ title: String, _ summary: String?, _ cost: Money?, _ horseId: String?) -> TimelineItem {
        TimelineItem(entryType: type, id: id, date: date, title: title, summary: shorten(summary), cost: cost, attachmentCount: 0, horseId: horseId)
    }

    private func join(_ parts: String?...) -> String? {
        let present = parts.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }

    private func shorten(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let single = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard single.count > Self.summaryLength else { return single }
        return String(single.prefix(Self.summaryLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
