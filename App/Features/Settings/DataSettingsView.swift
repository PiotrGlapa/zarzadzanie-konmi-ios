import HorselyCore
import HorselyKit
import SwiftUI

/// Ustawienia → Dane (T131, FR-M-UST-03): w trybie online „Pobieraj wszystkie załączniki”, limit miejsca z zajętością,
/// „tylko przez Wi‑Fi” i „Wyczyść pamięć podręczną” (kolejka zostaje); w obu trybach oryginały zdjęć i lokalizacja.
struct DataSettingsView: View {
    static let limits = [50, 100, 200, 500, 1000]

    @Environment(AppEnvironment.self) private var environment
    @State private var downloadAll = false
    @State private var limit = 200
    @State private var sendOriginals = false
    @State private var keepLocation = false
    @State private var wifiOnly = true
    @State private var used: Int64 = 0
    @State private var confirmClear = false
    @State private var cleared = false

    private var online: Bool { environment.workMode == .online }

    var body: some View {
        Form {
            if online {
                Section {
                    toggle("data_settings_download_all", "data_settings_download_all_hint", $downloadAll, id: "data-download-all") {
                        environment.settings.downloadAllAttachments = $0
                    }
                }
                Section {
                    Picker(selection: $limit) {
                        ForEach(Self.limits, id: \.self) { Text(tr("data_settings_limit_mb", $0)).tag($0) }
                    } label: {
                        Text("data_settings_attachments_limit")
                    }
                    .onChange(of: limit) { _, value in
                        environment.settings.attachmentLimitMB = value
                        Task { await environment.attachments.evict(); await loadUsage() }
                    }
                    .accessibilityIdentifier("data-limit")
                } footer: {
                    Text(tr("data_settings_attachments_used", ByteCountFormatter.string(fromByteCount: used, countStyle: .file), limit))
                }
            }
            Section {
                toggle("data_settings_send_originals", "data_settings_send_originals_hint", $sendOriginals, id: "data-send-originals") {
                    environment.settings.sendOriginals = $0
                }
                toggle("data_settings_keep_location", "data_settings_keep_location_hint", $keepLocation, id: "data-keep-location") {
                    environment.settings.keepPhotoLocation = $0
                }
            }
            if online {
                Section {
                    toggle("data_settings_wifi_only", "data_settings_wifi_only_hint", $wifiOnly, id: "data-wifi-only") {
                        environment.settings.wifiOnly = $0
                    }
                }
                Section {
                    Button(tr("data_settings_clear"), role: .destructive) { confirmClear = true }
                        .frame(minHeight: Spacing.minTouchTarget)
                        .accessibilityIdentifier("data-clear")
                    if cleared { Text("data_settings_cleared").font(.footnote) }
                } footer: {
                    Text("data_settings_clear_hint")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("data_settings_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(tr("data_settings_clear_title"), isPresented: $confirmClear) {
            Button(tr("data_settings_clear"), role: .destructive) { Task { await clear() } }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text("data_settings_clear_text")
        }
    }

    private func toggle(_ title: LocalizedStringKey, _ hint: LocalizedStringKey, _ value: Binding<Bool>, id: String, save: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; save($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(hint).font(.footnote).foregroundStyle(HorselyColor.onSurfaceVariant)
            }
        }
        .accessibilityIdentifier(id)
    }

    private func load() async {
        let settings = environment.settings
        downloadAll = settings.downloadAllAttachments
        limit = Self.limits.contains(settings.attachmentLimitMB) ? settings.attachmentLimitMB : 200
        sendOriginals = settings.sendOriginals
        keepLocation = settings.keepPhotoLocation
        wifiOnly = settings.wifiOnly
        await loadUsage()
    }

    private func loadUsage() async {
        used = (try? await environment.store.filesSize()) ?? 0
    }

    private func clear() async {
        _ = try? await environment.store.clearCache(files: environment.files)
        cleared = true
        await loadUsage()
        Task { await environment.refresh(force: true) }
    }
}
