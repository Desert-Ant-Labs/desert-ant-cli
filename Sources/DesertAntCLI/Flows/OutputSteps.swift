import Foundation

enum OutputSteps {
    static let all: [StepDef] = [view, table, folder]

    /// A file the flow made along the way is saved beside the input, so the path it
    /// prints still holds the file after the run.
    static let view = StepDef(
        type: "view", summary: "Prints the value, and puts it in the --json outputs.", category: .output,
        inputs: [Port(id: "value", type: .any)],
        noMap: true
    ) { run in
        guard let value = run.inputs["value"] else { return [:] }
        let kept = try FolderWriter.keep(value, run.context.run)
        run.context.run.show(run.context.step.id, kept, text: lines(kept))
        return [:]
    }

    static let folder = StepDef(
        type: "folder", summary: "Saves the value as files, beside the first input or in --output-dir, in a subfolder if `folder` names one.",
        category: .output,
        inputs: [Port(id: "value", type: .any, list: true), Port(id: "a", type: .any, optional: true)],
        defaults: ["folder": "", "name": "result", "auto": true],
        noMap: true
    ) { run in
        guard run.params["auto"]?.bool ?? true, let value = run.inputs["value"] else { return [:] }
        let pattern = run.params["name"]?.string ?? "result"
        if pattern.contains(#/\{\{\s*a\s*\}\}/#), run.inputs["a"] == nil { return [:] }
        let name = FolderWriter.fileName(pattern, a: run.inputs["a"]?.present.first, input: run.context.run.firstInput)
        let folder = FolderWriter.resolve(run.params["folder"]?.string ?? "", root: run.context.run.outputRoot)
        let flowRun = run.context.run
        for path in try FolderWriter.write(value, to: folder, name: name, force: flowRun.options.force, inputs: flowRun.binding?.paths ?? []) {
            run.context.run.wrote(path)
        }
        return [:]
    }

    /// Lines up lists item by item, a column each.
    static let table = StepDef(
        type: "table", summary: "Prints lists side by side, a row per item and a column per input.", category: .output,
        inputs: ["a", "b", "c"].map { Port(id: $0, type: .any, optional: true) },
        defaults: ["columns": ""],
        noMap: true
    ) { run in
        let keys = ["a", "b", "c"].filter { run.inputs[$0] != nil }
        guard keys.contains(where: { !run.inputs[$0]!.present.isEmpty }) else {
            run.context.note = "nothing to show"
            return [:]
        }
        let given = (run.params["columns"]?.string ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var headers: [String]
        var rows: [[Value?]]
        let only = keys.count == 1 ? run.inputs[keys[0]]!.items : []
        if !only.isEmpty, only.allSatisfy({ if case .record? = $0 { true } else { $0 == nil } }) {
            // One list of records: a column per field.
            headers = []
            for case .record(let fields)? in only {
                for (k, _) in fields where !headers.contains(k) { headers.append(k) }
            }
            rows = only.compactMap { $0 }.map { r in headers.map { r[$0] } }
        } else {
            headers = keys
            let columns = keys.map { run.inputs[$0]!.items }
            let count = columns.map(\.count).max() ?? 0
            rows = (0..<count).map { i in columns.map { i < $0.count ? $0[i] : nil } }
        }
        for (i, label) in given.enumerated() where i < headers.count && !label.isEmpty { headers[i] = label }
        let value = Value.list(rows.map { row in
            .record(zip(headers, row).map { ($0, $1 ?? .text("")) })
        })
        run.context.run.show(run.context.step.id, value, text: align([headers] + rows.map { $0.map { cell($0) } }))
        return [:]
    }

    /// A value as terminal lines: a list one item per line, a record as JSON.
    static func lines(_ value: Value) -> [String] {
        switch value {
        case .list, .stream: return value.items.map { cell($0) }
        case .record: return value.json().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        case .audio(let p), .video(let p), .image(let p), .file(let p): return [p]
        default:
            return value.asText.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
    }

    static func cell(_ value: Value?) -> String {
        guard let value else { return "" }
        if case .record = value { return value.json(pretty: false) }
        if let path = value.path { return path }
        return value.asText.replacingOccurrences(of: "\n", with: " ")
    }

    /// Columns padded to their widest cell, two spaces apart.
    static func align(_ rows: [[String]]) -> [String] {
        let widths = (0..<(rows.map(\.count).max() ?? 0)).map { c in rows.map { c < $0.count ? displayWidth($0[c]) : 0 }.max() ?? 0 }
        return rows.map { row in
            row.enumerated().map { c, text in
                c == row.count - 1 ? text : text + String(repeating: " ", count: widths[c] - displayWidth(text))
            }.joined(separator: "  ").replacing(#/\s+$/#, with: "")
        }
    }
}

/// Writes values as files: text as .txt, .md, .srt, or .vtt by what it holds, a table
/// as .csv, media as its own files, anything else as .json. Nothing replaces a file
/// unless --force says to: a taken name steps aside to `name-2.txt`.
enum FolderWriter {
    /// `inputs` are never replaced, even with `force`.
    static func write(_ value: Value, to folder: URL, name: String, force: Bool, inputs: [String] = []) throws -> [String] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = name.isEmpty ? "result" : name
        var written: [String] = []
        func place(_ file: String) throws -> String {
            let wanted = folder.appendingPathComponent(file).path
            let path = try Destination.resolve(requested: nil, default: wanted, input: "", force: force)
            let taken = written.contains(path) || inputs.contains { canonical($0) == canonical(path) }
            return taken ? Destination.firstFreeName(path) : path
        }
        func put(_ text: String, _ file: String) throws {
            let path = try place(file)
            try Data(text.utf8).write(to: URL(fileURLWithPath: path))
            written.append(path)
        }
        func copy(_ source: String) throws {
            let wanted = folder.appendingPathComponent((source as NSString).lastPathComponent).path
            if canonical(wanted) == canonical(source) { return }
            let path = try place((source as NSString).lastPathComponent)
            if force { try? FileManager.default.removeItem(atPath: path) }
            try FileManager.default.copyItem(atPath: source, toPath: path)
            written.append(path)
        }
        let items = value.present
        switch value {
        case .audio(let p), .video(let p), .image(let p), .file(let p): try copy(p)
        case .text(let t): try put(t, base + "." + textExtension(t))
        case .number, .bool: try put(value.asText, base + ".txt")
        case .list, .stream:
            if !items.isEmpty, items.allSatisfy({ $0.path != nil }) {
                for item in items { try copy(item.path!) }
            } else if !items.isEmpty, items.allSatisfy({ if case .record = $0 { true } else { false } }) {
                try put(CSV.text(items), base + ".csv")
            } else if items.allSatisfy({ $0.string != nil }) {
                try put(items.map(\.asText).joined(separator: "\n"), base + ".txt")
            } else {
                try put(value.json(), base + ".json")
            }
        case .record: try put(value.json(), base + ".json")
        }
        return written
    }

    /// Media in the run's scratch folder, copied beside the input or into --output-dir
    /// under its own name. Anything else as it was.
    static func keep(_ value: Value, _ run: FlowRun) throws -> Value {
        func one(_ v: Value?) throws -> Value? {
            guard let v, let path = v.path, path.hasPrefix(run.temp.path) else { return v }
            guard let saved = try write(v, to: run.outputRoot, name: "", force: run.options.force, inputs: run.binding?.paths ?? []).first else { return v }
            run.wrote(saved)
            switch v {
            case .audio: return .audio(saved)
            case .video: return .video(saved)
            case .image: return .image(saved)
            default: return .file(saved)
            }
        }
        switch value {
        case .list(let l): return .list(try l.map(one))
        case .stream(let l): return .stream(try l.map(one))
        default: return try one(value) ?? value
        }
    }

    /// The folder a setting names: a path as written, or a bare name inside `root`.
    static func resolve(_ setting: String, root: URL) -> URL {
        let trimmed = setting.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return root }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        return root.appendingPathComponent(trimmed)
    }

    /// A file name from a pattern: `{{a}}` from the value given, `{{name}}` the first
    /// input's name without its extension, the date and time, and no slashes or colons.
    static func fileName(_ pattern: String, a: Value?, input: String?) -> String {
        Placeholders.fill(pattern) { key in
            switch key {
            case "a": a.asText
            case "name": input.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "result"
            default: nil
            }
        }
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Captions keep their format, and text with Markdown in it is .md.
    static func textExtension(_ text: String) -> String {
        let head = text.drop { $0.isWhitespace }
        if head.hasPrefix("WEBVTT") { return "vtt" }
        if head.contains(#/^\d+\n\d\d:\d\d:\d\d,\d{3} --> /#) { return "srt" }
        if text.contains(#/(?m)^(#{1,6} |\s*[-*] |\s*\d+\. |> )|\*\*[^*]+\*\*/#) { return "md" }
        return "txt"
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// Records as a spreadsheet: a row each, their fields as columns in the order first
/// seen.
enum CSV {
    static func text(_ rows: [Value]) -> String {
        var keys: [String] = []
        for case .record(let fields) in rows {
            for (key, _) in fields where !keys.contains(key) { keys.append(key) }
        }
        func escaped(_ s: String) -> String {
            s.contains(where: { ",\"\n\r".contains($0) }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
        }
        func cell(_ v: Value?) -> String {
            if case .number(let n)? = v { return n.whole.map(String.init) ?? "\(n)" }
            if let path = v?.path { return path }
            return v.asText
        }
        let lines = rows.map { row in keys.map { escaped(cell(row[$0])) }.joined(separator: ",") }
        return ([keys.map(escaped).joined(separator: ",")] + lines).joined(separator: "\n") + "\n"
    }
}
