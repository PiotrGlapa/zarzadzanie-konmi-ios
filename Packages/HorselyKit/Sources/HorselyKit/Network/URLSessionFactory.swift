import Foundation
import HorselyCore
import Network

/// Wynik przesłania jednego żądania na jeden adres.
public enum TransportOutcome: Sendable {
    /// Odpowiedź programu (dowolny status); `remoteIP` — adres IP z metryk (dziennik połączeń).
    case response(status: Int, headers: [String: String], body: Data, file: URL?, remoteIP: String?)
    /// Błąd sieci: `sentBody` — żądanie (z treścią) wyszło, odpowiedzi brak.
    case failure(sentBody: Bool, code: URLError.Code?)
    /// Certyfikat odrzucony w uzgodnieniu TLS — żądanie (z kluczem) nie wyszło.
    case certificateRejected(TrustDecision)
}

/// Wysyłka żądania na wskazany adres. W aplikacji — `URLSessionTransport`; testy podstawiają konfigurację z zaślepką
/// `URLProtocol` albo własną implementację.
public protocol ProgramTransport: Sendable {
    func send(_ request: URLRequest, to address: ServerAddress, bodyFile: URL?, download: Bool, progress: (@Sendable (Int64, Int64?) -> Void)?) async -> TransportOutcome
}

/// Sprawdzenie, czy z adresem da się nawiązać połączenie TCP w limicie (3 s) — bez czekania 30 s na niedostępny adres lokalny
/// w sieci komórkowej (contracts/android/connection-behavior.md §1).
public protocol ConnectProbe: Sendable {
    func canConnect(host: String, port: Int, timeout: TimeInterval) async -> Bool
}

/// Zaślepka testów i podglądów: każdy adres osiągalny.
public struct AlwaysReachable: ConnectProbe {
    public init() {}
    public func canConnect(host: String, port: Int, timeout: TimeInterval) async -> Bool { true }
}

/// Próba TCP przez Network (`NWConnection`) — bez TLS i bez wysyłania danych.
public struct TCPConnectProbe: ConnectProbe {
    public init() {}

    public func canConnect(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let once = ResumeOnce()
        defer { connection.cancel() }
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(true)
                case .failed, .cancelled: once.resume(false)
                case .waiting: once.resume(false)
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.resume(false) }
        } ?? false
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool?, Never>?

        func set(_ continuation: CheckedContinuation<Bool?, Never>) {
            lock.lock()
            self.continuation = continuation
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
}

/// Transport na `URLSession`: osobna sesja na żądanie z delegatem, który ocenia certyfikat (`TrustEvaluator`) przed wysłaniem
/// klucza, zbiera metryki (IP, czy treść wyszła) i postęp. Limity: odpowiedź (odczyt) 30 s, plik — 60 s bez postępu.
public final class URLSessionTransport: ProgramTransport {
    public static let readTimeout: TimeInterval = 30
    public static let fileStallTimeout: TimeInterval = 60

    private let evaluator: TrustEvaluator
    private let configure: @Sendable (URLSessionConfiguration) -> Void

    /// - Parameter configure: zmiany konfiguracji sesji (testy: `protocolClasses` z zaślepką).
    public init(evaluator: TrustEvaluator = TrustEvaluator(), configure: @escaping @Sendable (URLSessionConfiguration) -> Void = { _ in }) {
        self.evaluator = evaluator
        self.configure = configure
    }

    public func send(_ request: URLRequest, to address: ServerAddress, bodyFile: URL?, download: Bool, progress: (@Sendable (Int64, Int64?) -> Void)?) async -> TransportOutcome {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = bodyFile == nil ? Self.readTimeout : Self.fileStallTimeout
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configure(configuration)
        let delegate = TaskDelegate(evaluator: evaluator, address: address, progress: progress)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return await withCheckedContinuation { continuation in
            delegate.continuation = continuation
            let task: URLSessionTask
            if let bodyFile {
                task = session.uploadTask(with: request, fromFile: bodyFile)
            } else if download {
                task = session.downloadTask(with: request)
            } else {
                task = session.dataTask(with: request)
            }
            task.resume()
        }
    }

    /// Delegat jednej sesji z jednym zadaniem.
    final class TaskDelegate: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
        private let evaluator: TrustEvaluator
        private let address: ServerAddress
        private let progress: (@Sendable (Int64, Int64?) -> Void)?
        private let lock = NSLock()
        var continuation: CheckedContinuation<TransportOutcome, Never>?
        private var data = Data()
        private var file: URL?
        private var rejection: TrustDecision?
        private var metrics: URLSessionTaskMetrics?

