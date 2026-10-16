import Foundation
import HorselyCore

/// Co zrobiło odświeżenie.
public enum SyncKind: String, Sendable {
    case full
    case incremental
    case upToDate
}

/// Postęp pobrania: rekordy i — gdy program podał `Content-Length` — ułamek bajtów.
public struct SyncProgress: Equatable, Sendable {
    public let records: Int
    public let bytes: Int64
    public let totalBytes: Int64?

    public init(records: Int, bytes: Int64, totalBytes: Int64?) {
        self.records = records
        self.bytes = bytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(bytes) / Double(totalBytes)))
    }
}

/// Wynik pobrania danych z programu.
public enum SyncOutcome: Equatable, Sendable {
    /// `unversioned` — program bez wersji rekordów: tryb zgodności 1.x, zmiany i usunięcia zablokowane (FR-SYN2-09).
    case done(kind: SyncKind, merge: MergeResult, records: Int, at: Date, unversioned: Bool)
    /// Pobranie nie doszło do skutku; zapisane paczki zostają, nic nie zostało uznane za usunięte w programie.
    case failed(ApiFailure)

    public var succeeded: Bool {
        if case .done = self { return true }
        return false
    }
}

/// Pobranie danych z programu (contracts/android/program-2.0-integration.md §3, mode-and-sync.md §2; `ProgramSync.kt`):
///
/// 1. `GET /system/info` — możliwości i stempel danych (zmiana `updatedSince`/`horseStatusInjured` wymusza pełne pobranie);
/// 2. plan: dane aktualne (stempel bez zmian i pusta kolejka) / zmiany (`updatedSince`) / pełne (brak możliwości, wymuszenie,
///    w tle raz na dobę);
/// 3. `GET /export?scope=full[&updatedSince=…]` do pliku z postępem, uzgadnianie paczkami po 500 rekordów — każda paczka w osobnej
///    transakcji ze świeżymi metadanymi (zmiana zrobiona w trakcie pobierania nigdy nie jest nadpisana);
/// 4. ocena nieobecności (pełne) albo usunięcia z `trashed[]`/`purged[]` (zmiany) — dopiero po przeczytaniu całości;
/// 5. stan (punkt, stempel, chwila pełnego) zapisany dopiero po udanym pobraniu — przerwane pobranie niczego nie przesuwa.
///
/// Program bez listy możliwości (1.5.0–1.6.x) dostaje zawsze pełne pobranie.
public final class SyncService: Sendable {
    public static let batchSize = 500

    private let client: ApiClient
    private let store: RecordStore
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private let onRemoved: @Sendable ([RecordRef]) async -> Void
    private let gate = SyncGate()

    public init(
        client: ApiClient, store: RecordStore, now: @escaping @Sendable () -> Date = { Date() }, log: @escaping @Sendable (String) -> Void = { _ in },
        onRemoved: @escaping @Sendable ([RecordRef]) async -> Void = { _ in }
    ) {
        self.client = client
        self.store = store
        self.now = now
        self.log = log
        self.onRemoved = onRemoved
    }

    // MARK: Możliwości

    /// Zapamiętuje możliwości z `system/info`; zmiana `updatedSince` albo `horseStatusInjured` ustawia wymuszenie pełnego pobrania.
    @discardableResult
    public func record(_ info: ProgramInfo) async throws -> CapabilitiesChange {
        try await store.writeQuietly { access in
            let before = ProgramCapabilities(serialized: try access.meta(SyncMetaKey.capabilities))
            let after = info.programCapabilities
            let change = CapabilitiesChange(before: before, after: after)
            try access.setMeta(SyncMetaKey.programVersion, info.appVersion)
            if change.changed {
                try access.setMeta(SyncMetaKey.capabilities, after.serialized.isEmpty ? nil : after.serialized)
                if change.forcesFullSync { try access.setMeta(SyncMetaKey.forceFull, "true") }
            }
            return change
        }
    }

    public func capabilities() async -> ProgramCapabilities {
        ProgramCapabilities(serialized: try? await store.meta(SyncMetaKey.capabilities))
    }

    // MARK: Odświeżenie

    /// Jedno odświeżenie naraz — kolejne wywołanie czeka na trwające i zwraca jego wynik (gest „Odśwież” w trakcie odświeżania).
    /// - Parameter background: praca w tle — raz na dobę pełne pobranie dla bezpieczeństwa.
    public func refresh(background: Bool = false, onProgress: @escaping @Sendable (SyncProgress) -> Void = { _ in }) async -> SyncOutcome {
        await gate.run { await self.run(background: background, onProgress: onProgress) }
    }

