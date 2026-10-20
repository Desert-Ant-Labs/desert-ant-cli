import Foundation

enum LogicSteps {
    static let all: [StepDef] = [ifElse, merge, list, best, template, join, convert]

    /// Sends each item down `yes` or `no`. A stream splits item by item, with holes on
    /// the side an item did not take, so the two sides stay aligned.
    static let ifElse = StepDef(
        type: "if", summary: "Sends each value down yes or no, by a check on it or on another value.", category: .logic,
        inputs: [Port(id: "value", type: .any), Port(id: "test", type: .any, optional: true)],
        outputs: [Port(id: "yes", type: .any), Port(id: "no", type: .any)],
        defaults: ["op": "equals", "operand": ""],
        noMap: true
    ) { run in
        let name = run.params["op"]?.string ?? "equals"
        guard let op = Condition(rawValue: name) else {
            throw StepError("op is \(list: Condition.allCases.map(\.rawValue), or: true), not \(name).")
        }
        let operand = run.params["operand"]?.string ?? ""
        let value = run.inputs["value"]
        let test = run.inputs["test"] ?? value
        if case .stream(let items) = value {
            let pass: [Bool?] = items.enumerated().map { i, v in
                guard v != nil else { return nil }
                if case .stream(let t) = test { return op.test(i < t.count ? t[i] : nil, operand) }
                return op.test(test, operand)
            }
            var out: [String: Value] = [:]
            out["yes"] = Value.sparse(items.enumerated().map { pass[$0] == true ? $1 : nil })
            out["no"] = Value.sparse(items.enumerated().map { pass[$0] == false ? $1 : nil })
            return out
        }
        guard let value else { return [:] }
        return op.test(test, operand) ? ["yes": value] : ["no": value]
    }

    /// Joins the two sides of an if back together, item by item.
    static let merge = StepDef(
        type: "merge", summary: "Joins the yes and no of an if back together, item by item.", category: .logic,
        inputs: [Port(id: "a", type: .any, optional: true), Port(id: "b", type: .any, optional: true)],
        outputs: [Port(id: "value", type: .any)],
        noMap: true, anyInput: true
    ) { run in
        let a = run.inputs["a"], b = run.inputs["b"]
        func stream(_ v: Value?) -> [Value?]? {
            if case .stream(let l) = v { l } else { nil }
        }
        func item(_ v: Value?, at i: Int) -> Value? {
            guard let l = stream(v) else { return v }
            return i < l.count ? l[i] : nil
        }
        if let n = [stream(a), stream(b)].compactMap({ $0?.count }).max() {
            return ["value": .stream((0..<n).map { item(a, at: $0) ?? item(b, at: $0) })]
        }
        guard let v = a ?? b else { return [:] }
        return ["value": v]
    }

    static let list = StepDef(
        type: "list", summary: "Sorts, slices, or counts a list. To sort by a score, wire the score into the `by` input.", category: .logic,
        inputs: [Port(id: "items", type: .any, list: true), Port(id: "by", type: .any, list: true, optional: true)],
        outputs: [Port(id: "result", type: .any)],
        defaults: ["op": "firstN", "n": 3],
        noMap: true
    ) { run in
        let name = run.params["op"]?.string ?? "firstN"
        guard let op = ListOp(rawValue: name) else {
            throw StepError("op is \(list: ListOp.allCases.map(\.rawValue), or: true), not \(name).")
        }
        let n = run.params["n"]?.int ?? (op.keeps ? 0 : 1)
        return op.run(run.inputs["items"]?.items ?? [], n: n, by: run.inputs["by"]?.items).map { ["result": $0] } ?? [:]
    }

