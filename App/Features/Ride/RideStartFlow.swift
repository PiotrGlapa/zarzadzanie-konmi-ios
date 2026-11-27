import HorselyCore
import HorselyKit
import SwiftUI
import UIKit
import UserNotifications

// Start nagrywania jazdy (Task 17 = Android 3.0.2 `RideStartFlow.kt`, NAG-02…NAG-04): koń → instrukcja noszenia (NAG-03 dosłownie,
// „Nie pokazuj więcej”) → dokładna lokalizacja „Podczas używania” (odmowa / przybliżona: wyjaśnienie z „Otwórz ustawienia”) → start.
// Kolejność i pomijanie kroków — `RideStartPolicy` (HorselyKit). Jedno nagrywanie naraz: gdy jazda już trwa, ekran otwiera nagrywanie,
// a gdy czeka niezakończona — pyta „Zapisz / Odrzuć” zamiast zakładać drugą sesję.
//
// Różnice względem Androida: bez kroku optymalizacji baterii; o zgodę na powiadomienia (ostrzeżenia: bateria, słaby GPS, 8 h, przerwanie —
// `SystemRideAlertPoster` bez zgody nic nie pokazuje) aplikacja pyta systemem tuż przed pierwszym startem, tylko gdy jeszcze nie pytała —
// bez osobnego ekranu, bo tekst Androida (`ride_notifications_text`) opisuje stałe powiadomienie usługi, którego na iOS nie ma.

/// Stan i przejścia ekranu startu (Android `RideStartViewModel`). Przejścia nie biegną równolegle (`busy`): szybkie powtórne dotknięcie albo
/// spóźniona odpowiedź systemu nie założy drugiej sesji.
@MainActor
@Observable
final class RideStartModel {
    private(set) var step: RideStartStep = .checking
    private(set) var horses: [LocalHorse] = []
    var horseId: String?
    private(set) var fromCard = false
    var dontShowAgain = false
    private(set) var failed = false
    /// Niezakończona jazda — pytanie „Zapisz / Odrzuć”.
    var recoveryPrompt: UnfinishedRide?
    /// Sesja założona — ekran przechodzi do nagrywania.
    private(set) var startedSessionId: String?
    /// Jazda już trwa — ekran przechodzi do nagrywania bez drugiego startu.
    private(set) var opened = false
    /// „Zapisz” na odzyskiwanej jeździe — ekran zakończenia.
    private(set) var finishSessionId: String?

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let preselectedHorseId: String?
    @ObservationIgnored private let preview: Bool
    /// Tworzony dopiero przy pierwszym użyciu (krok lokalizacji): menedżer lokalizacji nie powstaje w stanach podglądu (migawki) ani przed
    /// pytaniem o zgodę.
    @ObservationIgnored private var permissionRequester: LocationPermissionRequester?
    private var permission: LocationPermissionRequester {
        if let permissionRequester { return permissionRequester }
        let created = LocationPermissionRequester()
        permissionRequester = created
        return created
    }
    @ObservationIgnored private var busy = false

    init(environment: AppEnvironment, preselectedHorseId: String?) {
        self.environment = environment
        self.preselectedHorseId = preselectedHorseId
        self.preview = false
    }

    /// Stały stan do migawek (bez odczytu bazy i zgód).
    init(preview step: RideStartStep, environment: AppEnvironment, horses: [LocalHorse], horseId: String? = nil, fromCard: Bool = false, failed: Bool = false) {
        self.environment = environment
        self.preselectedHorseId = horseId
        self.preview = true
        self.step = step
        self.horses = horses
        self.horseId = horseId
        self.fromCard = fromCard
        self.failed = failed
    }

    var horse: LocalHorse? { horses.first { $0.id == horseId } }

    // MARK: Przejścia

    func load() async {
        guard !preview else { return }
        horses = HorseSearch.apply(environment.horseDirectory.horses, query: "", filter: .inStable)
        let selection = RideStartPolicy.initialSelection(preselectedHorseId: preselectedHorseId, horseIds: horses.map(\.id))
        horseId = selection.horseId
        fromCard = selection.fromCard
        await gate()
    }

    /// Jedno nagrywanie naraz (po decyzji startowej kontrolera — `RideRecovery.check` na nią czeka).
    private func gate() async {
        let check = await environment.rideRecovery.check()
        step = RideStartPolicy.gate(check)
        switch check {
        case .none: recoveryPrompt = nil
        case .recording: opened = true
        case let .pending(ride): recoveryPrompt = ride
        }
    }

    func changeHorse() {
        fromCard = false
    }