    private func run(background: Bool, onProgress: @escaping @Sendable (SyncProgress) -> Void) async -> SyncOutcome {
        let info: ProgramInfo
        switch await client.systemInfo() {
        case let .success(value): info = value
        case let .failure(failure): return .failed(failure)
        }
        guard let change = try? await record(info) else { return .failed(.badResponse) }
        let known = change.after
        let stamp = known.dataStamp ? info.dataStamp : nil
        let state = (try? await store.read { try $0.syncMetaState() }) ?? SyncMetaState()
        let queueEmpty = ((try? await store.read { try $0.operations() }) ?? []).allSatisfy { !$0.state.isUnsent }
        switch RefreshPlan.plan(capabilities: known, stamp: stamp, state: state, background: background, queueEmpty: queueEmpty, now: now()) {
        case .upToDate:
            log("odświeżanie: dane aktualne (stempel bez zmian)")
            try? await store.writeQuietly { try $0.setMeta(SyncMetaKey.lastSyncAt, RefreshPlan.formatInstant(self.now())) }
            return .done(kind: .upToDate, merge: MergeResult(), records: 0, at: now(), unversioned: false)
        case let .incremental(since):
            if let outcome = await download(since: since, known: known, stamp: stamp, onProgress: onProgress) { return outcome }
            log("odświeżanie: program odrzucił punkt zmian (400) — jedno pełne pobranie")
            return await download(since: nil, known: known, stamp: stamp, onProgress: onProgress) ?? .failed(.badResponse)
        case .full:
            return await download(since: nil, known: known, stamp: stamp, onProgress: onProgress) ?? .failed(.badResponse)
        }
    }

    /// Jedno pobranie; dla planu przyrostowego `400` kasuje punkt i zwraca `nil` (wołający robi jedno pełne pobranie).
    private func download(since: String?, known: ProgramCapabilities, stamp: String?, onProgress: @escaping @Sendable (SyncProgress) -> Void) async -> SyncOutcome? {
        var path = "export?scope=full"
        if let since { path += "&updatedSince=" + MatchSpec.encode(since) }
        let request = ApiRequest(.get, path, downloadToFile: true)
        let response: ApiResponse
        switch await client.execute(request, progress: { bytes, total in onProgress(SyncProgress(records: 0, bytes: bytes, totalBytes: total)) }) {
        case let .success(value):
            response = value
        case let .failure(.validationFailed(problem)):
            guard since != nil else { return .failed(.validationFailed(problem)) }
            try? await store.writeQuietly { try $0.setMeta(SyncMetaKey.nextUpdatedSince, nil) }
            return nil
        case let .failure(failure):
            return .failed(failure)
        }
        defer { if let file = response.file { try? FileManager.default.removeItem(at: file) } }
        let data: Data
        if let file = response.file {
            guard let read = try? Data(contentsOf: file, options: .mappedIfSafe) else { return .failed(.badResponse) }
            data = read
        } else {
            data = response.body
        }
        let document: ExportDocument
        do {
            document = try ExportDocument.parse(data)
        } catch {
            return .failed(.badResponse)
        }
        let incremental = RefreshPlan.isIncremental(requested: since != nil, header: document.header)
        let total = Int64(data.count)
        do {
            let applier = ExportApplier(store: store)
            try await applier.begin()
            var merge = MergeResult()
            var done = 0
            for start in stride(from: 0, to: document.records.count, by: Self.batchSize) {
                let batch = Array(document.records[start..<min(start + Self.batchSize, document.records.count)])
                merge = merge + (try await applier.merge(batch))
                done += batch.count
                onProgress(SyncProgress(records: done, bytes: total, totalBytes: total))
            }
            let tail = incremental
                ? try await applier.applyRemovals(document.removals.map { RecordRef(type: $0.type, id: $0.id) })
                : try await applier.finish()
            merge = merge + tail
            if !document.unknownRemovalTypes.isEmpty { log("odświeżanie: pominięto usunięcia nieznanych typów \(Set(document.unknownRemovalTypes).sorted())") }
            if !tail.removed.isEmpty { await onRemoved(tail.removed) }
            let unversioned = document.records.contains { $0.record.version <= 0 }
            let kind: SyncKind = incremental ? .incremental : .full
            let moment = now()
            let point = known.updatedSince ? RefreshPlan.nextPoint(header: document.header) : nil
            try await store.writeQuietly { access in
                try access.setMeta(SyncMetaKey.dataStamp, stamp)
                try access.setMeta(SyncMetaKey.nextUpdatedSince, point)
                try access.setMeta(SyncMetaKey.lastSyncAt, RefreshPlan.formatInstant(moment))
                try access.setMeta(SyncMetaKey.unversioned, unversioned ? "true" : nil)
                if kind == .full {
                    try access.setMeta(SyncMetaKey.lastFullAt, RefreshPlan.formatInstant(moment))
                    try access.setMeta(SyncMetaKey.forceFull, nil)
                }
            }
            log("odświeżanie: \(kind.rawValue), rekordów \(document.records.count), usunięto \(merge.removed.count)")
            return .done(kind: kind, merge: merge, records: document.records.count, at: moment, unversioned: unversioned)
        } catch {
            return .failed(.badResponse)
        }
    }

    // MARK: Sprawdzenie połączenia

