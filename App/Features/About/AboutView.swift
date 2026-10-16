import HorselyCore
import HorselyKit
import SwiftUI

/// O aplikacji (T133, FR-M-UST-05/06): pełna nazwa, wersja i kompilacja, autor, wersja programu (online) z ostrzeżeniem dla wersji
/// nowszej niż testowana, tryb zgodności, „Co nowego”, instrukcja, dziennik diagnostyczny i licencje.
struct AboutView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var unversioned = false

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.between) {
                    Text("app_full_name").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(tr("about_app_version", appVersion)).accessibilityIdentifier("about-version")
                    Text("about_author")
                    if environment.workMode == .online {
                        Text(environment.programVersion.map { tr("about_program_version", $0) } ?? tr("about_program_none"))
                        if let version = environment.programVersion, ProgramVersion.check(version) == .newerThanTested {
                            Text(tr("about_newer_program", version)).foregroundStyle(HorselyColor.warning)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if environment.workMode == .online, unversioned {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("about_compat_title").font(.headline).foregroundStyle(HorselyColor.error)
                        Text("about_compat_text").font(.subheadline)
                    }
                }
            }
            Section(tr("about_whats_new_title")) {
                Text("about_whats_new_fixes")
                Text("about_whats_new_rating")
                Text("about_whats_new_look")
            }
            Section(tr("about_manual")) {
                Text("about_manual_hint").foregroundStyle(HorselyColor.onSurfaceVariant)
            }
            Section {
                NavigationLink(value: AboutRoute.log) { Text("about_diagnostic_log") }
                    .accessibilityIdentifier("about-diagnostic-log")
                if let title = LicensesView.title { NavigationLink(value: AboutRoute.licenses) { Text(verbatim: title) } }
                    .accessibilityIdentifier("about-licenses")
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("about_title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AboutRoute.self) { route in
            switch route {
            case .log: DiagnosticLogView()
            case .licenses: LicensesView()
            }
        }
        .task {
            unversioned = (try? await environment.store.read { try $0.pairingInfo() })?.unversioned ?? false
        }
    }
}

enum AboutRoute: Hashable {
    case log
    case licenses
}

/// Licencje składników (`Licenses.md` w zasobach aplikacji).
struct LicensesView: View {
    static var text: String? {
        guard let url = Bundle.main.url(forResource: "Licenses", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Tytuł z nagłówka pliku („Licencje składników”).
    static var title: String? {
        text?.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
    }

    var body: some View {
        ScrollView {
            Text(Self.text ?? "").font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.screenEdge).textSelection(.enabled)
        }
        .background(HorselyColor.background)
        .navigationTitle(Self.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Dziennik diagnostyczny (T133, FR-029…FR-033): rozmiar i stan szczegółowego dziennika połączeń, wpisy od najnowszych czcionką
/// o stałej szerokości, „Wyślij” (temat „Log diagnostyczny — Horsely”), „Wyczyść” z potwierdzeniem.
struct DiagnosticLogView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var lines: [String] = []
    @State private var size = 0
    @State private var confirmClear = false
    @State private var file: URL?

    var body: some View {
        List {
            Section {
                Text(tr("diagnostic_log_header", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file), connectionState))
                    .font(.subheadline)
                    .accessibilityIdentifier("log-header")
                HStack(spacing: Spacing.between) {
                    if let file {
                        ShareLink(item: file, subject: Text("about_log_subject"), message: Text("about_log_subject")) { Text("diagnostic_log_send") }
                            .buttonStyle(.bordered)
                            .disabled(lines.isEmpty)
                            .accessibilityIdentifier("log-send")
                    }
                    Button(tr("diagnostic_log_clear"), role: .destructive) { confirmClear = true }
                        .buttonStyle(.bordered)
                        .disabled(lines.isEmpty)
                        .accessibilityIdentifier("log-clear")
                }
            }
            Section {
                if lines.isEmpty {
                    Text("diagnostic_log_empty").foregroundStyle(HorselyColor.onSurfaceVariant).accessibilityIdentifier("log-empty")
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("diagnostic_log_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .confirmationDialog(tr("diagnostic_log_clear_title"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(tr("diagnostic_log_clear"), role: .destructive) {
                environment.log.clear()
                load()
            }
        } message: {
            Text("diagnostic_log_clear_body")
        }
    }

    private var connectionState: String {
        if let until = environment.settings.connectionLogUntil, ConnectionLog.isEnabled(until: until), let date = RefreshPlan.parseInstant(until) {
            return tr("diagnostic_log_connection_on", ConnectionTexts.stamp(date) ?? "")
        }
        return tr("diagnostic_log_connection_off")
    }

    /// Wpisy i plik do wysłania (`horsely-log.txt` w katalogu tymczasowym).
    private func load() {
        lines = environment.log.entries()
        size = environment.log.sizeBytes
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-log.txt")
        try? Data(environment.log.text().utf8).write(to: url, options: .atomic)
        file = url
    }
}
