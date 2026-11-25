import Foundation

// Never write over the input or an existing file: a taken name steps aside (`talk_clear-2.mp4`), so a batch never stops and nothing is lost.

enum Destination {
    static func resolve(requested: String?, default defaultPath: String,
                        input: String, force: Bool) throws -> String {
        let path = requested ?? defaultPath
        guard canonical(path) != canonical(input) else {
            throw RunError("the output would replace the input. Choose another --output.")
        }
        if force || !FileManager.default.fileExists(atPath: path) { return path }
        return firstFreeName(path)
    }

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
