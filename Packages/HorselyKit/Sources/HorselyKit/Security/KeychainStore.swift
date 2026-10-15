import Foundation
import Security

/// Miejsce na tajny klucz (klucz API programu). W aplikacji — pęk kluczy; w testach — pamięć.
public protocol SecretStore: Sendable {
    func save(_ secret: String) throws
    func read() throws -> String?
    func delete() throws
}

public enum KeychainError: Error, Equatable {
    case status(OSStatus)
}

/// Klucz API w pęku kluczy: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (nie trafia do kopii ani na inne urządzenie,
/// dostępny dla zadań w tle po pierwszym odblokowaniu), grupa dostępu wspólna z rozszerzeniem udostępniania (NFR-M-04).
public struct KeychainStore: SecretStore {
    private let service: String
    private let account: String
    private let accessGroup: String?

    /// `accessGroup` — pełna nazwa grupy z prefiksem zespołu (`<TEAM>.pl.glapa.horsely.shared`); `nil` używa grupy domyślnej aplikacji.
    public init(service: String = "pl.glapa.horsely", account: String = "apiKey", accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func save(_ secret: String) throws {
        let data = Data(secret.utf8)
        var update = baseQuery
        update[kSecValueData as String] = data
        update[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(update as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let changes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updated = SecItemUpdate(baseQuery as CFDictionary, changes as CFDictionary)
            guard updated == errSecSuccess else { throw KeychainError.status(updated) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

/// Pamięć zamiast pęku kluczy — testy i podgląd.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(_ value: String? = nil) {
        self.value = value
    }

    public func save(_ secret: String) throws {
        lock.lock()
        defer { lock.unlock() }
        value = secret
    }

    public func read() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        value = nil
    }
}
