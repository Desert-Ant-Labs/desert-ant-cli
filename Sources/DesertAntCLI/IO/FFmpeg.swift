import Foundation

// The ffmpeg on PATH, for the media work AVFoundation and ImageIO do on a Mac.

enum FFmpeg {
    struct Tools: Sendable {
        let ffmpeg: String
        let ffprobe: String
    }

    static let tools: Tools? = locate(path: ProcessInfo.processInfo.environment["PATH"] ?? "")

    static func locate(path: String) -> Tools? {
        func find(_ name: String) -> String? {
            path.split(separator: ":").lazy
                .map { (String($0) as NSString).appendingPathComponent(name) }
                .first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        guard let ffmpeg = find("ffmpeg"), let ffprobe = find("ffprobe") else { return nil }
        return Tools(ffmpeg: ffmpeg, ffprobe: ffprobe)
    }

    static func require(for file: String, fallback: String? = nil) throws -> Tools {
        if let tools { return tools }
        let name = URL(fileURLWithPath: file).lastPathComponent
        throw RunError("reading \(name) needs ffmpeg, which is not installed. Install ffmpeg with \(installHint)\(fallback.map { ", or \($0)" } ?? "").")
    }

    /// How to install ffmpeg here, as a phrase that follows "Install ffmpeg with".
    static var installHint: String {
        #if os(macOS)
        return "`brew install ffmpeg`"
        #else
        return installHint(osRelease: (try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)) ?? "")
        #endif
    }

