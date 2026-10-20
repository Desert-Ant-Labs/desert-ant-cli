import Foundation

enum LogicSteps {
    static let all: [StepDef] = [template, join]

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
