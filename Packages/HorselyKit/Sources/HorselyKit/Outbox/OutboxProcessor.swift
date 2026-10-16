import Foundation
import HorselyCore

/// Dlaczego pętla wysyłki się zatrzymała.
public enum StopReason: String, Sendable {
    /// Nie ma sieci albo program nie odpowiada — kolejna próba wg `nextAttemptAt` / po odzyskaniu sieci.
    case noConnection
    /// Adres wstrzymany (401/403/429, zmieniony certyfikat) — zero ruchu do działania użytkownika lub `Retry-After`.
    case addressSuspended
}

public struct ProcessSummary: Equatable, Sendable {
    public var sent = 0
    public var needsFix = 0
    public var conflicts = 0
    public var pending = 0
    /// Najwcześniejsza kolejna próba operacji czekających z odstępem (zaplanowanie pracy w tle).
    public var nextAttemptAt: Date?
    public var stopped: StopReason?

    public init() {}
}

/// Wynik zapisu z połączeniem (FR-M-SYN-11).
public enum SendNowResult: Equatable, Sendable {
    /// Program przyjął zmianę w limicie czasu — „Zapisano”.
    case sent(resultId: String?)
    /// `400` w limicie czasu dla operacji bez rekordu w telefonie — błędy wracają do formularza.
    case rejected(ApiProblem)
    /// Termin zamknięty już wcześniej — „już załatwione”.
    case alreadyHandled
    /// Wysyłka wykryła konflikt — zmiana czeka na ekranie „Konflikty”.
    case conflict
    /// Brak wyniku w limicie czasu albo brak połączenia — „Zapisano — wyślę po połączeniu z komputerem”.
    case queued
}

