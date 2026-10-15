import Foundation

/// Dostęp do plików wzorcowych (`Resources/parity`, `Resources/golden`) skopiowanych z Androida.
/// Układ katalogów w pakiecie zasobów zależy od platformy, dlatego sprawdzane są oba warianty ścieżki.
enum Fixtures {
    static func url(_ path: String) -> URL {
        let base = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        let candidates = [
            base.appendingPathComponent("Resources/\(path)"),
            base.appendingPathComponent(path),
            Bundle.module.bundleURL.appendingPathComponent("Resources/\(path)"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: url(path))
    }

    static func string(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }
}
