import Foundation
import HorselyCore

/// Dziennik diagnostyczny (NFR-M-06, data-model.md §9): pliki tekstowe w App Group, rotacja 2 × 2,5 MB (łącznie 5 MB).
/// Wpis: czas, kategoria, komunikat — bez danych osobowych (nazw koni, kwot, treści wpisów). Zapis jest szeregowany blokadą,
/// więc można pisać z wielu wątków i z rozszerzenia.
public final class DiagnosticLog: @unchecked Sendable {
    public static let maxFileBytes = 2_500_000

    private let directory: URL
    private let dates: any DateProvider
    private let lock = NSLock()
    private let maxBytes: Int

    private var current: URL { directory.appendingPathComponent("diagnostic-0.log") }
    private var previous: URL { directory.appendingPathComponent("diagnostic-1.log") }

    public init(directory: URL, dates: any DateProvider = SystemDateProvider(), maxFileBytes: Int = DiagnosticLog.maxFileBytes) {
        self.directory = directory
        self.dates = dates
        self.maxBytes = maxFileBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Dodaje wpis; błędy zapisu są połykane (dziennik nie może psuć działania aplikacji).
    public func log(_ category: String, _ message: String) {
        let line = "\(dates.now().description)\t\(Self.clean(category))\t\(Self.clean(message))\n"
        lock.lock()
        defer { lock.unlock() }
        let data = Data(line.utf8)
        rotateIfNeeded(adding: data.count)
        if let handle = try? FileHandle(forWritingTo: current) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: current, options: .atomic)
        }
    }

    /// Wpisy od najnowszego.
    public func entries() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return [current, previous].flatMap { url -> [String] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return Array(text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).reversed())
        }
    }

    /// Cały dziennik jako tekst, od najstarszego (do wysłania w wiadomości).
    public func text() -> String {
        entries().reversed().joined(separator: "\n")
    }

    public var sizeBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return [current, previous].reduce(0) { sum, url in
            sum + ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: current)
        try? FileManager.default.removeItem(at: previous)
    }

    private func rotateIfNeeded(adding bytes: Int) {
        let size = (try? FileManager.default.attributesOfItem(atPath: current.path)[.size] as? Int) ?? 0
        guard size + bytes > maxBytes, size > 0 else { return }
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: current, to: previous)
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r", with: " ")
    }
}
