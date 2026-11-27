import Foundation

// Liczby JSON ze skalą zapisu (`24.60`, `98.0`, `7`) — odpowiednik `BigDecimal` z Androida w nagraniach jazdy ([K] 4.1).
// `JSONDecoder`/`JSONEncoder` Foundation nie gwarantują zachowania skali (`24.60` może wrócić jako `24.6`), dlatego nagranie
// czytane z tekstu przechodzi przez `JSONValue.parseKeepingScale`, a porównania „ze skalą” robi `textKeepingScale()`.

/// Zapis i odczyt `Decimal` z zachowaną skalą: mantysa i wykładnik dokładnie jak w tekście (`24.60` = 2460·10⁻²).
public enum DecimalText {
    /// `Decimal` z zapisu liczby JSON (`24.60`, `-3`, `0.0`, `1.5e2`) z mantysą i wykładnikiem jak w tekście; `nil` dla innego tekstu.
    public static func parse(_ text: String) -> Decimal? {
        let bytes = Array(text.utf8)
        var index = 0
        var negative = false
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") {
            negative = true
            index += 1
        }
        var digits: [UInt8] = []
        var exponent = 0
        while index < bytes.count, isDigit(bytes[index]) {
            digits.append(bytes[index] - UInt8(ascii: "0"))
            index += 1
        }
        guard !digits.isEmpty else { return nil }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            let start = index
            while index < bytes.count, isDigit(bytes[index]) {
                digits.append(bytes[index] - UInt8(ascii: "0"))
                exponent -= 1
                index += 1
            }
            guard index > start else { return nil }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            var exponentNegative = false
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                exponentNegative = bytes[index] == UInt8(ascii: "-")
                index += 1
            }
            let start = index
            var value = 0
            while index < bytes.count, isDigit(bytes[index]) {
                value = value * 10 + Int(bytes[index] - UInt8(ascii: "0"))
                guard value < 10_000 else { return nil }
                index += 1
            }
            guard index > start else { return nil }
            exponent += exponentNegative ? -value : value
        }
        guard index == bytes.count else { return nil }
        while digits.count > 1, digits[0] == 0 { digits.removeFirst() }
        // Mantysa do 19 cyfr mieści się w UInt64; wykładnik `Decimal` to -128…127. Inaczej — zwykły odczyt Foundation.
        guard digits.count <= 19, (-128...127).contains(exponent) else {
            return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        }
        var mantissa: UInt64 = 0
        for digit in digits { mantissa = mantissa * 10 + UInt64(digit) }
        return make(mantissa: mantissa, exponent: Int32(exponent), negative: negative)
    }

    /// Zapis liczby ze skalą `Decimal` (bez notacji naukowej): 2460·10⁻² → `24.60`, 0·10⁻¹ → `0.0`, 15·10⁰ → `15`.
    public static func text(_ value: Decimal) -> String {
        guard !value.isNaN else { return "NaN" }
        var digits = NSDecimalNumber(decimal: value.significand).stringValue
        if digits.hasPrefix("-") { digits.removeFirst() }
        let exponent = value.exponent
        if exponent > 0 {
            digits += String(repeating: "0", count: exponent)
        } else if exponent < 0 {
            let scale = -exponent
            if digits.count <= scale { digits = String(repeating: "0", count: scale - digits.count + 1) + digits }
            digits.insert(".", at: digits.index(digits.endIndex, offsetBy: -scale))
        }
        return value.sign == .minus && !value.isZero ? "-" + digits : digits
    }

    /// Współrzędna z 7 miejscami po przecinku (HALF_UP — remis od zera, jak `RoundingMode.HALF_UP`): tyle zapisuje program ([K] 2.1).
    /// `52.2297` → `52.2297000`, `-0.00000005` → `-0.0000001`.
    public static func coordinateText(_ value: Decimal) -> String {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, coordinateScale, .plain)
        var text = Self.text(rounded)
        if !text.contains(".") { text += "." }
        let fraction = text.split(separator: ".", omittingEmptySubsequences: false).last.map(\.count) ?? 0
        return text + String(repeating: "0", count: max(0, coordinateScale - fraction))
    }

    /// Współrzędna jak w `coordinateText`, jako `Decimal` o skali 7 (zapis w rekordzie załącznika).
    public static func coordinate(_ value: Decimal) -> Decimal {
        parse(coordinateText(value)) ?? value
    }

    public static let coordinateScale = 7

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    /// `Decimal` wprost z mantysy i wykładnika — bez skracania zer, które robią inicjalizatory z liczb całkowitych.
    private static func make(mantissa: UInt64, exponent: Int32, negative: Bool) -> Decimal {
        let w0 = UInt16(truncatingIfNeeded: mantissa)
        let w1 = UInt16(truncatingIfNeeded: mantissa >> 16)
        let w2 = UInt16(truncatingIfNeeded: mantissa >> 32)
        let w3 = UInt16(truncatingIfNeeded: mantissa >> 48)
        let length: UInt32 = w3 != 0 ? 4 : w2 != 0 ? 3 : w1 != 0 ? 2 : w0 != 0 ? 1 : 0
        return Decimal(
            _exponent: exponent,
            _length: length,
            _isNegative: negative && length > 0 ? 1 : 0,
            _isCompact: 0,
            _reserved: 0,
            _mantissa: (w0, w1, w2, w3, 0, 0, 0, 0)
        )
    }
}

