import HorselyCore
import HorselyKit
import QuickLook
import SwiftUI

/// Podgląd załącznika (FR-M-ZAL-05/06): plik z pamięci, z kolejki albo pobrany z programu; podgląd systemowy (obraz z powiększaniem,
/// PDF, wideo z przewijaniem, dokumenty), opis; „Udostępnij”, „Zapisz na urządzeniu”, „Ustaw jako zdjęcie główne” (obraz konia)
/// i „Usuń” z potwierdzeniem (trafia do kosza programu; niewysłany — znika z kolejki).
struct AttachmentViewer: View {
    let attachment: LocalAttachment

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var failure: String?
    @State private var saving: ExportedFile?
    @State private var confirmingDelete = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let file {
                    QuickLookPreview(url: file).ignoresSafeArea(edges: .bottom)
                } else if let failure {
                    VStack(spacing: Spacing.between) {
                        HIcon(name: AttachmentTile.icon(attachment.contentType), size: 48).foregroundStyle(HorselyColor.onSurfaceVariant)
                        Text(failure).multilineTextAlignment(.center)
                        Button(tr("common_retry")) { Task { await load() } }
                    }
                    .padding(Spacing.screenEdge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let text = attachment.description {
                    Text(text)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.screenEdge)
                        .background(HorselyColor.surfaceVariant)
                }
            }
            .background(HorselyColor.background)
            .navigationTitle(attachment.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common_close")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { actions }
            }
        }
        .task { await load() }
        .confirmationDialog(tr("attachments_delete_title"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(tr("attachments_viewer_delete"), role: .destructive) { Task { await delete() } }
            Button(tr("common_cancel"), role: .cancel) {}
        } message: {
            Text("attachments_delete_message")
        }
        .fileMover(isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }), file: saving?.url) { result in
            message = (try? result.get()) != nil ? tr("attachments_saved") : tr("reports_save_failed")
            saving = nil
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(tr("common_ok")) { message = nil }
        }
    }

    private var canSetMainPhoto: Bool {
        FilePolicy.isImage(attachment.contentType) && attachment.horseId != nil
    }

    private var actions: some View {
        Menu {
            if let file {
                ShareLink(item: file) { Label(tr("attachments_viewer_share"), systemImage: "square.and.arrow.up") }
                Button { save(file) } label: { Label(tr("attachments_viewer_save"), systemImage: "square.and.arrow.down") }
            }
            if canSetMainPhoto {
                Button { Task { await setMainPhoto() } } label: { Label(tr("attachments_viewer_set_main"), systemImage: "photo") }
            }
            Button(role: .destructive) { confirmingDelete = true } label: { Label(tr("attachments_viewer_delete"), systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").accessibilityLabel(tr("attachments_title"))
        }
        .accessibilityIdentifier("attachment-actions")
    }

    /// Plik pod nazwą załącznika (kopia w katalogu tymczasowym — podgląd, udostępnianie i zapis widzą prawdziwą nazwę).
    private func load() async {
        failure = nil
        do {
            let source = try await environment.attachments.content(attachment)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-view-\(attachment.id)", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let named = folder.appendingPathComponent(attachment.fileName)
            try FileManager.default.copyItem(at: source, to: named)
            file = named
        } catch AttachmentError.fileUnavailable {
            failure = tr("attachments_file_unavailable")
        } catch {
            failure = tr("attachments_download_failed")
        }
    }

    private func save(_ source: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-save-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: copy)
            saving = ExportedFile(url: copy)
        } catch {
            message = tr("reports_save_failed")
        }
    }

    private func setMainPhoto() async {
        guard let horseId = attachment.horseId else { return }
        do {
            try await environment.horses.choosePhoto(horseId: horseId, attachmentId: attachment.id)
            message = tr("attachments_main_set")
            if environment.workMode == .online { Task { _ = await environment.sendQueue() } }
        } catch {
            message = tr("photo_failed")
        }
    }

    private func delete() async {
        do {
            if await environment.attachments.isQueued(attachment.id) {
                try await environment.attachments.withdraw(attachment.id)
            } else {
                _ = try await environment.entries.delete(.attachment, id: attachment.id)
                if environment.workMode == .online { Task { _ = await environment.sendQueue() } }
            }
            environment.router.banner = BannerMessage(text: tr("attachments_deleted"))
            dismiss()
        } catch {
            message = tr("attachments_download_failed")
        }
    }
}

/// Podgląd systemowy (QuickLook) osadzony w widoku.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
