import Foundation

// Where an output file lands. Never on top of the input, and never on top of an
// existing file unless asked: a taken name steps aside the way the Finder does
// (`talk_clear-2.mp4`), so a batch never stops and nothing is lost.

enum Destination {
    /// The path to write to. `requested` is the user's `--output`, or nil for the
    /// command's default. Throws when the result would replace the input.
    static func resolve(requested: String?, default defaultPath: String,
                        input: String, force: Bool) throws -> String {
        let path = requested ?? defaultPath
        guard canonical(path) != canonical(input) else {
            throw RunError("the output would replace the input. Choose another --output.")
        }
        if force || !FileManager.default.fileExists(atPath: path) { return path }
        return firstFreeName(path)
    }

    /// `name.ext` -> `name-2.ext`, the first that does not exist yet.
    static func firstFreeName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for attempt in 2...9999 {
            var candidate = folder.appendingPathComponent("\(stem)-\(attempt)")
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
        }
        return path
    }

    /// The input's default sibling: `talk.mp4` -> `talk_clear.mp4`, or with another
    /// extension, `talk.mp4` -> `talk.srt`.
    static func sibling(of input: String, suffix: String, extension ext: String? = nil) -> String {
        let url = URL(fileURLWithPath: input)
        let ext = ext ?? url.pathExtension
        var out = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + suffix)
        if !ext.isEmpty { out = out.appendingPathExtension(ext) }
        return out.path
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
