import HorselyCore
import HorselyKit
import SwiftUI

/// Szczegóły terminu (FR-M-TER-03): rodzaj, koń, termin, status, notatka i akcje — Zarejestruj wizytę · Zrealizowany · Odrzuć ·
/// Przełóż · Edytuj · Usuń. Akcje na terminie otwartym; „Zarejestruj wizytę” otwiera formularz właściwego rodzaju z koniem i dzisiejszą datą.
struct ReminderDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let reminderId: String
    @State private var reminder: ReminderItem?
    @State private var isLoaded = false
    @State private var editing = false
    @State private var postponing = false
    @State private var postponeDate: LocalDate?
    @State private var confirmingDelete = false
    @State private var banner: BannerMessage?

    private var today: LocalDate { environment.dates.today() }

    var body: some View {
        Group {
            if let reminder {
                content(reminder)
            } else if isLoaded {
                Text("reminder_detail_not_found").multilineTextAlignment(.center).padding(Spacing.screenEdge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(HorselyColor.background)
        .navigationTitle("reminder_detail_title")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: environment.dataRevision) { await load() }
        .overlay(alignment: .bottom) {
            if let banner {
                SaveBanner(message: banner.text, undo: banner.undo) { self.banner = nil }.padding(.bottom, Spacing.between)
            }
        }
        .animation(.default, value: banner)
    }

    private func load() async {
        reminder = try? await environment.reminders.reminder(id: reminderId)
        isLoaded = true
    }

    private func content(_ reminder: ReminderItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.between) {
                InfoCard(tone: reminder.isOverdue && reminder.status == .open ? .warning : .neutral) {
                    ReminderContent(reminder: reminder, today: today)
                }
                .padding(.top, Spacing.between)
                detailRow("reminder_detail_horse", reminder.horseName ?? Formats.dash)
                detailRow("reminder_detail_kind", reminder.kind == .specialist ? (reminder.specialistTypeName ?? tr(reminder.kind.labelKey)) : tr(reminder.kind.labelKey))
                detailRow("reminder_detail_status", tr(reminder.status.labelKey))
                if let notes = HorseRules.clean(reminder.notes) { detailRow("reminder_detail_notes", notes) }
                if reminder.status == .open { actions(reminder) }
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.bottom, Spacing.addButtonClearance)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(tr("reminder_action_edit")) { editing = true }.accessibilityIdentifier("reminder-edit")
            }
        }
        .sheet(isPresented: $editing) {
            ReminderFormView(reminder: reminder, horseId: nil) { saved in
                banner = BannerMessage(text: tr("entry_updated")) { Task { try? await environment.entries.undo(saved.undo) } }
            }
        }
        .sheet(isPresented: $postponing) { postponeSheet(reminder) }
        .confirmationDialog(tr("reminder_delete_title"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(tr("reminder_action_delete"), role: .destructive) { delete(reminder) }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text("reminder_delete_message")
        }
    }

    private func detailRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
            Text(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func actions(_ reminder: ReminderItem) -> some View {
        VStack(spacing: Spacing.between) {
            Button {
                register(reminder)
            } label: {
                Text("reminder_action_register").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.primaryFilled)
            .tint(HorselyColor.primary)
            .accessibilityIdentifier("reminder-register")
            HStack(spacing: Spacing.between) {
                action("reminder_action_complete", id: "reminder-complete") { await complete(reminder) }
                action("reminder_action_dismiss", id: "reminder-dismiss") { await dismissReminder(reminder) }
            }
            HStack(spacing: Spacing.between) {
                action("reminder_action_postpone", id: "reminder-postpone") {
                    postponeDate = reminder.dueDate
                    postponing = true
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Text("reminder_action_delete").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reminder-delete")
            }
        }
        .padding(.top, Spacing.between)
    }

    private func action(_ title: LocalizedStringKey, id: String, perform: @escaping () async -> Void) -> some View {
        Button {
            Task { await perform() }
        } label: {
            Text(title).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
        }
        .buttonStyle(.bordered)
        .tint(HorselyColor.primary)
        .accessibilityIdentifier(id)
    }

    private func postponeSheet(_ reminder: ReminderItem) -> some View {
        NavigationStack {
            Form {
                DateField("reminder_postpone_title", date: $postponeDate, defaultSelection: today)
            }
            .navigationTitle("reminder_postpone_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common_cancel")) { postponing = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("common_save")) {
                        guard let date = postponeDate else { return }
                        postponing = false
                        Task { await postpone(reminder, to: date) }
                    }
                    .disabled(postponeDate == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Akcje

    private func register(_ reminder: ReminderItem) {
        let prefill = ReminderFormMapping.prefill(for: reminder, today: today)
        environment.router.entryRequest = EntryRequest(kind: FormKind(prefill: prefill.form), horseId: prefill.horseId, prefill: prefill)
    }

    private func complete(_ reminder: ReminderItem) async {
        await finish(try? await environment.reminders.complete(id: reminder.id), message: tr("reminder_status_completed"))
    }

    private func dismissReminder(_ reminder: ReminderItem) async {
        await finish(try? await environment.reminders.dismiss(id: reminder.id), message: tr("reminder_status_dismissed"))
    }

    private func postpone(_ reminder: ReminderItem, to date: LocalDate) async {
        await finish(try? await environment.reminders.postpone(reminder, to: date), message: tr("reminder_postponed"))
    }

    private func delete(_ reminder: ReminderItem) {
        Task {
            if let saved = (try? await environment.reminders.delete(id: reminder.id))?.saved {
                environment.router.banner = BannerMessage(text: tr("reminder_deleted")) { Task { try? await environment.entries.undo(saved.undo) } }
                dismiss()
            }
        }
    }

    private func finish(_ result: EntryResult?, message: String) async {
        guard let saved = result?.saved else {
            banner = BannerMessage(text: tr("reminder_already_handled"), undo: nil)
            return
        }
        banner = BannerMessage(text: message) { Task { try? await environment.entries.undo(saved.undo) } }
        await load()
    }
}

/// Komunikat u dołu ekranu z opcjonalnym „Cofnij”.
struct BannerMessage: Equatable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?

    init(text: String, undo: (() -> Void)? = nil) {
        self.text = text
        self.undo = undo
    }

    static func == (lhs: BannerMessage, rhs: BannerMessage) -> Bool { lhs.id == rhs.id }
}
