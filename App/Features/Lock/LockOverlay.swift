import HorselyKit
import SwiftUI
import UIKit

/// Stan blokady aplikacji (T132, FR-TRB-09): zablokowana przy otwarciu i po powrocie po ponad 5 minutach w tle; zasłona ukrywa treść
/// w przełączniku aplikacji; telefon bez blokady ekranu wyłącza blokadę z informacją.
@MainActor
@Observable
final class AppLockState {
    private(set) var locked: Bool
    /// Zasłona, gdy aplikacja nie jest na pierwszym planie (przełącznik aplikacji, przejście w tło).
    private(set) var covered = false
    /// „Blokada aplikacji wyłączona” — telefon nie ma już blokady ekranu.
    var notice = false
    private var authenticating = false

    init(locked: Bool) {
        self.locked = locked
    }

    func unlocked() {
        locked = false
    }

    func sceneChanged(_ phase: ScenePhase, settings: SettingsStore) {
        let enabled = settings.appLockEnabled
        switch phase {
        case .background:
            if !locked { settings.appLockLastBackgroundAt = Date().timeIntervalSince1970 }
            covered = enabled
        case .inactive:
            // Okno uwierzytelniania też wprowadza scenę w stan nieaktywny — wtedy zasłona już jest zbędna.
            if !authenticating { covered = enabled }
        case .active:
            covered = false
            guard enabled else { return }
            if AppLockAuthenticator().availability() == .noPasscode {
                settings.appLockEnabled = false
                locked = false
                notice = true
                return
            }
            let backgrounded = settings.appLockLastBackgroundAt.map { Date(timeIntervalSince1970: $0) }
            if backgrounded != nil, AppLockPolicy.requiresUnlock(enabled: true, backgroundedAt: backgrounded, now: Date()) { locked = true }
        @unknown default:
            break
        }
    }

    func unlock() async {
        guard locked, !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        if await AppLockAuthenticator().authenticate(reason: tr("app_lock_prompt_title")) { locked = false }
    }
}

/// „Aplikacja zablokowana” — bez danych; odblokowanie zabezpieczeniem telefonu (próba od razu po pokazaniu).
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
        .task { await environment.appLock.unlock() }
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