/// Silnik kolejki wysyłki (research R11, konstytucja IV; `OutboxProcessor.kt`). Wysyła operacje w kolejności dodania z zachowaniem
/// zależności: zależna czeka, aż poprzednik będzie `Sent`; poprzednik „Wymaga poprawy” blokuje zależne, niezależne idą dalej.
/// Po wyniku nieznanym (zerwanie po wysłaniu treści) liczy rekordy przed i po albo — z `idempotencyKey` — ponawia z tym samym
/// `Idempotency-Key`, więc nie tworzy duplikatów. Po `401`/`403`/`429` pętla się zatrzymuje (SC-M-08).
///
/// Przebiegi są szeregowane: jeden naraz, kolejne czekają na poprzedni.
public actor OutboxProcessor {
    public static let sendNowTimeout: TimeInterval = 1

    private let store: RecordStore
    private let client: ApiClient
    private let capabilities: @Sendable () async -> ProgramCapabilities
    private let now: @Sendable () -> Date
    private let newId: @Sendable () -> String
    private let log: @Sendable (String) -> Void
    /// Postęp wysyłki pliku: identyfikator operacji, wysłane bajty, wszystkie bajty.
    private let uploadProgress: (@Sendable (String, Int64, Int64?) -> Void)?
    private let reconciler: RecordReconciler
    private let detector: ConflictDetector
    private var tail: Task<Void, Never>?

    public init(
        store: RecordStore, client: ApiClient, capabilities: @escaping @Sendable () async -> ProgramCapabilities = { .none },
        now: @escaping @Sendable () -> Date = { Date() }, newId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        log: @escaping @Sendable (String) -> Void = { _ in }, uploadProgress: (@Sendable (String, Int64, Int64?) -> Void)? = nil
    ) {
        self.uploadProgress = uploadProgress
        self.store = store
        self.client = client
        self.capabilities = capabilities
        self.now = now
        self.newId = newId
        self.log = log
        reconciler = RecordReconciler(store: store)
        detector = ConflictDetector(client: client, store: store, now: now, newId: newId)
    }

    // MARK: Wejście

    /// Wysyła wszystko, co gotowe. Wołane po dodaniu operacji, po odzyskaniu sieci, przy starcie i w tle.
    public func processAll() async -> ProcessSummary {
        await schedule { await self.runLoop(only: nil) }.value
    }

    /// Zapis z połączeniem: wysyła operację (i jej niewysłane zależności) i czeka na wynik do `timeout`. Po upływie limitu wysyłka
    /// trwa dalej, a wynik widać w kolejce.
    public func sendNow(_ operationId: String, timeout: TimeInterval = OutboxProcessor.sendNowTimeout) async -> SendNowResult {
        let scope = (try? await store.read { access in OperationCoalescer.dependencyScope(operationId, in: try access.operations()) }) ?? [operationId]
        let task = schedule { await self.runLoop(only: Set(scope)) }
        let finished = await Self.race(task, timeout: timeout)
        guard finished else { return .queued }
        guard let operation = try? await store.read({ try $0.operation(operationId) }) else {
            let history = (try? await store.read { try $0.history() }) ?? []
            switch history.first(where: { $0.operationId == operationId })?.outcome {
            case .sent?: return .sent(resultId: nil)
            case .alreadyHandled?: return .alreadyHandled
            default: return .queued
            }
        }
        switch operation.state {
        case .sent: return .sent(resultId: operation.resultId)
        case .alreadyHandled: return .alreadyHandled
        case .conflict: return .conflict
        case .needsFix:
            // Operacje z rekordem w telefonie (reguły sprawdził już silnik) zostają w kolejce do poprawy.
            if let problem = operation.problem, problem.status == 400, operation.recordType == nil {
                _ = try? await store.writeQuietly { try $0.deleteOperation(operationId, allowed: [.needsFix]) }
                return .rejected(problem)
            }
            return .queued
        default:
            return .queued
        }
    }

    /// „Cofnij” po zapisie: usuwa operację `Pending` z zależnymi, bez historii; `false`, gdy wysyłka już się zaczęła.
    public func cancel(_ operationId: String) async -> Bool {
        guard let result = try? await store.writeQuietly({ try $0.deleteOperation(operationId, allowed: [.pending]) }) else { return false }
        result.files.forEach(Self.release)
        return !result.removed.isEmpty
    }

    /// Start aplikacji: przerwane wysyłki mają wynik nieznany, historia starsza niż 30 dni znika.
    public func recover() async {
        let moment = now()
        _ = try? await store.writeQuietly { access in
            try access.recoverInterrupted(now: moment)
            try access.purgeHistory(before: moment.addingTimeInterval(-30 * 24 * 3600))
            try access.purgeResolvedConflicts(before: moment.addingTimeInterval(-30 * 24 * 3600))
        }
    }

    private func schedule(_ work: @escaping @Sendable () async -> ProcessSummary) -> Task<ProcessSummary, Never> {
        let previous = tail
        let task = Task { () -> ProcessSummary in
            await previous?.value
            return await work()
        }
        tail = Task { _ = await task.value }
        return task
    }

    /// `true` — zadanie skończyło się przed upływem limitu.
    private static func race(_ task: Task<ProcessSummary, Never>, timeout: TimeInterval) async -> Bool {
        let once = Once()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            Task {
                _ = await task.value
                once.resume(true)
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                once.resume(false)
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?

        func set(_ value: CheckedContinuation<Bool, Never>) {
            lock.lock()
            continuation = value
            lock.unlock()
        }

        func resume(_ value: Bool) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    // MARK: Pętla

    private enum Step {
        case next
        /// Operacja plikowa niedozwolona w tej sieci — pomijamy ją w tym przebiegu, niezależne idą dalej.
        case skip
        case stop(StopReason)
    }

    private func runLoop(only: Set<String>?) async -> ProcessSummary {
        let moment = now()
        // Operacje w stanie `Sending`, których nikt już nie obsługuje, mają wynik nieznany.
        _ = try? await store.writeQuietly { access in
            for op in try access.operations() where op.state == .sending && (only?.contains(op.id) ?? true) {
                try access.updateOperation(op.id, expected: [.sending]) { current in
                    var next = current
                    next.state = .unknown
                    next.updatedAt = moment
                    return next
                }
            }
        }

        var sent = 0
        var stopped: StopReason?
        for op in await operations() where op.state == .unknown && (only?.contains(op.id) ?? true) {
            if case let .stop(reason) = await reconcile(op) {
                stopped = reason
                break
            }
        }

        var skipped = Set<String>()
        while stopped == nil {
            guard let next = await nextReady(skipped: skipped, only: only) else { break }
            switch await send(next) {
            case .next:
                if await operation(next.id)?.state == .sent { sent += 1 }
            case .skip:
                skipped.insert(next.id)
            case let .stop(reason):
                stopped = reason
            }
        }

        _ = try? await store.writeQuietly { try $0.purgeSent() }
        let remaining = await operations()
        var summary = ProcessSummary()
        summary.sent = sent
        summary.needsFix = remaining.filter { $0.state == .needsFix }.count
        summary.conflicts = remaining.filter { $0.state == .conflict }.count
        summary.pending = remaining.filter { $0.state == .pending }.count
        summary.nextAttemptAt = remaining.filter { $0.state == .pending }.compactMap(\.nextAttemptAt).min()
        summary.stopped = stopped
        return summary
    }

    private func operations() async -> [OutboxOperation] {
        (try? await store.read { try $0.operations() }) ?? []
    }

    private func operation(_ id: String) async -> OutboxOperation? {
        try? await store.read { try $0.operation(id) }
    }

    private func file(_ id: String) async -> OutboxFile? {
        try? await store.read { try $0.outboxFile(id) }
    }

    private func nextReady(skipped: Set<String>, only: Set<String>?) async -> OutboxOperation? {
        let all = await operations()
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let moment = now()
        return all.first { op in
            op.state == .pending && !skipped.contains(op.id) && (only?.contains(op.id) ?? true)
                && (op.nextAttemptAt.map { $0 <= moment } ?? true)
                && op.dependsOn.allSatisfy { byId[$0]?.state == .sent }
                // Zmiany tego samego rekordu wychodzą po kolei.
                && !all.contains { $0.sequence < op.sequence && $0.state.isUnsent && $0.sameRecord(as: op) }
                // Operacje zależne od rekordu w konflikcie czekają na rozstrzygnięcie.
                && !all.contains { blocked in
                    blocked.state == .conflict && blocked.id != op.id && blocked.recordId.map { op.payload.containsString($0) } == true
                }
        }
    }

    // MARK: Wysyłka jednej operacji

    private func send(_ candidate: OutboxOperation) async -> Step {
        guard let op = await operation(candidate.id), op.state == .pending else { return .next }
        guard let resolved = await resolve(op) else {
            return await fix(op, ApiProblem(title: "Operacja zależy od rekordu, którego już nie ma w kolejce"), from: [.pending])
        }
        if op.kind.isChange { return await sendChange(op, resolved: resolved) }
        let attachment = op.kind == .createAttachment ? await file(op.id) : nil
        if op.kind == .createAttachment && (attachment == nil || !FileManager.default.fileExists(atPath: attachment!.path)) {
            return await fix(op, ApiProblem(title: "Brak pliku załącznika na telefonie"), from: [.pending])
        }

        // Z kluczem idempotencji ponowienie jest bezpieczne, więc licznika nie trzeba; bez klucza — licznik przed wysyłką.
        let useKey = await capabilities().idempotencyKey
        var countBefore: Int?
        if op.kind.isCreate && !useKey {
            switch await count(resolved, file: attachment) {
            case let .success(counted): countBefore = counted.count
            case let .failure(failure): return await handleFailure(op, failure, from: [.pending])
            }
        }
        let expected = op.updatedAt
        let moment = now()
        let counted = countBefore
        guard let sending = try? await store.writeQuietly({ try $0.markSending(op.id, countBefore: counted, expectedUpdatedAt: expected, now: moment) }) else { return .next }
        var outgoing = sending
        outgoing.payload = resolved.payload
        let result = await execute(outgoing, file: attachment, useKey: useKey)
        return await handleResult(sending, result)
    }

    private func sendChange(_ candidate: OutboxOperation, resolved: OutboxOperation) async -> Step {
        guard let type = resolved.recordType, let recordId = resolved.recordId,
              let path = RecordPaths.item(type, id: recordId, parentId: resolved.text("competitionId"))
        else { return await fix(candidate, ApiProblem(title: "Nie można ustalić adresu rekordu w programie"), from: [.pending]) }
        let expected = candidate.updatedAt
        let moment = now()
        guard let sending = try? await store.writeQuietly({ try $0.markSending(candidate.id, countBefore: nil, expectedUpdatedAt: expected, now: moment) }) else { return .next }
        var op = sending
        op.payload = resolved.payload
        op.recordId = resolved.recordId
        return op.kind.isDelete ? await sendDelete(op, path: path) : await sendUpdate(op, path: path)
    }

    private func sendUpdate(_ op: OutboxOperation, path: String) async -> Step {
        guard let base = op.baseVersion else { return await fix(op, ApiProblem(title: "Brak wersji rekordu z programu — zmiana nie może być wysłana")) }
        let body = op.payload.removing("competitionId")
        switch await client.execute(.json(.put, path, body, ifMatch: base)) {
        case let .success(response):
            try? await reconciler.updated(op, response: response.json)
            await markSent(op, resultId: op.recordId)
            return .next
        case let .failure(failure):
            switch failure {
            case let .conflict(problem):
                return problem.conflictReason == .versionMismatch ? await found(op, await detector.editEdit(op, current: problem.current)) : await fix(op, problem)
            case .notFound:
                return await found(op, await detector.editDelete(op))
            case let .validationFailed(p), let .payloadTooLarge(p), let .unsupportedMediaType(p), let .forbidden(p), let .unprocessable(p):
                return await fix(op, p)
            case .network, .badResponse:
                return await backoff(op)
            case let .serverError(status, problem):
                return status >= 500 ? await backoff(op) : await fix(op, problem)
            default:
                return await handleFailure(op, failure, from: [.sending])
            }
        }
    }

    private func sendDelete(_ op: OutboxOperation, path: String) async -> Step {
        // Program z `ifMatchDelete` sprawdza wersję w tym samym żądaniu; starszy — sprawdzamy sami odczytem kontrolnym.
        let guardVersion = await capabilities().ifMatchDelete ? op.baseVersion : nil
        if guardVersion == nil {
            switch await client.get(path) {
            case let .success(response):
                if let json = response.json, let version = json["version"]?.intValue, let base = op.baseVersion, version > base {
                    return await found(op, detector.deleteEdit(op, theirs: json))
                }
            case .failure(.notFound):
                return await alreadyHandled(op)
            case let .failure(failure):
                return await handleFailure(op, failure, from: [.sending])
            }
        }
        switch await client.execute(ApiRequest(.delete, path, ifMatch: guardVersion)) {
        case .success:
            try? await reconciler.deleted(op)
            await markSent(op, resultId: op.recordId)
            return .next
        case let .failure(failure):
            switch failure {
            case .notFound:
                return await alreadyHandled(op)
            case let .conflict(problem):
                guard guardVersion != nil, problem.conflictReason == .versionMismatch else { return await fix(op, problem) }
                var theirs = problem.current
                if theirs == nil || theirs == .null {
                    switch await detector.fetch(op) {
                    case let .record(json): theirs = json
                    case .gone: return await alreadyHandled(op)
                    case let .failed(fetchFailure): return await handleFailure(op, fetchFailure, from: [.sending])
                    }
                }
                guard let theirs else { return await alreadyHandled(op) }
                return await found(op, detector.deleteEdit(op, theirs: theirs))
            case let .validationFailed(problem):
                return await fix(op, problem)
            case .network, .badResponse:
                return await backoff(op)
            case let .serverError(status, problem):
                return status >= 500 ? await backoff(op) : await fix(op, problem)
            default:
                return await handleFailure(op, failure, from: [.sending])
            }
        }
    }

    /// Skutek rozpoznania konfliktu.
    private func found(_ op: OutboxOperation, _ detection: Detection) async -> Step {
        switch detection {
        case let .found(conflict):
            return await recordConflict(op, conflict)
        case let .sameAsMine(theirs):
            try? await reconciler.updated(op, response: theirs)
            await markSent(op, resultId: op.recordId)
            return .next
        case let .failed(failure):
            return await handleFailure(op, failure, from: [.sending])
        }
    }

    /// Zapisuje konflikt, wstrzymuje operację (`Conflict`) i oznacza lokalny rekord; zależne czekają.
    private func recordConflict(_ op: OutboxOperation, _ conflict: Conflict) async -> Step {
        let moment = now()
        _ = try? await store.write { access in
            let moved = try access.updateOperation(op.id, expected: [.sending, .pending]) { current in
                var next = current
                next.state = .conflict
                next.problem = nil
                next.updatedAt = moment
                return next
            }
            guard moved != nil else { return }
            try access.putConflict(conflict)
            if var row = try access.get(conflict.recordType, id: conflict.recordId), !row.isDeleted {
                row.syncState = .conflict
                try access.upsert([row])
            }
        }
        log("kolejka: konflikt \(conflict.kind.rawValue) (\(op.kind.rawValue))")
        return .next
    }

    /// Podstawia `resultId` operacji poprzedzających w miejsce odwołań do rekordów tworzonych w kolejce.
    private func resolve(_ op: OutboxOperation) async -> OutboxOperation? {
        var resolved = op
        for depId in op.dependsOn {
            guard let dep = await operation(depId), let resultId = dep.resultId else { return nil }
            resolved.payload = resolved.payload.replacingValues(dep.localRef, with: resultId)
            if resolved.recordId == dep.localRef { resolved.recordId = resultId }
        }
        return resolved
    }

    private func execute(_ op: OutboxOperation, file: OutboxFile?, useKey: Bool) async -> Result<(id: String?, json: JSONValue?), ApiFailure> {
        let key = useKey ? op.id : nil
        switch op.kind {
        case .createAttachment:
            guard let file else { return .failure(.badResponse) }
            let upload: URL
            do {
                upload = try MultipartBody.write(fields: [("ownerType", op.text("ownerType") ?? ""), ("ownerId", op.text("ownerId") ?? "")]
                    + (file.description.map { [("description", $0)] } ?? []), file: file)
            } catch {
                return .failure(.badResponse)
            }
            defer { try? FileManager.default.removeItem(at: upload) }
            let request = ApiRequest(.post, "attachments", contentType: "multipart/form-data; boundary=\(MultipartBody.boundary)", bodyFile: upload, idempotencyKey: key, forFile: true)
            return await client.execute(request, progress: Self.progress(uploadProgress, operationId: op.id)).map { response in
                let json = response.json
                let first = json?.arrayValue?.first ?? json
                return (first?["id"]?.stringValue, first)
            }
        case .completeReminder, .dismissReminder:
            let id = op.text("id") ?? ""
            let action = op.kind == .completeReminder ? "complete" : "dismiss"
            return await client.execute(ApiRequest(.post, "reminders/\(id)/\(action)", idempotencyKey: key)).map { (id, $0.json) }
        default:
            let path = op.kind.path.replacingOccurrences(of: "{competitionId}", with: op.text("competitionId") ?? "")
            let body = op.kind == .createCompetitionStart ? op.payload.removing("competitionId") : op.payload
            return await client.execute(.json(.post, path, body, idempotencyKey: key)).map { response in
                let json = response.json
                let first = json?.arrayValue?.first ?? json
                return (first?["id"]?.stringValue ?? response.location.map { String($0.split(separator: "/").last ?? "") }, json)
            }
        }
    }

    private func handleResult(_ op: OutboxOperation, _ result: Result<(id: String?, json: JSONValue?), ApiFailure>) async -> Step {
        let action = op.kind.isReminderAction
        switch result {
        case let .success(sent):
            if op.kind.isCreate, op.recordType != nil {
                try? await reconciler.created(op, response: sent.json, serverId: sent.id ?? op.recordId ?? "")
            } else if action, op.recordType != nil {
                try? await reconciler.updated(op, response: sent.json)
            }
            await markSent(op, resultId: sent.id)
            return .next
        case let .failure(failure):
            switch failure {
            case let .validationFailed(problem):
                return await fix(op, problem)
            case let .notFound(problem):
                return action ? await alreadyHandled(op) : await fix(op, problem.withDefaultTitle("Koń lub rekord został usunięty w międzyczasie"))
            case let .conflict(problem):
                if action && problem.conflictReason == .invalidState { return await alreadyHandled(op) }
                // Pierwsze żądanie z tym kluczem jeszcze trwa w programie — ponowienie po odstępie, bez komunikatu.
                if problem.isIdempotencyKeyInProgress { return await backoff(op) }
                return await fix(op, problem)
            case let .unprocessable(problem):
                return await fix(op, problem)
            case let .payloadTooLarge(problem):
                return await fix(op, problem.withDefaultTitle("Plik jest za duży"))
            case let .unsupportedMediaType(problem):
                return await fix(op, problem.withDefaultTitle("Niedozwolony typ pliku"))
            case let .forbidden(problem):
                return await fix(op, problem)
            case let .network(sentBody, _):
                return sentBody ? await unknown(op) : await backoff(op)
            case let .serverError(status, problem):
                return status >= 500 ? await unknown(op) : await fix(op, problem)
            case .badResponse:
                return await unknown(op)
            default:
                return await handleFailure(op, failure, from: [.sending])
            }
        }
    }

    /// Błędy, po których operacja zostaje czekająca: wstrzymany adres, limit żądań, brak sieci, brak dozwolonego adresu.
    private func handleFailure(_ op: OutboxOperation, _ failure: ApiFailure, from: Set<OutboxState>) async -> Step {
        let moment = now()
        func back(nextAttempt: Date? = nil) async {
            _ = try? await store.writeQuietly { access in
                try access.updateOperation(op.id, expected: from) { current in
                    var next = current
                    next.state = .pending
                    if let nextAttempt { next.nextAttemptAt = nextAttempt }
                    next.updatedAt = moment
                    return next
                }
            }
        }
        switch failure {
        case .unauthorized, .keyHomeOnly, .remoteAccessDisabled, .suspended, .certificateRejected:
            await back()
            log("kolejka: adres wstrzymany (\(op.kind.rawValue))")
            return .stop(.addressSuspended)
        case let .rateLimited(seconds, _):
            await back(nextAttempt: moment.addingTimeInterval(seconds))
            return .stop(.addressSuspended)
        case .noUsableAddress, .noNetwork:
            await back()
            return op.kind.sendsFile ? .skip : .stop(.noConnection)
        case .network, .serverError, .badResponse:
            return await backoff(op)
        case let .notFound(problem):
            return op.kind.isReminderAction ? await alreadyHandled(op, from: from) : await fix(op, problem, from: from)
        case let .validationFailed(p), let .conflict(p), let .forbidden(p), let .payloadTooLarge(p), let .unsupportedMediaType(p), let .unprocessable(p):
            return await fix(op, p, from: from)
        }
    }

    /// Błąd sieci: operacja wraca do `Pending` z rosnącym odstępem (15 s → … maks. 30 min).
    @discardableResult
    private func backoff(_ op: OutboxOperation) async -> Step {
        let moment = now()
        _ = try? await store.writeQuietly { access in
            try access.updateOperation(op.id, expected: [.pending, .sending, .unknown]) { current in
                var next = current
                next.state = .pending
                next.attempts = current.attempts + 1
                next.nextAttemptAt = moment.addingTimeInterval(RetryPolicy.delay(afterAttempts: current.attempts + 1))
                next.updatedAt = moment
                return next
            }
        }
        log("kolejka: ponowienie \(op.kind.rawValue)")
        return .stop(.noConnection)
    }

    private func fix(_ op: OutboxOperation, _ problem: ApiProblem, from: Set<OutboxState> = [.sending, .pending]) async -> Step {
        let moment = now()
        _ = try? await store.writeQuietly { access in
            try access.updateOperation(op.id, expected: from) { current in
                var next = current
                next.state = .needsFix
                next.problem = problem
                next.updatedAt = moment
                return next
            }
        }
        log("kolejka: wymaga poprawy \(op.kind.rawValue) (\(problem.status.map(String.init) ?? "-"))")
        return .next
    }

    private func alreadyHandled(_ op: OutboxOperation, from: Set<OutboxState> = [.sending, .pending]) async -> Step {
        let moment = now()
        let file = try? await store.writeQuietly { access -> OutboxFile? in
            let updated = try access.updateOperation(op.id, expected: from) { current in
                var next = current
                next.state = .alreadyHandled
                next.updatedAt = moment
                return next
            }
            guard updated != nil else { return nil }
            try access.addHistory(QueueHistoryEntry(operationId: op.id, kind: op.kind, summary: op.summary, outcome: .alreadyHandled, at: moment))
            return try access.outboxFile(op.id)
        }
        if let file = file ?? nil { Self.release(file) }
        return .next
    }

    private func markSent(_ op: OutboxOperation, resultId: String?) async {
        let moment = now()
        let file = try? await store.writeQuietly { access -> OutboxFile? in
            let updated = try access.updateOperation(op.id, expected: [.sending, .unknown]) { current in
                var next = current
                next.state = .sent
                next.resultId = resultId
                next.problem = nil
                next.updatedAt = moment
                return next
            }
            guard updated != nil else { return nil }
            try access.addHistory(QueueHistoryEntry(operationId: op.id, kind: op.kind, summary: op.summary, outcome: .sent, at: moment))
            return try access.outboxFile(op.id)
        }
        if let file = file ?? nil { Self.release(file) }
    }

    /// Postęp wysyłki jednej operacji dla `ApiClient` (bajty wysłane, wszystkie).
    static func progress(_ sink: (@Sendable (String, Int64, Int64?) -> Void)?, operationId: String) -> (@Sendable (Int64, Int64?) -> Void)? {
        guard let sink else { return nil }
        return { sent, total in sink(operationId, sent, total) }
    }

    static func release(_ file: OutboxFile) {
        try? FileManager.default.removeItem(atPath: file.path)
    }

    // MARK: Wynik nieznany: licznik przed i po

    private func unknown(_ op: OutboxOperation) async -> Step {
        let moment = now()
        guard let current = try? await store.writeQuietly({ access in
            try access.updateOperation(op.id, expected: [.sending]) { value in
                var next = value
                next.state = .unknown
                next.updatedAt = moment
                return next
            }
        }) else { return .next }
        return await reconcile(current)
    }

    /// Ustala, czy operacja o nieznanym wyniku dotarła do programu: więcej pasujących rekordów niż przed wysyłką → `Sent`.
    private func reconcile(_ op: OutboxOperation) async -> Step {
        // Zmiana i usunięcie są idempotentne co do skutku: po wyniku nieznanym wysyłamy ponownie.
        if op.kind.isChange {
            let moment = now()
            _ = try? await store.writeQuietly { access in
                try access.updateOperation(op.id, expected: [.unknown]) { current in
                    var next = current
                    next.state = .pending
                    next.updatedAt = moment
                    return next
                }
            }
            return .next
        }
        guard let resolved = await resolve(op) else {
            return await fix(op, ApiProblem(title: "Operacja zależy od rekordu, którego już nie ma"), from: [.unknown])
        }
        if op.kind.isReminderAction {
            let id = resolved.text("id") ?? ""
            switch await client.get("reminders/\(id)") {
            case let .success(response):
                if response.json?["status"]?.stringValue == ReminderStatus.open.rawValue {
                    await backoff(op)
                    return .next
                }
                try? await reconciler.updated(op, response: response.json)
                await markSent(op, resultId: id)
                return .next
            case .failure(.notFound):
                return await alreadyHandled(op, from: [.unknown])
            case let .failure(failure):
                return Self.reconcileStop(failure)
            }
        }
        // Z kluczem idempotencji wynik nieznany to zwykłe ponowienie z tym samym kluczem; operacja z licznikiem (próba bez klucza)
        // nadal idzie przez licznik — program nie zna jej klucza, więc ponowienie dałoby duplikat.
        if op.kind.isCreate && op.countBefore == nil, await capabilities().idempotencyKey {
            await backoff(op)
            return .next
        }
        let attachment = op.kind == .createAttachment ? await file(op.id) : nil
        switch await count(resolved, file: attachment) {
        case let .success(counted):
            if counted.count > (op.countBefore ?? 0) {
                await reconcileFound(resolved, serverId: counted.newestId)
                await markSent(op, resultId: counted.newestId)
            } else {
                // Rekord nie powstał — bezpiecznie wysyłamy ponownie po odstępie.
                await backoff(op)
            }
            return .next
        case let .failure(failure):
            if case let .rateLimited(seconds, _) = failure {
                let moment = now()
                _ = try? await store.writeQuietly { access in
                    try access.updateOperation(op.id, expected: [.unknown]) { current in
                        var next = current
                        next.nextAttemptAt = moment.addingTimeInterval(seconds)
                        return next
                    }
                }
            }
            return Self.reconcileStop(failure)
        }
    }

    private static func reconcileStop(_ failure: ApiFailure) -> Step {
        switch failure {
        case .network, .serverError, .badResponse, .noNetwork, .noUsableAddress: .stop(.noConnection)
        default: .stop(.addressSuspended)
        }
    }

    /// Tworzenie rozpoznane po wyniku nieznanym: rekord z programu pobieramy, żeby lokalny wiersz dostał jego wersję.
    private func reconcileFound(_ op: OutboxOperation, serverId: String?) async {
        guard op.kind.isCreate, let type = op.recordType, let serverId else { return }
        var json: JSONValue?
        if let path = RecordPaths.item(type, id: serverId, parentId: op.text("competitionId")), case let .success(response) = await client.get(path) {
            json = response.json
        }
        try? await reconciler.created(op, response: json, serverId: serverId)
    }

    /// Licznik pasujących rekordów (zapytanie dopasowania, wszystkie strony; skrócone listy — pełne rekordy kandydatów).
    private func count(_ op: OutboxOperation, file: OutboxFile?) async -> Result<(count: Int, newestId: String?), ApiFailure> {
        guard let spec = MatchSpec.forOperation(op, sha256: file?.sha256) else { return .success((0, nil)) }
        var records: [JSONValue] = []
        if spec.paged {
            var page = 1
            while true {
                switch await client.execute(ApiRequest(.get, spec.url(page: page), forFile: op.kind.sendsFile)) {
                case let .failure(failure):
                    return .failure(failure)
                case let .success(response):
                    guard let json = response.json else { return .failure(.badResponse) }
                    let items = json["items"]?.arrayValue ?? []
                    records += items
                    let total = json["totalCount"]?.intValue ?? records.count
                    if items.count < MatchSpec.pageSize || records.count >= total { break }
                    page += 1
                    continue
                }
                break
            }
        } else {
            switch await client.execute(ApiRequest(.get, spec.url(), forFile: op.kind.sendsFile)) {
            case let .failure(failure): return .failure(failure)
            case let .success(response): records = response.json?.arrayValue ?? []
            }
        }
        if spec.detail {
            var full: [JSONValue] = []
            for record in records {
                guard let id = record["id"]?.stringValue else { continue }
                switch await client.execute(ApiRequest(.get, "\(spec.path)/\(id)", forFile: op.kind.sendsFile)) {
                case let .success(response): if let json = response.json { full.append(json) }
                case .failure(.notFound): continue
                case let .failure(failure): return .failure(failure)
                }
            }
            records = full
        }
        return .success(spec.count(payload: op.payload, records: records))
    }
}

extension OperationCoalescer {
    /// Operacja i jej niewysłane poprzedniki (przechodnio) — zakres wysyłki „Zapisz” z połączeniem.
    static func dependencyScope(_ id: String, in queue: [OutboxOperation]) -> [String] {
        let byId = Dictionary(queue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String] = []
        func visit(_ current: String) {
            guard let op = byId[current], !result.contains(current) else { return }
            result.append(current)
            op.dependsOn.forEach(visit)
        }
        visit(id)
        return result
    }
}

/// Treść `multipart/form-data` w pliku tymczasowym (wysyłka załącznika strumieniowo, bez wczytywania pliku do pamięci w żądaniu).
enum MultipartBody {
    static let boundary = "HorselyBoundary7d1c9a"

    static func write(fields: [(String, String)], file: OutboxFile) throws -> URL {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-upload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        func text(_ value: String) throws { try handle.write(contentsOf: Data(value.utf8)) }
        for (name, value) in fields {
            try text("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\(value)\r\n")
        }
        let safeName = file.fileName.replacingOccurrences(of: "\"", with: "")
        try text("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(file.contentType)\r\n\r\n")
        let source = try FileHandle(forReadingFrom: URL(fileURLWithPath: file.path))
        defer { try? source.close() }
        while let chunk = try source.read(upToCount: 1 << 20), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }
        try text("\r\n--\(boundary)--\r\n")
        return target
    }
}
