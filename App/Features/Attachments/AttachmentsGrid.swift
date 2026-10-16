import HorselyCore
import HorselyKit
import SwiftUI

/// Załączniki wpisu albo konia (T115, FR-M-ZAL-01/05): nagłówek z „Dodaj załącznik”, siatka miniatur (pliki bez miniatury — ikona
/// rodzaju i nazwa), oznaczenie „czeka na wysłanie” / „wymaga poprawy”; dotknięcie otwiera podgląd.
struct AttachmentsSection: View {
    let owner: AttachmentOwner
    /// Zakładka „Załączniki” konia: wszystkie załączniki konia (także wpisów), dodawanie — do konia.
    var horseWide = false

    @Environment(AppEnvironment.self) private var environment
    @State private var attachments: [LocalAttachment]?
    @State private var adding = false
    @State private var opened: LocalAttachment?
    @State private var working = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.between) {
            // Przy dużym tekście przycisk przechodzi pod tytuł (bez łamania słów).
            ViewThatFits(in: .horizontal) {
                HStack {
                    title
                    Spacer()
                    addButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                    addButton
                }
            }
            if let attachments {
                if attachments.isEmpty {
                    Text("attachments_empty").font(.subheadline).foregroundStyle(HorselyColor.onSurfaceVariant)
                } else {
                    AttachmentsGrid(attachments: attachments) { opened = $0 }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.between)
            }
        }
        .task(id: environment.dataRevision) { await load() }
        .sheet(isPresented: $adding) {
            AddAttachmentSheet(lowStorage: environment.workMode == .standalone && environment.attachments.isLowOnStorage()) { picked, description in
                Task { await add(picked, description: description) }
            }
        }
        .sheet(item: $opened) { attachment in
            AttachmentViewer(attachment: attachment)
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(tr("common_ok")) { message = nil }
        }
    }

    private var title: some View {
        HStack(spacing: Spacing.between) {
            Text("attachments_title").font(.headline).fixedSize().accessibilityAddTraits(.isHeader)
            if working { ProgressView() }
        }
    }

    private var addButton: some View {
        Button {
            adding = true
        } label: {
            Label { Text("attachments_add").fixedSize() } icon: { HIcon(name: "attach_file", size: 20) }
                .frame(minHeight: Spacing.minTouchTarget)
        }
        .disabled(working)
        .accessibilityIdentifier("attachments-add")
    }

    private func load() async {
        attachments = horseWide
            ? try? await environment.attachments.attachments(horseId: owner.id)
            : try? await environment.attachments.attachments(ownerId: owner.id)
    }

    /// Przygotowanie plików poza wątkiem głównym (zmniejszanie zdjęć), potem zapis; pominięte pliki — komunikat z przyczyną.
    private func add(_ picked: [PickedFile], description: String?) async {
        working = true
        defer { working = false }
        let store = environment.attachments
        let (ready, rejected) = await Task.detached(priority: .userInitiated) { PickedFile.prepare(picked, with: store) }.value
        if !ready.isEmpty {
            do {
                try await store.add(owner, ready.map { PendingAttachment(file: $0, description: description) })
                await load()
                if environment.workMode == .online { Task { _ = await environment.sendQueue() } }
            } catch {
                ready.forEach(store.discard)
                message = tr("attachments_share_rejected", error.localizedDescription)
                return
            }
        }
        if !rejected.isEmpty { message = tr("attachments_share_rejected", rejected.joined(separator: " ")) }
    }
}

/// Plik wybrany w arkuszu dodawania: dane (aparat, galeria) albo plik (aplikacja Pliki, wideo z galerii).
enum PickedFile: Sendable {
    case data(Data, name: String, mimeType: String?)
    case file(URL, name: String?, mimeType: String?, securityScoped: Bool)

    /// Sprawdza i kopiuje pliki do katalogu importu; zwraca gotowe pliki i opisy pominiętych („plik.exe — Ten typ…”).
    static func prepare(_ picked: [PickedFile], with store: AttachmentStore) -> (ready: [ImportedFile], rejected: [String]) {
        var ready: [ImportedFile] = []
        var rejected: [String] = []
        for item in picked {
            do {
                switch item {
                case let .data(data, name, mimeType):
                    ready.append(try store.prepare(data: data, fileName: name, mimeType: mimeType))
                case let .file(url, name, mimeType, scoped):
                    let accessing = scoped && url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    ready.append(try store.prepare(fileAt: url, fileName: name, mimeType: mimeType))
                    if !scoped { try? FileManager.default.removeItem(at: url) }
                }
            } catch let AttachmentError.rejected(reason) {
                rejected.append("\(item.displayName) — \(reason)")
            } catch {
                rejected.append(item.displayName)
            }
        }
        return (ready, rejected)
    }

    var displayName: String {
        switch self {
        case let .data(_, name, _): name
        case let .file(url, name, _, _): name ?? url.lastPathComponent
        }
    }
}

/// Siatka kafli 96 pt (jak na Androidzie).
struct AttachmentsGrid: View {
    let attachments: [LocalAttachment]
    let onOpen: (LocalAttachment) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: AttachmentTile.side), spacing: Spacing.between)], alignment: .leading, spacing: Spacing.between) {
            ForEach(attachments) { attachment in
                Button { onOpen(attachment) } label: { AttachmentTile(attachment: attachment) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(attachment.fileName)
                    .accessibilityHint(tr("attachments_open", attachment.fileName))
                    .accessibilityIdentifier("attachment-tile")
            }
        }
    }
}

/// Kafel: miniatura (z pamięci albo programu) albo ikona rodzaju z nazwą; pasek oznaczenia kolejki na dole.
struct AttachmentTile: View {
    static let side: CGFloat = 96

    let attachment: LocalAttachment
    @Environment(AppEnvironment.self) private var environment
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12).fill(HorselyColor.surfaceVariant)
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: Self.side, height: Self.side).clipped()
            } else {
                VStack(spacing: 4) {
                    HIcon(name: Self.icon(attachment.contentType), size: 28).foregroundStyle(HorselyColor.onSurfaceVariant)
                    Text(attachment.fileName).font(.caption2).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(HorselyColor.onSurfaceVariant)
                }
                .padding(6)
                .frame(width: Self.side, height: Self.side)
            }
            if let marker = environment.marker(.attachment, id: attachment.id) {
                Text(LocalizedStringKey(RecordMarkerLabel.key(marker)))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(HorselyColor.onPrimary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HorselyColor.primary.opacity(0.85))
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: attachment.id) {
            guard FilePolicy.isImage(attachment.contentType), let data = await environment.attachments.thumbnail(attachment) else { return }
            thumbnail = UIImage(data: data)
        }
    }

    static func icon(_ contentType: String) -> String {
        if contentType.hasPrefix("image/") { return "image" }
        if contentType.hasPrefix("video/") { return "videocam" }
        if contentType == "application/pdf" { return "picture_as_pdf" }
        return "description"
    }
}
