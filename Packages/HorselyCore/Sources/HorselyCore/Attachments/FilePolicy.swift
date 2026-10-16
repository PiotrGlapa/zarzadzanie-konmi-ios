import Foundation

/// Wynik sprawdzenia pliku przed dodaniem do kolejki albo magazynu.
public enum FileVerdict: Equatable, Sendable {
    /// `fileName` — bezpieczna nazwa (bez ścieżki) z rozszerzeniem; `contentType` — typ kanoniczny wysyłany do programu.
    case allowed(fileName: String, contentType: String)
    case rejected(reason: String)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

/// Dozwolone pliki (FR-M-ZAL-02, `FilePolicy.kt`): jpg, png, heic, webp, pdf, docx, xlsx, txt, mp4, mov; najwyżej 100 MB.
/// Sprawdzenie dotyczy rozszerzenia i typu MIME — typ ogólny albo brak typu nie dyskwalifikuje pliku z dozwolonym rozszerzeniem,
/// ale typ wskazujący na coś innego (np. aplikację) tak.
public enum FilePolicy {
    public static let maxBytes: Int64 = 100 * 1024 * 1024

    static let byExtension: [String: String] = [
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "heic": "image/heic",
        "webp": "image/webp",
        "pdf": "application/pdf",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "txt": "text/plain",
        "mp4": "video/mp4",
        "mov": "video/quicktime",
    ]

    /// Dodatkowe typy MIME, które systemy podają dla tych samych plików.
    static let mimeAliases: [String: String] = ["image/heif": "image/heic", "image/jpg": "image/jpeg", "video/x-quicktime": "video/quicktime"]

    static let extensionForMime: [String: String] = [
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/heic": "heic",
        "image/webp": "webp",
        "application/pdf": "pdf",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
        "text/plain": "txt",
        "video/mp4": "mp4",
        "video/quicktime": "mov",
    ]

    static let generic: Set<String> = ["", "application/octet-stream", "binary/octet-stream"]

    static let typesMessage = "Dozwolone pliki: JPG, PNG, HEIC, WEBP, PDF, DOCX, XLSX, TXT, MP4, MOV."

    public static func check(fileName: String, mimeType: String?, sizeBytes: Int64) -> FileVerdict {
        if sizeBytes <= 0 { return .rejected(reason: "Plik jest pusty.") }
        if sizeBytes > maxBytes { return .rejected(reason: "Plik jest za duży (najwyżej 100 MB).") }

        let safeName = sanitize(fileName)
        let fileExtension = Self.fileExtension(safeName)
        let mime = canonicalMime(mimeType)

        if let canonical = byExtension[fileExtension] {
            if let mime, !generic.contains(mime), mime != canonical {
                return .rejected(reason: "Typ pliku nie zgadza się z jego rozszerzeniem. \(typesMessage)")
            }
            return .allowed(fileName: safeName, contentType: canonical)
        }
        // Plik z innej aplikacji bywa bez rozszerzenia, ale z dobrym typem MIME.
        if fileExtension.isEmpty, let mime, let suffix = extensionForMime[mime] {
            return .allowed(fileName: "\(safeName).\(suffix)", contentType: mime)
        }
        return .rejected(reason: "Ten typ pliku nie jest dozwolony. \(typesMessage)")
    }

    /// Czy plik to obraz poddawany przygotowaniu (zmniejszenie, usunięcie lokalizacji).
    public static func isImage(_ contentType: String) -> Bool { contentType.hasPrefix("image/") }

    /// Rozszerzenie nazwy małymi literami (bez kropki); pusty napis — brak.
    public static func fileExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    static func canonicalMime(_ mimeType: String?) -> String? {
        guard let raw = mimeType else { return nil }
        let head = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let value = head.trimmingCharacters(in: .whitespaces).lowercased()
        return mimeAliases[value] ?? value
    }

    /// Sama nazwa pliku: bez katalogów (także w stylu Windows) i bez znaków sterujących.
    static func sanitize(_ name: String) -> String {
        let afterSlash = name.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? name
        let leaf = afterSlash.split(separator: "\\", omittingEmptySubsequences: false).last.map(String.init) ?? afterSlash
        var scalars = String.UnicodeScalarView()
        for scalar in leaf.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) { scalars.append(scalar) }
        let cleaned = String(scalars).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "plik" : cleaned
    }
}