public extension JSONValue {
    /// Odczyt JSON z liczbami ze skalą zapisu (`24.60` zostaje 2460·10⁻²) — nagrania jazdy i porównania „ze skalą” jak w Androidzie.
    static func parseKeepingScale(_ data: Data) throws -> JSONValue {
        var parser = ScaleParser(bytes: Array(data))
        return try parser.document()
    }

    static func parseKeepingScale(_ text: String) throws -> JSONValue {
        try parseKeepingScale(Data(text.utf8))
    }

    /// Tekst JSON z kluczami w porządku alfabetycznym i liczbami ze skalą `Decimal` (`DecimalText.text`) — do porównań „ze skalą”.
    func textKeepingScale() -> String {
        var out = ""
        write(into: &out)
        return out
    }

    private func write(into out: inout String) {
        switch self {
        case .null: out += "null"
        case let .bool(value): out += value ? "true" : "false"
        case let .number(value): out += DecimalText.text(value)
        case let .string(value): Self.writeString(value, into: &out)
        case let .array(items):
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += "," }
                item.write(into: &out)
            }
            out += "]"
        case let .object(fields):
            out += "{"
            for (index, key) in fields.keys.sorted().enumerated() {
                if index > 0 { out += "," }
                Self.writeString(key, into: &out)
                out += ":"
                fields[key]?.write(into: &out)
            }
            out += "}"
        }
    }

    private static func writeString(_ value: String, into out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}

/// Błąd odczytu JSON ze skalą (pozycja w bajtach).
public struct JSONScaleError: Error, Equatable, Sendable {
    public let offset: Int
}

/// Prosty parser JSON (RFC 8259), który zachowuje zapis liczb.
private struct ScaleParser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
        // BOM UTF-8.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
    }

    mutating func document() throws -> JSONValue {
        let value = try parseValue()
        skipSpace()
        guard index == bytes.count else { throw JSONScaleError(offset: index) }
        return value
    }

    private mutating func skipSpace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func parseValue() throws -> JSONValue {
        skipSpace()
        guard index < bytes.count else { throw JSONScaleError(offset: index) }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        default: return try parseNumber()
        }
    }

    private mutating func expect(_ word: String) throws {
        let expected = Array(word.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else {
            throw JSONScaleError(offset: index)
        }
        index += expected.count
    }

    private mutating func parseObject() throws -> JSONValue {
        index += 1
        var fields: [String: JSONValue] = [:]
        skipSpace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(fields)
        }
        while true {
            skipSpace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw JSONScaleError(offset: index) }
            let key = try parseString()
            skipSpace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw JSONScaleError(offset: index) }
            index += 1
            fields[key] = try parseValue()
            skipSpace()
            guard index < bytes.count else { throw JSONScaleError(offset: index) }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(fields)
            } else {
                throw JSONScaleError(offset: index)
            }
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        index += 1
        var items: [JSONValue] = []
        skipSpace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        while true {
            items.append(try parseValue())
            skipSpace()
            guard index < bytes.count else { throw JSONScaleError(offset: index) }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(items)
            } else {
                throw JSONScaleError(offset: index)
            }
        }
    }

    private mutating func parseString() throws -> String {
        index += 1
        var out: [UInt8] = []
        while true {
            guard index < bytes.count else { throw JSONScaleError(offset: index) }
            let byte = bytes[index]
            index += 1
            if byte == UInt8(ascii: "\"") { break }
            if byte != UInt8(ascii: "\\") {
                out.append(byte)
                continue
            }
            guard index < bytes.count else { throw JSONScaleError(offset: index) }
            let escaped = bytes[index]
            index += 1
            switch escaped {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(escaped)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0C)
            case UInt8(ascii: "n"): out.append(0x0A)
            case UInt8(ascii: "r"): out.append(0x0D)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "u"):
                var code = try parseHex4()
                if (0xD800...0xDBFF).contains(code), index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                    let saved = index
                    index += 2
                    let low = try parseHex4()
                    if (0xDC00...0xDFFF).contains(low) {
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    } else {
                        index = saved
                    }
                }
                let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
                out.append(contentsOf: Array(String(Character(scalar)).utf8))
            default:
                throw JSONScaleError(offset: index - 1)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private mutating func parseHex4() throws -> UInt32 {
        guard index + 4 <= bytes.count, let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else {
            throw JSONScaleError(offset: index)
        }
        index += 4
        return value
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = index
        while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
        guard index > start, let value = DecimalText.parse(String(decoding: bytes[start..<index], as: UTF8.self)) else {
            throw JSONScaleError(offset: start)
        }
        return .number(value)
    }
}
