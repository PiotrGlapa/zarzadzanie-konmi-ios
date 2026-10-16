import CommonCrypto
import CryptoKit
import Foundation

/// Liczby w kopii — pokazywane przed odtworzeniem (FR-KOP-02): konie, wpisy, załączniki, pozycje kosza.
public struct BackupCounts: Codable, Equatable, Sendable {
    public var horses: Int
    public var entries: Int
    public var attachments: Int
    public var trash: Int

    public init(horses: Int = 0, entries: Int = 0, attachments: Int = 0, trash: Int = 0) {
        self.horses = horses
        self.entries = entries
        self.attachments = attachments
        self.trash = trash
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        horses = try c.decodeIfPresent(Int.self, forKey: .horses) ?? 0
        entries = try c.decodeIfPresent(Int.self, forKey: .entries) ?? 0
        attachments = try c.decodeIfPresent(Int.self, forKey: .attachments) ?? 0
        trash = try c.decodeIfPresent(Int.self, forKey: .trash) ?? 0
    }
}

/// `manifest.json` (contracts/android/backup-format.md §3; `BackupModels.kt` Androida 2.0.1) — pierwszy wpis archiwum; `entries` to
/// sumy `sha256` pozostałych wpisów (`export.json`, `phone.json`, `attachments/<id>`).
public struct BackupManifest: Codable, Equatable, Sendable {
    public static let format = "zk-kopia"
    /// Najwyższy `formatVersion`, który ta aplikacja odtworzy (zgodność wstecz, FR-KOP-04).
    public static let formatVersion = 2
    public static let exportSchemaVersion = "1.5"
    public static let manifestName = "manifest.json"
    public static let exportName = "export.json"
    public static let phoneName = "phone.json"
    public static let attachmentsPrefix = "attachments/"
    public static let fileExtension = "zkkopia"

    public var format: String
    public var formatVersion: Int
    public var createdAt: String
    public var appVersion: String
    public var exportSchemaVersion: String
    public var counts: BackupCounts
    public var entries: [String: String]

    public init(createdAt: String, appVersion: String, counts: BackupCounts, entries: [String: String]) {
        format = Self.format
        formatVersion = Self.formatVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        exportSchemaVersion = Self.exportSchemaVersion
        self.counts = counts
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? Self.format
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? Self.formatVersion
        createdAt = try c.decode(String.self, forKey: .createdAt)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        exportSchemaVersion = try c.decodeIfPresent(String.self, forKey: .exportSchemaVersion) ?? Self.exportSchemaVersion
        counts = try c.decodeIfPresent(BackupCounts.self, forKey: .counts) ?? BackupCounts()
        entries = try c.decodeIfPresent([String: String].self, forKey: .entries) ?? [:]
    }

    public static func attachmentEntry(_ id: String) -> String { attachmentsPrefix + id }

    /// Czas utworzenia kopii (do ekranu odtwarzania).
    public var created: LocalDateTime? { LocalDateTime(createdAt) }

    /// `Zarzadzanie-konmi-kopia-RRRR-MM-DD.zkkopia`.
    public static func manualFileName(_ date: LocalDate) -> String { "Zarzadzanie-konmi-kopia-\(date).\(fileExtension)" }

    /// `zk-auto-RRRR-MM-DD.zkkopia`.
    public static func autoFileName(_ date: LocalDate) -> String { "zk-auto-\(date).\(fileExtension)" }

