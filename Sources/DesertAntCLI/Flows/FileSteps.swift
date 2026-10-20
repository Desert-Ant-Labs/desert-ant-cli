import Foundation

/// Steps that copy, move, or rename a person's own files. They change nothing without
/// `--apply`; until then they print what they would do.
enum FileSteps {
    static let all: [StepDef] = [rename, copy]

    static let rename = StepDef(
        type: "rename", summary: "Renames files from a pattern, as {{date}}-{{n}}, in place or as copies in a folder.",
        category: .output,
        inputs: [Port(id: "files", type: .any, list: true), Port(id: "a", type: .any, list: true, optional: true)],
        outputs: [Port(id: "names", type: .text)],
        defaults: ["pattern": "{{date}}-{{n}}", "mode": "copy", "folder": "", "auto": false],
        noMap: true
    ) { run in
        let paths = (run.inputs["files"]?.present ?? []).compactMap(\.path)
        guard !paths.isEmpty else { return [:] }
        let action: FileOps.Action
        switch run.params["mode"]?.string ?? "copy" {
        case "copy": action = .copy
        case "rename": action = .move
        case let other: throw StepError("mode is copy or rename, not \(other).")
        }
        let names = FileOps.names(for: paths, pattern: run.params["pattern"]?.string ?? "{{name}}", a: run.inputs["a"]?.items ?? [])
        let folder = run.params["folder"]?.string ?? ""
        let targets = zip(paths, names).map { path, name -> String in
            let dir = action == .move || folder.isEmpty
                ? URL(fileURLWithPath: path).deletingLastPathComponent()
                : FolderWriter.resolve(folder, root: run.context.run.outputRoot)
            return dir.appendingPathComponent(name).path
        }
        try FileOps.carry(paths, to: targets, action, run.context)
        return ["names": .list(names.map { .text($0) })]
    }

    static let copy = StepDef(
        type: "copy", summary: "Copies or moves files into a folder, sorted into subfolders by a pattern such as {{a}}.",
        category: .output,
        inputs: [Port(id: "files", type: .any, list: true), Port(id: "a", type: .any, list: true, optional: true)],
        defaults: ["mode": "copy", "subfolder": "", "folder": "", "auto": false],
        noMap: true
    ) { run in
        let items = run.inputs["files"]?.items ?? []
        let a = run.inputs["a"]?.items ?? []
        var paths: [String] = [], subs: [Value?] = []
        for (i, item) in items.enumerated() {
            guard let path = item?.path else { continue }
            paths.append(path)
            subs.append(i < a.count ? a[i] : nil)
        }
        guard !paths.isEmpty else { return [:] }
        let mode = run.params["mode"]?.string ?? "copy"
        guard let action = FileOps.Action(rawValue: mode) else { throw StepError("mode is copy or move, not \(mode).") }
        let folder = FolderWriter.resolve(run.params["folder"]?.string ?? "", root: run.context.run.outputRoot)
        let pattern = run.params["subfolder"]?.string ?? ""
        let targets = paths.enumerated().map { i, path -> String in
            let sub = FileOps.fill(pattern, path: path, a: subs[i])
            return (sub.isEmpty ? folder : folder.appendingPathComponent(sub)).appendingPathComponent((path as NSString).lastPathComponent).path
        }
        try FileOps.carry(paths, to: targets, action, run.context)
        return [:]
    }
}

/// Naming, copying, and moving files.
enum FileOps {
    enum Action: String, Sendable {
        case copy, move
    }

    /// With `--apply`, copies or moves the files and lists the new paths; without it,
    /// shows what it would do and changes nothing.
    static func carry(_ paths: [String], to targets: [String], _ action: Action, _ context: StepContext) throws {
        let run = context.run
        let verb = action == .copy ? "copy" : context.step.type == "rename" ? "rename" : "move"
        guard run.options.apply else {
            let pairs = zip(paths, targets).filter { canonical($0) != canonical($1) }
            run.show(context.step.id, .list(pairs.map { .record([("action", .text(verb)), ("from", .file($0)), ("to", .file($1))]) }),
                     text: pairs.map { "would \(verb) \($0) to \($1)" })
            context.note = "pass --apply to \(verb) \(pairs.count == 1 ? "this file" : "these \(pairs.count) files")"
            return
        }
        for path in try apply(paths, to: targets, action) { run.wrote(path) }
    }

