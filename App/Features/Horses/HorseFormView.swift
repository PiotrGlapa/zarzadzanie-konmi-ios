import HorselyCore
import SwiftUI

/// Formularz konia (FR-M-KON-03): sekcje Podstawowe · Szczegóły · „Kwoty konia (ocena własna)”, pole „Zdjęcie”, status z datą i
/// notatką (także „Kontuzjowany”), błędy reguł programu przy polach, „Zapisz” przypięte do dołu, potwierdzenie porzucenia zmian
/// (przycisk „Zamknij”, gest zsunięcia arkusza). `horseId = nil` — nowy koń.
struct HorseFormView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var model: HorseFormModel
    @State private var confirmingDiscard = false
    @State private var showingPhotoSheet = false
    let onSaved: () -> Void

    init(horse: LocalHorse?, onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        self._model = State(initialValue: HorseFormModel(horse: horse))
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                detailsSection
                financeSection
                if let failure = model.failure {
                    Section { Text(failure).foregroundStyle(HorselyColor.error) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(HorselyColor.background)
            .navigationTitle(model.isEditing ? "horse_form_title_edit" : "horse_form_title_new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("common_close")) { close() }.accessibilityIdentifier("horse-form-close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                FormSaveBar(isSaving: model.isSaving) {
                    Task {
                        if await model.save(using: environment) {
                            onSaved()
                            dismiss()
                        }
                    }
                }
                .accessibilityIdentifier("horse-form-save")
            }
            .confirmationDialog(tr("common_discard_title"), isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button(tr("common_discard_confirm"), role: .destructive) { dismiss() }
                Button(tr("common_discard_keep"), role: .cancel) {}
            } message: {
                Text("common_discard_message")
            }
            .sheet(isPresented: $showingPhotoSheet) {
                HorsePhotoSheet(horse: model.horse, hasPhoto: hasPhoto, context: .form) { result in
                    switch result {
                    case let .picked(image): model.pendingPhoto = image; model.pendingPhotoRemoval = false
                    case .removed: model.pendingPhoto = nil; model.pendingPhotoRemoval = true
                    case .chosenFromAttachments: break
                    }
                }
            }
        }
        .tint(HorselyColor.primary)
        .interactiveDismissDisabled(model.isDirty)
    }

    private var today: LocalDate { environment.dates.today() }

    private var hasPhoto: Bool {
        model.pendingPhoto != nil || (model.horse?.photoAttachmentId != nil && !model.pendingPhotoRemoval)
    }

    private func close() {
        if model.isDirty { confirmingDiscard = true } else { dismiss() }
    }

    // MARK: Sekcje

    private var basicSection: some View {
        Section {
            textField("horse_form_name", text: $model.draft.name, key: "name", capitalization: .words, required: true, identifier: "horse-name")
            Toggle("horse_form_foal", isOn: $model.draft.isFoal).accessibilityIdentifier("horse-foal")
            textField(
                "horse_form_passport", text: $model.draft.passportNumber, key: "passportNumber", capitalization: .characters,
                required: !model.draft.isFoal, identifier: "horse-passport", noAutocorrect: true
            )
            textField("horse_form_stable_name", text: $model.draft.stableName, key: "stableName", capitalization: .words)
            Picker("horse_form_sex", selection: $model.draft.sex) {
                Text("horse_form_sex_none").tag(Sex?.none)
                ForEach(Sex.allCases, id: \.self) { Text(LocalizedStringKey($0.labelKey)).tag(Sex?.some($0)) }
            }
            textField("horse_form_breed", text: $model.draft.breed, key: "breed", capitalization: .words)
            textField("horse_form_color", text: $model.draft.color, key: "color", capitalization: .words)
            fieldWithErrors("birthDate") {
                DateField("horse_form_birth_date", date: $model.draft.birthDate, maximum: today, defaultSelection: today)
            }
            if model.draft.birthDate != nil {
                Toggle("horse_form_birth_year_only", isOn: $model.draft.birthYearOnly)
            }
            photoRow
        } header: {
            Text("form_section_basic")
        }
    }

    private var detailsSection: some View {
        Section {
            textField("horse_form_ueln", text: $model.draft.ueln, key: "ueln", capitalization: .characters, noAutocorrect: true)
            textField("horse_form_microchip", text: $model.draft.microchipNumber, key: "microchipNumber", keyboard: .numbersAndPunctuation)
            textField("horse_form_farrier_interval", text: $model.intervalText, key: "farrierIntervalWeeks", keyboard: .numberPad, identifier: "horse-interval")
            Picker("horse_form_status", selection: $model.draft.status) {
                ForEach(HorseStatus.allCases, id: \.self) { Text(LocalizedStringKey($0.labelKey)).tag($0) }
            }
            .accessibilityIdentifier("horse-status")
            if model.draft.status != .active {
                fieldWithErrors("statusDate") {
                    DateField("horse_form_status_date", date: $model.draft.statusDate, maximum: today, defaultSelection: today)
                }
            }
            textField("entry_kind_note", text: $model.draft.statusNote, key: "statusNote")
            textField("form_section_notes", text: $model.draft.notes, key: "notes")
        } header: {
            Text("form_section_details")
        }
    }

    private var financeSection: some View {
        Section {
            moneyField("horse_form_purchase_price", text: $model.purchasePriceText, key: "finance.purchasePrice")
            fieldWithErrors("finance.purchaseDate") {
                DateField("horse_form_purchase_date", date: financeDate($model.purchaseDate), maximum: today, defaultSelection: today)
            }
            moneyField("horse_form_sale_price", text: $model.salePriceText, key: "finance.salePrice")
            fieldWithErrors("finance.saleDate") {
                DateField("horse_form_sale_date", date: financeDate($model.saleDate), maximum: today, defaultSelection: today)
            }
            moneyField("horse_form_estimated_value", text: $model.estimatedValueText, key: "finance.estimatedValue")
        } header: {
            Text("horse_form_finance_title")
        } footer: {
            Text("horse_form_finance_hint")
        }
    }

    private var photoRow: some View {
        Button {
            showingPhotoSheet = true
        } label: {
            HStack {
                Text("photo_field_label").foregroundStyle(HorselyColor.onBackground)
                Spacer()
                if model.pendingPhoto != nil {
                    Text("photo_pending_hint").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                } else {
                    Text(hasPhoto ? "photo_change" : "photo_add").foregroundStyle(HorselyColor.primary)
                }
            }
            .frame(minHeight: Spacing.minTouchTarget)
        }
        .accessibilityIdentifier("horse-photo")
    }

    // MARK: Pola

    private func financeDate(_ binding: Binding<LocalDate?>) -> Binding<LocalDate?> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0; model.markFinanceTouched() })
    }

    private func textField(
        _ title: LocalizedStringKey, text: Binding<String>, key: String, label: LocalizedStringKey? = nil,
        capitalization: TextInputAutocapitalization = .sentences, keyboard: UIKeyboardType = .default, required: Bool = false, identifier: String? = nil,
        noAutocorrect: Bool = false
    ) -> some View {
        fieldWithErrors(key) {
            LabeledContent {
                TextField("", text: text, prompt: required ? Text("common_required") : nil)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(capitalization)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled(keyboard != .default || noAutocorrect)
                    .accessibilityIdentifier(identifier ?? key)
            } label: {
                Text(label ?? title)
            }
        }
    }

    private func moneyField(_ title: LocalizedStringKey, text: Binding<String>, key: String) -> some View {
        fieldWithErrors(key) {
            LabeledContent {
                TextField("", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; model.markFinanceTouched() }))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
            } label: {
                Text(title)
            }
        }
    }

    /// Pole z komunikatami reguł pod spodem (kolor błędu + ikona, informacja nigdy tylko kolorem).
    private func fieldWithErrors<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            ForEach(model.errors(for: key), id: \.self) { message in
                Label {
                    Text(message).font(.footnote)
                } icon: {
                    HIcon(name: "warning", size: 16)
                }
                .foregroundStyle(HorselyColor.error)
                .accessibilityLabel(message)
            }
            ForEach(model.warnings[key] ?? [], id: \.self) { message in
                Label {
                    Text(message).font(.footnote)
                } icon: {
                    HIcon(name: "info", size: 16)
                }
                .foregroundStyle(HorselyColor.warning)
            }
        }
    }
}
