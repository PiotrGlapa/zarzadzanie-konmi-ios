import Foundation

/// Wynik szukania miniatury załącznika-obrazu (`AttachmentStore.thumbnail(attachmentId:)`).
public enum ThumbnailResult: Equatable, Sendable {
    case image(Data)
    /// Program potwierdził, że zdjęcia nie ma (`404`) albo plik nie jest obrazem — nie ponawiać do końca sesji.
    case unavailable
    /// Brak pliku w telefonie i brak sieci albo odpowiedzi — ponowić po kolejnej synchronizacji.
    case failed
}

/// Pobieranie brakujących miniatur zdjęć koni (FR-006…FR-009): równolegle (najwyżej `concurrency` naraz, SC-002), bez
/// ponawiania nieudanych przy każdej emisji listy koni. `failed` czyści `forgetFailures()` po zakończonej synchronizacji,
/// powrocie na pierwszy plan albo przejściu na tryb samodzielny; `unavailable` zostaje do końca sesji.
public actor ThumbnailFetcher {
    public static let defaultConcurrency = 4

    private let source: @Sendable (String) async -> ThumbnailResult
    private let concurrency: Int
    private var failed: Set<String> = []
    private var unavailable: Set<String> = []

    public init(concurrency: Int = ThumbnailFetcher.defaultConcurrency, source: @escaping @Sendable (String) async -> ThumbnailResult) {
        self.concurrency = max(1, concurrency)
        self.source = source
    }

    public init(attachments: AttachmentStore, concurrency: Int = ThumbnailFetcher.defaultConcurrency) {
        self.init(concurrency: concurrency) { await attachments.thumbnail(attachmentId: $0) }
    }

    /// Szuka miniatur dla `ids` (poza nieudanymi i niedostępnymi); każdą gotową przekazuje do `deliver` od razu.
    public func fetch(_ ids: [String], deliver: @escaping @Sendable (String, Data) async -> Void) async {
        let wanted = ids.filter { !failed.contains($0) && !unavailable.contains($0) }
        guard !wanted.isEmpty else { return }
        let queue = WorkQueue(wanted)
        let source = source
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(concurrency, wanted.count) {
                group.addTask { [self] in
                    while let id = queue.next() {
                        switch await source(id) {
                        case let .image(data): await deliver(id, data)
                        case .failed: await markFailed(id)
                        case .unavailable: await markUnavailable(id)
                        }
                    }
                }
            }
        }
    }

    /// Nieudane pobrania wracają do kolejki (kolejna synchronizacja, powrót na pierwszy plan, przejście na tryb samodzielny).
    public func forgetFailures() {
        failed.removeAll()
    }

    private func markFailed(_ id: String) {
        failed.insert(id)
    }

    private func markUnavailable(_ id: String) {
        unavailable.insert(id)
    }
}

/// Kolejka identyfikatorów dla równoległych „pracowników”.
private final class WorkQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String]

    init(_ items: [String]) {
        self.items = items.reversed()
    }

    func next() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return items.popLast()
    }
}
