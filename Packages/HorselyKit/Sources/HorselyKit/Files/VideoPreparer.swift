import AVFoundation
import Foundation
import HorselyCore

/// Parametry filmu potrzebne do decyzji o zmniejszeniu: krótszy bok w pikselach (obrót nie ma znaczenia) i czas trwania.
public struct VideoInfo: Equatable, Sendable {
    public let shortSidePx: Int
    public let durationSeconds: Int

    public init(shortSidePx: Int, durationSeconds: Int) {
        self.shortSidePx = shortSidePx
        self.durationSeconds = durationSeconds
    }
}

/// Zmniejszenie filmu do 720p — wydzielone, żeby logikę przygotowania dało się sprawdzić bez prawdziwego kodeka.
public protocol VideoTranscoding: Sendable {
    /// Zapisuje przekodowany film w `target` i go zwraca; `progress` dostaje 0–100. Anulowanie zadania przerywa kodowanie.
    func prepare(source: URL, target: URL, progress: @escaping @Sendable (Int) -> Void) async throws -> URL
}

public enum VideoPreparerError: Error, Equatable, Sendable {
    /// System nie umie przekodować tego pliku (brak ścieżki wideo, nieobsługiwany kodek).
    case unsupported
}

/// Zmniejszenie filmu do 720p (krótszy bok) w `.mp4` (H.264 + AAC) przez `AVAssetExportSession` z presetem `AVAssetExportPreset1280x720`
/// (decyzja A10; odpowiednik Media3 Transformer z Androida). Preset zachowuje orientację (macierz obrotu ścieżki); postęp jest
/// odczytywany ze `states(updateInterval:)` co pół sekundy. Plik częściowy znika przy błędzie i anulowaniu.
public struct VideoPreparer: VideoTranscoding {
    public init() {}

    public func prepare(source: URL, target: URL, progress: @escaping @Sendable (Int) -> Void) async throws -> URL {
        try? FileManager.default.removeItem(at: target)
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPreset1280x720) else {
            throw VideoPreparerError.unsupported
        }
        session.shouldOptimizeForNetworkUse = true
        let box = SessionBox(session: session)
        let watcher = Task {
            for await state in box.session.states(updateInterval: 0.5) {
                if case let .exporting(progress: current) = state {
                    progress(min(max(Int(current.fractionCompleted * 100), 0), 100))
                }
            }
        }
        defer { watcher.cancel() }
        do {
            try await box.session.export(to: target, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        progress(100)
        return target
    }

    /// `AVAssetExportSession` jest używana tylko przez to wywołanie: eksport i odczyt postępu (bezpieczny wątkowo w AVFoundation).
    private struct SessionBox: @unchecked Sendable {
        let session: AVAssetExportSession
    }
}

/// Odczyt parametrów filmu z pliku (`MediaVideoInspector` Androida); `nil`, gdy pliku nie da się odczytać jako filmu.
public enum VideoInspector {
    public static func inspect(_ url: URL) async -> VideoInfo? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first, let size = try? await track.load(.naturalSize) else { return nil }
        let width = Int(abs(size.width).rounded())
        let height = Int(abs(size.height).rounded())
        guard width > 0, height > 0 else { return nil }
        let seconds = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        return VideoInfo(shortSidePx: min(width, height), durationSeconds: seconds.isFinite && seconds > 0 ? Int(seconds.rounded(.up)) : 0)
    }
}

/// Film gotowy do wysyłki albo zapisu.
///
/// - `transcoded`: film został zmniejszony do 720p (nowy plik `.mp4`), inaczej `file` to plik źródłowy
/// - `replacedSource`: plik źródłowy zastąpiony przekodowanym — wołający usuwa go dopiero po utrwaleniu wyniku, żeby przerwanie w środku
///   nie zostawiło wpisu ze ścieżką do usuniętego pliku; `nil`, gdy film nie był zmniejszany
/// - `thumbnail`: JPEG ≤ 1 MB z pierwszą klatką — `nil`, gdy klatki nie udało się odczytać (film idzie bez miniatury)
public struct ReadyVideo: Equatable, Sendable {
    public let file: URL
    public let fileName: String
    public let contentType: String
    public let sizeBytes: Int64
    public let sha256: String
    public let thumbnail: URL?
    public let transcoded: Bool
    public let replacedSource: URL?
}

/// Wynik przygotowania filmu: gotowy plik (z miniaturą) albo odrzucenie z komunikatem dla użytkownika.
public enum PreparedVideo: Equatable, Sendable {
    case ready(ReadyVideo)
    case rejected(String)
}

/// Przygotowanie filmu przed wysyłką (decyzja A10, `VideoPreparation.kt` Androida): zmniejszenie do 720p według `VideoPolicy` i miniatura
/// pierwszej klatki. Czynność jest ta sama w kolejce (operacja `held` do końca przygotowania) i w trybie samodzielnym (przed zapisem pliku).
public struct VideoPreparation: Sendable {
    static let transcodeFailed = "Nie udało się zmniejszyć filmu do 720p. Spróbuj ponownie albo wybierz inny film."
    static let unreadable = "Nie udało się odczytać filmu — jest za duży, żeby go wysłać bez zmniejszenia."

