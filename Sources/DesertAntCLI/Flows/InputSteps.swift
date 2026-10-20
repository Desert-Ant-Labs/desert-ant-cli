import Foundation

/// The pieces a text splits into.
enum Segment {
    case lines, sentences, paragraphs

    func split(_ text: String) -> [String] {
        let trimmed = { (s: Substring) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let pieces: [String]
        switch self {
        case .lines:
            pieces = text.split(whereSeparator: \.isNewline).map(trimmed)
        case .paragraphs:
            pieces = text.split(separator: #/\n\s*\n/#).map(trimmed)
        case .sentences:
            pieces = Self.sentences(text).map(trimmed)
        }
        return pieces.filter { !$0.isEmpty }
    }

    /// The same rule on every platform, so a flow splits a text the same way on macOS
    /// and Linux: a sentence ends at a period, question mark, or exclamation mark, with
    /// any closing quotes, before a space and a capital or a digit, or a line break.
    static func sentences(_ text: String) -> [Substring] {
        var out: [Substring] = []
        var start = text.startIndex
        for match in text.matches(of: #/[.!?]+["'”’)]*(\s+(?=[\p{Lu}\d"'“‘(])|\s*\n+)/#) {
            out.append(text[start..<match.range.lowerBound] + text[match.range.lowerBound..<match.range.upperBound])
            start = match.range.upperBound
        }
        if start < text.endIndex { out.append(text[start...]) }
        return out
    }
}

enum InputSteps {
    static let all: [StepDef] = [text, textlist, audio, image, photos, files, watch]

    /// The file names a text input reads from a folder.
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "text"]

    /// The files the command line's paths are filtered by when a folder is given,
    /// or nil to take every file.
    static func extensions(for type: String) -> Set<String>? {
        switch type {
        case "audio": RunInputKind.file.extensions
        case "image", "photos": RunInputKind.image.extensions
        case "text", "textlist": textExtensions
        default: nil
        }
    }

    /// Whether the step takes every path in one run. The others run once per path.
    static func takesList(_ type: String) -> Bool {
        ["photos", "files", "watch", "textlist"].contains(type)
    }

    static func split(_ text: String) -> [String: Value] {
        [
            "text": .text(text),
            "lines": .list(Segment.lines.split(text).map { .text($0) }),
            "sentences": .list(Segment.sentences.split(text).map { .text($0) }),
            "paragraphs": .list(Segment.paragraphs.split(text).map { .text($0) }),
        ]
    }

    static let text = StepDef(
        type: "text", summary: "Text from the command line, stdin, a file, or the flow itself.", category: .input,
        outputs: [Port(id: "text", type: .text), Port(id: "lines", type: .text, each: true),
                  Port(id: "sentences", type: .text, each: true), Port(id: "paragraphs", type: .text, each: true)],
        defaults: ["text": ""]
    ) { run in
        let text: String
        switch run.context.bound {
        case .text(let t)?: text = t
        case .paths(let p)?: text = try p.map(read).joined(separator: "\n\n")
        case nil: text = run.params["text"]?.string ?? ""
        }
        return split(text)
    }

    static let textlist = StepDef(
        type: "textlist", summary: "Several texts, one item each: lines on stdin, files, or a list in the flow.", category: .input,
        outputs: [Port(id: "items", type: .any, each: true)],
        defaults: ["items": .array([])]
    ) { run in
        let items: [String]
        switch run.context.bound {
        case .text(let t)?: items = Segment.lines.split(t)
        case .paths(let p)?: items = try p.map(read)
        case nil: items = run.params["items"]?.strings ?? []
        }
        let kept = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return kept.isEmpty ? [:] : ["items": .list(kept.map { .text($0) })]
    }

    static let audio = StepDef(
        type: "audio", summary: "An audio or video file.", category: .input,
        outputs: [Port(id: "audio", type: .audio)],
        defaults: ["file": .null]
    ) { run in
        guard let path = run.context.bound?.paths.first ?? given(run.params["file"]) else { return [:] }
        try exists(path)
        return ["audio": RunInputKind.isVideo(path) ? .video(path) : .audio(path)]
    }

    static let image = StepDef(
        type: "image", summary: "A photo.", category: .input,
        outputs: [Port(id: "image", type: .image)],
        defaults: ["file": .null]
    ) { run in
        guard let path = run.context.bound?.paths.first ?? given(run.params["file"]) else { return [:] }
        try exists(path)
        return ["image": .image(path)]
    }

    static let photos = StepDef(
        type: "photos", summary: "Several photos at once, as a list.", category: .input,
        outputs: [Port(id: "photos", type: .image, each: true)],
        defaults: ["files": .array([])]
    ) { run in
        let paths = run.context.bound?.paths ?? (run.params["files"]?.strings ?? []).compactMap { given(.string($0)) }
        for path in paths { try exists(path) }
        return paths.isEmpty ? [:] : ["photos": .list(paths.map { .image($0) })]
    }

    /// Photos come out as photos, so Eye and Moderator can read them, and any other
    /// file as itself.
    static let files = StepDef(
        type: "files", summary: "Files, or every file in some folders, as a list.", category: .input,
        outputs: [Port(id: "files", type: .any, each: true)],
        defaults: ["files": .array([]), "folders": .array([])]
    ) { run in
        let paths = try run.context.bound?.paths ?? listed(run.params)
        for path in paths { try exists(path) }
        return paths.isEmpty ? [:] : ["files": .list(paths.map(asFile))]
    }

    /// Runs as a files input: the paths on the command line, or the folder it watches.
    static let watch = StepDef(
        type: "watch", summary: "The files in a folder, as photos, recordings, texts, and files.", category: .input,
        outputs: [Port(id: "files", type: .any, each: true), Port(id: "photos", type: .image, each: true),
                  Port(id: "audio", type: .audio, each: true), Port(id: "text", type: .text, each: true)],
        defaults: ["folder": "", "files": .array([])]
    ) { run in
        var paths = try run.context.bound?.paths ?? listed(run.params)
        if paths.isEmpty, let folder = given(run.params["folder"]) { paths = try contents(of: folder) }
        guard !paths.isEmpty else { return [:] }
        var photos: [Value?] = [], audio: [Value?] = [], texts: [Value?] = []
        for path in paths {
            let ext = (path as NSString).pathExtension.lowercased()
            if RunInputKind.image.extensions.contains(ext) {
                photos.append(.image(path))
            } else if RunInputKind.file.extensions.contains(ext) {
                audio.append(RunInputKind.isVideo(path) ? .video(path) : .audio(path))
            } else if textExtensions.contains(ext), let t = try? read(path) {
                texts.append(.text(t))
            }
        }
        var out: [String: Value] = ["files": .list(paths.map(asFile))]
        if !photos.isEmpty { out["photos"] = .list(photos) }
        if !audio.isEmpty { out["audio"] = .list(audio) }
        if !texts.isEmpty { out["text"] = .list(texts) }
        return out
    }

    /// A path from the flow file, with `~` expanded. A `/samples/` path is a
    /// placeholder for a file the person passes, so it counts as no path.
    static func given(_ param: Param?) -> String? {
        guard let path = param?.string?.trimmingCharacters(in: .whitespaces), !path.isEmpty,
              !path.hasPrefix("/samples/") else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    private static func listed(_ params: Params) throws -> [String] {
        let folders = try (params["folders"]?.strings ?? []).compactMap { given(.string($0)) }.flatMap(contents)
        return folders + (params["files"]?.strings ?? []).compactMap { given(.string($0)) }
    }

    /// The visible files in a folder, A to Z.
    static func contents(of folder: String) throws -> [String] {
        try Inputs.expand([folder], extensions: nil, noun: "", recursive: false).files
    }

    static func asFile(_ path: String) -> Value {
        RunInputKind.image.extensions.contains((path as NSString).pathExtension.lowercased()) ? .image(path) : .file(path)
    }

    static func exists(_ path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { throw StepError("no file at \(path).") }
    }

    static func read(_ path: String) throws -> String {
        try exists(path)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw StepError("could not read \(path) as UTF-8 text.")
        }
        return text
    }
}