    static let best = StepDef(
        type: "best", summary: "Picks the item with the highest score.", category: .logic,
        inputs: [Port(id: "items", type: .any, list: true), Port(id: "scores", type: .any, list: true)],
        outputs: [Port(id: "best", type: .any), Port(id: "score", type: .any)],
        noMap: true
    ) { run in
        let items = run.inputs["items"]?.items ?? []
        let scores = (run.inputs["scores"]?.items ?? []).map { $0?.asNumber ?? .nan }
        var at = -1
        for (i, v) in scores.enumerated() where i < items.count && items[i] != nil && v.isFinite {
            if at < 0 || v > scores[at] { at = i }
        }
        guard at >= 0, let item = items[at] else { return [:] }
        return ["best": item, "score": .number(scores[at])]
    }

    static let template = StepDef(
        type: "template", summary: "Fills {{a}}, {{b}}, and {{c}} into a text, with {{date}}, {{time}}, and {{b|lang}} for a language's name.",
        category: .logic,
        inputs: ["a", "b", "c"].map { Port(id: $0, type: .any, optional: true) },
        outputs: [Port(id: "text", type: .text)],
        defaults: ["template": "{{a}}"],
        noMap: true
    ) { run in
        let template = run.params["template"]?.string ?? ""
        let streams = ["a", "b", "c"].filter { run.inputs[$0]?.isStream == true }
        func fill(_ i: Int?) -> String? {
            if let i, streams.contains(where: { k in let l = run.inputs[k]!.items; return i >= l.count || l[i] == nil }) { return nil }
            return Placeholders.fill(template) { key in
                guard ["a", "b", "c"].contains(key) else { return nil }
                var v = run.inputs[key]
                if let i, v?.isStream == true { v = v!.items[i] }
                return v.asText
            }
        }
        if streams.isEmpty { return ["text": .text(fill(nil) ?? "")] }
        let n = streams.map { run.inputs[$0]!.items.count }.max() ?? 0
        return Value.sparse((0..<n).map { fill($0).map(Value.text) }).map { ["text": $0] } ?? [:]
    }

    static let join = StepDef(
        type: "join", summary: "Joins a list into one text, a line, a space, a comma, or a blank line apart.", category: .logic,
        inputs: [Port(id: "items", type: .any, list: true)],
        outputs: [Port(id: "text", type: .text)],
        defaults: ["separator": "newline"],
        noMap: true
    ) { run in
        let name = run.params["separator"]?.string ?? "newline"
        guard let separator = ["newline": "\n", "space": " ", "comma": ", ", "paragraph": "\n\n"][name] else {
            throw StepError("separator is newline, space, comma, or paragraph, not \(name).")
        }
        return ["text": .text((run.inputs["items"]?.present ?? []).map(\.asText).joined(separator: separator))]
    }
}

/// The checks an if step makes.
enum Condition: String, CaseIterable, Sendable {
    case equals, notEquals, oneOf, contains, above, below, truthy, falsy, empty