    static func installHint(osRelease: String) -> String {
        var fields: [String: String] = [:]
        for line in osRelease.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<eq])] = line[line.index(after: eq)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).lowercased()
        }
        let id = fields["ID"] ?? ""
        let family = [id] + (fields["ID_LIKE"] ?? "").split(separator: " ").map(String.init)
        if id == "fedora" { return "`sudo dnf install ffmpeg-free`" }
        if family.contains(where: { $0 == "debian" || $0 == "ubuntu" }) { return "`sudo apt install ffmpeg`" }
        if family.contains("arch") { return "`sudo pacman -S ffmpeg`" }
        if family.contains(where: { $0.contains("suse") }) { return "`sudo zypper install ffmpeg`" }
        // RHEL and its rebuilds carry ffmpeg in RPM Fusion only.
        if family.contains(where: { $0 == "rhel" || $0 == "centos" || $0 == "fedora" }) {
            return "`sudo dnf install ffmpeg` from RPM Fusion"
        }
        return "your package manager"
    }

    /// Whether this ffmpeg draws subtitles, which needs libass.
    static func hasSubtitles(_ tools: Tools) -> Bool {
        let filters = (try? run(tools.ffmpeg, ["-hide_banner", "-filters"], file: "filters")) ?? Data()
        return String(decoding: filters, as: UTF8.self).contains(" subtitles ")
    }

    // MARK: - Probe

    struct Probe: Sendable, Equatable {
        var hasVideo = false
        var hasAudio = false
        var durationSec = 0.0
        var channels = 0
        var width = 0
        var height = 0
        /// Degrees the player turns the picture.
        var rotation = 0
    }

    static func probe(_ path: String, tools: Tools) throws -> Probe {
        // Whole sections, since ffmpeg versions name the rotation's place differently.
        let data = try run(tools.ffprobe, ["-v", "error", "-print_format", "json", "-show_streams", "-show_format", path], file: path)
        guard let probe = parseProbe(data) else {
            throw RunError("could not read \(name(path)) as a media file.")
        }
        return probe
    }

    static func parseProbe(_ data: Data) -> Probe? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var probe = Probe()
        for stream in json["streams"] as? [[String: Any]] ?? [] {
            switch stream["codec_type"] as? String {
            case "audio":
                if !probe.hasAudio { probe.channels = stream["channels"] as? Int ?? 0 }
                probe.hasAudio = true
            case "video":
                if !probe.hasVideo {
                    probe.width = stream["width"] as? Int ?? 0
                    probe.height = stream["height"] as? Int ?? 0
                    for side in stream["side_data_list"] as? [[String: Any]] ?? [] {
                        if let r = side["rotation"] as? Int { probe.rotation = r }
                    }
                    if let tags = stream["tags"] as? [String: Any], let r = (tags["rotate"] as? String).flatMap(Int.init) {
                        probe.rotation = r
                    }
                }
                probe.hasVideo = true
            default: break
            }
        }
        if let format = json["format"] as? [String: Any], let text = format["duration"] as? String {
            probe.durationSec = Double(text) ?? 0
        }
        return probe
    }

    // MARK: - Audio

    /// One array per channel, mixed down to `channels` when given.
    static func decodeAudio(_ path: String, sampleRate: Double, channels wanted: Int? = nil,
                            tools: Tools) throws -> [[Float]] {
        let info = try probe(path, tools: tools)
        guard info.hasAudio else { throw RunError("\(name(path)) has no audio track.") }
        let channels = max(1, wanted ?? info.channels)
        let data = try run(tools.ffmpeg, [
            "-v", "error", "-nostdin", "-i", path, "-vn",
            "-f", "f32le", "-acodec", "pcm_f32le", "-ac", "\(channels)", "-ar", "\(Int(sampleRate))", "-",
        ], file: path)
        return deinterleave(data, channels: channels)
    }

    static func deinterleave(_ data: Data, channels: Int) -> [[Float]] {
        let frames = data.count / (4 * channels)
        var out = Array(repeating: [Float](repeating: 0, count: frames), count: channels)
        data.withUnsafeBytes { raw in
            for frame in 0..<frames {
                for c in 0..<channels {
                    let bits = raw.loadUnaligned(fromByteOffset: (frame * channels + c) * 4, as: UInt32.self)
                    out[c][frame] = Float(bitPattern: UInt32(littleEndian: bits))
                }
            }
        }
        return out
    }

    static func encode(wav: String, to destination: String, tools: Tools) throws {
        try run(tools.ffmpeg, ["-v", "error", "-nostdin", "-y", "-i", wav, "-vn", destination],
                file: destination, writing: true)
    }

    // MARK: - Images

    /// The first frame as stored, RGB. EXIF orientation is left to `Exif`.
    static func decodeImage(_ path: String, tools: Tools) throws -> (width: Int, height: Int, rgb: [UInt8]) {
        let info = try probe(path, tools: tools)
        guard info.hasVideo, info.width > 0, info.height > 0 else {
            throw RunError("could not read \(name(path)) as an image.")
        }
        let data = try run(tools.ffmpeg, [
            "-v", "error", "-nostdin", "-noautorotate", "-i", path,
            "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
        ], file: path)
        guard data.count == info.width * info.height * 3 else {
            throw RunError("could not read \(name(path)) as an image.")
        }
        return (info.width, info.height, [UInt8](data))
    }

    // MARK: - Clips

    /// Copies the tracks, as AVFoundation's passthrough export does. When the container
    /// cannot hold the source's codecs, ffmpeg's default encoders for it take over.
    static func cut(_ source: String, ranges: [(start: Double, duration: Double)],
                    to destination: String, tools: Tools) throws {
        let kept = ranges.filter { $0.duration > 0 }
        guard !kept.isEmpty else { throw RunError("the clip's time range lies outside the source") }
        do {
            try cut(source, ranges: kept, to: destination, copy: true, tools: tools)
        } catch {
            try? FileManager.default.removeItem(atPath: destination)
            try cut(source, ranges: kept, to: destination, copy: false, tools: tools)
        }
    }

    private static func cut(_ source: String, ranges: [(start: Double, duration: Double)],
                            to destination: String, copy: Bool, tools: Tools) throws {
        // Subtitle and data tracks stop a copy into most containers.
        let audioOnly = audioContainers.contains(URL(fileURLWithPath: destination).pathExtension.lowercased())
        let streams = (audioOnly ? ["-map", "0:a:0", "-vn"] : ["-map", "0:v:0?", "-map", "0:a:0?"])
            + ["-sn", "-dn"] + (copy ? ["-c", "copy"] : [])
        func segment(_ range: (start: Double, duration: Double), to path: String) throws {
            try run(tools.ffmpeg, ["-v", "error", "-nostdin", "-y", "-ss", seconds(range.start), "-i", source,
                                   "-t", seconds(range.duration)] + streams + ["-avoid_negative_ts", "make_zero", path],
                    file: path, writing: true)
        }
        if ranges.count == 1 {
            try segment(ranges[0], to: destination)
            return
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("desertant-cut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let ext = URL(fileURLWithPath: destination).pathExtension
        var list = ""
        for (i, range) in ranges.enumerated() {
            let part = scratch.appendingPathComponent("part-\(i).\(ext)").path
            try segment(range, to: part)
            list += "file '\(part.replacingOccurrences(of: "'", with: "'\\''"))'\n"
        }
        let listFile = scratch.appendingPathComponent("parts.txt").path
        try list.write(toFile: listFile, atomically: true, encoding: .utf8)
        try run(tools.ffmpeg, ["-v", "error", "-nostdin", "-y", "-f", "concat", "-safe", "0", "-i", listFile,
                               "-c", "copy", destination],
                file: destination, writing: true)
    }

    static let audioContainers: Set<String> = ["m4a", "wav", "aiff", "aif", "caf", "mp3", "aac", "flac"]

    private static func seconds(_ s: Double) -> String { String(format: "%.3f", max(0, s)) }
    private static func name(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }

    // MARK: - Running

    /// stdout, or an error carrying ffmpeg's last line.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], file: String, writing: Bool = false, in directory: URL? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Drained together, or a full stderr pipe stalls ffmpeg.
        let errors = Drain(stderr.fileHandleForReading)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let message = errors.wait()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let last = String(decoding: message, as: UTF8.self).split(separator: "\n").last
                .map { ": " + $0.trimmingCharacters(in: .whitespaces) } ?? ""
            throw RunError("ffmpeg could not \(writing ? "write" : "read") \(name(file))\(last)")
        }
        return data
    }

    private final class Drain: @unchecked Sendable {
        private var data = Data()
        private let done = DispatchSemaphore(value: 0)

        init(_ handle: FileHandle) {
            Thread.detachNewThread { [self] in
                data = handle.readDataToEndOfFile()
                done.signal()
            }
        }

        func wait() -> Data {
            done.wait()
            return data
        }
    }
}
