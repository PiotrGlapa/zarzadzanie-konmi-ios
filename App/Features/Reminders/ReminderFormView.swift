import HorselyCore
import HorselyKit
import SwiftUI

/// Formularz terminu (FR-M-TER): Podstawowe (koń, rodzaj, termin, tytuł, typ specjalisty) · Uwagi (notatka). `reminder = nil` — nowy.
struct ReminderFormView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    private let editing: ReminderItem?
    @State private var input: ReminderInput
    @State private var baseline: ReminderInput
    @State private var errors: [String: [String]] = [:]
    @State private var failure: String?
    @State private var isSaving = false
    @State private var confirmingDiscard = false
    @State private var specialistTypes: [LocalDictionaryItem] = []
    let onSaved: (EntrySaved) -> Void

    init(reminder: ReminderItem?, horseId: String?, onSaved: @escaping (EntrySaved) -> Void) {
        self.editing = reminder
        self.onSaved = onSaved
        var input = ReminderInput()
        if let reminder {
            input.horseId = reminder.horseId
            input.kind = reminder.kind
            input.dueDate = reminder.dueDate
            input.title = reminder.title
            input.specialistTypeId = reminder.specialistTypeId
            input.notes = reminder.notes
        } else {
            input.horseId = horseId
            input.kind = .other
        }
        self._input = State(initialValue: input)
        self._baseline = State(initialValue: input)
    }

    private var today: LocalDate { environment.dates.today() }
    private var horses: [LocalHorse] { environment.horseDirectory.horses }

    private var titleBinding: Binding<String> {
        Binding(get: { input.title ?? "" }, set: { input.title = $0 })
    }

    private var notesBinding: Binding<String> {
        Binding(get: { input.notes ?? "" }, set: { input.notes = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("horseId") {
                        HorsePicker(title: "reminder_detail_horse", horses: horses, selection: $input.horseId, identifier: "reminder-horse")
                    }
                    field("kind") {
                        Picker(selection: Binding(get: { input.kind ?? .other }, set: { input.kind = $0 })) {
                            ForEach(ReminderKind.allCases, id: \.self) { Text(LocalizedStringKey($0.labelKey)).tag($0) }
                        } label: {
                            Text("reminder_form_kind")
                        }
                        .accessibilityIdentifier("reminder-kind")
                    }
                    if input.kind == .specialist {
                        field("specialistTypeId") {
                            DictionaryPicker(title: "reminder_form_specialist_type", items: specialistTypes, selection: $input.specialistTypeId, identifier: "reminder-specialist")
                        }
                    }
                    field("dueDate") {
                        DateField("reminder_form_date", date: $input.dueDate, defaultSelection: today)
                    }
                    field("title") {
                        TextRow(title: "reminder_form_title_field", text: titleBinding, required: true, identifier: "reminder-title")
                    }
                } header: {
                    Text("form_section_basic")
                }
                Section {
                    TextRow(title: "reminder_form_notes", text: notesBinding, multiline: true, identifier: "reminder-notes")
                } header: {
                    Text("form_section_notes")
                }
                if let failure {
                    Section { Text(failure).foregroundStyle(HorselyColor.error) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HorselyColor.background)
            .navigationTitle(editing == nil ? "reminder_form_title_new" : "reminder_form_title_edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("common_close")) { close() }.accessibilityIdentifier("reminder-form-close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                FormSaveBar(isSaving: isSaving) { save() }.accessibilityIdentifier("reminder-form-save")
            }
            .confirmationDialog(tr("common_discard_title"), isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button(tr("common_discard_confirm"), role: .destructive) { dismiss() }
                Button(tr("common_discard_keep"), role: .cancel) {}
            } message: {
                Text("common_discard_message")
            }
            .task {
                if editing == nil, input.dueDate == nil {
                    input.dueDate = today
                    baseline.dueDate = today
                }
                await environment.prepareStore()
                specialistTypes = ((try? await environment.entries.allDictionaryItems()) ?? []).filter { $0.dictionaryType == .specialistType }
            }
        }
        .tint(HorselyColor.primary)
        .interactiveDismissDisabled(input != baseline)
    }

    private func close() {
        if input != baseline { confirmingDiscard = true } else { dismiss() }
    }

    private func field<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            ForEach(errors[key] ?? [], id: \.self) { message in
                Label {
                    Text(message).font(.footnote)
                } icon: {
                    HIcon(name: "warning", size: 16)
                }
                .foregroundStyle(HorselyColor.error)
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errors = [:]
        failure = nil
        let input = self.input
        let id = editing?.id
        let version = editing?.version ?? 0
        Task {
            defer { isSaving = false }
            do {
                let result = try await environment.entries.perform { id == nil ? $0.createReminder(input) : $0.updateReminder(id: id!, input, expectedVersion: version) }
                switch result {
                case let .saved(saved):
                    onSaved(saved)
                    dismiss()
                case let .rejected(problem):
                    if case let .validation(fieldErrors, _) = problem { errors = fieldErrors } else { failure = problem.message }
                }
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