    func test(_ value: Value?, _ operand: String) -> Bool {
        let text = value.asText
        switch self {
        case .equals: return text.lowercased() == operand.lowercased()
        case .notEquals: return text.lowercased() != operand.lowercased()
        case .oneOf:
            return operand.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }.contains(text.lowercased())
        case .contains: return text.lowercased().contains(operand.lowercased())
        case .above: return (value?.asNumber ?? .nan) > (Double(operand) ?? .nan)
        case .below: return (value?.asNumber ?? .nan) < (Double(operand) ?? .nan)
        case .truthy:
            switch value {
            case nil: return false
            case .bool(let b)?: return b
            case .number(let n)?: return n != 0
            case .text(let s)?: return !s.isEmpty && s != "false"
            default: return true
            }
        case .falsy: return !Condition.truthy.test(value, operand)
        case .empty:
            if case .number(let n)? = value, n == 0 { return true }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// What a list step does to a list. The sorts keep the whole list unless given `n`.
enum ListOp: String, CaseIterable, Sendable {
    case desc, asc, most, firstN, lastN, item, count, unique, sort, reverse, compact

    var keeps: Bool { [.desc, .asc, .sort].contains(self) }

    func run(_ list: [Value?], n: Int, by: [Value?]?) -> Value? {
        let present = list.compactMap { $0 }
        let n = max(0, n)
        let keep = { (l: [Value]) in n > 0 ? Array(l.prefix(n)) : l }
        switch self {
        case .desc: return .list(keep(sorted(list, by: by, ascending: false)))
        case .asc, .sort: return .list(keep(sorted(list, by: by, ascending: true)))
        case .most:
            var counts: [String: (value: Value, count: Int, first: Int)] = [:]
            for (i, v) in present.enumerated() { counts[v.asText, default: (v, 0, i)].count += 1 }
            return .list(counts.values.sorted { ($1.count, $0.first) < ($0.count, $1.first) }.prefix(n).map(\.value))
        case .firstN: return .list(Array(present.prefix(n)))
        case .lastN: return .list(Array(present.suffix(n)))
        case .item: return n >= 1 && n <= present.count ? present[n - 1] : nil
        case .count: return .number(Double(present.count))
        case .unique:
            var seen = Set<String>()
            return .list(present.filter { seen.insert($0.asText).inserted })
        case .reverse: return .list(present.reversed())
        case .compact: return .list(present.filter { !$0.asText.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }

    private func sorted(_ list: [Value?], by: [Value?]?, ascending: Bool) -> [Value] {
        let pairs = list.enumerated().compactMap { i, v -> (Value, Value?)? in
            guard let v else { return nil }
            return (v, by.map { i < $0.count ? $0[i] : nil } ?? v)
        }
        // A stable sort: equal keys keep their order.
        return pairs.enumerated().sorted { a, b in
            let order = compare(a.element.1, b.element.1)
            if order == 0 { return a.offset < b.offset }
            return ascending ? order < 0 : order > 0
        }.map(\.element.0)
    }
}

/// Numbers by value, everything else by its words.
func compare(_ a: Value?, _ b: Value?) -> Int {
    if let x = a?.asNumber, let y = b?.asNumber, x.isFinite, y.isFinite { return x < y ? -1 : x > y ? 1 : 0 }
    switch a.asText.localizedStandardCompare(b.asText) {
    case .orderedAscending: return -1
    case .orderedDescending: return 1
    case .orderedSame: return 0
    }
}

/// The `{{...}}` placeholders that templates and file names fill in. A date reads
/// 2026-10-14 and a time 14.05.30, so text made from a pattern also makes a good file
/// name. `{{b|lang}}` gives a language code's English name.
enum Placeholders {
    static func stamp(_ part: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = part == "time" ? "HH.mm.ss" : "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// `pattern` with `{{date}}` and `{{time}}` from `moment`, asked for only when the
    /// pattern uses them, and every other placeholder from `value`. A placeholder
    /// `value` does not know stays as written.
    static func fill(_ pattern: String, at moment: () -> Date = { Date() }, _ value: (String) -> String?) -> String {
        var date: Date?
        return pattern.replacing(#/\{\{\s*(\w+)(\|lang)?\s*\}\}/#) { m in
            let key = String(m.output.1)
            if key == "date" || key == "time" {
                if date == nil { date = moment() }
                return stamp(key, date!)
            }
            guard let text = value(key) else { return String(m.output.0) }
            return m.output.2 != nil ? languageName(text) : text
        }
    }

    /// Placeholders numbered by kind, the same data always getting the same one.
    struct Numbering {
        private var tags: [String: String] = [:]
        private var counts: [String: Int] = [:]

        mutating func tag(_ label: String, _ original: String) -> String {
            let key = "\(label):\(original.lowercased())"
            if let known = tags[key] { return known }
            counts[label, default: 0] += 1
            let tag = "[\(label)_\(counts[label]!)]"
            tags[key] = tag
            return tag
        }
    }

    /// "fr" as "French".
    static func languageName(_ code: String) -> String {
        guard !code.isEmpty else { return "Unknown" }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }
}

/// The formats the convert step writes, by what they hold.
enum FileFormat: String, CaseIterable, Sendable {
    case jpeg, png, heic, tiff, m4a, wav, aiff, caf, txt, md, csv, json

    enum Group: String, Sendable {
        case photo, audio, text, data

        var noun: String {
            switch self {
            case .photo: "a photo"
            case .audio: "a recording"
            case .text: "text"
            case .data: "a table"
            }
        }
    }

    var ext: String { self == .jpeg ? "jpg" : rawValue }

    var group: Group {
        switch self {
        case .jpeg, .png, .heic, .tiff: .photo
        case .m4a, .wav, .aiff, .caf: .audio
        case .txt, .md: .text
        case .csv, .json: .data
        }
    }

    /// The formats this machine writes for a group.
    static func of(_ group: Group) -> [FileFormat] {
        allCases.filter { f in
            guard f.group == group else { return false }
            #if canImport(ImageIO)
            return true
            #else
            return f != .heic
            #endif
        }
    }

    static func group(of value: Value) -> Group? {
        switch value {
        case .image: .photo
        case .audio, .video: .audio
        case .text, .number, .bool: .text
        case .record: .data
        case .list(let l), .stream(let l):
            l.lazy.compactMap { $0 }.first.flatMap { item in
                if case .record = item { return .data }
                return group(of: item)
            }
        case .file: nil
        }
    }
}

extension LogicSteps {
    static let convert = StepDef(
        type: "convert", summary: "Saves a photo as JPEG, PNG, TIFF, or HEIC, audio as M4A, WAV, AIFF, or CAF, text as .txt or .md, and a table as CSV or JSON.",
        category: .logic,
        inputs: [Port(id: "value", type: .any)],
        outputs: [Port(id: "file", type: .any)],
        defaults: ["to": ""]
    ) { run in
        guard let value = run.inputs["value"] else { return [:] }
        let name = run.params["to"]?.string ?? ""
        let chosen: FileFormat?
        if name.isEmpty {
            chosen = nil
        } else {
            guard let f = FileFormat(rawValue: name.lowercased() == "jpg" ? "jpeg" : name.lowercased()) else {
                throw StepError("to is \(list: FileFormat.allCases.map(\.rawValue), or: true), not \(name).")
            }
            chosen = f
        }
        guard let group = FileFormat.group(of: value) else {
            throw StepError("convert takes photos, audio, text, or a table, and got \(value.kind).")
        }
        let format = chosen ?? FileFormat.of(group)[0]
        guard FileFormat.of(group).contains(format) else {
            throw StepError("\(group.noun) converts to \(list: FileFormat.of(group).map(\.rawValue), or: true), not \(format.rawValue).")
        }
        if group != .data, case .list(let items) = value {
            var files: [Value?] = []
            for item in items { files.append(try await item.asyncMap { try await write($0, format, run.context) }) }
            return ["file": .list(files)]
        }
        return ["file": try await write(value, format, run.context)]
    }

    private static func write(_ value: Value, _ format: FileFormat, _ context: StepContext) async throws -> Value {
        func stem(_ fallback: String) -> String {
            guard let path = value.path else { return fallback }
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        switch value {
        case .image(let path):
            let out = try context.scratch(stem("photo") + "." + format.ext)
            try Pictures.write(Pictures.pixels(path), to: out.path)
            return .image(out.path)
        case .audio(let path), .video(let path):
            let out = try context.scratch(stem("recording") + "." + format.ext)
            try await Media.convertAudio(path, to: out.path)
            return .audio(out.path)
        case .record, .list, .stream:
            let text = format == .csv ? CSV.text(value.present.isEmpty ? [value] : value.present) : value.json() + "\n"
            let out = try context.scratch("table." + format.ext)
            try Data(text.utf8).write(to: out)
            return .file(out.path)
        default:
            let text = value.asText
            let first = text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(40)) } ?? ""
            let name = first.replacing(#/[^\w -]+/#, with: "").trimmingCharacters(in: .whitespaces)
            let out = try context.scratch((name.isEmpty ? "text" : name) + "." + format.ext)
            try Data(text.utf8).write(to: out)
            return .file(out.path)
        }
    }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
