import Foundation

/// What moves between steps. Media moves by path.
///
/// A `stream` is a list going item by item: every step after it that takes one item
/// runs once per item, until a step that takes a whole list collects it. A nil item is
/// one a branch skipped, kept so lists stay aligned.
indirect enum Value: Sendable {
    case text(String)
    case number(Double)
    case bool(Bool)
    case audio(String)
    case video(String)
    case image(String)
    case file(String)
    case record([(String, Value)])
    case list([Value?])
    case stream([Value?])

    var isStream: Bool {
        if case .stream = self { true } else { false }
    }

    /// The items of a list or a stream, holes included. Anything else is a list of one.
    var items: [Value?] {
        switch self {
        case .list(let l), .stream(let l): l
        default: [self]
        }
    }

    var present: [Value] { items.compactMap { $0 } }

    var string: String? {
        if case .text(let s) = self { s } else { nil }
    }

    /// The file behind a media value.
    var path: String? {
        switch self {
        case .audio(let p), .video(let p), .image(let p), .file(let p): p
        default: nil
        }
    }

    /// Audio, or the audio track of a video.
    var audioPath: String? {
        switch self {
        case .audio(let p), .video(let p): p
        default: nil
        }
    }

    subscript(key: String) -> Value? {
        if case .record(let fields) = self { fields.first { $0.0 == key }?.1 } else { nil }
    }

    /// The value as words, for templates, comparisons, and the terminal.
    var asText: String {
        switch self {
        case .text(let s): return s
        case .number(let n): return Value.format(n)
        case .bool(let b): return b ? "true" : "false"
        case .audio(let p), .video(let p), .image(let p), .file(let p): return (p as NSString).lastPathComponent
        case .list(let l), .stream(let l): return l.compactMap { $0?.asText }.joined(separator: ", ")
        case .record:
            for key in ["name", "label", "emoji", "text"] {
                if let v = self[key] { return v.asText }
            }
            return json(pretty: false)
        }
    }

    var asNumber: Double? {
        switch self {
        case .number(let n): n
        case .bool(let b): b ? 1 : 0
        case .text(let s): Double(s.trimmingCharacters(in: .whitespaces))
        default: Double(asText)
        }
    }

    static func format(_ n: Double) -> String {
        n.whole.map(String.init) ?? String(format: "%.3f", n)
    }

    func json(pretty: Bool = true) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? asText
    }

    /// A stream when any item survived, otherwise nothing.
    static func sparse(_ items: [Value?]) -> Value? {
        items.contains { $0 != nil } ? .stream(items) : nil
    }
}

// `Value` alone would name Optional's own generic parameter.
extension Optional where Wrapped == DesertAntCLI.Value {
    var asText: String { self?.asText ?? "" }
}

/// Media is an object naming its kind, `{"audio": "talk.wav"}`, so a path never reads
/// as text.
extension Value: Encodable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .number(let n):
            var c = encoder.singleValueContainer()
            if let i = n.whole { try c.encode(i) } else if n.isFinite { try c.encode(n) } else { try c.encodeNil() }
        case .bool(let b):
            var c = encoder.singleValueContainer()
            try c.encode(b)
        case .audio(let p), .video(let p), .image(let p), .file(let p):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(p, forKey: Key(kind))
        case .record(let fields):
            var c = encoder.container(keyedBy: Key.self)
            for (k, v) in fields { try c.encode(v, forKey: Key(k)) }
        case .list(let l), .stream(let l):
            var c = encoder.unkeyedContainer()
            for item in l {
                if let item { try c.encode(item) } else { try c.encodeNil() }
            }
        }
    }

    /// The kind of value, as `flow check` and errors name it.
    var kind: String {
        switch self {
        case .text: "text"
        case .number: "number"
        case .bool: "bool"
        case .audio: "audio"
        case .video: "video"
        case .image: "image"
        case .file: "file"
        case .record: "record"
        case .list, .stream: "list"
        }
    }
}