        init(evaluator: TrustEvaluator, address: ServerAddress, progress: (@Sendable (Int64, Int64?) -> Void)?) {
            self.evaluator = evaluator
            self.address = address
            self.progress = progress
        }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            let decision = evaluator.evaluate(trust, host: challenge.protectionSpace.host, mode: address.trustMode, pinnedSha256: address.certSha256)
            if decision == .accept {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                lock.lock()
                rejection = decision
                lock.unlock()
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            self.data.append(data)
            lock.unlock()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            progress?(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // Plik tymczasowy sesji znika po powrocie z tej metody — przenosimy go.
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("horsely-download-\(UUID().uuidString)")
            try? FileManager.default.moveItem(at: location, to: target)
            lock.lock()
            file = target
            lock.unlock()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            progress?(totalBytesSent, totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            lock.lock()
            self.metrics = metrics
            lock.unlock()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            let body = data
            let downloaded = file
            let rejected = rejection
            let collected = metrics
            lock.unlock()
            guard let pending else { return }
            let transaction = collected?.transactionMetrics.last
            let remoteIP = transaction?.remoteAddress
            if let rejected {
                pending.resume(returning: .certificateRejected(rejected))
                return
            }
            if let error {
                let code = (error as? URLError)?.code
                pending.resume(returning: .failure(sentBody: Self.bodySent(transaction: transaction, code: code), code: code))
                return
            }
            guard let http = task.response as? HTTPURLResponse else {
                pending.resume(returning: .failure(sentBody: true, code: nil))
                return
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
            }
            pending.resume(returning: .response(status: http.statusCode, headers: headers, body: body, file: downloaded, remoteIP: remoteIP))
        }

        /// Czy treść żądania zdążyła wyjść: z metryk (koniec wysyłania żądania), a bez nich — z kodu błędu (błędy nawiązywania
        /// połączenia to „nie wysłano”; pozostałe ostrożnie „wysłano” — wynik nieznany, bez ryzyka duplikatu).
        static func bodySent(transaction: URLSessionTaskTransactionMetrics?, code: URLError.Code?) -> Bool {
            // Metryki są wiarygodne tylko dla prawdziwego połączenia (osobna sesja na żądanie — połączenie zawsze nowe).
            if let transaction, transaction.connectStartDate != nil || transaction.isReusedConnection, transaction.requestStartDate != nil {
                return transaction.requestEndDate != nil
            }
            guard let code else { return true }
            return !notSentCodes.contains(code)
        }

        static let notSentCodes: Set<URLError.Code> = [
            .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed, .serverCertificateUntrusted,
            .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
            .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection, .internationalRoamingOff, .callIsActive, .dataNotAllowed,
            .cancelled, .badURL, .unsupportedURL,
        ]
    }
}

/// Sonda TLS adresu ręcznego bez odcisku (contracts/android/pairing-and-connection.md): uzgodnienie TLS bez wysłania żądania HTTP —
/// zwraca „Wystawca: <CN>, dla: <nazwa>” do potwierdzenia albo `nil` (certyfikat nieważny / samopodpisany).
public enum TLSProbe {
    public static func issuer(of url: String, evaluator: TrustEvaluator = TrustEvaluator()) async -> String? {
        guard let target = URL(string: url) else { return nil }
        let delegate = ProbeDelegate(evaluator: evaluator)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = AddressOrder.connectTimeout * 3
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return await withCheckedContinuation { continuation in
            delegate.continuation = continuation
            session.dataTask(with: target).resume()
        }
    }

    final class ProbeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let evaluator: TrustEvaluator
        private let lock = NSLock()
        var continuation: CheckedContinuation<String?, Never>?
        private var summary: String?

        init(evaluator: TrustEvaluator) {
            self.evaluator = evaluator
        }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if let trust = challenge.protectionSpace.serverTrust {
                let found = evaluator.probeSummary(trust, host: challenge.protectionSpace.host)
                lock.lock()
                summary = found
                lock.unlock()
            }
            // Żądanie nigdy nie wychodzi — przerywamy po ocenie certyfikatu.
            completionHandler(.cancelAuthenticationChallenge, nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            let found = summary
            lock.unlock()
            pending?.resume(returning: found)
        }
    }
}