    /// Nazwa wpisu archiwum, którą kopia może zawierać (bez ścieżek wychodzących poza katalog).
    public static func isValidEntryName(_ name: String) -> Bool {
        if name == manifestName || name == exportName || name == phoneName { return true }
        guard name.hasPrefix(attachmentsPrefix) else { return false }
        let id = name.dropFirst(attachmentsPrefix.count)
        return (1 ... 64).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// Przyczyna niepowodzenia zapisu albo odczytu kopii (FR-KOP-03) — komunikat po polsku jak w Androidzie.
public enum BackupError: Error, Equatable, Sendable, LocalizedError {
    case needsPassword
    case wrongPassword
    case corrupted(String)
    case newerVersion(Int)
    case sourceCorrupted(String)

    public var message: String {
        switch self {
        case .needsPassword: "Ta kopia jest chroniona hasłem."
        case .wrongPassword: "Nieprawidłowe hasło."
        case let .corrupted(detail): "Plik uszkodzony lub niekompletny (\(detail))."
        case let .newerVersion(version): "Kopia z nowszej wersji aplikacji (format \(version)) — zaktualizuj aplikację."
        case let .sourceCorrupted(id): "Plik załącznika w telefonie jest uszkodzony (\(id))."
        }
    }

    public var errorDescription: String? { message }
}

/// Szyfrowanie pliku kopii hasłem (contracts/android/backup-format.md §2; `BackupCrypto.kt`): nagłówek `ZKKOPIA1`, PBKDF2-HMAC-SHA256
/// (310 000 iteracji, sól 16 B), AES-256-GCM w porcjach do 1 MiB uwierzytelnianych razem z numerem i flagą „ostatnia”. Strumieniowo,
/// plik do pliku.
public enum BackupCrypto {
    public static let magic = Data("ZKKOPIA1".utf8)
    public static let kdfPBKDF2SHA256: UInt8 = 1
    public static let iterations = 310_000
    public static let saltBytes = 16
    public static let nonceBytes = 12
    public static let tagBytes = 16
    public static let chunkBytes = 1024 * 1024
    static let headerBytes = 8 + 1 + 4 + 16
    static let maxIterations = 10_000_000

    public static func isEncrypted(_ prefix: Data) -> Bool { prefix.count >= magic.count && prefix.prefix(magic.count) == magic }

    /// Szyfruje plik `source` do `target` (nadpisuje).
    public static func encrypt(source: URL, target: URL, password: String, iterations: Int = iterations) throws {
        let salt = SymmetricKey(size: SymmetricKeySize(bitCount: saltBytes * 8)).withUnsafeBytes { Data($0) }
        let key = try deriveKey(password, salt: salt, iterations: iterations)
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var header = magic
        header.append(kdfPBKDF2SHA256)
        header.append(bigEndian(UInt32(iterations)))
        header.append(salt)
        try output.write(contentsOf: header)
        var index: UInt64 = 0
        var current = try input.read(upToCount: chunkBytes) ?? Data()
        while true {
            let next = current.count == chunkBytes ? (try input.read(upToCount: chunkBytes) ?? Data()) : Data()
            let last = next.isEmpty
            let sealed = try AES.GCM.seal(current, using: key, nonce: AES.GCM.Nonce(), authenticating: aad(salt: salt, index: index, last: last))
            let data = sealed.ciphertext + sealed.tag
            try output.write(contentsOf: bigEndian(UInt32(data.count)) + sealed.nonce.withUnsafeBytes { Data($0) } + data)
            index += 1
            if last { break }
            current = next
        }
    }

    /// Odszyfrowuje `source` do `target`. Błędy: `wrongPassword` (pierwsza porcja nie przechodzi weryfikacji), `corrupted`.
    public static func decrypt(source: URL, target: URL, password: String) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let header = try input.read(upToCount: headerBytes) ?? Data()
        guard header.count == headerBytes, header.prefix(magic.count) == magic else { throw BackupError.corrupted("nagłówek") }
        guard header[header.startIndex + 8] == kdfPBKDF2SHA256 else { throw BackupError.corrupted("nieznana funkcja klucza") }
        let iterations = Int(readUInt32(header, at: 9))
        guard (1 ... maxIterations).contains(iterations) else { throw BackupError.corrupted("liczba iteracji") }
        let salt = Data(header[(header.startIndex + 13) ..< (header.startIndex + headerBytes)])
        let key = try deriveKey(password, salt: salt, iterations: iterations)
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }

        func readLength() throws -> Int? {
            let bytes = try input.read(upToCount: 4) ?? Data()
            if bytes.isEmpty { return nil }
            guard bytes.count == 4 else { throw BackupError.corrupted("plik obcięty") }
            return Int(readUInt32(bytes, at: 0))
        }

        var index: UInt64 = 0
        guard var length = try readLength() else { throw BackupError.corrupted("brak danych") }
        while true {
            guard length >= tagBytes, length <= chunkBytes + tagBytes else { throw BackupError.corrupted("porcja \(index)") }
            let nonce = try input.read(upToCount: nonceBytes) ?? Data()
            let data = try input.read(upToCount: length) ?? Data()
            guard nonce.count == nonceBytes, data.count == length else { throw BackupError.corrupted("plik obcięty") }
            let next = try readLength()
            let last = next == nil
            let plain: Data
            do {
                plain = try open(nonce: nonce, data: data, key: key, aad: aad(salt: salt, index: index, last: last))
            } catch {
                if index == 0 {
                    // Pierwsza porcja: albo złe hasło, albo plik obcięty tuż po niej (flaga „ostatnia” się nie zgadza).
                    let truncated = (try? open(nonce: nonce, data: data, key: key, aad: aad(salt: salt, index: index, last: !last))) != nil
                    throw truncated ? BackupError.corrupted("plik obcięty") : BackupError.wrongPassword
                }
                throw BackupError.corrupted("porcja \(index)")
            }
            try output.write(contentsOf: plain)
            index += 1
            guard let next else { break }
            length = next
        }
    }

    static func open(nonce: Data, data: Data, key: SymmetricKey, aad: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: data.prefix(data.count - tagBytes), tag: data.suffix(tagBytes))
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    /// PBKDF2-HMAC-SHA256, hasło w UTF-8 (jak `PBEKeySpec` w Javie), klucz 256 bitów.
    static func deriveKey(_ password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBuffer in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), password, passwordBytes.count, saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &derived, derived.count
            )
        }
        guard status == kCCSuccess else { throw BackupError.corrupted("klucz") }
        return SymmetricKey(data: derived)
    }

    static func aad(salt: Data, index: UInt64, last: Bool) -> Data {
        var data = magic
        data.append(salt)
        withUnsafeBytes(of: index.bigEndian) { data.append(contentsOf: $0) }
        data.append(last ? 1 : 0)
        return data
    }

    static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return data[start ..< start + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
