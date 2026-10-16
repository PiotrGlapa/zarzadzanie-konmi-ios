import HorselyCore
import HorselyKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Plik kopii `.zkkopia` (wymienny z Androidem).
    static let horselyBackup = UTType(filenameExtension: BackupManifest.fileExtension, conformingTo: .data) ?? .data
}

/// Kopia zapasowa trybu samodzielnego (T127, FR-KOP-01…09): data i rodzaj ostatniej kopii, „Utwórz kopię zapasową” (hasło ×2
/// z ostrzeżeniem, wybór miejsca, postęp i rozmiar), „Odtwórz z kopii” (data, liczby, „Obecne dane zostaną zastąpione”),
/// „Automatyczna kopia co tydzień” (folder, ostatni błąd, „Wskaż folder ponownie”).
struct BackupView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var creating = false
    @State private var saving: ExportedFile?
    @State private var pendingResult: BackupResult?
    @State private var progress = BackupProgress()
    @State private var restoring = false
    @State private var pickingFolder = false
    @State private var autoEnabled = false
    @State private var message: String?
    @State private var refresh = 0

    var body: some View {
        let settings = environment.settings
        List {
            Section {
                Text("backup_hint").font(.subheadline)
                Text(lastBackupText).font(.subheadline.weight(.semibold)).accessibilityIdentifier("backup-last")
            }
            Section {
                Button {
                    creating = true
                } label: {
                    Label(tr("backup_create"), systemImage: "square.and.arrow.down").frame(minHeight: Spacing.minTouchTarget)
                }
                .disabled(progress.running)
                .accessibilityIdentifier("backup-create")
                if progress.running {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        Text(tr("backup_progress", progress.done, progress.total)).font(.footnote)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    restoring = true
                } label: {
                    Label(tr("backup_restore"), systemImage: "arrow.counterclockwise").frame(minHeight: Spacing.minTouchTarget)
                }
                .accessibilityIdentifier("backup-restore")
            }
            Section {
                Toggle(isOn: Binding(get: { autoEnabled }, set: { toggleAuto($0) })) { Text("backup_auto_title") }
                    .accessibilityIdentifier("backup-auto")
                if autoEnabled {
                    Text(folderText).font(.footnote)
                    Button(tr(settings.backupAutoFolderBookmark == nil ? "backup_auto_pick" : "backup_pick_folder_again")) { pickingFolder = true }
                        .frame(minHeight: Spacing.minTouchTarget)
                        .accessibilityIdentifier("backup-pick-folder")
                    if let error = settings.backupAutoLastError {
                        Text(tr("backup_auto_error", error)).font(.footnote).foregroundStyle(HorselyColor.error)
                    }
                }
            } footer: {
                Text("backup_auto_hint")
            }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case let .success(url) = result { chooseFolder(url) }
            }
        }
        .id(refresh)
        .scrollContentBackground(.hidden)
        .background(HorselyColor.background)
        .navigationTitle(tr("backup_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { autoEnabled = environment.settings.backupAutoEnabled }
        .sheet(isPresented: $creating) {
            CreateBackupSheet { password in create(password: password) }
        }
        .sheet(isPresented: $restoring) {
            RestoreBackupFlow { message = tr("backup_restored") }
        }
        .fileMover(isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }), file: saving?.url) { result in
            if (try? result.get()) != nil, let done = pendingResult {
                record(done, kind: "manual")
                let size = ByteCountFormatter.string(fromByteCount: done.bytes, countStyle: .file)
                message = done.missingFiles.isEmpty ? tr("backup_done", size) : tr("backup_done_missing", size, done.missingFiles.count)
            }
            pendingResult = nil
            saving = nil
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(tr("common_ok")) { message = nil }
        }
    }

    private var lastBackupText: String {
        guard let at = BackupPolicy.date(environment.settings.backupLastAt) else { return tr("backup_last_none") }
        let kind = environment.settings.backupLastKind == "auto" ? tr("backup_kind_auto") : tr("backup_kind_manual")
        return tr("backup_last", ConnectionTexts.stamp(at) ?? "", kind)
    }

    private var folderText: String {
        guard let url = AutoBackupRunner.folder(environment.settings) else { return tr("backup_auto_no_folder") }
        return tr("backup_auto_folder", url.lastPathComponent)
    }

    /// Kopia do pliku tymczasowego z nazwą jak w Androidzie, potem „Zapisz w…” (przeniesienie w miejsce wybrane przez użytkownika).
    private func create(password: String?) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-export-\(UUID().uuidString)", isDirectory: true)
        let file = folder.appendingPathComponent(BackupManifest.manualFileName(environment.dates.today()))
        let box = progress
        box.start()
        let limit = environment.settings.attachmentLimitMB
        let service = environment.backup
        Task {
            defer { box.running = false }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let result = try await service.write(to: file, password: password, attachmentsCacheMb: limit) { done, total in
                    Task { @MainActor in box.update(done, total) }
                }
                pendingResult = result
                saving = ExportedFile(url: file)
            } catch {
                message = tr("backup_failed", (error as? BackupError)?.message ?? error.localizedDescription)
            }
        }
    }

    private func record(_ result: BackupResult, kind: String) {
        let settings = environment.settings
        settings.backupLastAt = BackupPolicy.stamp(Date())
        settings.backupLastKind = kind
        settings.backupLastChangeCounter = result.changeCounter
        refresh += 1
    }

    private func toggleAuto(_ on: Bool) {
        autoEnabled = on
        environment.settings.backupAutoEnabled = on
        if on, environment.settings.backupAutoFolderBookmark == nil { pickingFolder = true }
        refresh += 1
    }

    private func chooseFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData() else {
            message = tr("backup_auto_no_folder")
            return
        }
        environment.settings.backupAutoFolderBookmark = bookmark
        environment.settings.backupAutoLastError = nil
        refresh += 1
        Task { await AutoBackupRunner.runIfDue(environment) }
    }
}

