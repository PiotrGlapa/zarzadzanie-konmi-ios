import Foundation

/// Wynik sprawdzenia adresu wpisanego albo odczytanego z kodu QR.
public enum AddressCheck: Equatable, Sendable {
    /// `baseUrl` — adres znormalizowany: schemat, host, port i ścieżka `/api/v1` (bez końcowego `/`).
    case ok(CheckedAddress)
    case rejected(Reason)

    public enum Reason: String, Equatable, Sendable {
        case malformed
        case unsupportedScheme
        case insecureNonLocal
        case remoteMustBeHttps

        public var message: String {
            switch self {
            case .malformed: "Nie rozpoznaję tego adresu. Wpisz go w postaci https://adres:port/api/v1"
            case .unsupportedScheme: "Adres musi zaczynać się od https:// albo http://"
            case .insecureNonLocal: "Adres spoza sieci lokalnej musi używać https (połączenia szyfrowanego). Jawny http jest dozwolony tylko w domowej sieci."
            case .remoteMustBeHttps: "Adres zdalny z kodu QR musi używać https."
            }
        }
    }

    public var address: CheckedAddress? {
        if case let .ok(address) = self { return address }
        return nil
    }

    public var reason: Reason? {
        if case let .rejected(reason) = self { return reason }
        return nil
    }
}

/// Adres po sprawdzeniu: `host` bez nawiasów IPv6, `isLocal` — wyłącznie z literału hosta.
public struct CheckedAddress: Hashable, Sendable {
    public let baseUrl: String
    public let host: String
    public let port: Int
    public let isLocal: Bool
    public let isHttps: Bool

    public init(baseUrl: String, host: String, port: Int, isLocal: Bool, isHttps: Bool) {
        self.baseUrl = baseUrl
        self.host = host
        self.port = port
        self.isLocal = isLocal
        self.isHttps = isHttps
    }
}

/// Reguły adresu (research R6, konstytucja III; `AddressRules.kt`). „Lokalny” wyłącznie z **literału** hosta — bez rozwiązywania
/// nazw (odporność na podmianę DNS): prywatny IPv4 (10/8, 172.16/12, 192.168/16, 169.254/16), IPv6 `fc00::/7` i `fe80::/10`
/// albo nazwa kończąca się `.local`. Jawny `http` jest dozwolony wyłącznie dla adresów lokalnych (po potwierdzeniu ostrzeżenia
/// w interfejsie).
///
/// - Parameter treatLoopbackAsLocal: tylko testy z zaślepką na `127.0.0.1`; w aplikacji zawsze `false`.
public struct AddressRules: Sendable {
    public static let apiPath = "/api/v1"
    public static let `default` = AddressRules()

    private let treatLoopbackAsLocal: Bool

    public init(treatLoopbackAsLocal: Bool = false) {
        self.treatLoopbackAsLocal = treatLoopbackAsLocal
    }

    /// Czy host (nazwa, IPv4 albo IPv6, także w nawiasach) jest adresem sieci lokalnej.
    public func isLocalHost(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if host.isEmpty { return false }
        if let octets = Self.parseIPv4(host) {
            return Self.isPrivateIPv4(octets) || (treatLoopbackAsLocal && octets[0] == 127)
        }
        if host.contains(":") { return isLocalIPv6(host) }
        return host.hasSuffix(".local") && host.count > ".local".count && !host.hasPrefix(".")
    }

