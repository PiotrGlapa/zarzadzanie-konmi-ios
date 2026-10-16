import HorselyCore
import HorselyKit
import SwiftUI
import UniformTypeIdentifiers

/// Tekst z katalogu `Localizable.xcstrings` dołączonego do rozszerzenia (klucze ze `strings.xml` Androida).
func shareText(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

func shareText(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: shareText(key), locale: Locale(identifier: "pl_PL"), arguments: arguments)
}

/// Przebieg udostępniania: kopia plików do skrzynki App Group (sprawdzenie typu i rozmiaru) → wybór konia → wpis konia albo
/// „Nowa notatka” → zatwierdzenie pozycji skrzynki → „Gotowe”. Rozszerzenie tylko czyta bazę; załączniki tworzy aplikacja
/// (przy otwarciu i w tle). Tryb nieustawiony albo brak parowania w trybie online — komunikat bez kopiowania plików.
@MainActor
@Observable
final class ShareFlowModel {
    enum Step: Equatable {
        case preparing
        case unsetMode
        case notPaired
        case horse
        case target
        case done
        case failed
    }

    /// Komunikat trybu nieustawionego (contracts/app-entry-points-ios.md — tekst kontraktu iOS).
    static let unsetModeMessage = "Najpierw otwórz aplikację Horsely i wybierz tryb pracy"

    private(set) var step: Step = .preparing
    private(set) var files: [SharedInboxEntry.File] = []
    private(set) var rejected: [String] = []
    private(set) var horses: [LocalHorse] = []
    private(set) var horse: LocalHorse?
    private(set) var entries: [TimelineItem] = []
    private(set) var online = false
    var query = ""
    var noteTitle = ""

    private let items: [NSExtensionItem]
    private let finish: (_ cancelled: Bool) -> Void
    private var inbox: SharedInbox?
    private var folder: URL?
    private var store: RecordStore?

    init(items: [NSExtensionItem], finish: @escaping (_ cancelled: Bool) -> Void) {
        self.items = items
        self.finish = finish
    }

    var visibleHorses: [LocalHorse] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return horses }
        return horses.filter { $0.name.localizedCaseInsensitiveContains(text) || ($0.stableName?.localizedCaseInsensitiveContains(text) ?? false) }
    }

    func start() async {
        let settings = SettingsStore()
        guard settings.workMode != .unset, let group = AppDatabase.appGroupDirectory(identifier: SettingsStore.appGroupSuiteName),
              let database = try? AppDatabase.openReadOnly(in: group) else {
            step = .unsetMode
            return
        }
        let store = RecordStore(database: database)
        self.store = store
        online = settings.workMode == .online
        if online, (try? await store.read({ try $0.pairingInfo() }))?.pairedAt == nil {
            step = .notPaired
            return
        }
        let inbox = SharedInbox.inGroup(group)
        self.inbox = inbox
        do {
            let folder = try inbox.newFolder()
            self.folder = folder
            let providers = items.flatMap { $0.attachments ?? [] }
            for (index, provider) in providers.enumerated() {
                switch await Self.copy(provider, into: folder, index: index) {
                case let .copied(file): files.append(file)
                case let .rejected(reason): rejected.append(reason)
                }
            }
        } catch {
            step = .failed
            return
        }
        horses = ((try? await store.read { access in
            try access.query(.horse).compactMap { try $0.record(as: LocalHorse.self) }
        }) ?? []).sorted { PolishNames.isOrdered($0.name, before: $1.name) }
        step = .horse
    }

    func pick(_ horse: LocalHorse) async {
        self.horse = horse
        entries = []
        step = .target
        guard let store else { return }
        let repository = EntryRepository(store: store, dates: SystemDateProvider(), mode: { .standalone })
        entries = (try? await repository.timeline(TimelineFilter(horseId: horse.id, pageSize: 20)).items) ?? []
    }

    func back() {
        horse = nil
        step = .horse
    }

    func attach(to item: TimelineItem) {
        let ownerType: AttachmentOwnerType = switch item.entryType {
        case .vetVisit: .vetVisit
        case .farrierVisit: .farrierVisit
        case .physioVisit: .physioVisit
        case .specialistVisit: .specialistVisit
        case .competitionStart: .competitionStart
        case .purchase: .purchase
        case .note: .note
        }
        commit(.entry(ownerType: ownerType, ownerId: item.id))
    }

    func attachToNewNote() {
        commit(.newNote(title: noteTitle))
    }

    func cancel() {
        if let folder, step != .done { inbox?.remove(folder) }
        finish(true)
    }

    func close() {
        finish(false)
    }

    private func commit(_ target: SharedInboxEntry.Target) {
        guard let horse, let inbox, let folder, !files.isEmpty else { return }
        do {
            try inbox.commit(SharedInboxEntry(horseId: horse.id, target: target, files: files), folder: folder)
            step = .done
        } catch {
            step = .failed
        }
    }

    // MARK: Kopia plików

    enum CopyResult: Sendable {
        case copied(SharedInboxEntry.File)
        case rejected(String)
    }

    /// Kopia strumieniowa pliku z dostawcy do folderu skrzynki; plik niedozwolony albo > 100 MB — opis przyczyny.
    static func copy(_ provider: NSItemProvider, into folder: URL, index: Int) async -> CopyResult {
        guard let type = Self.fileType(of: provider) else {
            return .rejected(shareText("attachments_share_rejected", provider.suggestedName ?? "plik"))
        }
        let suggested = provider.suggestedName ?? "plik-\(index + 1)"
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: .rejected(suggested))
                    return
                }
                let baseName = suggested.contains(".") ? suggested : (type.preferredFilenameExtension.map { "\(suggested).\($0)" } ?? url.lastPathComponent)
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                switch FilePolicy.check(fileName: baseName, mimeType: type.preferredMIMEType, sizeBytes: size) {
                case let .rejected(reason):
                    continuation.resume(returning: .rejected("\(baseName) — \(reason)"))
                case let .allowed(fileName, contentType):
                    let name = Self.unique(fileName, in: folder)
                    do {
                        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
                        continuation.resume(returning: .copied(SharedInboxEntry.File(name: name, contentType: contentType)))
                    } catch {
                        continuation.resume(returning: .rejected(baseName))
                    }
                }
            }
        }
    }

    /// Najlepszy typ pliku dostawcy: wideo, obraz, PDF, tekst, inne dane.
    static func fileType(of provider: NSItemProvider) -> UTType? {
        let registered: [UTType] = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
        let preferred: [UTType] = [.movie, .image, .pdf, .plainText, .data]
        for candidate in preferred {
            if let match = registered.first(where: { $0.conforms(to: candidate) }) { return match }
        }
        return nil
    }

    /// Nazwa bez kolizji w folderze („zdjecie.jpg”, „zdjecie-2.jpg”…).
    nonisolated static func unique(_ name: String, in folder: URL) -> String {
        var candidate = name
        var counter = 2
        let stem = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = suffix.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(suffix)"
            counter += 1
        }
        return candidate
    }
}

