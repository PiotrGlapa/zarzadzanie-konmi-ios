import HorselyCore
import HorselyKit
import SwiftUI
import UserNotifications

/// Ekran wyboru trybu pracy przy pierwszym uruchomieniu (FR-TRB-02, wariant B): pełna nazwa jako tytuł, pytanie, dwie opcje z opisami
/// (domyślnie „Tak, połącz z programem”), „Dalej” i informacja o Ustawieniach; po wyborze trybu samodzielnego także „Odtwórz z kopii
/// zapasowej”. Tryb online zostaje zapamiętany dopiero po udanym parowaniu (faza 5); samodzielny — po zgodzie na powiadomienia.
struct ModeChoiceView: View {
    @Environment(AppEnvironment.self) private var environment

    private enum Choice { case online, standalone }
    private enum Step { case choice, notifications, pairing }

    @State private var choice: Choice = .online
    @State private var step: Step = .choice
    @State private var restoring = false

    var body: some View {
        switch step {
        case .choice: choiceScreen
        case .notifications: NotificationsRationaleView(onContinue: finishStandalone)
        case .pairing: PairingFlowView(purpose: .firstRun, onFinish: { step = .choice })
        }
    }

    private var choiceScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.beforeSection) {
                Text(tr("mode_choice_title"))
                    .font(.title.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("mode_choice_question")
                    .font(.headline)
                VStack(spacing: Spacing.between) {
                    optionRow(.online, title: "mode_choice_online", hint: "mode_choice_online_hint")
                    optionRow(.standalone, title: "mode_choice_standalone", hint: "mode_choice_standalone_hint")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(tr("mode_choice_group"))

                if choice == .standalone {
                    // Odtworzenie kopii (także z Androida) od razu kończy wybór: tryb samodzielny z danymi z kopii.
                    Button { restoring = true } label: {
                        Text("mode_choice_restore").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                    }
                    .buttonStyle(.bordered)
                    .tint(HorselyColor.primary)
                    .accessibilityIdentifier("mode-restore")
                }

                Button(action: next) {
                    Text("mode_choice_next").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.primaryFilled)
                .tint(HorselyColor.primary)
                .accessibilityIdentifier("mode-next")

                Text("mode_choice_later")
                    .font(.footnote)
                    .foregroundStyle(HorselyColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(Spacing.screenEdge)
        }
        .background(HorselyColor.background)
        .sheet(isPresented: $restoring) {
            RestoreBackupFlow { finishStandalone() }.environment(environment)
        }
    }

    private func optionRow(_ option: Choice, title: LocalizedStringKey, hint: LocalizedStringKey) -> some View {
        let selected = choice == option
        return Button {
            choice = option
        } label: {
            HStack(alignment: .top, spacing: Spacing.between + 4) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? HorselyColor.primary : HorselyColor.onSurfaceVariant)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                    Text(hint).font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.cardPadding)
            .frame(minHeight: Spacing.minTouchTarget)
            .background(selected ? HorselyColor.primaryContainer.opacity(0.5) : Color.clear, in: RoundedRectangle(cornerRadius: Spacing.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cardRadius)
                    .strokeBorder(selected ? HorselyColor.primary : HorselyColor.outlineVariant, lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(option == .online ? "mode-online" : "mode-standalone")
    }

    private func next() {
        switch choice {
        case .online: step = .pairing
        case .standalone: step = .notifications
        }
    }

    private func finishStandalone() {
        // Pierwsza kopia ma 7 dni na pierwsze dane (jak w Androidzie) — przypomnienie nie pojawia się od razu.
        environment.settings.backupReminderSnoozedUntil = BackupPolicy.stamp(Date().addingTimeInterval(BackupPolicy.interval))
        environment.workMode = .standalone
        environment.router.resumeDeferred(mode: .standalone)
    }
}

/// Zgoda na powiadomienia z wyjaśnieniem (tryb samodzielny, po „Dalej”): prośba systemowa pojawia się dopiero po dotknięciu „Dalej”;
/// odmowa nie blokuje aplikacji (powiadomienia można włączyć później w Ustawieniach).
private struct NotificationsRationaleView: View {
    let onContinue: () -> Void
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.beforeSection) {
            Spacer()
            AccentIcon(icon: "event", color: SectionAccent.reminders.color, diameter: 72)
            Text("notif_permission_title").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("notif_permission_text").font(.body).foregroundStyle(HorselyColor.onSurfaceVariant)
            Spacer()
            Button {
                guard !asking else { return }
                asking = true
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    onContinue()
                }
            } label: {
                Text("mode_choice_next").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.primaryFilled)
            .tint(HorselyColor.primary)
            .disabled(asking)
            .accessibilityIdentifier("notifications-next")
        }
        .padding(Spacing.screenEdge)
        .background(HorselyColor.background)
    }
}

