import Foundation
import HorselyCore

/// Walidator JSON Schema 2020-12 w zakresie słów kluczowych `export-schema-1.6.json` (odpowiednik `OpenApiSchemas.exportErrors16`
/// z testów Androida, który używa biblioteki networknt). Liczby porównywane są jako `Decimal` ze skalą zapisu
/// (`JSONValue.parseKeepingScale`), więc `multipleOf: 0.01` i zakresy są dokładne. `format` i `contentEncoding` są — jak
/// w domyślnym dialekcie 2020-12 — tylko adnotacjami (nie są sprawdzane).
struct JSONSchemaValidator {
    let root: JSONValue

    init(schema: Data) throws {
        root = try JSONValue.parseKeepingScale(schema)
    }

    /// Błędy walidacji dokumentu (pusta lista — dokument zgodny ze schematem).
    func errors(_ document: Data) throws -> [String] {
        let instance = try JSONValue.parseKeepingScale(document)
        var out: [String] = []
        validate(instance, against: root, at: "$", into: &out)
        return out
    }

    private func isValid(_ instance: JSONValue, against schema: JSONValue) -> Bool {
        var out: [String] = []
        validate(instance, against: schema, at: "", into: &out)
        return out.isEmpty
    }

    private func resolve(_ reference: String) -> JSONValue? {
        guard reference.hasPrefix("#/") else { return nil }
        var node: JSONValue? = root
        for part in reference.dropFirst(2).split(separator: "/") {
            node = node?[String(part)]
        }
        return node
    }

    private func validate(_ instance: JSONValue, against schema: JSONValue, at path: String, into out: inout [String]) {
        if case let .bool(allowed) = schema {
            if !allowed { out.append("\(path): schemat nie dopuszcza wartości") }
            return
        }
        guard case let .object(rules) = schema else { return }

        if let reference = rules["$ref"]?.stringValue {
            if let target = resolve(reference) {
                validate(instance, against: target, at: path, into: &out)
            } else {
                out.append("\(path): nieznane odwołanie \(reference)")
            }
        }
        if let type = rules["type"] {
            let names: [String]
            switch type {
            case let .string(name): names = [name]
            case let .array(items): names = items.compactMap(\.stringValue)
            default: names = []
            }
            if !names.contains(where: { Self.matches(instance, type: $0) }) {
                out.append("\(path): typ inny niż \(names.joined(separator: "|"))")
            }
        }
        if let allowed = rules["enum"]?.arrayValue, !allowed.contains(instance) {
            out.append("\(path): wartości nie ma w enum")
        }
        if let constant = rules["const"], constant != instance {
            out.append("\(path): wartość różna od const")
        }
        if let parts = rules["allOf"]?.arrayValue {
            for part in parts { validate(instance, against: part, at: path, into: &out) }
        }
        if let parts = rules["oneOf"]?.arrayValue {
            let passing = parts.filter { isValid(instance, against: $0) }.count
            if passing != 1 { out.append("\(path): oneOf spełnia \(passing) schematów zamiast 1") }
        }
        if let excluded = rules["not"], isValid(instance, against: excluded) {
            out.append("\(path): wartość spełnia schemat z not")
        }
        if let condition = rules["if"], isValid(instance, against: condition), let then = rules["then"] {
            validate(instance, against: then, at: path, into: &out)
        }

        switch instance {
        case let .object(fields):
            for name in rules["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] where fields[name] == nil {
                out.append("\(path): brak wymaganego pola \(name)")
            }
            let properties = rules["properties"]?.objectValue ?? [:]
            for (name, value) in fields {
                if let property = properties[name] {
                    validate(value, against: property, at: path + "." + name, into: &out)
                } else if rules["additionalProperties"] == .bool(false) {
                    out.append("\(path): pole spoza schematu \(name)")
                } else if let additional = rules["additionalProperties"], case .object = additional {
                    validate(value, against: additional, at: path + "." + name, into: &out)
                }
            }
        case let .array(items):
            if let itemSchema = rules["items"] {
                for (index, item) in items.enumerated() { validate(item, against: itemSchema, at: "\(path)[\(index)]", into: &out) }
            }
            if let minimum = rules["minItems"]?.intValue, items.count < minimum { out.append("\(path): mniej niż \(minimum) elementów") }
            if let maximum = rules["maxItems"]?.intValue, items.count > maximum { out.append("\(path): więcej niż \(maximum) elementów") }
        case let .number(value):
            if case let .number(minimum)? = rules["minimum"], value < minimum { out.append("\(path): \(value) < minimum \(minimum)") }
            if case let .number(maximum)? = rules["maximum"], value > maximum { out.append("\(path): \(value) > maximum \(maximum)") }
            if case let .number(step)? = rules["multipleOf"], !Self.isInteger(value / step) { out.append("\(path): \(value) nie jest wielokrotnością \(step)") }
        case let .string(text):
            let length = text.unicodeScalars.count
            if let minimum = rules["minLength"]?.intValue, length < minimum { out.append("\(path): napis krótszy niż \(minimum)") }
            if let maximum = rules["maxLength"]?.intValue, length > maximum { out.append("\(path): napis dłuższy niż \(maximum)") }
            if let pattern = rules["pattern"]?.stringValue, text.range(of: pattern, options: .regularExpression) == nil {
                out.append("\(path): napis nie pasuje do \(pattern)")
            }
        default:
            break
        }
    }

    private static func matches(_ instance: JSONValue, type: String) -> Bool {
        switch instance {
        case .null: return type == "null"
        case .bool: return type == "boolean"
        case .object: return type == "object"
        case .array: return type == "array"
        case .string: return type == "string"
        case let .number(value): return type == "number" || (type == "integer" && isInteger(value))
        }
    }

    private static func isInteger(_ value: Decimal) -> Bool {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return rounded == value
    }
}
