import HorselyCore
import HorselyKit
import SwiftUI

/// Formularz wpisu (FR-M-WPI): nagłówek z akcentem koloru rodzaju, sekcje wg `FormSpec` (Podstawowe · Szczegóły · Koszty ·
/// Następna wizyta · Uwagi), „Więcej szczegółów”, „*” przy polach wymaganych, błędy reguł programu pod polami, „Zapisz” w pasku
/// nawigacji i przypięte do dołu, potwierdzenie porzucenia zmian (przycisk „Zamknij”, gest zsunięcia arkusza).
struct EntryFormView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var model: EntryFormModel
    @State private var confirmingDiscard = false
    @State private var confirmingInjury = false
    /// Wywoływane po zapisie: zapis (z cofnięciem) i informacja, czy to była edycja.
    let onSaved: (EntrySaved, Bool) -> Void

    init(model: EntryFormModel, onSaved: @escaping (EntrySaved, Bool) -> Void) {
        self._model = State(initialValue: model)
        self.onSaved = onSaved
    }

    private var today: LocalDate { environment.dates.today() }
    private var horses: [LocalHorse] { environment.horseDirectory.horses }
    private var kindTitle: String { tr(model.kind.titleKey) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    header
                    ForEach(Array(FormSpec.sections(for: model.kind).enumerated()), id: \.offset) { _, section in
                        sectionView(section)
                    }
                    if model.hasMoreFields {
                        Section {
                            Button(tr(model.showMore ? "entry_form_less" : "entry_form_more")) { model.showMore.toggle() }
                                .frame(minHeight: Spacing.minTouchTarget)
                                .accessibilityIdentifier("entry-form-more")
                        }
                    }
                    if let failure = model.failure {
                        Section { Text(failure).foregroundStyle(HorselyColor.error).accessibilityIdentifier("entry-form-failure") }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                .background(HorselyColor.background)
                .navigationTitle(model.isEditing ? tr("entry_form_edit", kindTitle) : tr("entry_form_new", kindTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("common_close")) { close() }.accessibilityIdentifier("entry-form-close")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("common_save")) { save(proxy) }.disabled(model.isSaving).accessibilityIdentifier("entry-form-save-nav")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    FormSaveBar(isSaving: model.isSaving) { save(proxy) }
                        .accessibilityIdentifier("entry-form-save")
                }
                .confirmationDialog(tr("common_discard_title"), isPresented: $confirmingDiscard, titleVisibility: .visible) {
                    Button(tr("common_discard_confirm"), role: .destructive) { dismiss() }
                    Button(tr("common_discard_keep"), role: .cancel) {}
                } message: {
                    Text("common_discard_message")
                }
                .confirmationDialog(tr("training_injured_title"), isPresented: $confirmingInjury, titleVisibility: .visible) {
                    Button(tr("common_save")) { commit(proxy) }
                    Button(tr("common_cancel"), role: .cancel) {}
                } message: {
                    Text("training_injured_message")
                }
            }
            .task { await model.load(using: environment) }
        }
        .tint(HorselyColor.primary)
        .interactiveDismissDisabled(model.isDirty)
    }

    private func close() {
        if model.isDirty { confirmingDiscard = true } else { dismiss() }
    }

    private func save(_ proxy: ScrollViewProxy) {
        if !model.isEditing, model.needsInjuryConfirmation(horses: horses) {
            confirmingInjury = true
        } else {
            commit(proxy)
        }
    }

    private func commit(_ proxy: ScrollViewProxy) {
        Task {
            if let saved = await model.save(using: environment) {
                onSaved(saved, model.isEditing)
                dismiss()
            } else if let field = model.firstErrorField {
                withAnimation { proxy.scrollTo(field, anchor: .center) }
            }
        }
    }

    // MARK: Układ

    private var header: some View {
        Section {
            HStack(spacing: Spacing.between + 4) {
                AccentIcon(model.kind.accent)
                Text(kindTitle).font(.headline).foregroundStyle(model.kind.accent.color).accessibilityAddTraits(.isHeader)
            }
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func sectionView(_ section: FormSection) -> some View {
        let slots = section.slots.filter { model.isVisible($0) }
        if !slots.isEmpty {
            Section {
                ForEach(slots, id: \.self) { slot in
                    fieldWithErrors(slot.field) { input(slot.field) }.id(slot.field)
                }
            } header: {
                Text(LocalizedStringKey(section.titleKey))
            }
        }
    }

    private func label(_ field: FormField) -> LocalizedStringKey {
        let required = FormSpec.isRequired(field, kind: model.kind)
        return LocalizedStringKey(tr(field.labelKey(for: model.kind)) + (required ? " *" : ""))
    }

    /// Pole z komunikatami reguł pod spodem (kolor błędu + ikona, informacja nigdy tylko kolorem).
    private func fieldWithErrors<Content: View>(_ field: FormField, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            ForEach(model.errors(for: field), id: \.self) { message in
                Label {
                    Text(message).font(.footnote)
                } icon: {
                    HIcon(name: "warning", size: 16)
                }
                .foregroundStyle(HorselyColor.error)
                .accessibilityLabel(message)
            }
            ForEach(model.warnings(for: field), id: \.self) { message in
                Label {
                    Text(message).font(.footnote)
                } icon: {
                    HIcon(name: "info", size: 16)
                }
                .foregroundStyle(HorselyColor.warning)
            }
        }
    }

    // MARK: Pola

    private func dictionary(_ field: FormField, _ type: DictionaryType, _ selection: Binding<String?>) -> some View {
        DictionaryPicker(title: label(field), items: model.items(type), selection: selection, identifier: "entry-\(type.rawValue)")
    }

    private func contact(_ field: FormField, _ type: ContactType, _ selection: Binding<String?>) -> some View {
        ContactPicker(
            title: label(field), contacts: model.contacts, type: type, selection: selection,
            add: { name in await model.addContact(name: name, type: type, using: environment) }, identifier: "entry-contact-\(type.rawValue)"
        )
    }

    private func multi(_ field: FormField, _ type: DictionaryType, _ selection: Binding<[String]>) -> some View {
        let options = model.items(type).filter { $0.isActive || selection.wrappedValue.contains($0.id) }.map { MultiSelect.Option(id: $0.id, name: $0.value) }
        return MultiSelect(title: label(field), options: options, selection: selection)
    }

    private func money(_ field: FormField, _ text: Binding<String>, suffix: String? = tr("common_currency_suffix")) -> some View {
        MoneyField(title: label(field), text: text, suffix: suffix, identifier: "entry-\(field)")
    }

    private func text(_ field: FormField, _ text: Binding<String>, multiline: Bool = false, caps: Bool = false) -> some View {
        TextRow(
            title: label(field), text: text, required: FormSpec.isRequired(field, kind: model.kind), multiline: multiline,
            capitalization: caps ? .characters : .sentences, identifier: "entry-\(field)"
        )
    }

    private var horseOptions: [MultiSelect.Option] {
        HorseSearch.apply(horses, query: "", filter: .inStable).map { MultiSelect.Option(id: $0.id, name: $0.name) }
    }

    private var trainingCost: Binding<String> {
        Binding(get: { model.draft.cost }, set: { model.draft.cost = $0; model.markTrainingEdited(.cost) })
    }

    @ViewBuilder
    private func input(_ field: FormField) -> some View {
        switch field {
        case .horse: horseInput
        case .horses:
            MultiSelect(title: label(.horses), options: horseOptions, selection: $model.draft.horseIds, emptyText: tr("entry_pick_horses_none"), identifier: "entry-horses")
        case .date:
            DateField(label(.date), date: $model.draft.date, maximum: model.kind == .training ? today : nil, defaultSelection: today)
                .onChange(of: model.draft.date) { _, _ in model.applyFarrierSuggestion(horses: horses) }
        case .dateTime:
            DateField(label(.dateTime), date: $model.draft.date, defaultSelection: today)
            DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) { Text("field_visit_time") }
                .environment(\.locale, Locale(identifier: "pl_PL"))
        case .startDate:
            DateField(label(.startDate), date: $model.draft.startDate, defaultSelection: today)
        case .visitType: dictionary(.visitType, .vetVisitType, $model.draft.visitTypeId)
        case .farrierService: dictionary(.farrierService, .farrierService, $model.draft.farrierServiceId)
        case .specialistType: dictionary(.specialistType, .specialistType, $model.draft.specialistTypeId)
        case .trainingType: dictionary(.trainingType, .trainingType, $model.draft.trainingTypeId)
        case .category: dictionary(.category, .purchaseCategory, $model.draft.categoryId)
        case .unit: dictionary(.unit, .unit, $model.draft.unitId)
        case .rank: dictionary(.rank, .competitionRank, $model.draft.rankId)
        case .discipline: dictionary(.discipline, .competitionDiscipline, $model.draft.disciplineId)
        case .vetContact: contact(.vetContact, .vet, $model.draft.contactId)
        case .farrierContact: contact(.farrierContact, .farrier, $model.draft.contactId)
        case .physioContact: contact(.physioContact, .physio, $model.draft.contactId)
        case .specialistContact: contact(.specialistContact, .specialist, $model.draft.contactId)
        case .supplier: contact(.supplier, .shop, $model.draft.supplierId)
        case .organizer: contact(.organizer, .organizer, $model.draft.organizerId)
        case .rider:
            contact(.rider, .rider, model.kind == .training ? Binding(get: { model.draft.riderId }, set: { model.draft.riderId = $0; model.markTrainingEdited(.rider) }) : $model.draft.riderId)
        case .trainer:
            contact(.trainer, .trainer, Binding(get: { model.draft.trainerId }, set: { model.draft.trainerId = $0; model.markTrainingEdited(.trainer) }))
        case .reason: text(.reason, $model.draft.reason, multiline: true)
        case .diagnosis: text(.diagnosis, $model.draft.diagnosis, multiline: true)
        case .recommendations: text(.recommendations, $model.draft.recommendations, multiline: true)
        case .vaccineOrProduct: text(.vaccineOrProduct, $model.draft.vaccineOrProduct)
        case .batchNumber: text(.batchNumber, $model.draft.batchNumber, caps: true)
        case .medications: medicationsInput
        case .hoofNotes: text(.hoofNotes, $model.draft.hoofNotes, multiline: true)
        case .bodyAreas: multi(.bodyAreas, .physioBodyArea, $model.draft.bodyAreaIds)
        case .techniques: multi(.techniques, .physioTechnique, $model.draft.techniqueIds)
        case .observations: text(.observations, $model.draft.observations, multiline: true)
        case .description: text(.description, $model.draft.descriptionText, multiline: true)
        case .cost: money(.cost, $model.draft.cost)
        case .trainingCost: money(.trainingCost, trainingCost)
        case .foreignAmount: foreignInput
        case .nextVisitDate:
            DateField(
                label(.nextVisitDate),
                date: Binding(get: { model.draft.nextVisitDate }, set: { model.draft.nextVisitDate = $0; model.markNextVisitEdited() }),
                defaultSelection: (model.draft.date ?? today).adding(days: 7)
            )
        case .nextVisitPurpose: text(.nextVisitPurpose, $model.draft.nextVisitPurpose)
        case .title: text(.title, $model.draft.title)
        case .content: text(.content, $model.draft.content, multiline: true)
        case .pinned: Toggle(label(.pinned), isOn: $model.draft.pinned)
        case .productName: text(.productName, $model.draft.productName)
        case .quantity:
            MoneyField(title: label(.quantity), text: $model.draft.quantity, suffix: nil, identifier: "entry-quantity")
                .onChange(of: model.draft.quantity) { _, _ in model.updateAmountSuggestion() }
        case .unitPrice:
            MoneyField(title: label(.unitPrice), text: $model.draft.unitPrice, identifier: "entry-unitPrice")
                .onChange(of: model.draft.unitPrice) { _, _ in model.updateAmountSuggestion() }
        case .amount:
            money(.amount, Binding(get: { model.draft.amount }, set: { model.draft.amount = $0; model.amountEditedManually() }))
        case .deliveryCost: money(.deliveryCost, $model.draft.deliveryCost)
        case .total:
            Text(tr("entry_total", model.purchaseTotal))
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("entry-total")
        case .assignment:
            Picker(selection: $model.draft.assignment) {
                ForEach(PurchaseAssignment.allCases, id: \.self) { Text(LocalizedStringKey($0.labelKey)).tag($0) }
            } label: {
                Text(label(.assignment))
            }
            .accessibilityIdentifier("entry-assignment")
        case .notes: text(.notes, $model.draft.notes, multiline: true)
        case .competitionChoice: competitionInput
        case .competitionName: text(.competitionName, $model.draft.competitionName)
        case .dateFrom: DateField(label(.dateFrom), date: $model.draft.dateFrom, defaultSelection: today)
        case .dateTo: DateField(label(.dateTo), date: $model.draft.dateTo, defaultSelection: model.draft.dateFrom ?? today)
        case .city: text(.city, $model.draft.city)
        case .venue: text(.venue, $model.draft.venue)
        case .className: text(.className, $model.draft.className)
        case .placement: IntegerField(title: label(.placement), text: $model.draft.placement, identifier: "entry-placement")
        case .participants: IntegerField(title: label(.participants), text: $model.draft.participants, identifier: "entry-participants")
        case .resultStatus:
            Picker(selection: $model.draft.resultStatus) {
                Text("dictionary_picker_not_selected").tag(ResultStatus?.none)
                ForEach(ResultStatus.allCases, id: \.self) { Text(LocalizedStringKey($0.labelKey)).tag(ResultStatus?.some($0)) }
            } label: {
                Text(label(.resultStatus))
            }
        case .rating:
            VStack(alignment: .leading, spacing: 0) {
                Text(label(.rating))
                StarRatingInput(rating: $model.draft.rating)
            }
        case .entryFee: money(.entryFee, $model.draft.entryFee)
        case .otherCosts: money(.otherCosts, $model.draft.otherCosts)
        case .prizeMoney: money(.prizeMoney, $model.draft.prizeMoney)
        case .penaltyPoints: MoneyField(title: label(.penaltyPoints), text: $model.draft.penaltyPoints, suffix: nil)
        case .scorePercent: MoneyField(title: label(.scorePercent), text: $model.draft.scorePercent, suffix: "%")
        case .timeSeconds: MoneyField(title: label(.timeSeconds), text: $model.draft.timeSeconds, suffix: nil)
        case .duration: IntegerField(title: label(.duration), text: $model.draft.duration, identifier: "entry-duration")
        case .intensity:
            Picker(selection: $model.draft.intensity) {
                Text("dictionary_picker_not_selected").tag(Intensity?.none)
                ForEach(Intensity.allCases, id: \.self) { Text(LocalizedStringKey($0.labelKey)).tag(Intensity?.some($0)) }
            } label: {
                Text(label(.intensity))
            }
        case .obstacleHeight: IntegerField(title: label(.obstacleHeight), text: $model.draft.obstacleHeight, identifier: "entry-obstacle")
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: model.draft.hour, minute: model.draft.minute)) ?? Date() },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                model.draft.hour = parts.hour ?? 0
                model.draft.minute = parts.minute ?? 0
            }
        )
    }

    /// Koń: wybór jednego konia; u kowala dodatkowo przełącznik „Kilka koni” (nowy wpis) zamieniający wybór na listę zaznaczeń.
    @ViewBuilder
    private var horseInput: some View {
        if model.kind == .farrier, !model.isEditing {
            Toggle("entry_many_toggle", isOn: $model.draft.manyHorses)
                .accessibilityIdentifier("entry-many-horses")
                .onChange(of: model.draft.manyHorses) { _, _ in model.applyFarrierSuggestion(horses: horses) }
        }
        if model.kind == .farrier, model.draft.manyHorses, !model.isEditing {
            MultiSelect(title: label(.horses), options: horseOptions, selection: $model.draft.horseIds, emptyText: tr("entry_pick_horses_none"), identifier: "entry-horses")
        } else {
            HorsePicker(title: label(.horse), horses: horses, selection: $model.draft.horseId, identifier: "entry-horse")
                .onChange(of: model.draft.horseId) { _, _ in Task { await model.horseChanged(using: environment) } }
        }
    }

    private var foreignInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            MoneyField(title: label(.foreignAmount), text: $model.draft.originalAmount, suffix: nil, identifier: "entry-originalAmount")
            TextRow(title: "field_original_currency", text: $model.draft.originalCurrency, capitalization: .characters, identifier: "entry-originalCurrency")
        }
    }

    private var medicationsInput: some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            Text(label(.medications)).font(.subheadline.weight(.semibold))
            ForEach($model.draft.medications) { $medication in
                let index = model.draft.medications.firstIndex { $0.id == medication.id } ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("entry_medication_title", index + 1)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                    TextRow(title: "entry_medication_name", text: $medication.name, required: true, identifier: "entry-medication-name-\(index)")
                    TextRow(title: "entry_medication_dosage", text: $medication.dosage, identifier: "entry-medication-dosage-\(index)")
                    Picker(selection: $medication.administration) {
                        Text("dictionary_picker_not_selected").tag(MedicationMode?.none)
                        ForEach(MedicationMode.allCases, id: \.self) { Text(LocalizedStringKey($0.labelKey)).tag(MedicationMode?.some($0)) }
                    } label: {
                        Text("field_medications")
                    }
                    ForEach(model.medicationErrors(at: index), id: \.self) { message in
                        Label { Text(message).font(.footnote) } icon: { HIcon(name: "warning", size: 16) }.foregroundStyle(HorselyColor.error)
                    }
                    Button(role: .destructive) {
                        model.draft.medications.removeAll { $0.id == medication.id }
                    } label: {
                        Text("entry_medication_remove").frame(minHeight: Spacing.minTouchTarget)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                model.draft.medications.append(MedicationDraft())
            } label: {
                Label {
                    Text("entry_medication_add")
                } icon: {
                    HIcon(name: "add", size: 20)
                }
                .frame(minHeight: Spacing.minTouchTarget, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("entry-medication-add")
        }
    }

    /// Start w zawodach: istniejące zawody albo „Nowe zawody” (nazwa, data, miejscowość) tworzone razem ze startem.
    @ViewBuilder
    private var competitionInput: some View {
        if let start = model.editing as? LocalCompetitionStart {
            LabeledContent {
                Text(model.competitions.first { $0.id == start.competitionId }?.name ?? Formats.dash).foregroundStyle(HorselyColor.onSurfaceVariant)
            } label: {
                Text(label(.competitionChoice))
            }
        } else {
            Picker(selection: $model.draft.newCompetition) {
                Text("entry_competition_existing").tag(false)
                Text("entry_competition_new").tag(true)
            } label: {
                Text(label(.competitionChoice))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("entry-competition-mode")
            if model.draft.newCompetition {
                TextRow(title: "entry_competition_name", text: $model.draft.competitionName, required: true, identifier: "entry-competition-name")
                DateField("entry_competition_date_from", date: $model.draft.dateFrom, defaultSelection: today)
                TextRow(title: "entry_competition_city", text: $model.draft.city, identifier: "entry-competition-city")
            } else if model.competitions.isEmpty {
                Text("entry_competition_offline").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
            } else {
                Picker(selection: $model.draft.competitionId) {
                    Text("dictionary_picker_not_selected").tag(String?.none)
                    ForEach(model.competitions) { competition in
                        Text("\(competition.name) · \(Formats.date(competition.dateFrom))").tag(String?.some(competition.id))
                    }
                } label: {
                    Text("entry_competition_pick")
                }
                .accessibilityIdentifier("entry-competition-pick")
            }
        }
    }
}