/// Hasło kopii (opcjonalne, dwa razy) z ostrzeżeniem o pliku bez hasła i nieodzyskiwalnym haśle.
struct CreateBackupSheet: View {
    let onCreate: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var repeated = ""

    private var mismatch: Bool { !password.isEmpty && password != repeated }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(tr("backup_password"), text: $password).textContentType(.newPassword).accessibilityIdentifier("backup-password")
                    SecureField(tr("backup_password_repeat"), text: $repeated).textContentType(.newPassword).accessibilityIdentifier("backup-password-repeat")
                } header: {
                    Text("backup_password_title")
                } footer: {
                    if mismatch {
                        Text("backup_password_mismatch").foregroundStyle(HorselyColor.error)
                    } else {
                        Text("backup_password_warning")
                    }
                }
                Button {
                    onCreate(password.isEmpty ? nil : password)
                    dismiss()
                } label: {
                    Text("backup_choose_location").frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .disabled(mismatch)
                .accessibilityIdentifier("backup-choose-location")
            }
            .navigationTitle(tr("backup_create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common_cancel")) { dismiss() } } }
        }
    }
}

/// Odtworzenie z kopii (Kopia zapasowa i ekran powitalny): wybór pliku, hasło (gdy plik je ma), ekran z datą i liczbami,
/// „Obecne dane zostaną zastąpione”, odtworzenie niepodzielne; błąd zostawia dane bez zmian.
struct RestoreBackupFlow: View {
    /// Po udanym odtworzeniu (np. ustawienie trybu samodzielnego na ekranie powitalnym).
    let onRestored: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var picking = true
    @State private var file: URL?
    @State private var password = ""
    @State private var needsPassword = false
    @State private var manifest: BackupManifest?
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                if needsPassword {
                    Section {
                        SecureField(tr("backup_password"), text: $password).accessibilityIdentifier("restore-password")
                        Button(tr("common_next")) { Task { await inspect() } }.disabled(password.isEmpty)
                    } header: {
                        Text("backup_password_needed")
                    }
                }
                if let manifest {
                    Section {
                        Text(tr(
                            "backup_restore_info", manifest.created.map { Formats.dataStamp($0) } ?? manifest.createdAt, manifest.counts.horses,
                            manifest.counts.entries, manifest.counts.attachments
                        ))
                        Text("backup_restore_warning").font(.subheadline.weight(.semibold)).foregroundStyle(HorselyColor.error)
                        Button(tr("backup_restore_confirm"), role: .destructive) { Task { await restore() } }
                            .frame(minHeight: Spacing.minTouchTarget)
                            .disabled(working)
                            .accessibilityIdentifier("restore-confirm")
                    } header: {
                        Text("backup_restore_title")
                    }
                }
                if working { ProgressView().frame(maxWidth: .infinity) }
                if let failure { Text(failure).foregroundStyle(HorselyColor.error) }
            }
            .navigationTitle(tr("backup_restore"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common_cancel")) { close() } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.horselyBackup, .data]) { result in
                switch result {
                case let .success(url): Task { await open(url) }
                case .failure: close()
                }
            }
        }
        .interactiveDismissDisabled(working)
    }

    /// Kopia pliku do katalogu tymczasowego (dostęp do pliku spoza aplikacji jest tylko chwilowy).
    private func open(_ url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-restore-\(UUID().uuidString).\(BackupManifest.fileExtension)")
        do {
            try FileManager.default.copyItem(at: url, to: copy)
            file = copy
            await inspect()
        } catch {
            failure = tr("backup_corrupted")
        }
    }

    private func inspect() async {
        guard let file else { return }
        failure = nil
        let service = environment.backup
        let secret = password.isEmpty ? nil : password
        do {
            manifest = try await Task.detached { try service.inspect(file, password: secret) }.value
            needsPassword = needsPassword && manifest == nil
        } catch let error as BackupError {
            switch error {
            case .needsPassword: needsPassword = true
            case .wrongPassword:
                needsPassword = true
                failure = tr("backup_wrong_password")
            case .newerVersion: failure = tr("backup_newer")
            default: failure = tr("backup_corrupted")
            }
        } catch {
            failure = tr("backup_corrupted")
        }
    }

    private func restore() async {
        guard let file else { return }
        working = true
        defer { working = false }
        let service = environment.backup
        let secret = password.isEmpty ? nil : password
        do {
            let prepared = try await Task.detached { try service.prepare(file, password: secret) }.value
            defer { service.discard(prepared) }
            try await service.apply(prepared)
            try? FileManager.default.removeItem(at: file)
            await environment.horseDirectory.refresh()
            onRestored()
            dismiss()
        } catch {
            let reason = (error as? BackupError)?.message ?? error.localizedDescription
            failure = tr("backup_restore_failed", reason)
        }
    }

    private func close() {
        if let file { try? FileManager.default.removeItem(at: file) }
        dismiss()
    }
}

/// Postęp zapisu kopii („Zapisywanie kopii… N z M”).
@MainActor
@Observable
final class BackupProgress {
    var running = false
    private(set) var done = 0
    private(set) var total = 1

    func start() {
        running = true
        done = 0
        total = 1
    }

    func update(_ done: Int, _ total: Int) {
        self.done = done
        self.total = total
    }
}
