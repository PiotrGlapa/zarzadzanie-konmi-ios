import AVFoundation
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// „Zdjęcie / film” w trakcie jazdy (Task 17, ZAT-05 = Android 3.0.2 `RideMediaFiles.kt` + systemowy aparat): `UIImagePickerController`
// ze zdjęciem albo filmem, plik w `ride-media/` w kontenerze aplikacji, w sesji adres względny `ride-media/<uuid>.<rozszerzenie>`.
// Zgody: aparat — `NSCameraUsageDescription`, dźwięk filmu — `NSMicrophoneUsageDescription` (system pyta przy pierwszym użyciu).

/// Pliki zdjęć i filmów z jazd. Adres w sesji jest względny (`ride-media/<nazwa>`), bo ścieżka bezwzględna kontenera iOS zmienia się
/// między instalacjami i przy odtworzeniu kopii. Obce adresy (poza katalogiem jazd, z `..` albo `/` w nazwie) są pomijane.
struct RideMediaFiles: Sendable {
    static let directoryName = "ride-media"

    let root: URL

    /// Nowy, pusty plik (`extension` bez kropki): adres do zapisania w sesji i położenie na dysku.
    func newFile(extension ext: String) throws -> (uri: String, url: URL) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.lowercased()).\(ext)"
        return ("\(Self.directoryName)/\(name)", root.appendingPathComponent(name, isDirectory: false))
    }

    /// Plik wskazany adresem z sesji albo `nil` dla adresu obcego.
    func url(for uri: String) -> URL? {
        let prefix = "\(Self.directoryName)/"
        guard uri.hasPrefix(prefix) else { return nil }
        let name = String(uri.dropFirst(prefix.count))
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.contains("..") else { return nil }
        return root.appendingPathComponent(name, isDirectory: false)
    }

    /// Usuwa pliki jazdy (odrzucenie, nieudane dodanie); obce adresy pomija.
    func delete(_ uris: [String]) {
        for uri in uris {
            guard let url = url(for: uri) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Co zrobić aparatem.
enum RideCameraMode: String, Identifiable, Sendable {
    case photo
    case video

    var id: String { rawValue }
}

/// Plik zrobiony aparatem i zapisany w katalogu jazd.
struct RideCapturedMedia: Sendable {
    let uri: String
    let contentType: String
}

/// Systemowy aparat (`UIImagePickerController`) w trybie zdjęcia albo filmu. Zdjęcie trafia do pliku JPEG, film jest przenoszony z katalogu
/// tymczasowego aparatu. Błąd zapisu zgłasza `nil` (ekran pokazuje „Nie udało się dodać pliku do jazdy.”).
struct RideCameraPicker: UIViewControllerRepresentable {
    let mode: RideCameraMode
    let files: RideMediaFiles
    let onResult: (RideCapturedMedia?) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        switch mode {
        case .photo:
            picker.mediaTypes = [UTType.image.identifier]
            picker.cameraCaptureMode = .photo
        case .video:
            picker.mediaTypes = [UTType.movie.identifier]
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeHigh
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(files: files, onResult: onResult, onCancel: onCancel) }

    /// Czy można otworzyć aparat; inaczej klucz komunikatu (`ride_camera_unavailable`, `ride_camera_denied`).
    static func unavailableMessageKey() -> String? {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return "ride_camera_unavailable" }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: return "ride_camera_denied"
        default: return nil
        }
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let files: RideMediaFiles
        let onResult: (RideCapturedMedia?) -> Void
        let onCancel: () -> Void

        init(files: RideMediaFiles, onResult: @escaping (RideCapturedMedia?) -> Void, onCancel: @escaping () -> Void) {
            self.files = files
            self.onResult = onResult
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let movie = info[.mediaURL] as? URL {
                onResult(store(movie: movie))
            } else if let image = info[.originalImage] as? UIImage {
                onResult(store(image: image))
            } else {
                onResult(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        private func store(image: UIImage) -> RideCapturedMedia? {
            guard let data = image.jpegData(compressionQuality: 0.9), let file = try? files.newFile(extension: "jpg") else { return nil }
            do {
                try data.write(to: file.url, options: .atomic)
                return RideCapturedMedia(uri: file.uri, contentType: "image/jpeg")
            } catch {
                return nil
            }
        }

        private func store(movie: URL) -> RideCapturedMedia? {
            let ext = movie.pathExtension.isEmpty ? "mov" : movie.pathExtension.lowercased()
            guard let file = try? files.newFile(extension: ext) else { return nil }
            do {
                try FileManager.default.moveItem(at: movie, to: file.url)
            } catch {
                do {
                    try FileManager.default.copyItem(at: movie, to: file.url)
                } catch {
                    return nil
                }
            }
            let type = UTType(filenameExtension: ext)?.preferredMIMEType ?? "video/quicktime"
            return RideCapturedMedia(uri: file.uri, contentType: type)
        }
    }
}
