import AVFoundation
import CoreTransferable
import HorselyCore
import HorselyKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Dodawanie plików (FR-M-ZAL-01): „Zrób zdjęcie” (aparat), „Wybierz z galerii” (`PhotosPicker`, wiele, zdjęcia i wideo — bez
/// zgody na bibliotekę), „Wybierz plik” (aplikacja Pliki: PDF, DOCX, XLSX, TXT, obrazy, wideo); opis do 500 znaków dotyczy
/// wybranych plików. W trybie samodzielnym przy < 500 MB wolnego miejsca — ostrzeżenie.
struct AddAttachmentSheet: View {
    let lowStorage: Bool
    let onPicked: ([PickedFile], String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var galleryItems: [PhotosPickerItem] = []
    @State private var showingGallery = false
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var loading = false
    @State private var message: String?

    static let fileTypes: [UTType] = [
        .jpeg, .png, .heic, .webP, .pdf, .plainText, .mpeg4Movie, .quickTimeMovie,
        UTType(filenameExtension: "docx") ?? .data, UTType(filenameExtension: "xlsx") ?? .data,
    ]

    private var limitExceeded: Bool { description.count > AttachmentStore.descriptionLimit }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("attachments_description", text: $description, axis: .vertical)
                        .lineLimit(1 ... 4)
                        .accessibilityIdentifier("attachments-description")
                } footer: {
                    if limitExceeded {
                        Text("attachments_description_limit").foregroundStyle(HorselyColor.error)
                    } else {
                        Text("\(description.count)/\(AttachmentStore.descriptionLimit)")
                    }
                }
                if let message {
                    Text(message).font(.subheadline).foregroundStyle(HorselyColor.error)
                }
                if lowStorage {
                    Text("attachments_low_storage").font(.subheadline).foregroundStyle(HorselyColor.error)
                }
                Section {
                    sourceButton("photo_camera", "attachments_camera", identifier: "attachments-camera") { openCamera() }
                    sourceButton("photo_library", "attachments_gallery", identifier: "attachments-gallery") { showingGallery = true }
                    sourceButton("attach_file", "attachments_files", identifier: "attachments-files") { showingFiles = true }
                }
                .disabled(limitExceeded || loading)
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("attachments_add_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common_cancel")) { dismiss() } } }
        }
        .photosPicker(isPresented: $showingGallery, selection: $galleryItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos]))
        .onChange(of: galleryItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadGallery(items) }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: Self.fileTypes, allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result, !urls.isEmpty else { return }
            finish(urls.map { .file($0, name: $0.lastPathComponent, mimeType: UTType(filenameExtension: $0.pathExtension)?.preferredMIMEType, securityScoped: true) })
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(onImage: { data in
                showingCamera = false
                finish([.data(data, name: "zdjecie-\(Self.stamp()).jpg", mimeType: "image/jpeg")])
            }, onCancel: { showingCamera = false })
            .ignoresSafeArea()
        }
    }

    private func sourceButton(_ icon: String, _ title: LocalizedStringKey, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.between) {
                HIcon(name: icon, size: 24).foregroundStyle(HorselyColor.primary)
                Text(title).foregroundStyle(HorselyColor.onBackground)
            }
            .frame(minHeight: Spacing.minTouchTarget)
        }
        .accessibilityIdentifier(identifier)
    }

    /// Aparat: bez urządzenia — komunikat; odmowa zgody — „wybierz z galerii albo plik”.
    private func openCamera() {
        message = nil
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            message = tr("attachments_camera_unavailable")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            message = tr("attachments_camera_denied")
        default:
            showingCamera = true
        }
    }

    private func loadGallery(_ items: [PhotosPickerItem]) async {
        loading = true
        var picked: [PickedFile] = []
        for (index, item) in items.enumerated() {
            let types = item.supportedContentTypes
            if types.contains(where: { $0.conforms(to: .movie) }), let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                picked.append(.file(movie.url, name: movie.url.lastPathComponent, mimeType: UTType(filenameExtension: movie.url.pathExtension)?.preferredMIMEType, securityScoped: false))
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                let type = types.first { $0.conforms(to: .image) } ?? .jpeg
                let suffix = type.preferredFilenameExtension ?? "jpg"
                picked.append(.data(data, name: "zdjecie-\(Self.stamp())-\(index + 1).\(suffix)", mimeType: type.preferredMIMEType))
            }
        }
        galleryItems = []
        loading = false
        finish(picked)
    }

    private func finish(_ picked: [PickedFile]) {
        guard !picked.isEmpty else { return }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        onPicked(picked, text.isEmpty ? nil : text)
        dismiss()
    }

    static func stamp() -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        return String(format: "%04d%02d%02d-%02d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}

/// Wideo z galerii jako plik (bez wczytywania do pamięci): kopia w katalogu tymczasowym.
struct PickedMovie: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-picked-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedMovie(url: target)
        }
    }
}
