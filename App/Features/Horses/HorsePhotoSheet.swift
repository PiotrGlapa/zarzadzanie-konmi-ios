import HorselyCore
import HorselyKit
import PhotosUI
import SwiftUI
import UIKit

enum PhotoSheetContext {
    /// Pole „Zdjęcie” w formularzu: wynik czeka na zapis konia.
    case form
    /// Dotknięcie zdjęcia na karcie konia: wynik zapisuje się od razu.
    case card
}

enum PhotoSheetResult {
    case picked(PreparedImage)
    case removed
    case chosenFromAttachments
}

/// Arkusz zdjęcia konia (FR-ZDK-01): „Zrób zdjęcie”, „Wybierz z telefonu” (`PhotosPicker`, bez zgody na bibliotekę),
/// „Wybierz z załączników konia” (na karcie), „Pokaż zdjęcie”, „Usuń zdjęcie” (z potwierdzeniem; tylko odpina). Wybrane zdjęcie
/// przechodzi przez kadrowanie (FR-ZDK-02).
struct HorsePhotoSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let horse: LocalHorse?
    let hasPhoto: Bool
    let context: PhotoSheetContext
    /// Bajty zdjęcia do „Pokaż zdjęcie” (np. oczekujące w formularzu); `nil` — z magazynu.
    var previewData: Data?
    let onResult: (PhotoSheetResult) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cropSource: CropSource?
    @State private var viewerImage: UIImage?
    @State private var showingViewer = false
    @State private var confirmingRemoval = false
    @State private var attachments: [LocalAttachment] = []
    @State private var showingAttachments = false
    @State private var loadFailed = false

    init(horse: LocalHorse?, hasPhoto: Bool, context: PhotoSheetContext, previewData: Data? = nil, onResult: @escaping (PhotoSheetResult) -> Void) {
        self.horse = horse
        self.hasPhoto = hasPhoto
        self.context = context
        self.previewData = previewData
        self.onResult = onResult
    }

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            List {
                Button { showingCamera = true } label: { row("camera.fill", "photo_take") }
                    .disabled(!cameraAvailable)
                    .accessibilityHint(cameraAvailable ? "" : tr("attachments_camera_unavailable"))
                    .accessibilityIdentifier("photo-take")
                PhotosPicker(selection: $pickerItem, matching: .images) { row("photo.on.rectangle", "photo_pick") }
                    .accessibilityIdentifier("photo-pick")
                if context == .card, horse != nil {
                    Button { Task { await openAttachments() } } label: { row("paperclip", "photo_from_attachments") }
                }
                if hasPhoto {
                    Button { Task { await openViewer() } } label: { row("eye", "photo_show") }
                    Button(role: .destructive) { confirmingRemoval = true } label: { row("trash", "photo_remove") }
                }
                if loadFailed { Text("photo_crop_failed").foregroundStyle(HorselyColor.error) }
            }
            .navigationTitle("photo_sheet_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common_close")) { dismiss() } }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    showingCamera = false
                    Task { await prepare(data) }
                } onCancel: {
                    showingCamera = false
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $cropSource) { source in
                PhotoCropView(source: source.image, onCancel: { cropSource = nil }) { result in
                    cropSource = nil
                    onResult(.picked(result))
                    dismiss()
                }
            }
            .sheet(isPresented: $showingViewer) { viewer }
            .sheet(isPresented: $showingAttachments) { attachmentsList }
            .confirmationDialog(tr("photo_remove_title"), isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button(tr("common_delete"), role: .destructive) {
                    onResult(.removed)
                    dismiss()
                }
                Button(tr("common_cancel"), role: .cancel) {}
            } message: {
                Text("photo_remove_text")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ systemImage: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.between + 4) {
            Image(systemName: systemImage).frame(width: 28).foregroundStyle(HorselyColor.primary)
            Text(title)
            Spacer()
        }
        .frame(minHeight: Spacing.minTouchTarget)
        .contentShape(Rectangle())
    }

    // MARK: Ładowanie

    private func load(_ item: PhotosPickerItem) async {
        loadFailed = false
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            loadFailed = true
            pickerItem = nil
            return
        }
        pickerItem = nil
        await prepare(data)
    }

    /// Zmniejsza do 2560 px (bez lokalizacji) i otwiera kadrowanie.
    private func prepare(_ data: Data) async {
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { try ImagePreparer.prepare(data) }.value
            cropSource = CropSource(image: prepared)
        } catch {
            loadFailed = true
        }
    }

    // MARK: Podgląd i załączniki

    private func openViewer() async {
        var data = previewData
        if data == nil, let attachmentId = horse?.photoAttachmentId { data = await environment.horses.originalData(attachmentId: attachmentId) }
        guard let data, let image = UIImage(data: data) else { loadFailed = true; return }
        viewerImage = image
        showingViewer = true
    }

    private var viewer: some View {
        NavigationStack {
            Group {
                if let viewerImage {
                    Image(uiImage: viewerImage).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(tr("photo_show"))
                }
            }
            .background(Color.black)
            .navigationTitle("photo_sheet_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common_close")) { showingViewer = false } } }
        }
    }

    private func openAttachments() async {
        guard let horse else { return }
        attachments = (try? await environment.horses.imageAttachments(horseId: horse.id)) ?? []
        showingAttachments = true
    }

    private var attachmentsList: some View {
        NavigationStack {
            Group {
                if attachments.isEmpty {
                    Text("photo_no_images").multilineTextAlignment(.center).padding(Spacing.screenEdge)
                } else {
                    List(attachments, id: \.id) { attachment in
                        Button {
                            Task {
                                if let horse { try? await environment.horses.choosePhoto(horseId: horse.id, attachmentId: attachment.id) }
                                showingAttachments = false
                                onResult(.chosenFromAttachments)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(attachment.fileName)
                                Spacer()
                                if attachment.id == horse?.photoAttachmentId { Image(systemName: "checkmark").foregroundStyle(HorselyColor.primary) }
                            }
                            .frame(minHeight: Spacing.minTouchTarget)
                        }
                    }
                }
            }
            .navigationTitle("photo_choose_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common_close")) { showingAttachments = false } } }
        }
    }
}

/// Obraz do kadrowania jako element prezentacji pełnoekranowej (`fullScreenCover(item:)` wymaga `Identifiable`).
private struct CropSource: Identifiable {
    let id = UUID()
    let image: PreparedImage
}

/// Aparat (`UIImagePickerController`): zdjęcie wraca jako dane obrazu; brak aparatu obsługuje arkusz (przycisk nieaktywny).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    let onCancel: () -> Void

    init(onImage: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
        self.onImage = onImage
        self.onCancel = onCancel
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
                onImage(data)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