struct ShareFlowView: View {
    @Bindable var model: ShareFlowModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(shareText("attachments_share_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if model.step == .target {
                            Button(shareText("common_back")) { model.back() }
                        } else if model.step != .done {
                            Button(shareText("common_cancel")) { model.cancel() }
                        }
                    }
                    if model.step == .done || model.step == .unsetMode || model.step == .notPaired || model.step == .failed {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(shareText("common_ok")) { model.step == .done ? model.close() : model.cancel() }
                        }
                    }
                }
        }
        .tint(Color(red: 0x2E / 255, green: 0x7D / 255, blue: 0x32 / 255))
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .preparing:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unsetMode:
            message(ShareFlowModel.unsetModeMessage)
        case .notPaired:
            message(shareText("attachments_share_no_pairing"))
        case .failed:
            message(shareText("photo_failed"))
        case .done:
            message(shareText(model.online ? "common_saved_queued" : "common_saved"))
        case .horse:
            List {
                summary
                if !model.files.isEmpty {
                    Section(shareText("attachments_share_choose_horse")) {
                        ForEach(model.visibleHorses, id: \.id) { horse in
                            Button {
                                Task { await model.pick(horse) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(horse.name).foregroundStyle(.primary)
                                    if let stable = horse.stableName, !stable.isEmpty { Text(stable).font(.footnote).foregroundStyle(.secondary) }
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
            .searchable(text: $model.query, prompt: shareText("horse_picker_search"))
        case .target:
            List {
                summary
                Section(model.horse?.name ?? "") {
                    TextField(shareText("field_title"), text: $model.noteTitle)
                    Button(shareText("attachments_share_new_note")) { model.attachToNewNote() }
                        .frame(minHeight: 44)
                }
                if !model.entries.isEmpty {
                    Section {
                        ForEach(model.entries) { item in
                            Button {
                                model.attach(to: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text("\(shareText(Self.typeKey(item.entryType))) · \(Formats.date(item.date))").font(.footnote).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
        }
    }

    private var summary: some View {
        Section {
            Text(shareText("attachments_share_files_count", model.files.count)).font(.headline)
            if !model.rejected.isEmpty {
                Text(shareText("attachments_share_rejected", model.rejected.joined(separator: "; "))).foregroundStyle(.red)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.headline).multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func typeKey(_ type: TimelineEntryType) -> String {
        switch type {
        case .vetVisit: "timeline_type_vet_visit"
        case .farrierVisit: "timeline_type_farrier_visit"
        case .physioVisit: "timeline_type_physio_visit"
        case .specialistVisit: "timeline_type_specialist_visit"
        case .competitionStart: "timeline_type_competition_start"
        case .purchase: "timeline_type_purchase"
        case .note: "timeline_type_note"
        }
    }
}