    /// „Odśwież” / sprawdzanie samoczynne: zwalnia wstrzymania czasowe (nie klucza ani certyfikatu) i pyta `GET /system/info`.
    public func checkConnection() async -> Bool {
        try? await store.writeQuietly { access in
            for address in try access.addresses() where address.hold.reason == .rateLimited || address.hold.reason == .addressBlocked {
                try access.setHold(address.id, .active)
            }
        }
        guard case let .success(info) = await client.systemInfo() else { return false }
        _ = try? await record(info)
        return true
    }
}

/// Zapis wyników pobrania do magazynu (`SyncMerger` z Androida): decyzje z `HorselyCore.SyncMerger`, metadane czytane świeżo
/// w transakcji każdej paczki.
struct ExportApplier: Sendable {
    let store: RecordStore
    private let seen = SeenRecords()

    init(store: RecordStore) {
        self.store = store
    }

    /// Usuwa przewidywane skutki reguł (`Projected`) — liczone są od nowa po pobraniu.
    func begin() async throws {
        try await store.write { access in
            if try !access.withState(.projected).isEmpty { try access.deleteState(.projected) }
        }
    }

    func merge(_ batch: [ExportedRecord]) async throws -> MergeResult {
        guard !batch.isEmpty else { return MergeResult() }
        await seen.add(batch.map { RecordRef(type: $0.record.recordType, id: $0.record.id) })
        return try await store.write { access in
            let live = try access.liveRecords()
            var fresh: [RecordType: [String: RecordMeta]] = [:]
            for (type, group) in Dictionary(grouping: batch, by: { $0.record.recordType }) {
                fresh[type] = try access.metas(type, ids: group.map(\.record.id))
            }
            var result = MergeResult()
            var writes: [StoredRecord] = []
            for exported in batch {
                let record = exported.record
                let local = fresh[record.recordType]?[record.id]
                switch SyncMerger.incoming(version: record.version, local: local, hasOperation: live.contains(RecordRef(type: record.recordType, id: record.id))) {
                case .insert:
                    writes.append(try StoredRecord.of(record, syncState: .synced, dateKey: exported.dateKey))
                    result.inserted += 1
                case .replace:
                    writes.append(try StoredRecord.of(record, syncState: .synced, dateKey: exported.dateKey))
                    result.replaced += 1
                case .unchanged:
                    result.unchanged += 1
                case .keepPending:
                    result.keptPending += 1
                }
            }
            if !writes.isEmpty { try access.upsert(writes) }
            return result
        }
    }

    /// Ocena nieobecności po pełnym przeczytaniu eksportu.
    func finish() async throws -> MergeResult {
        let present = await seen.all()
        return try await store.write { access in
            let live = try access.liveRecords()
            var result = MergeResult()
            for type in RecordType.allCases {
                for (id, meta) in try access.metas(type) where !present.contains(RecordRef(type: type, id: id)) {
                    try Self.absent(RecordRef(type: type, id: id), meta: meta, live: live, access: access, result: &result)
                }
            }
            return result
        }
    }

    /// Eksport przyrostowy: rekordy z `trashed[]`/`purged[]` przechodzą tę samą tabelę co nieobecne w pełnym eksporcie. Rekord,
    /// który w tym samym eksporcie wrócił w `data` (przywrócony z kosza), nie jest usuwany.
    func applyRemovals(_ refs: [RecordRef]) async throws -> MergeResult {
        guard !refs.isEmpty else { return MergeResult() }
        let present = await seen.all()
        let wanted = Array(Set(refs.filter { !present.contains($0) }))
        return try await store.write { access in
            let live = try access.liveRecords()
            var result = MergeResult()
            for (type, group) in Dictionary(grouping: wanted, by: \.type) {
                let metas = try access.metas(type, ids: group.map(\.id))
                for ref in group {
                    guard let meta = metas[ref.id] else { continue }
                    try Self.absent(ref, meta: meta, live: live, access: access, result: &result)
                }
            }
            return result
        }
    }

    private static func absent(_ ref: RecordRef, meta: RecordMeta, live: Set<RecordRef>, access: RecordAccess, result: inout MergeResult) throws {
        switch SyncMerger.absent(local: meta, hasOperation: live.contains(ref)) {
        case .remove:
            try access.deleteHard(ref.type, id: ref.id)
            result.removed.append(ref)
        case .editDeleteConflict:
            result.editDeleteConflicts.append(ref)
        case .keep:
            break
        }
    }
}

/// Rekordy widziane w bieżącym pobraniu.
actor SeenRecords {
    private var refs = Set<RecordRef>()

    func add(_ items: [RecordRef]) {
        refs.formUnion(items)
    }

    func all() -> Set<RecordRef> { refs }
}

/// Jedno odświeżenie naraz: kolejne wywołania dołączają do trwającego.
actor SyncGate {
    private var running: Task<SyncOutcome, Never>?

    func run(_ work: @escaping @Sendable () async -> SyncOutcome) async -> SyncOutcome {
        if let running { return await running.value }
        let task = Task { await work() }
        running = task
        let result = await task.value
        running = nil
        return result
    }
}
