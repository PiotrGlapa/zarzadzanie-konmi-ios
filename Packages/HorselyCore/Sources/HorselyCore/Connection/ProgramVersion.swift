import Foundation

/// Wynik porównania wersji programu z wersjami granicznymi (research R21, `ProgramVersion.kt`).
public enum VersionCheck: String, Sendable, Equatable {
    /// Niższa niż `ProgramVersion.minimum` — parowanie odrzucone (FR-M-POL-04).
    case tooOld
    /// Od 1.5.0 do najnowszej testowanej włącznie.
    case supported
    /// Nowsza niż `ProgramVersion.tested` — działa dalej, ostrzeżenie raz na wersję (FR-M-UST-06).
    case newerThanTested
    /// Niepoprawny napis wersji — nie parujemy.
    case unknown

    public var isUsable: Bool { self == .supported || self == .newerThanTested }
}

/// Wersja `major.minor.patch`; przyrostek po `+` lub `-` jest pomijany, brakujące składniki to 0.
public struct ProgramVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Najniższa obsługiwana wersja programu.
    public static let minimum = ProgramVersion(major: 1, minor: 5, patch: 0)
    /// Najnowsza wersja programu, z którą aplikacja była testowana.
    public static let tested = ProgramVersion(major: 2, minor: 0, patch: 0)

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ text: String) {
        let core = text.trimmingCharacters(in: .whitespaces).prefix { $0 != "+" && $0 != "-" }
        if core.isEmpty { return nil }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        self.init(major: numbers[0], minor: numbers.count > 1 ? numbers[1] : 0, patch: numbers.count > 2 ? numbers[2] : 0)
    }

    public static func check(_ appVersion: String) -> VersionCheck {
        guard let version = ProgramVersion(appVersion) else { return .unknown }
        if version < minimum { return .tooOld }
        if version > tested { return .newerThanTested }
        return .supported
    }

    public static func < (lhs: ProgramVersion, rhs: ProgramVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}
