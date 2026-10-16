import HorselyCore
import HorselyKit
import SwiftUI

/// Przebieg parowania (T086, contracts/android/pairing-and-connection.md): wyjaśnienie dostępu do sieci lokalnej → skan QR albo wpis
/// ręczny → ostrzeżenie `http` / potwierdzenie wystawcy → sprawdzenie programu → wynik (wersja, liczba koni, ostrzeżenia) →
/// zapis parowania i ewentualnie rozpoznanie stajni. Przerwanie wraca do miejsca wywołania (FR-TRB-03).
struct PairingFlowView: View {
    enum Purpose {
        /// Pierwsze uruchomienie: „Tak, połącz z programem”.
        case firstRun
        /// „Połącz ponownie (nowy kod QR)” / odrzucony klucz / zmieniony certyfikat.
        case repair
        /// Zmiana trybu samodzielny → online (dane telefonu usuwane dopiero po udanym parowaniu).
        case switchFromStandalone
    }

    private enum Step: Equatable {
        case explainer
        case scanner
        case manual
        case checking
        case result(PairingResult)
        case mismatch(StableIdentity)
    }

    let purpose: Purpose
    let onFinish: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: Step = .explainer
    @State private var request: PairingRequest?
    @State private var error: String?
    @State private var confirmCleartext: PairingRequest?
    @State private var confirmIssuer: (request: PairingRequest, summary: String)?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            content
                .background(HorselyColor.background)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("common_cancel"), action: onFinish).accessibilityIdentifier("pairing-cancel")
                    }
                }
        }
        // Zasłona w przełączniku aplikacji — klucz API i kod QR nie trafiają do podglądu.
        .overlay {
            if scenePhase != .active { HorselyColor.background.ignoresSafeArea() }
        }
        .alert(tr("pairing_cleartext_title"), isPresented: Binding(get: { confirmCleartext != nil }, set: { if !$0 { confirmCleartext = nil } })) {
            Button(tr("pairing_cleartext_confirm")) {
                if let pending = confirmCleartext { check(pending) }
                confirmCleartext = nil
            }
            Button(tr("common_cancel"), role: .cancel) { confirmCleartext = nil }
        } message: {
            Text("pairing_cleartext_body")
        }
        .alert(tr("pairing_issuer_title"), isPresented: Binding(get: { confirmIssuer != nil }, set: { if !$0 { confirmIssuer = nil } })) {
            Button(tr("pairing_issuer_trust")) {
                if let pending = confirmIssuer {
                    let trusted = PairingRequest(url: pending.request.url, key: pending.request.key, trustedIssuerSummary: pending.summary)
                    check(trusted)
                }
                confirmIssuer = nil
            }
            Button(tr("common_cancel"), role: .cancel) { confirmIssuer = nil }
        } message: {
            Text(confirmIssuer?.summary ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .explainer:
            LocalNetworkExplainerView(error: error, onScan: { error = nil; step = .scanner }, onManual: { error = nil; step = .manual })
        case .scanner:
            QrScannerView(onCode: handleScanned, onManual: { step = .manual })
        case .manual:
            ManualPairingView(error: error, onConnect: handleManual)
        case .checking:
            VStack(spacing: Spacing.beforeSection) {
                ProgressView()
                Text("pairing_checking").font(.body).foregroundStyle(HorselyColor.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("pairing-checking")
        case let .result(result):
            PairingResultView(result: result, saving: saving, onContinue: { save(result) })
        case let .mismatch(identity):
            StableMismatchView(identity: identity, onSendAnyway: {
                Task {
                    try? await environment.pairing.release()
                    await environment.sendQueue()
                    onFinish()
                }
            }, onDeleteQueue: {
                Task {
                    try? await environment.pairing.dropQueue()
                    onFinish()
                }
            })
        }
    }

    // MARK: Przebieg

    private func handleScanned(_ text: String) {
        switch PairingCodeParser().parse(text) {
        case let .success(code):
            start(PairingRequest(code: code))
        case let .failure(failure):
            error = failure.message
            step = .explainer
        }
    }

    private func handleManual(_ request: PairingRequest) {
        if !request.url.isHttps {
            confirmCleartext = request
        } else if request.certSha256 == nil {
            step = .checking
            Task {
                if let summary = await TLSProbe.issuer(of: request.url.baseUrl + "/system/info") {
                    confirmIssuer = (request, summary)
                    step = .manual
                } else {
                    error = tr("pairing_error_untrusted")
                    step = .manual
                }
            }
        } else {
            check(request)
        }
    }

    private func start(_ request: PairingRequest) {
        if !request.url.isHttps {
            confirmCleartext = request
        } else {
            check(request)
        }
    }

    private func check(_ candidate: PairingRequest) {
        request = candidate
        step = .checking
        Task {
            switch await environment.pairing.verify(candidate) {
            case let .success(result):
                step = .result(result)
            case let .failure(failure):
                error = Self.message(failure)
                step = candidate.trustedIssuerSummary != nil || candidate.remoteUrl == nil && candidate.certSha256 == nil ? .manual : .explainer
            }
        }
    }

    private func save(_ result: PairingResult) {
        guard let request, !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                if result.versionCheck == .newerThanTested { environment.settings.programVersionWarnedFor = result.programVersion }
                let identity = try await environment.completePairing(request, result: result)
                if identity == .match { onFinish() } else { step = .mismatch(identity) }
            } catch {
                self.error = tr("pairing_error_other")
                step = .explainer
            }
        }
    }

    static func message(_ failure: PairingFailure) -> String {
        switch failure {
        case .programTooOld: return tr("pairing_error_too_old")
        case .unknownVersion: return tr("pairing_error_other")
        case let .api(apiFailure):
            switch apiFailure {
            case .unauthorized: return tr("pairing_error_unauthorized")
            case .certificateRejected: return tr("connection_certificate_changed")
            case .keyHomeOnly: return tr("connection_key_home_only")
            case .remoteAccessDisabled: return tr("connection_remote_disabled")
            case .network, .noUsableAddress, .noNetwork: return tr("pairing_error_no_connection")
            default: return tr("pairing_error_other")
            }
        }
    }
}

extension StableIdentity {
    var missingHorses: Int {
        if case let .mismatch(missing, _) = self { return missing }
        return 0
    }
}