    /// Sprawdza i normalizuje adres programu. Bez schematu zakładamy `https://`; brak ścieżki uzupełniamy o `/api/v1`.
    /// - Parameter remoteQr: `true` dla `remoteUrl` z kodu QR — wyłącznie `https`.
    public func check(_ input: String, remoteQr: Bool = false) -> AddressCheck {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .rejected(.malformed) }
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let separator = withScheme.range(of: "://") else { return .rejected(.malformed) }
        let scheme = withScheme[..<separator.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" else { return .rejected(.unsupportedScheme) }
        let rest = withScheme[separator.upperBound...]
        let authorityEnd = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
        let authority = String(rest[..<authorityEnd])
        var path = String(rest[authorityEnd...])
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<cut]) }
        guard let parsed = Self.parseAuthority(authority) else { return .rejected(.malformed) }

        let https = scheme == "https"
        let local = isLocalHost(parsed.host)
        if !https && remoteQr { return .rejected(.remoteMustBeHttps) }
        if !https && !local { return .rejected(.insecureNonLocal) }
        guard let normalizedPath = Self.normalizePath(path) else { return .rejected(.malformed) }
        let defaultPort = https ? 443 : 80
        let port = parsed.port ?? defaultPort
        let hostPart = parsed.host.contains(":") ? "[\(parsed.host)]" : parsed.host
        let portPart = parsed.port == nil ? "" : ":\(port)"
        return .ok(CheckedAddress(baseUrl: "\(scheme)://\(hostPart)\(portPart)\(normalizedPath)", host: parsed.host, port: port, isLocal: local, isHttps: https))
    }

    // MARK: Pomocnicze

    private static func normalizePath(_ path: String) -> String? {
        var trimmed = path
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare(apiPath) == .orderedSame { return apiPath }
        return nil
    }

    /// `host[:port]` albo `[ipv6][:port]`; bez danych logowania. Host małymi literami.
    private static func parseAuthority(_ authority: String) -> (host: String, port: Int?)? {
        if authority.isEmpty || authority.contains("@") { return nil }
        var host: String
        var portText: Substring?
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return nil }
            host = String(authority[authority.index(after: authority.startIndex)..<close])
            let after = authority[authority.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":") else { return nil }
                portText = after.dropFirst()
            }
            guard host.contains(":") else { return nil }
        } else {
            let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { return nil }
            host = String(parts[0])
            if parts.count == 2 { portText = parts[1] }
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
            guard host.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else { return nil }
        }
        host = host.lowercased()
        if host.isEmpty { return nil }
        var port: Int?
        if let portText {
            guard !portText.isEmpty, portText.allSatisfy(\.isASCIIDigit), let value = Int(portText), (1...65535).contains(value) else { return nil }
            port = value
        }
        return (host, port)
    }

    static func parseIPv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCIIDigit), let value = Int(part), (0...255).contains(value) else { return nil }
            octets.append(value)
        }
        return octets
    }

    static func isPrivateIPv4(_ o: [Int]) -> Bool {
        switch (o[0], o[1]) {
        case (10, _): true
        case (172, 16...31): true
        case (192, 168): true
        case (169, 254): true
        default: false
        }
    }

    /// Tylko literały szesnastkowe (strefa po `%` pomijana) — nigdy zapytanie DNS.
    private func isLocalIPv6(_ host: String) -> Bool {
        let literal = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let allowed = Set("0123456789abcdef:.")
        guard !literal.isEmpty, literal.allSatisfy({ allowed.contains($0) }), let bytes = Self.parseIPv6(literal) else { return false }
        // Adres IPv4 zapisany jako IPv6 (`::ffff:a.b.c.d`).
        if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
            return Self.isPrivateIPv4(bytes[12..<16].map(Int.init))
        }
        let uniqueLocal = (bytes[0] & 0xFE) == 0xFC
        let linkLocal = bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80
        let loopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
        return uniqueLocal || linkLocal || (treatLoopbackAsLocal && loopback)
    }

    /// 16 bajtów adresu IPv6 (z `::` i końcówką IPv4) albo `nil`, gdy literał jest niepoprawny.
    static func parseIPv6(_ text: String) -> [UInt8]? {
        let halves = text.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        func groups(_ part: String) -> [UInt16]? {
            if part.isEmpty { return [] }
            var result: [UInt16] = []
            let items = part.split(separator: ":", omittingEmptySubsequences: false)
            for (index, item) in items.enumerated() {
                if item.contains("."), index == items.count - 1 {
                    guard let v4 = parseIPv4(String(item)) else { return nil }
                    result.append(UInt16(v4[0] << 8 | v4[1]))
                    result.append(UInt16(v4[2] << 8 | v4[3]))
                } else {
                    guard !item.isEmpty, item.count <= 4, let value = UInt16(item, radix: 16) else { return nil }
                    result.append(value)
                }
            }
            return result
        }
        guard let head = groups(halves[0]) else { return nil }
        var all = head
        if halves.count == 2 {
            guard let tail = groups(halves[1]), head.count + tail.count <= 7 else { return nil }
            all += Array(repeating: 0, count: 8 - head.count - tail.count) + tail
        }
        guard all.count == 8 else { return nil }
        return all.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