    private let transcoder: any VideoTranscoding
    private let inspect: @Sendable (URL) async -> VideoInfo?
    private let thumbnail: @Sendable (URL) async -> Data?

    /// - Parameters:
    ///   - inspect: odczyt parametrów filmu (`VideoInspector`)
    ///   - thumbnail: JPEG pierwszej klatki (`VideoThumbnail.make`)
    public init(
        transcoder: any VideoTranscoding = VideoPreparer(),
        inspect: @escaping @Sendable (URL) async -> VideoInfo? = { await VideoInspector.inspect($0) },
        thumbnail: @escaping @Sendable (URL) async -> Data? = { await VideoThumbnail.make(video: $0) }
    ) {
        self.transcoder = transcoder
        self.inspect = inspect
        self.thumbnail = thumbnail
    }

    /// Czy `file` trzeba zmniejszyć (wtedy w kolejce czeka w stanie `held`); nieczytelny film mniejszy niż 100 MB idzie bez zmian.
    public func needsTranscoding(_ file: URL, sendOriginal: Bool) async -> Bool {
        decide(file, await inspect(file), sendOriginal: sendOriginal) != .keepOriginal
    }

    /// Miniatura pierwszej klatki `file` (film, którego zmniejszać nie trzeba).
    public func thumbnail(of file: URL) async -> Data? {
        await thumbnail(file)
    }

    /// Zmniejsza `source` (gdy trzeba) i robi miniaturę. Źródło nigdy nie jest tu usuwane (przy zmniejszeniu wraca jako `replacedSource`);
    /// przy odrzuceniu też zostaje — decyzję o usunięciu podejmuje wołający. Anulowanie zadania przerywa kodowanie (`CancellationError`).
    ///
    /// - Parameters:
    ///   - existingThumbnail: miniatura już przygotowana (z nagrania jazdy) — zostaje, nowej nie robimy
    ///   - lenient: tryb samodzielny (nic nie jest wysyłane, więc limit 100 MB nie obowiązuje): film, którego nie udało się zmniejszyć albo
    ///     który po zmniejszeniu nadal przekracza limit, zapisuje się mimo to (zmniejszony, a gdy kodowanie zawiodło — oryginalny)
    public func prepare(
        source: URL, fileName: String, contentType: String, sendOriginal: Bool, existingThumbnail: URL? = nil, lenient: Bool = false,
        progress: @escaping @Sendable (Int) -> Void = { _ in }
    ) async throws -> PreparedVideo {
        let info = await inspect(source)
        var file = source
        var name = fileName
        var type = contentType
        var transcoded = false
        let decision: VideoDecision = lenient && sendOriginal ? .keepOriginal : decide(source, info, sendOriginal: sendOriginal)
        switch decision {
        case let .reject(message):
            if !lenient { return .rejected(message) }
        case .transcode:
            let target = source.deletingLastPathComponent().appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-720p.mp4")
            do {
                _ = try await transcoder.prepare(source: source, target: target, progress: progress)
                let verdict = VideoPolicy.afterTranscode(sizeBytes: Self.size(of: target), durationSeconds: info?.durationSeconds ?? 0)
                if case let .reject(message) = verdict, !lenient {
                    try? FileManager.default.removeItem(at: target)
                    return .rejected(message)
                }
                file = target
                name = (name as NSString).deletingPathExtension + ".mp4"
                type = "video/mp4"
                transcoded = true
            } catch {
                try? FileManager.default.removeItem(at: target)
                // Przerwane (np. koniec czasu zadania w tle) — nie odrzucamy: przygotowanie wznowi się później.
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                if !lenient { return .rejected(Self.transcodeFailed) }
            }
        case .keepOriginal:
            break
        }
        var thumbnailURL = existingThumbnail.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        if thumbnailURL == nil, let jpeg = await thumbnail(file) {
            let target = file.deletingLastPathComponent().appendingPathComponent(file.deletingPathExtension().lastPathComponent + "-miniatura.jpg")
            try jpeg.write(to: target, options: .atomic)
            thumbnailURL = target
        }
        let (size, digest) = try FileDigest.sha256(of: file)
        return .ready(ReadyVideo(
            file: file, fileName: name, contentType: type, sizeBytes: size, sha256: digest, thumbnail: thumbnailURL, transcoded: transcoded,
            replacedSource: transcoded ? source : nil
        ))
    }

    private func decide(_ file: URL, _ info: VideoInfo?, sendOriginal: Bool) -> VideoDecision {
        let size = Self.size(of: file)
        guard let info else {
            // Parametrów nie da się odczytać: mały plik idzie bez zmian, większego nie da się ani wysłać, ani zmniejszyć.
            return VideoPolicy.canSendOriginal(sizeBytes: size) ? .keepOriginal : .reject(Self.unreadable)
        }
        return VideoPolicy.decide(shortSidePx: info.shortSidePx, sizeBytes: size, sendOriginal: sendOriginal)
    }

    static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