    /// „Dalej” na kroku konia albo instrukcji.
    func next() async {
        guard !busy else { return }
        switch step {
        case .horse:
            guard horse != nil else { return }
            await advance(from: .horse)
        case .wearHint:
            if dontShowAgain { environment.settings.rideWearHintHidden = true }
            await advance(from: .wearHint)
        default:
            break
        }
    }

    /// „Zezwól” na kroku lokalizacji: pytanie systemu, potem start albo wyjaśnienie.
    func requestLocation() async {
        guard step == .location, !busy else { return }
        busy = true
        let answer = await permission.request()
        busy = false
        guard step == .location else { return }
        let next = RideStartPolicy.afterLocationAnswer(answer)
        if next == .starting { await begin() } else { step = next }
    }

    /// Powrót z ustawień systemu (aplikacja znów aktywna): zgoda mogła zostać nadana.
    func recheckLocation() async {
        guard step == .locationDenied, !busy else { return }
        await advance(from: .locationDenied)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func advance(from current: RideStartStep) async {
        let next = RideStartPolicy.next(after: current, wearHintHidden: environment.settings.rideWearHintHidden, location: permission.current)
        if next == .starting { await begin() } else { step = next }
    }

    /// Start dokładnie raz: zgoda na powiadomienia (tylko gdy jeszcze nie pytano), parametry konia, sesja i kontroler nagrywania.
    private func begin() async {
        guard !busy, step != .starting, startedSessionId == nil, let horse else { return }
        busy = true
        defer { busy = false }
        step = .starting
        failed = false
        await askForNotificationsOnce()
        let params = await environment.rideParameters(horse.id)
        do {
            startedSessionId = try await environment.ride.start(horse: HorseRef(id: horse.id, name: horse.name, passportNumber: horse.passportNumber), params: params)
        } catch let error as RideStartError {
            if let next = RideStartPolicy.step(for: error) {
                step = next
                if next == .opened { opened = true }
            } else {
                // Sesja powstała, ale GPS nie ruszył — kontroler oznaczył ją jako przerwaną: pytanie „Zapisz / Odrzuć”.
                await failedStart()
            }
        } catch {
            await failedStart()
        }
    }

    /// Nieudany start: komunikat i możliwość ponowienia; często to druga sesja (`onlyOneActiveSession`) — wtedy odzyskiwanie bez komunikatu.
    private func failedStart() async {
        failed = true
        await gate()
        if step != .horse { failed = false }
    }

    /// Ostrzeżenia nagrywania są powiadomieniami lokalnymi — bez zgody system ich nie pokazuje. Pytanie pada raz (stan „nieustalona”);
    /// odmowa nie blokuje nagrywania. W przebiegach testowych — bez pytania systemu.
    private func askForNotificationsOnce() async {
        guard !environment.launchOptions.isTestRun else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: Odzyskiwanie

    func save(_ ride: UnfinishedRide) async {
        do {
            finishSessionId = try await environment.rideRecovery.save(ride)
        } catch {
            environment.log.log(RideRecordingController.logCategory, "Zapis odzyskiwanej jazdy nie powiódł się (\(String(describing: type(of: error))))")
            await gate()
        }
    }

    func discard(_ ride: UnfinishedRide) async {
        do {
            try await environment.rideRecovery.discard(sessionId: ride.sessionId)
        } catch {
            environment.log.log(RideRecordingController.logCategory, "Odrzucenie jazdy nie powiodło się (\(String(describing: type(of: error))))")
        }
        await gate()
    }
}

/// Ekran startu nagrywania („Nagraj jazdę”).
struct RideStartView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: RideStartModel
    let onClose: () -> Void
    let onRecording: () -> Void
    let onFinish: (String) -> Void

    init(model: RideStartModel, onClose: @escaping () -> Void, onRecording: @escaping () -> Void, onFinish: @escaping (String) -> Void) {
        self._model = State(initialValue: model)
        self.onClose = onClose
        self.onRecording = onRecording
        self.onFinish = onFinish
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.screenEdge) {
                stepContent
            }
            .padding(Spacing.screenEdge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HorselyColor.background)
        .navigationTitle("ride_record")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { RideBackButton(action: onClose) }
        }
        .rideRecoveryAlert(
            $model.recoveryPrompt,
            onSave: { ride in Task { await model.save(ride) } },
            onDiscard: { ride in Task { await model.discard(ride) } },
            onDismiss: onClose
        )
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.recheckLocation() } }
        }
        .onChange(of: model.startedSessionId) { _, id in if id != nil { onRecording() } }
        .onChange(of: model.opened) { _, opened in if opened { onRecording() } }
        .onChange(of: model.finishSessionId) { _, id in if let id { onFinish(id) } }
    }

    @ViewBuilder private var stepContent: some View {
        let content = RideStartPolicy.content(for: model.step)
        if let progress = content.progressKey {
            HStack(spacing: 12) {
                ProgressView()
                Text(LocalizedStringKey(progress)).font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            switch model.step {
            case .horse: horseStep(content)
            case .wearHint: wearHintStep(content)
            case .location: infoStep(content) { Task { await model.requestLocation() } }
            case .locationDenied: infoStep(content) { model.openSettings() }
            default: EmptyView()
            }
        }
    }

    @ViewBuilder private func horseStep(_ content: RideStartStepContent) -> some View {
        if model.horses.isEmpty {
            Text("ride_start_no_horses").font(.body).foregroundStyle(HorselyColor.onBackground)
        } else {
            if let text = content.textKey { Text(LocalizedStringKey(text)).font(.body).foregroundStyle(HorselyColor.onBackground) }
            if model.fromCard, let horse = model.horse {
                HStack {
                    Text(horse.name).font(.title2.weight(.semibold)).foregroundStyle(HorselyColor.onBackground)
                    Spacer()
                    Button("ride_start_horse_change") { model.changeHorse() }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: Spacing.minTouchTarget)
                        .accessibilityIdentifier("ride-start-change-horse")
                }
            } else {
                HStack {
                    Text("field_label_horse").font(.body).foregroundStyle(HorselyColor.onBackground)
                    Spacer()
                    HorsePicker(title: "field_label_horse", horses: model.horses, selection: $model.horseId, identifier: "ride-start-horse")
                        .labelsHidden()
                }
                .padding(.horizontal, Spacing.cardPadding)
                .frame(minHeight: Spacing.minTouchTarget)
                .background(HorselyColor.surfaceVariant.opacity(0.5), in: RoundedRectangle(cornerRadius: Spacing.cardRadius))
            }
            if model.failed {
                Text("ride_start_failed").font(.subheadline).foregroundStyle(HorselyColor.error)
            }
            primaryButton(content.buttonKey, enabled: model.horse != nil) { Task { await model.next() } }
        }
    }

    @ViewBuilder private func wearHintStep(_ content: RideStartStepContent) -> some View {
        stepTexts(content)
        if let key = content.doNotShowAgainKey {
            Button {
                model.dontShowAgain.toggle()
            } label: {
                HStack(spacing: 12) {
                    HIcon(name: model.dontShowAgain ? "check_box" : "check_box_outline_blank", size: 24)
                        .foregroundStyle(model.dontShowAgain ? HorselyColor.primary : HorselyColor.onSurfaceVariant)
                    Text(LocalizedStringKey(key)).font(.body).foregroundStyle(HorselyColor.onBackground)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Spacing.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.dontShowAgain ? [.isToggle, .isSelected] : .isToggle)
            .accessibilityIdentifier("ride-wear-dont-show")
        }
        primaryButton(content.buttonKey, enabled: true) { Task { await model.next() } }
    }

    @ViewBuilder private func infoStep(_ content: RideStartStepContent, action: @escaping () -> Void) -> some View {
        stepTexts(content)
        primaryButton(content.buttonKey, enabled: true, action: action)
    }

    @ViewBuilder private func stepTexts(_ content: RideStartStepContent) -> some View {
        if let title = content.titleKey {
            Text(LocalizedStringKey(title))
                .font(content.titleIsError ? .headline : .title2.weight(.semibold))
                .foregroundStyle(content.titleIsError ? HorselyColor.error : HorselyColor.onBackground)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let text = content.textKey {
            Text(LocalizedStringKey(text)).font(.body).foregroundStyle(HorselyColor.onBackground).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func primaryButton(_ key: String?, enabled: Bool, action: @escaping () -> Void) -> some View {
        if let key {
            Button(action: action) {
                Text(LocalizedStringKey(key)).font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.primaryFilled)
            .disabled(!enabled)
            .accessibilityIdentifier("ride-start-primary")
        }
    }
}

/// „Wstecz” w pasku ekranów nagrywania (pełny ekran nad kartami — bez systemowego przycisku powrotu).
struct RideBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward").font(.body.weight(.semibold))
        }
        .frame(minWidth: Spacing.minTouchTarget, minHeight: Spacing.minTouchTarget)
        .accessibilityLabel(tr("common_back"))
        .accessibilityIdentifier("ride-back")
    }
}
