import Foundation
import Yams

/// A step's settings as plain data, read from a flow file's `with`.
enum Param: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Param])
    case object([String: Param])

    /// Numbers read back the same on every machine, never as "0,5".
    var string: String? {
        switch self {
        case .string(let s): s
        case .number(let n): n.whole.map(String.init) ?? String(n)
        case .bool(let b): b ? "true" : "false"
        default: nil
        }
    }

    var number: Double? {
        switch self {
        case .number(let n): n
        case .string(let s): Double(s.trimmingCharacters(in: .whitespaces))
        case .bool(let b): b ? 1 : 0
        default: nil
        }
    }

    /// Held within a range an `Int` can take, so a hand-edited 1e300 never stops a run.
    var int: Int? {
        guard let n = number, n.isFinite else { return nil }
        return Int(min(max(n, -1e15), 1e15))
    }

    var bool: Bool? {
        switch self {
        case .bool(let b): b
        case .number(let n): n != 0
        case .string(let s): ["true", "yes", "1"].contains(s.lowercased())
        default: nil
        }
    }

    var array: [Param]? {
        if case .array(let a) = self { a } else { nil }
    }

    var strings: [String] {
        array?.compactMap(\.string) ?? []
    }

    /// A value from YAML: a scalar by its resolved tag, a sequence, or a mapping with
    /// text keys.
    init(_ node: Yams.Node) {
        switch node {
        case .scalar:
            switch node.any {
            case let b as Bool: self = .bool(b)
            case let i as Int: self = .number(Double(i))
            case let d as Double: self = .number(d)
            case is NSNull: self = .null
            default: self = .string(node.string ?? "")
            }
        case .sequence(let s): self = .array(s.map(Param.init))
        case .mapping(let m):
            var object: [String: Param] = [:]
            for (key, value) in m { object[key.string ?? ""] = Param(value) }
            self = .object(object)
        case .alias: self = .null
        }
    }

    /// One value typed on the command line, as `--set clips.count=3`: a number or a flag
    /// when it reads as one, otherwise text.
    static func parse(_ text: String) -> Param {
        guard let node = try? Yams.compose(yaml: text), case .scalar = node else { return .string(text) }
        let param = Param(node)
        if case .null = param { return .string(text) }
        return param
    }
}

typealias Params = [String: Param]

extension Param: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension Double {
    /// The number as an `Int` when it has no fraction and fits.
    var whole: Int? {
        guard isFinite, rounded() == self, abs(self) < 1e15 else { return nil }
        return Int(self)
    }
}
