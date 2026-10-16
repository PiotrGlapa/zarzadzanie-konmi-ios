import Foundation
import HorselyCore

/// Wysyłka plików w tle (T114, FR-M-ZAL-04): żądania z treścią w pliku (`CreateAttachment`) idą sesją w tle
/// `pl.glapa.horsely.upload`, więc system kończy je także po przejściu aplikacji w tło; pozostałe żądania — zwykłym transportem.
///
/// Wznawianie: gdy aplikację zamknięto w trakcie, operacja zostaje w stanie „wysyłanie”; przy starcie kolejka przechodzi
/// w „wynik nieznany” i ustala wynik licznikiem przed i po albo ponawia z tym samym `Idempotency-Key` — plik wysyła się
/// najwyżej ponownie w całości, bez duplikatu w programie.
public final class BackgroundUploader: NSObject, ProgramTransport, URLSessionDataDelegate, @unchecked Sendable {
    public static let identifier = "pl.glapa.horsely.upload"

    private struct Pending {
        let continuation: CheckedContinuation<TransportOutcome, Never>
        let address: ServerAddress
        let progress: (@Sendable (Int64, Int64?) -> Void)?
        var data = Data()
        var rejection: TrustDecision?
        var metrics: URLSessionTaskMetrics?
    }

    private let base: ProgramTransport
    private let evaluator: TrustEvaluator
    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private var session: URLSession?
    private var finishedEvents: (@Sendable () -> Void)?

    /// - Parameters:
    ///   - base: transport zwykłych żądań (i pobierania plików).
    ///   - identifier: identyfikator sesji w tle (`BGTaskSchedulerPermittedIdentifiers` / contracts/app-entry-points-ios.md).
    public init(base: ProgramTransport = URLSessionTransport(), evaluator: TrustEvaluator = TrustEvaluator(), identifier: String = BackgroundUploader.identifier) {
        self.base = base
        self.evaluator = evaluator
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.timeoutIntervalForRequest = URLSessionTransport.fileStallTimeout
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let created = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        lock.withLock { session = created }
    }

    public func send(_ request: URLRequest, to address: ServerAddress, bodyFile: URL?, download: Bool, progress: (@Sendable (Int64, Int64?) -> Void)?) async -> TransportOutcome {
        guard let bodyFile, !download, let session = lock.withLock({ session }) else {
            return await base.send(request, to: address, bodyFile: bodyFile, download: download, progress: progress)
        }
        return await withCheckedContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: bodyFile)
            lock.withLock { pending[task.taskIdentifier] = Pending(continuation: continuation, address: address, progress: progress) }
            task.resume()
        }
    }

    /// Zdarzenia sesji po wznowieniu aplikacji przez system (`.backgroundTask(.urlSession)`): wywołuje `completion`, gdy sesja
    /// dostarczy wszystkie zdarzenia.
    public func handleEvents(completion: @escaping @Sendable () -> Void) {
        lock.withLock { finishedEvents = completion }
    }

    // MARK: URLSessionDelegate

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock { () -> (@Sendable () -> Void)? in
            defer { finishedEvents = nil }
            return finishedEvents
        }
        completion?()
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = challenge.protectionSpace.host.lowercased()
        let match = lock.withLock { pending.first { Self.host(of: $0.value.address) == host } }
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust,
              let match else {
            // Zadanie sprzed ponownego uruchomienia (bez zapamiętanego adresu) — bez weryfikacji przypiętego certyfikatu nie wysyłamy.
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let address = match.value.address
        let decision = evaluator.evaluate(trust, host: challenge.protectionSpace.host, mode: address.trustMode, pinnedSha256: address.certSha256)
        if decision == .accept {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            lock.withLock { pending[match.key]?.rejection = decision }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock { pending[dataTask.taskIdentifier]?.data.append(data) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = lock.withLock { pending[task.taskIdentifier]?.progress }
        progress?(totalBytesSent, totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : nil)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.withLock { pending[task.taskIdentifier]?.metrics = metrics }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let entry = lock.withLock({ pending.removeValue(forKey: task.taskIdentifier) }) else { return }
        let transaction = entry.metrics?.transactionMetrics.last
        if let rejection = entry.rejection {
            entry.continuation.resume(returning: .certificateRejected(rejection))
            return
        }
        if let error {
            let code = (error as? URLError)?.code
            entry.continuation.resume(returning: .failure(sentBody: URLSessionTransport.TaskDelegate.bodySent(transaction: transaction, code: code), code: code))
            return
        }
        guard let http = task.response as? HTTPURLResponse else {
            entry.continuation.resume(returning: .failure(sentBody: true, code: nil))
            return
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
        }
        entry.continuation.resume(returning: .response(status: http.statusCode, headers: headers, body: entry.data, file: nil, remoteIP: transaction?.remoteAddress))
    }
}

extension BackgroundUploader {
    /// Host adresu (bez schematu, portu i nawiasów IPv6) — do dopasowania wyzwania TLS do zadania.
    static func host(of address: ServerAddress) -> String {
        let hostPort = address.hostAndPort
        if hostPort.hasPrefix("["), let end = hostPort.firstIndex(of: "]") {
            return String(hostPort[hostPort.index(after: hostPort.startIndex)..<end]).lowercased()
        }
        return (hostPort.split(separator: ":").first.map(String.init) ?? hostPort).lowercased()
    }
}

extension BackgroundUploader {
    /// Jedna sesja w tle na proces — system pozwala na jedną sesję o danym identyfikatorze.
    public static let shared = BackgroundUploader()
}
