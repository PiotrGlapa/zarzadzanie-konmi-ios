import HorselyKit
import SwiftUI
import UIKit

/// Stan blokady aplikacji (T132, FR-TRB-09; 2.0.2 FR-001…FR-005): cienka powłoka `@Observable` nad `AppLockMachine`
/// z HorselyKit (cała logika i jej testy są w pakiecie). Zablokowana przy zimnym starcie i po powrocie po ponad 5 minutach
/// w tle; zasłona ukrywa treść w przełączniku aplikacji; telefon bez blokady ekranu wyłącza blokadę z informacją.
@MainActor
@Observable
final class AppLockState {
    private var machine: AppLockMachine
    /// Przebieg testowy aplikacji nigdy nie blokuje.
    private let suppressed: Bool

    init(enabled: Bool, suppressed: Bool) {
        self.suppressed = suppressed
        machine = AppLockMachine(enabled: enabled && !suppressed)
        machine.launch()
    }

    var locked: Bool { machine.locked }
    /// Zasłona, gdy aplikacja nie jest na pierwszym planie (przełącznik aplikacji, przejście w tło).
    var covered: Bool { machine.covered }
    /// „Blokada aplikacji wyłączona” — telefon nie ma już blokady ekranu.
    var notice: Bool {
        get { machine.disabledNotice }
        set { if !newValue { machine.acknowledgeNotice() } }
    }

    /// Ustawienie „Blokada aplikacji” zmieniło się w Ustawieniach (włączenie nie blokuje bieżącej sesji).
    func settingChanged(_ settings: SettingsStore) {
        machine.setEnabled(settings.appLockEnabled && !suppressed)
    }

    func sceneChanged(_ phase: ScenePhase, settings: SettingsStore, now: Date = Date()) {
        settingChanged(settings)
        switch phase {
        case .background:
            machine.didEnterBackground(at: now)
        case .inactive:
            machine.willResignActive()
        case .active:
            let passcode = !machine.enabled || AppLockAuthenticator().availability() != .noPasscode
            machine.didBecomeActive(at: now, passcodeAvailable: passcode)
            if machine.disabledNotice { settings.appLockEnabled = false }
        @unknown default:
            break
        }
    }

    /// Przycisk „Odblokuj” — zawsze ponawia próbę.
    func unlock() async {
        guard machine.locked, !machine.authenticating else { return }
        machine.authenticationStarted()
        let success = await AppLockAuthenticator().authenticate(reason: tr("app_lock_prompt_title"))
        machine.authenticationFinished(success: success)
    }

    /// Samoczynna próba tuż po pokazaniu ekranu blokady — tylko raz na epizod blokady, żeby anulowanie okna nie wywoływało go w kółko.
    func autoUnlock() async {
        guard machine.autoPromptAvailable else { return }
        await unlock()
    }
}

/// „Aplikacja zablokowana” — bez danych; odblokowanie zabezpieczeniem telefonu (jedna samoczynna próba po pokazaniu, potem przycisk).
struct LockOverlay: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: Spacing.beforeSection) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 56)).foregroundStyle(HorselyColor.primary).accessibilityHidden(true)
            Text("app_lock_title").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("app_lock_text").multilineTextAlignment(.center).foregroundStyle(HorselyColor.onSurfaceVariant)
            Button {
                Task { await environment.appLock.unlock() }
            } label: {
                Text("app_lock_unlock").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
            }
            .buttonStyle(.primaryFilled)
            .tint(HorselyColor.primary)
            .accessibilityIdentifier("app-lock-unlock")
            Spacer()
        }
        .padding(Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HorselyColor.background)
        .task { await environment.appLock.autoUnlock() }
    }
}

/// Zasłona w przełączniku aplikacji: tło i znak aplikacji, bez treści.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            HorselyColor.background
            HIcon(name: "horse_head", size: 72).foregroundStyle(HorselyColor.primary)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Okno blokady i zasłony nad oknem aplikacji (poziom alertu), żeby zakryć też otwarte arkusze i formularze.
struct LockWindowHost: UIViewRepresentable {
    let environment: AppEnvironment
    let locked: Bool
    let covered: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        let environment = environment
        let locked = locked
        let covered = covered
        // Okno sceny bywa jeszcze nieznane przy pierwszym rysowaniu — ponowna próba w następnym przebiegu pętli.
        Task { @MainActor in
            coordinator.update(scene: view.window?.windowScene, environment: environment, locked: locked, covered: covered)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var window: UIWindow?
        private var showingLock: Bool?

        func update(scene: UIWindowScene?, environment: AppEnvironment, locked: Bool, covered: Bool) {
            guard locked || covered else {
                window?.isHidden = true
                window = nil
                showingLock = nil
                return
            }
            guard let scene = scene ?? window?.windowScene else { return }
            let window = self.window ?? UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            if showingLock != locked {
                let content: AnyView = locked ? AnyView(LockOverlay().environment(environment)) : AnyView(PrivacyCover())
                window.rootViewController = UIHostingController(rootView: content.preferredColorScheme(environment.theme.colorScheme))
                showingLock = locked
            }
            window.isHidden = false
            self.window = window
        }
    }
}
