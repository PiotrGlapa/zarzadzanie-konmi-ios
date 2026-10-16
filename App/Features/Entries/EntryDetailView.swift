import HorselyCore
import HorselyKit
import SwiftUI

/// Wpis wskazany z listy (oś czasu, Pulpit, zakładki karty konia).
struct EntryRoute: Hashable {
    let recordType: RecordType
    let id: String
}

extension FormKind {
    init?(recordType: RecordType) {
        switch recordType {
        case .vetVisit: self = .vet
        case .farrierVisit: self = .farrier
        case .physioVisit: self = .physio
        case .specialistVisit: self = .specialist
        case .note: self = .note
        case .purchase: self = .purchase
        case .training: self = .training
        case .competition: self = .competition
        case .competitionStart: self = .start
        default: return nil
        }
    }
}

/// Szczegóły wpisu (FR-M-WPI): sekcje jak w formularzu (tylko pola z wartością), gwiazdki oceny, „Edytuj”, „Usuń” z potwierdzeniem
/// i — przy zakupie — „Powtórz zakup”. Nieistniejący wpis: „Nie znaleziono wpisu”.
struct EntryDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let route: EntryRoute
    @State private var record: (any LocalRecord)?
    @State private var isLoaded = false
    @State private var dictionaries: [LocalDictionaryItem] = []
    @State private var contacts: [LocalContact] = []
    @State private var competitions: [LocalCompetition] = []
    @State private var editing: EntryFormModel?
    @State private var confirmingDelete = false
    @State private var banner: BannerMessage?

    private var kind: FormKind? { FormKind(recordType: route.recordType) }

    var body: some View {
        Group {
            if let record, let kind {
                content(record, kind)
            } else if isLoaded {
                Text("entry_not_found").multilineTextAlignment(.center).padding(Spacing.screenEdge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(HorselyColor.background)
        .navigationTitle("entry_detail_title")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: environment.dataRevision) { await load() }
        .overlay(alignment: .bottom) {
            if let banner {
                SaveBanner(message: banner.text, undo: banner.undo) { self.banner = nil }.id(banner.id).padding(.bottom, Spacing.between)
            }
        }
        .animation(.default, value: banner)
    }

    private func load() async {
        record = try? await environment.entries.record(route.recordType, id: route.id)
        dictionaries = (try? await environment.entries.allDictionaryItems()) ?? []
        contacts = (try? await environment.entries.allContacts()) ?? []
        competitions = (try? await environment.entries.competitions()) ?? []
        isLoaded = true
    }

    private func draft(_ record: any LocalRecord) -> EntryDraft {
        switch record {
        case let record as LocalVetVisit: EntryDraft(vet: record)
        case let record as LocalFarrierVisit: EntryDraft(farrier: record)
        case let record as LocalPhysioVisit: EntryDraft(physio: record)
        case let record as LocalSpecialistVisit: EntryDraft(specialist: record)
        case let record as LocalNote: EntryDraft(note: record)
        case let record as LocalPurchase: EntryDraft(purchase: record)
        case let record as LocalTraining: EntryDraft(training: record)
        case let record as LocalCompetition: EntryDraft(competition: record)
        case let record as LocalCompetitionStart: EntryDraft(start: record)
        default: EntryDraft()
        }
    }

    private func content(_ record: any LocalRecord, _ kind: FormKind) -> some View {
        let draft = draft(record)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Spacing.between + 4) {
                    AccentIcon(kind.accent)
                    Text(LocalizedStringKey(kind.titleKey)).font(.headline).foregroundStyle(kind.accent.color).accessibilityAddTraits(.isHeader)
                }
                .padding(.top, Spacing.between)
                ForEach(Array(FormSpec.sections(for: kind).enumerated()), id: \.offset) { _, section in
                    sectionView(section, kind: kind, draft: draft, record: record)
                }
                actions(record, kind)
                Color.clear.frame(height: Spacing.addButtonClearance)
            }
            .padding(.horizontal, Spacing.screenEdge)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(tr("common_edit")) { startEditing(record, kind) }.accessibilityIdentifier("entry-edit")
            }
        }
        .sheet(item: $editing) { model in
            EntryFormView(model: model) { saved, _ in
                banner = BannerMessage(text: tr("entry_updated")) { Task { try? await environment.entries.undo(saved.undo) } }
            }
            .environment(environment)
        }
        .confirmationDialog(tr("entry_delete_title"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(tr("common_delete"), role: .destructive) { delete(record) }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text("entry_delete_message")
        }
    }

    private func startEditing(_ record: any LocalRecord, _ kind: FormKind) {
        editing = EntryFormModel(kind: kind, editing: record, today: environment.dates.today(), now: environment.dates.now())
    }

    private func delete(_ record: any LocalRecord) {
        let type = route.recordType
        let id = route.id
        Task {
            if let saved = (try? await environment.entries.delete(type, id: id))?.saved {
                environment.router.banner = BannerMessage(text: tr("entry_deleted")) { Task { try? await environment.entries.undo(saved.undo) } }
                dismiss()
            }
        }
    }

    private func actions(_ record: any LocalRecord, _ kind: FormKind) -> some View {
        VStack(spacing: Spacing.between) {
            if let purchase = record as? LocalPurchase {
                Button {
                    environment.router.entryRequest = EntryRequest(kind: .purchase, repeating: purchase)
                } label: {
                    Text("purchases_repeat").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .tint(HorselyColor.primary)
                .accessibilityIdentifier("entry-repeat")
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text("common_delete").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("entry-delete")
        }
        .padding(.top, Spacing.beforeSection)
    }

    // MARK: Sekcje

    @ViewBuilder
    private func sectionView(_ section: FormSection, kind: FormKind, draft: EntryDraft, record: any LocalRecord) -> some View {
        let rows = section.slots.compactMap { slot in value(slot.field, kind: kind, draft: draft).map { (slot.field, $0) } }
        let rating = section.slots.contains { $0.field == .rating } ? draft.rating : nil
        if !rows.isEmpty || rating != nil {
            SectionHeader(LocalizedStringKey(section.titleKey))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { DividerLine(inset: 0) }
                    detailRow(row.0.labelKey(for: kind), row.1, field: row.0)
                }
                if let rating {
                    if !rows.isEmpty { DividerLine(inset: 0) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("field_rating").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                        StarRatingDisplay(rating: rating)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.between)
                }
            }
        }
    }

    private func detailRow(_ key: String, _ value: String, field: FormField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if field != .total { Text(LocalizedStringKey(key)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant) }
            Text(value).accessibilityIdentifier("entry-detail-\(field)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.between)
        .accessibilityElement(children: .combine)
    }

    // MARK: Wartości pól

    private func horseName(_ id: String?) -> String? {
        id.flatMap { id in environment.horseDirectory.horses.first { $0.id == id }?.name }
    }

    private func item(_ id: String?) -> String? {
        id.flatMap { id in dictionaries.first { $0.id == id }?.value }
    }

    private func contact(_ id: String?) -> String? {
        id.flatMap { id in contacts.first { $0.id == id }?.name }
    }

    private func names(_ ids: [String]) -> String? {
        let result = ids.compactMap { item($0) }
        return result.isEmpty ? nil : result.joined(separator: ", ")
    }

    private func text(_ value: String) -> String? { HorseRules.clean(value) }

    private func money(_ value: String) -> String? {
        if case let .valid(amount) = MoneyInput.parse(value) { return Formats.money(amount) }
        return nil
    }

    private func number(_ value: String, suffix: String = "") -> String? {
        text(value).map { $0 + suffix }
    }

    private func value(_ field: FormField, kind: FormKind, draft: EntryDraft) -> String? {
        switch field {
        case .horse: return kind == .purchase ? (draft.assignment == .singleHorse ? horseName(draft.horseId) : nil) : horseName(draft.horseId)
        case .horses:
            let names = draft.horseIds.compactMap { horseName($0) }
            return kind == .purchase && draft.assignment == .multipleHorses && !names.isEmpty ? names.joined(separator: ", ") : nil
        case .date: return draft.date.map { Formats.date($0) }
        case .dateTime: return draft.visitDateTime.map { Formats.dateTime($0) }
        case .startDate: return draft.startDate.map { Formats.date($0) }
        case .visitType: return item(draft.visitTypeId)
        case .farrierService: return item(draft.farrierServiceId)
        case .specialistType: return item(draft.specialistTypeId)
        case .trainingType: return item(draft.trainingTypeId)
        case .category: return item(draft.categoryId)
        case .unit: return item(draft.unitId)
        case .rank: return item(draft.rankId)
        case .discipline: return item(draft.disciplineId)
        case .vetContact, .farrierContact, .physioContact, .specialistContact: return contact(draft.contactId)
        case .supplier: return contact(draft.supplierId)
        case .organizer: return contact(draft.organizerId)
        case .rider: return contact(draft.riderId)
        case .trainer: return contact(draft.trainerId)
        case .reason: return text(draft.reason)
        case .diagnosis: return text(draft.diagnosis)
        case .recommendations: return text(draft.recommendations)
        case .vaccineOrProduct: return text(draft.vaccineOrProduct)
        case .batchNumber: return text(draft.batchNumber)
        case .medications:
            let lines = draft.medications.map { medication -> String in
                var parts = [medication.name]
                if let dosage = text(medication.dosage) { parts.append(dosage) }
                if let mode = medication.administration { parts.append(tr(mode.labelKey)) }
                return parts.joined(separator: " · ")
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        case .hoofNotes: return text(draft.hoofNotes)
        case .bodyAreas: return names(draft.bodyAreaIds)
        case .techniques: return names(draft.techniqueIds)
        case .observations: return text(draft.observations)
        case .description: return text(draft.descriptionText)
        case .cost, .trainingCost: return money(draft.cost)
        case .foreignAmount:
            guard let amount = text(draft.originalAmount) else { return nil }
            return "\(amount) \(draft.originalCurrency)"
        case .nextVisitDate: return draft.nextVisitDate.map { Formats.date($0) }
        case .nextVisitPurpose: return text(draft.nextVisitPurpose)
        case .title: return text(draft.title)
        case .content: return text(draft.content)
        case .pinned: return draft.pinned ? tr("field_pinned") : nil
        case .productName: return text(draft.productName)
        case .quantity: return text(draft.quantity)
        case .unitPrice: return money(draft.unitPrice)
        case .amount: return money(draft.amount)
        case .deliveryCost:
            if case let .valid(delivery) = MoneyInput.parse(draft.deliveryCost), delivery.value > 0 { return Formats.money(delivery) }
            return nil
        case .total:
            guard case let .valid(amount) = MoneyInput.parse(draft.amount) else { return nil }
            var delivery = Money.zero
            if case let .valid(value) = MoneyInput.parse(draft.deliveryCost) { delivery = value }
            return tr("entry_total", Formats.money(PurchaseAmount.total(amount: amount, delivery: delivery)))
        case .assignment: return kind == .purchase ? tr(draft.assignment.labelKey) : nil
        case .notes: return text(draft.notes)
        case .competitionChoice: return competitions.first { $0.id == draft.competitionId }.map { "\($0.name) · \(Formats.date($0.dateFrom))" }
        case .competitionName: return text(draft.competitionName)
        case .dateFrom: return draft.dateFrom.map { Formats.date($0) }
        case .dateTo: return draft.dateTo.map { Formats.date($0) }
        case .city: return text(draft.city)
        case .venue: return text(draft.venue)
        case .className: return text(draft.className)
        case .placement: return number(draft.placement)
        case .participants: return number(draft.participants)
        case .resultStatus: return draft.resultStatus.map { tr($0.labelKey) }
        case .rating: return nil
        case .entryFee: return money(draft.entryFee)
        case .otherCosts: return money(draft.otherCosts)
        case .prizeMoney: return money(draft.prizeMoney)
        case .penaltyPoints: return text(draft.penaltyPoints)
        case .scorePercent: return number(draft.scorePercent, suffix: " %")
        case .timeSeconds: return number(draft.timeSeconds, suffix: " s")
        case .duration: return Int(draft.duration).map { Formats.duration(minutes: $0) }
        case .intensity: return draft.intensity.map { tr($0.labelKey) }
        case .obstacleHeight: return Int(draft.obstacleHeight).map { tr("trainings_height", $0) }
        }
    }
}
