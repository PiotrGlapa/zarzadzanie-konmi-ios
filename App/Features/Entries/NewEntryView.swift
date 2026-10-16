import HorselyCore
import HorselyKit
import SwiftUI

/// Prośba o nowy wpis z dowolnego miejsca aplikacji („+”, szybkie dodawanie na Pulpicie, karta konia, adres `horsely://`):
/// brakujące kroki (rodzaj, koń) pyta `NewEntryView`.
struct EntryRequest: Identifiable, Equatable {
    let id = UUID()
    /// Rodzaj formularza; `nil` — użytkownik wybiera.
    var kind: FormKind?
    /// Termin zamiast wpisu (`kind` jest wtedy `nil`).
    var isReminder = false
    var horseId: String?
    /// Kowal „Kilka koni”.
    var manyHorses = false
    /// Z terminu: „Zarejestruj wizytę” (koń, dzisiejsza data, rodzaj specjalisty).
    var prefill: FormPrefill?
    /// „Powtórz zakup”.
    var repeating: LocalPurchase?

    static func == (lhs: EntryRequest, rhs: EntryRequest) -> Bool { lhs.id == rhs.id }

    /// Ta sama prośba z nowym identyfikatorem (kolejne otwarcie arkusza).
    func renewed() -> EntryRequest {
        var copy = EntryRequest()
        copy.kind = kind
        copy.isReminder = isReminder
        copy.horseId = horseId
        copy.manyHorses = manyHorses
        copy.prefill = prefill
        copy.repeating = repeating
        return copy
    }
}

extension FormKind {
    init?(prefill form: EntryForm) {
        switch form {
        case .vetVisit: self = .vet
        case .farrierVisit: self = .farrier
        case .physioVisit: self = .physio
        case .specialistVisit: self = .specialist
        case .competitionStart: self = .start
        case .note: self = .note
        }
    }
}

