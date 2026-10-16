import HorselyCore
import HorselyKit
import SwiftUI

/// Ustawienia (T131, FR-M-UST-00): w tej kolejności — „Połączenie z programem” (tylko online) · „Tryb pracy” · „Powiadomienia” ·
/// „Blokada aplikacji” · „Dane” · „Wygląd”. „Kopia zapasowa” i „O aplikacji” są w menu „Więcej”.
struct SettingsHubView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            if environment.workMode == .online {
                NavigationLink(value: SettingsDestination.connection) { Text("connection_settings_title") }
                    .accessibilityIdentifier("settings-connection")
            }
            NavigationLink(value: SettingsDestination.workMode) { Text("work_mode_title") }
                .accessibilityIdentifier("settings-work-mode")
            NavigationLink(value: SettingsDestination.notifications) { Text("notif_settings_title") }
                .accessibilityIdentifier("settings-notifications")
            NavigationLink(value: SettingsDestination.appLock) { Text("app_lock_setting_title") }
                .accessibilityIdentifier("settings-app-lock")
            NavigationLink(value: SettingsDestination.data) { Text("data_settings_title") }
                .accessibilityIdentifier("settings-data")
            NavigationLink(value: SettingsDestination.appearance) { Text("appearance_settings_title") }
                .accessibilityIdentifier("settings-appearance")
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("nav_settings"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SettingsDestination.self) { destination in
            switch destination {
            case .workMode: WorkModeView()
            case .connection: ConnectionSettingsView()
            case .notifications: NotificationSettingsView()
            case .appLock: AppLockSettingsView()
            case .data: DataSettingsView()
            case .appearance: AppearanceSettingsView()
            case let .address(id): AddressEditView(addressId: id)
            }
        }
    }
}

enum SettingsDestination: Hashable {
    case workMode
    case connection
    case notifications
    case appLock
    case data
    case appearance
    /// `nil` — nowy adres.
    case address(String?)
}

