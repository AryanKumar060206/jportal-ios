import Foundation

/**
 * a json tree, read leniently the way the portal needs: numbers arrive as
 * strings and strings as numbers, nulls stand in for missing fields, and a
 * field that won't read falls back to its default instead of failing the
 * whole response. numbers keep their literal text so long ids survive.
 */
public enum JSON: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public static func parse(_ data: Data) throws -> JSON {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSON(foundation: any)
    }

    public static func parse(_ text: String) throws -> JSON {
        try parse(Data(text.utf8))
    }

    init(foundation any: Any) {
        switch any {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.stringValue)
            }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map(JSON.init(foundation:)))
        case let d as [String: Any]: self = .object(d.mapValues(JSON.init(foundation:)))
        default: self = .null
        }
    }

    // reading

    public subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    public var isNull: Bool { if case .null = self { return true } else { return false } }

    public var object: [String: JSON]? { if case .object(let o) = self { return o } else { return nil } }

    /// strings as is, numbers and bools as their text
    public var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    public var double: Double? {
        switch self {
        case .number(let n): return Double(n)
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var int: Int? {
        if let d = double, d.isFinite { return Int(d) }
        return nil
    }

    public var array: [JSON] { if case .array(let a) = self { return a } else { return [] } }

    public func str(_ key: String, _ fallback: String = "") -> String { self[key].string ?? fallback }
    public func dbl(_ key: String, _ fallback: Double = 0) -> Double { self[key].double ?? fallback }
    public func optDbl(_ key: String) -> Double? { self[key].double }
    public func int(_ key: String, _ fallback: Int = 0) -> Int { self[key].int ?? fallback }
    public func optInt64(_ key: String) -> Int64? { self[key].double.map { Int64($0) } }
    public func optStr(_ key: String) -> String? { self[key].string }

    // writing

    /// compact json text. object keys come out sorted so the same value always encodes the same
    public var serialized: String {
        var out = ""
        write(&out)
        return out
    }

    func write(_ out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): JSON.writeString(s, &out)
        case .array(let a):
            out += "["
            for (i, x) in a.enumerated() {
                if i > 0 { out += "," }
                x.write(&out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, k) in o.keys.sorted().enumerated() {
                if i > 0 { out += "," }
                JSON.writeString(k, &out)
                out += ":"
                o[k]!.write(&out)
            }
            out += "}"
        }
    }

    static func writeString(_ s: String, _ out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where u.value < 0x20: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b }))
    }
    public init(nilLiteral: ()) { self = .null }
}

/**
 * a request body whose keys go out in the order they were written, like the
 * portal's own bundle sends them. values are plain json.
 */
public struct Payload: Sendable {
    public private(set) var pairs: [(String, JSON)] = []

    public init() {}

    public init(_ pairs: KeyValuePairs<String, JSON>) {
        self.pairs = pairs.map { ($0.key, $0.value) }
    }

    public mutating func put(_ key: String, _ value: JSON) { pairs.append((key, value)) }
    public mutating func put(_ key: String, _ value: String) { pairs.append((key, .string(value))) }

    public var serialized: String {
        var out = "{"
        for (i, (k, v)) in pairs.enumerated() {
            if i > 0 { out += "," }
            JSON.writeString(k, &out)
            out += ":"
            v.write(&out)
        }
        return out + "}"
    }
}