    /// A new name for every file, from a pattern. `{{name}}` is the old name, `{{n}}`
    /// the number padded to the size of the batch, `{{date}}` and `{{time}}` when the
    /// file was made, and `{{a}}` the value given for that file. The extension stays,
    /// and a slash makes a folder.
    static func names(for paths: [String], pattern: String, a: [Value?] = []) -> [String] {
        let width = String(paths.count).count
        var taken = Set<String>()
        return paths.enumerated().map { i, path in
            var stem = fill(pattern, path: path, number: i + 1, width: width, a: i < a.count ? a[i] : nil)
            if stem.isEmpty { stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
            let ext = (path as NSString).pathExtension.isEmpty ? "" : "." + (path as NSString).pathExtension.lowercased()
            var name = stem + ext, k = 2
            while !taken.insert(name.lowercased()).inserted {
                name = "\(stem)-\(k)\(ext)"
                k += 1
            }
            return name
        }
    }

    /// The pattern filled in for one file, each part of a path cleaned for a file name.
    static func fill(_ pattern: String, path: String, number: Int = 1, width: Int = 1, a: Value? = nil) -> String {
        let filled = Placeholders.fill(pattern, at: { date(of: path) }) { key in
            switch key {
            case "name": URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            case "n": String(repeating: "0", count: max(0, width - String(number).count)) + String(number)
            case "a": (a?.present.first).asText
            default: nil
            }
        }
        return filled.split(separator: "/").map(clean).filter { !$0.isEmpty }.joined(separator: "/")
    }

    /// When a file was made: a photo's capture date, else the file's own dates.
    static func date(of path: String) -> Date {
        if let taken = Pictures.captureDate(path) { return Date(timeIntervalSince1970: taken) }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.creationDate] as? Date ?? attributes?[.modificationDate] as? Date ?? Date()
    }

    /// No colons, control characters, or leading dots.
    private static func clean(_ part: Substring) -> String {
        let bad = CharacterSet(charactersIn: ":\\").union(.controlCharacters).union(.newlines)
        return String(String.UnicodeScalarView(part.unicodeScalars.map { bad.contains($0) ? "-" : $0 }))
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// Copies or moves each file to its target. A different file already there stays,
    /// and the new one takes the next free name. A copy that is already there is not
    /// made again.
    static func apply(_ paths: [String], to targets: [String], _ action: Action) throws -> [String] {
        let fm = FileManager.default
        var done: [String] = []
        for (from, planned) in zip(paths, targets) {
            if canonical(from) == canonical(planned) { continue }
            try fm.createDirectory(atPath: (planned as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            var to = planned
            if fm.fileExists(atPath: to) {
                if action == .copy, fm.contentsEqual(atPath: from, andPath: to) { continue }
                if action == .move, canonical(from).lowercased() == canonical(to).lowercased() {
                    // Only the case changed, on a disk that ignores case: go through a temporary name.
                    let temporary = (from as NSString).deletingLastPathComponent + "/.\(UUID().uuidString)"
                    try fm.moveItem(atPath: from, toPath: temporary)
                    try fm.moveItem(atPath: temporary, toPath: to)
                    done.append(to)
                    continue
                }
                to = Destination.firstFreeName(planned)
            }
            do {
                if action == .copy { try fm.copyItem(atPath: from, toPath: to) } else { try fm.moveItem(atPath: from, toPath: to) }
            } catch {
                throw StepError("could not \(action.rawValue) \(from) to \(to): \(error.localizedDescription)")
            }
            done.append(to)
        }
        return done
    }

    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
