import Foundation
import Transcript

// A timed transcript, from a recognizer behind the `Transcriber` protocol or from a
// file, which works on every platform with no model at all.

/// Turns a media file into timed words.
protocol Transcriber: Sendable {
    /// The model's name for a progress line, e.g. "voz".
    var name: String { get }
    /// Whether the weights are on disk already.
    func isDownloaded() -> Bool
    /// Fetch the weights, reporting 0...1. A no-op when they are present.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws
    /// Words with times, in order. `progress` is 0...1.
    func transcribe(_ media: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [TimedWord]
}

/// A transcript read from a file: SRT or VTT, JSON as `[{"start", "end", "text"}]`,
/// or the document `desertant voz --json` writes (its `sentences`).
enum TranscriptFile {
    static func load(_ url: URL) throws -> [Sentence] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let cues: [(start: Double, end: Double, text: String)]
        switch url.pathExtension.lowercased() {
        case "json": cues = try json(text)
        case "srt", "vtt": cues = srt(text)
        default: throw RunError("transcript must be .srt, .vtt, or .json, not .\(url.pathExtension)")
        }
        guard !cues.isEmpty else { throw RunError("no timed lines in \(url.lastPathComponent)") }
        return cues.enumerated().map { Sentence(id: $0.offset, text: $0.element.text,
                                                 start: $0.element.start, end: $0.element.end) }
    }

    /// Captions as SRT: an index, `00:00:01,000 --> 00:00:04,500`, the text.
    static func srt(_ cues: [Caption]) -> String {
        cues.enumerated()
            .map { i, c in "\(i + 1)\n\(stamp(c.start, ",")) --> \(stamp(c.end, ","))\n\(c.text)\n" }
            .joined(separator: "\n")
    }

    /// Captions as WebVTT: the header, then cues with a period before the milliseconds.
    static func vtt(_ cues: [Caption]) -> String {
        "WEBVTT\n\n" + cues
            .map { "\(stamp($0.start, ".")) --> \(stamp($0.end, "."))\n\($0.text)\n" }
            .joined(separator: "\n")
    }

    /// The transcript as text, one sentence per line.
    static func text(_ sentences: [Sentence]) -> String {
        sentences.map(\.text).joined(separator: "\n") + "\n"
    }

    private static func stamp(_ seconds: Double, _ separator: String) -> String {
        let ms = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%02d\(separator)%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    private struct Line: Decodable { let start: Double; let end: Double; let text: String }
    private struct Document: Decodable { let sentences: [Line] }

    private static func json(_ text: String) throws -> [(Double, Double, String)] {
        let data = Data(text.utf8)
        if let cues = try? JSONDecoder().decode([Line].self, from: data) {
            return cues.map { ($0.start, $0.end, $0.text) }
        }
        if let doc = try? JSONDecoder().decode(Document.self, from: data) {
            return doc.sentences.map { ($0.start, $0.end, $0.text) }
        }
        throw RunError("transcript JSON must be an array of {start, end, text} in seconds, or the document `desertant voz --json` writes")
    }

    /// Blocks separated by blank lines: an optional index, a `00:00:01,000 --> 00:00:04,000`
    /// line, then the text. VTT uses a period for the millisecond separator; both parse.
    private static func srt(_ text: String) -> [(Double, Double, String)] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .compactMap { block in
                let lines = block.split(separator: "\n").map(String.init)
                guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
                let parts = lines[timing].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, let start = seconds(parts[0]), let end = seconds(parts[1]) else { return nil }
                let body = lines[(timing + 1)...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                return body.isEmpty ? nil : (start, end, body)
            }
    }

    /// `hh:mm:ss,mmm` or `mm:ss.mmm` to seconds.
    static func seconds(_ stamp: String) -> Double? {
        let clean = stamp.split(separator: " ").first.map(String.init) ?? stamp
        let parts = clean.replacingOccurrences(of: ",", with: ".").split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count), let last = Double(parts.last!) else { return nil }
        var total = last
        var scale = 60.0
        for part in parts.dropLast().reversed() {
            guard let n = Double(part) else { return nil }
            total += n * scale
            scale *= 60
        }
        return total
    }
}