/// Połączenie z programem (T091): wersja programu, adresy (dodaj, popraw, usuń, kolejność), szyfrowanie i zasada zaufania, stan
/// wstrzymania, „Sprawdź połączenie” dla każdego adresu, „Połącz ponownie (nowy kod QR)”, „Rozłącz” z przypomnieniem o kluczu,
/// szczegółowy dziennik połączeń.
struct ConnectionSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var addresses: [ServerAddress] = []
    @State private var checkResults: [String: Bool] = [:]
    @State private var checking: String?
    @State private var confirmDisconnect = false
    @State private var disconnected = false

    var body: some View {
        List {
            Section {
                Text(environment.programVersion.map { tr("connection_program", $0) } ?? tr("connection_program_unknown"))
                    .accessibilityIdentifier("connection-program")
            }
            Section(tr("connection_addresses")) {
                ForEach(Array(addresses.enumerated()), id: \.element.id) { index, address in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(address.url).font(.body).textSelection(.enabled)
                        Text(Self.origin(address)).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                        Text(Self.trust(address)).font(.footnote).foregroundStyle(address.isHttps ? HorselyColor.onSurfaceVariant : HorselyColor.warning)
                        Text(Self.state(address)).font(.footnote).foregroundStyle(address.hold.reason == nil ? HorselyColor.onSurfaceVariant : HorselyColor.warning)
                        if let ok = checkResults[address.id] {
                            Text(ok ? tr("connection_check_result_ok") : tr("connection_check_result_failed"))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(ok ? HorselyColor.success : HorselyColor.error)
                        }
                        HStack {
                            Button(tr("connection_action_check")) { check(address) }
                                .disabled(checking != nil)
                            Spacer()
                            if index > 0 {
                                Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                                    .accessibilityLabel(tr("connection_address_move_up"))
                            }
                            if index < addresses.count - 1 {
                                Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                                    .accessibilityLabel(tr("connection_address_move_down"))
                            }
                            NavigationLink(value: SettingsDestination.address(address.id)) { Text("common_edit") }
                                .fixedSize()
                        }
                        .buttonStyle(.borderless)
                        .font(.footnote)
                    }
                    .padding(.vertical, 4)
                    .swipeActions {
                        if addresses.count > 1 {
                            Button(tr("connection_address_delete"), role: .destructive) { delete(address) }
                        }
                    }
                }
                NavigationLink(value: SettingsDestination.address(nil)) { Text("connection_address_add") }
            }
            Section {
                Toggle(isOn: Binding(
                    get: { ConnectionLog.isEnabled(until: environment.settings.connectionLogUntil) },
                    set: { on in
                        environment.settings.connectionLogUntil = on ? RefreshPlan.formatInstant(Date().addingTimeInterval(7 * 24 * 3600)) : nil
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("connection_log_title")
                        if let until = environment.settings.connectionLogUntil, ConnectionLog.isEnabled(until: until), let date = RefreshPlan.parseInstant(until) {
                            Text(tr("connection_log_on", ConnectionTexts.stamp(date) ?? "")).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                        } else {
                            Text("connection_log_off_description").font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
                        }
                    }
                }
            }
            Section {
                Button(tr("connection_pair_again")) { environment.router.showPairing = true }
                    .accessibilityIdentifier("connection-pair-again")
                Button(tr("connection_disconnect"), role: .destructive) { confirmDisconnect = true }
                    .accessibilityIdentifier("connection-disconnect")
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("connection_settings_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert(tr("connection_disconnect_title"), isPresented: $confirmDisconnect) {
            Button(tr("connection_disconnect_confirm"), role: .destructive) { disconnect() }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            let unsent = environment.queueCount
            Text(unsent > 0 ? tr("connection_disconnect_body") + "\n" + trPlural("connection_disconnect_queue_warning", unsent) : tr("connection_disconnect_body"))
        }
        .alert(tr("connection_disconnect"), isPresented: $disconnected) {
            Button(tr("common_ok")) { Task { try? await environment.disconnect() } }
        } message: {
            Text("connection_disconnected_reminder")
        }
    }

    private func load() async {
        addresses = (try? await environment.store.read { try $0.addresses() }) ?? []
    }

    private func check(_ address: ServerAddress) {
        checking = address.id
        Task {
            // „Sprawdź połączenie” zwalnia wstrzymanie adresu i wysyła jedno żądanie.
            var released = address
            released.hold = .active
            try? await environment.store.writeQuietly { try $0.setHold(address.id, .active) }
            let result = await environment.client.executeOn(released, .get("system/info"))
            let ok: Bool
            if case .success = result { ok = true } else { ok = false }
            environment.connectionLog.check(address: address, result: ok ? "odpowiada" : "brak odpowiedzi", network: environment.network.conditions.label)
            checkResults[address.id] = ok
            checking = nil
            if ok {
                environment.connection.clearDenial()
                await environment.refresh(force: true)
            }
            await load()
        }
    }

    private func move(_ index: Int, by offset: Int) {
        var reordered = addresses
        reordered.swapAt(index, index + offset)
        for position in reordered.indices { reordered[position].position = position }
        let saved = reordered
        Task {
            try? await environment.store.writeQuietly { access in for address in saved { try access.saveAddress(address) } }
            await load()
        }
    }

    private func delete(_ address: ServerAddress) {
        Task {
            try? await environment.store.writeQuietly { try $0.deleteAddress(address.id) }
            await load()
        }
    }

    private func disconnect() {
        disconnected = true
    }

    static func origin(_ address: ServerAddress) -> String {
        if address.issuerSummary != nil { return tr("connection_address_origin_manual") }
        return address.isRemote ? tr("connection_address_origin_qr_remote") : tr("connection_address_origin_qr_local")
    }

    static func trust(_ address: ServerAddress) -> String {
        switch address.trustMode {
        case .pinned: tr("connection_trust_pinned")
        case .trustedIssuer: tr("connection_trust_issuer", address.issuerSummary ?? "—")
        case .plainHttpConfirmed: tr("connection_trust_cleartext")
        }
    }

    static func state(_ address: ServerAddress) -> String {
        guard address.hold.isBlocked(at: Date()) else { return tr("connection_address_state_active") }
        if let until = address.hold.until { return tr("connection_address_state_blocked_until", ConnectionTexts.stamp(until) ?? "") }
        return tr("connection_address_state_waiting")
    }
}

/// Dodanie albo poprawa adresu: sprawdzenie reguł, ostrzeżenie `http`, dla `https` bez odcisku — potwierdzenie wystawcy.
struct AddressEditView: View {
    let addressId: String?
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var fingerprint = ""
    @State private var error: String?
    @State private var existing: ServerAddress?
    @State private var confirmCleartext = false
    @State private var issuer: String?

    var body: some View {
        Form {
            Section(tr("pairing_manual_address")) {
                TextField(tr("pairing_manual_address"), text: $url, prompt: Text("pairing_manual_address_hint"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let error { Text(error).font(.footnote).foregroundStyle(HorselyColor.error) }
            }
            Section {
                TextField(tr("pairing_manual_fingerprint"), text: $fingerprint, axis: .vertical)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
            } footer: {
                Text("address_edit_fingerprint_hint")
            }
            Section {
                Button(tr("address_edit_save")) { save() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr(addressId == nil ? "address_edit_title_new" : "address_edit_title_edit"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let addressId, let found = try? await environment.store.read({ try $0.addresses() }).first(where: { $0.id == addressId }) else { return }
            existing = found
            url = found.url
            fingerprint = found.certSha256 ?? ""
        }
        .alert(tr("pairing_cleartext_title"), isPresented: $confirmCleartext) {
            Button(tr("pairing_cleartext_confirm")) { store(trust: .plainHttpConfirmed, pin: nil, issuer: nil) }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text("pairing_cleartext_body")
        }
        .alert(tr("pairing_issuer_title"), isPresented: Binding(get: { issuer != nil }, set: { if !$0 { issuer = nil } })) {
            Button(tr("pairing_issuer_trust")) { store(trust: .trustedIssuer, pin: nil, issuer: issuer) }
            Button(tr("common_cancel"), role: .cancel) { issuer = nil }
        } message: {
            Text(issuer ?? "")
        }
    }

    private var checked: CheckedAddress? { AddressRules.default.check(url).address }

    private func save() {
        error = nil
        let result = AddressRules.default.check(url)
        guard let address = result.address else {
            error = result.reason?.message
            return
        }
        let cleaned = fingerprint.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "")
        if !cleaned.isEmpty {
            guard let pin = PairingCodeParser.normalizeFingerprint(cleaned) else {
                error = tr("pairing_manual_fingerprint_format")
                return
            }
            store(trust: .pinned, pin: pin, issuer: nil)
        } else if !address.isHttps {
            confirmCleartext = true
        } else {
            Task {
                if let summary = await TLSProbe.issuer(of: address.baseUrl + "/system/info") {
                    issuer = summary
                } else {
                    error = tr("pairing_error_untrusted")
                }
            }
        }
    }

    private func store(trust: TrustMode, pin: String?, issuer: String?) {
        guard let address = checked else { return }
        Task {
            let count = (try? await environment.store.read { try $0.addresses().count }) ?? 0
            let saved = ServerAddress(
                id: existing?.id ?? UUID().uuidString.lowercased(), url: address.baseUrl, position: existing?.position ?? count, trustMode: trust,
                certSha256: pin, issuerSummary: issuer, isRemote: !address.isLocal
            )
            try? await environment.store.writeQuietly { try $0.saveAddress(saved) }
            dismiss()
        }
    }
}
