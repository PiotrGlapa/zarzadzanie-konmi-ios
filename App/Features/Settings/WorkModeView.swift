import HorselyCore
import HorselyKit
import SwiftUI

/// Tryb pracy (T092, FR-TRB-05…07; kierunek samodzielny → online): dwa ostrzeżenia z liczbą koni, wpisów i datą ostatniej kopii,
/// „Usuń dane i połącz” (niszczący, nie domyślny), kreator parowania; dane telefonu usuwane dopiero po udanym parowaniu (jedna
/// transakcja). Przerwana zmiana jest zapamiętana (`modeChange.pending`) i można ją wznowić. Kierunek online → samodzielny (T129): ostrzeżenie z liczbą niewysłanych zmian, pobranie aktualnych danych i brakujących plików, ostrzeżenie o brakach, usunięcie połączenia i klucza.
struct WorkModeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var counts: (horses: Int, entries: Int) = (0, 0)
    @State private var firstWarning = false
    @State private var secondWarning = false
    @State private var pairing = false
    @State private var standaloneWarning = false
    @State private var preparing = false
    @State private var fetched = BackupProgress()
    @State private var missing: (syncFailed: Bool, files: Int)?
    @State private var failure = false

    var body: some View {
        List {
            Section(tr("work_mode_current")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(environment.workMode == .online ? tr("work_mode_online") : tr("work_mode_standalone")).font(.headline)
                    Text(environment.workMode == .online ? tr("work_mode_online_hint") : tr("work_mode_standalone_hint"))
                        .font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                .accessibilityElement(children: .combine)
            }
            if environment.workMode == .standalone {
                Section {
                    Button(tr("work_mode_to_online")) { firstWarning = true }
                        .accessibilityIdentifier("work-mode-to-online")
                }
            }
            if environment.workMode == .online {
                Section {
                    Button(tr("work_mode_to_standalone")) { standaloneWarning = true }
                        .disabled(preparing)
                        .accessibilityIdentifier("work-mode-to-standalone")
                    if preparing {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("work_mode_preparing_title").font(.headline)
                            ProgressView()
                            Text(tr("work_mode_preparing_text", fetched.done)).font(.footnote)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("work_mode_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCounts() }
        .alert(tr("work_mode_online_title"), isPresented: $firstWarning) {
            Button(tr("common_next")) { secondWarning = true }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text(tr("work_mode_online_text", counts.horses, counts.entries, lastBackup))
        }
        .alert(tr("work_mode_online_title"), isPresented: $secondWarning) {
            Button(tr("work_mode_delete_and_connect"), role: .destructive) {
                environment.settings.modeChangePending = "toOnline"
                pairing = true
            }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text(tr("work_mode_online_confirm_text", counts.horses, counts.entries))
        }
        .alert(tr("work_mode_standalone_title"), isPresented: $standaloneWarning) {
            Button(tr("work_mode_to_standalone")) { Task { await prepareStandalone() } }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text(tr("work_mode_standalone_text", environment.queueCount))
        }
        .alert(tr("work_mode_missing_title"), isPresented: Binding(get: { missing != nil }, set: { if !$0 { missing = nil } })) {
            Button(tr("work_mode_continue_anyway"), role: .destructive) { Task { await completeStandalone() } }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text(missingText)
        }
        .alert(tr("work_mode_failed"), isPresented: $failure) {
            Button(tr("common_ok")) {}
        }
        .fullScreenCover(isPresented: $pairing) {
            PairingFlowView(purpose: .switchFromStandalone) {
                pairing = false
                // Anulowanie: dane i tryb samodzielny bez zmian (SC-2-08).
                if environment.workMode == .standalone { environment.settings.modeChangePending = nil }
            }
            .environment(environment)
        }
        .onAppear {
            // Wznowienie przerwanej zmiany trybu (np. aplikacja zamknięta w trakcie parowania).
            if environment.workMode == .standalone, environment.settings.modeChangePending == "toOnline" { pairing = true }
        }
    }

    private var missingText: String {
        guard let missing else { return "" }
        var lines: [String] = []
        if missing.syncFailed { lines.append(tr("work_mode_missing_sync")) }
        if missing.files > 0 { lines.append(tr("work_mode_missing_files", missing.files)) }
        lines.append(tr("work_mode_missing_hint"))
        return lines.joined(separator: "
")
    }

    /// Online → samodzielny: aktualne dane i brakujące oryginały z programu; braki — ostrzeżenie z „Przejdź mimo braków”.
    private func prepareStandalone() async {
        preparing = true
        let box = fetched
        box.start()
        let result = await environment.prepareStandaloneSwitch { count in box.update(count, count) }
        preparing = false
        if result.syncFailed || result.missingFiles > 0 {
            missing = (result.syncFailed, result.missingFiles)
        } else {
            await completeStandalone()
        }
    }

    private func completeStandalone() async {
        do {
            try await environment.completeStandaloneSwitch()
            environment.router.banner = BannerMessage(text: tr("work_mode_changed_standalone"))
        } catch {
            failure = true
        }
    }

    private var lastBackup: String {
        environment.settings.backupLastAt.flatMap { RefreshPlan.parseInstant($0) }.flatMap { ConnectionTexts.stamp($0) } ?? tr("work_mode_no_backup")
    }

    private func loadCounts() async {
        let result = try? await environment.store.read { access -> (Int, Int) in
            let horses = try access.count(.horse)
            var entries = 0
            for type in RecordType.allCases where type != .horse && type != .dictionary && type != .contact && type != .attachment {
                entries += try access.count(type)
            }
            return (horses, entries)
        }
        if let result { counts = (result.0, result.1) }
    }
}