/// „Nowy wpis” (FR-M-WPI): rodzaj (ikony i kolory rodzajów, linie między wierszami) → koń (ostatnio używane na górze, u kowala
/// także „Kilka koni”) → formularz. Kroki znane z prośby są pomijane.
struct NewEntryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var request: EntryRequest
    @State private var recentIds: [String] = []
    @State private var form: EntryFormModel?
    @State private var showingReminder = false
    let onSaved: (EntrySaved, Bool) -> Void

    init(request: EntryRequest, onSaved: @escaping (EntrySaved, Bool) -> Void) {
        self._request = State(initialValue: request)
        self.onSaved = onSaved
    }

    private var horses: [LocalHorse] { HorseSearch.apply(environment.horseDirectory.horses, query: "", filter: .inStable) }

    var body: some View {
        Group {
            if let form {
                EntryFormView(model: form, onSaved: onSaved)
            } else if showingReminder {
                ReminderFormView(reminder: nil, horseId: request.horseId) { saved in onSaved(saved, false) }
            } else {
                NavigationStack {
                    stepContent
                        .navigationDestination(for: FormKind.self) { kind in horseStep(kind: kind, reminder: false) }
                        .navigationDestination(for: String.self) { _ in horseStep(kind: nil, reminder: true) }
                        .background(HorselyColor.background)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(tr("common_close")) { dismiss() }.accessibilityIdentifier("new-entry-close")
                            }
                        }
                }
                .tint(HorselyColor.primary)
            }
        }
        .task { await start() }
    }

    // MARK: Kroki

    @ViewBuilder
    private var stepContent: some View {
        if let kind = request.kind, request.horseId == nil, kind.asksForHorse {
            horseStep(kind: kind, reminder: false)
        } else if request.isReminder, request.horseId == nil {
            horseStep(kind: nil, reminder: true)
        } else if let kind = request.kind, !kind.asksForHorse {
            ProgressView()
        } else {
            kindStep
        }
    }

    private var kindStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("entry_new_choose_kind").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
                    .padding(.top, Spacing.between).padding(.bottom, Spacing.between)
                DividedList(FormKind.creatable) { kind in
                    kindRow(kind)
                }
                DividerLine()
                reminderRow
            }
            .padding(.horizontal, Spacing.screenEdge)
        }
        .navigationTitle("entry_new_title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func kindRow(_ kind: FormKind) -> some View {
        NavigationLink(value: kind) {
            HStack(spacing: Spacing.between + 4) {
                AccentIcon(kind.accent)
                Text(LocalizedStringKey(kind.titleKey)).foregroundStyle(HorselyColor.onBackground)
                Spacer()
            }
            .frame(minHeight: Spacing.minTouchTarget + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-entry-kind-\(kind.rawValue)")
    }

    private var reminderRow: some View {
        NavigationLink(value: "reminder") {
            HStack(spacing: Spacing.between + 4) {
                AccentIcon(SectionAccent.reminders)
                Text("entry_new_reminder").foregroundStyle(HorselyColor.onBackground)
                Spacer()
            }
            .frame(minHeight: Spacing.minTouchTarget + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-entry-kind-reminder")
    }

    /// Wybór konia: ostatnio używane na górze, reszta po imieniu; u kowala pierwszy wiersz „Kilka koni”.
    private func horseStep(kind: FormKind?, reminder: Bool) -> some View {
        let recent = recentIds.compactMap { id in horses.first { $0.id == id } }
        let rest = horses.filter { horse in !recentIds.contains(horse.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("entry_new_choose_horse").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
                    .padding(.top, Spacing.between).padding(.bottom, Spacing.between)
                if kind == .farrier {
                    manyRow
                    DividerLine()
                }
                DividedList(recent + rest) { horse in
                    Button {
                        choose(horse: horse, kind: kind, reminder: reminder)
                    } label: {
                        HStack(spacing: Spacing.between + 4) {
                            HorseAvatar(photo: environment.horseDirectory.thumbnail(for: horse), diameter: 40)
                            Text(horse.name).foregroundStyle(HorselyColor.onBackground)
                            Spacer()
                        }
                        .frame(minHeight: Spacing.minTouchTarget + 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("new-entry-horse-\(horse.name)")
                }
                if horses.isEmpty {
                    Text("horses_empty_title").foregroundStyle(HorselyColor.onSurfaceVariant).padding(.vertical, 32).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Spacing.screenEdge)
        }
        .navigationTitle(kind.map { LocalizedStringKey($0.titleKey) } ?? "entry_new_reminder")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var manyRow: some View {
        Button {
            open(.farrier, horseId: nil, many: true)
        } label: {
            HStack(spacing: Spacing.between + 4) {
                AccentIcon(EntryAccent.farrier)
                Text("entry_many_toggle").foregroundStyle(HorselyColor.onBackground)
                Spacer()
            }
            .frame(minHeight: Spacing.minTouchTarget + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-entry-many-horses")
    }

    private func choose(horse: LocalHorse, kind: FormKind?, reminder: Bool) {
        if reminder {
            request.horseId = horse.id
            showingReminder = true
        } else if let kind {
            open(kind, horseId: horse.id, many: false)
        }
    }

    private func open(_ kind: FormKind, horseId: String?, many: Bool) {
        let model = EntryFormModel(kind: kind, horseId: horseId, today: environment.dates.today(), now: environment.dates.now())
        model.draft.manyHorses = many
        if let prefill = request.prefill {
            model.draft.date = prefill.date
            if let specialist = prefill.specialistTypeId { model.draft.specialistTypeId = specialist }
        }
        form = model
    }

    private func start() async {
        recentIds = (try? await environment.entries.recentHorseIds()) ?? []
        if let repeating = request.repeating {
            form = EntryFormModel.repeating(repeating, today: environment.dates.today(), now: environment.dates.now())
            return
        }
        if request.isReminder, request.horseId != nil {
            showingReminder = true
            return
        }
        guard let kind = request.kind else { return }
        if !kind.asksForHorse || request.horseId != nil || request.manyHorses {
            open(kind, horseId: request.horseId, many: request.manyHorses)
        }
    }
}
