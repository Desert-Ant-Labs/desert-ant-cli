#if canImport(CoreML) && canImport(AVFoundation)
import Foundation
import Transcript

// Voz: a transcript with a time on every word. Sentences on stdout, captions and
// transcripts as files, the document under --json (which `clips --transcript` reads).

struct VozRunner: ModelRunner {
    let id = "voz"
    let inputKind = RunInputKind.file
    let emits: String? = "transcript"
    let options = [
        RunOption(name: "timestamps", help: "A time before each sentence."),
        RunOption(name: "srt", help: "Also write captions as <input>.srt beside the input."),
        RunOption(name: "vtt", help: "Also write captions as <input>.vtt beside the input."),
        RunOption(name: "txt", help: "Also write the transcript as <input>.txt beside the input."),
        RunOption(name: "output", help: "Write one file at this path; the format comes from its extension: srt, vtt, txt, or json."),
        RunOption(name: "format", help: "What stdout carries: text (default), srt, vtt, txt, or json."),
        RunOption(name: "force", help: "Replace an existing file instead of stepping aside."),
    ]

    private let transcriber = VozTranscriber()

    func isDownloaded() -> Bool { transcriber.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await transcriber.prepare(progress: progress)
    }

    struct Document: Encodable {
        let input: String
        let text: String
        let durationSec: Double
        let loadSec: Double
        let processingSec: Double
        let words: [Span]
        let sentences: [Span]
        let captions: [Caption]
        let files: [String: String]
    }
    struct Span: Encodable {
        let start: Double
        let end: Double
        let text: String
    }

    enum Kind: String, CaseIterable {
        case text, srt, vtt, txt, json
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input)") }
        let format = try kind(arguments["format"] ?? (out.isJSON ? "json" : "text"))

        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        progress.update(nil, label: "loading voz, slower the first time on this Mac")
        let loading = Date()
        try await transcriber.prepare { _ in }
        let loadSec = Date().timeIntervalSince(loading)
        let t = try await transcriber.transcription(of: URL(fileURLWithPath: input)) {
            progress.update($0, label: "transcribing")
        }
        progress.finish()
        let sentences = t.sentences
        let cues = Captions.captions(from: t.words, sentences: sentences)
        let force = arguments["force"] == "true"

        // Files: the flags write beside the input, --output writes one path.
        var files: [String: String] = [:]
        for ext in ["srt", "vtt", "txt"] where arguments[ext] == "true" {
            let path = try Destination.resolve(requested: nil, default: Destination.sibling(of: input, suffix: "", extension: ext),
                                               input: input, force: force)
            try render(input: input, try kind(ext), t, sentences, cues, files: [:], loadSec: loadSec).write(toFile: path, atomically: true, encoding: .utf8)
            files[ext] = path
        }
        if let wanted = arguments["output"] {
            let ext = URL(fileURLWithPath: wanted).pathExtension.lowercased()
            guard let k = Kind(rawValue: ext), k != .text else {
                throw RunError("--output needs an extension that names the format: srt, vtt, txt, or json.")
            }
            let path = try Destination.resolve(requested: wanted, default: wanted, input: input, force: force)
            try render(input: input, k, t, sentences, cues, files: files, loadSec: loadSec).write(toFile: path, atomically: true, encoding: .utf8)
            files[ext] = path
        }

        // Stdout.
        if format == .json {
            out.emit(document(input: input, t, sentences, cues, files: files, loadSec: loadSec))
            return
        }
        if format == .text {
            let width = min(Terminal.columns, 100)
            let show = arguments["timestamps"] == "true"
            let keyWidth = Format.stamp(sentences.last?.start ?? 0).count
            for s in sentences {
                if show {
                    let stamp = Format.stamp(s.start)
                    for line in column(stamp, keyWidth: keyWidth, text: s.text, width: width, palette: out.palette,
                                       keyStyle: { out.palette.accent($0) }) { out.line(line) }
                } else {
                    for line in wrap(s.text, width: width) { out.line(line) }
                }
            }
        } else {
            print(try render(input: input, format, t, sentences, cues, files: files, loadSec: loadSec), terminator: "")
        }
        out.space()
        for (ext, path) in files.sorted(by: { $0.key < $1.key }) { out.note("\(ext)  \(path)") }
        out.note("Loaded in \(Format.elapsed(loadSec)). \(Format.spoken(t.durationSec)) of audio in "
                 + "\(Format.elapsed(t.processingSec)), \(Format.realtime(material: t.durationSec, elapsed: t.processingSec)).")
    }

    private func kind(_ name: String) throws -> Kind {
        guard let k = Kind(rawValue: name.lowercased()) else {
            throw RunError("format must be one of \(Kind.allCases.map(\.rawValue).joined(separator: ", ")), not \(name).")
        }
        return k
    }

    private func render(input: String, _ kind: Kind, _ t: VozTranscriber.Transcription, _ sentences: [Sentence], _ cues: [Caption],
                        files: [String: String], loadSec: Double) throws -> String {
        switch kind {
        case .srt: return TranscriptFile.srt(cues)
        case .vtt: return TranscriptFile.vtt(cues)
        case .txt, .text: return TranscriptFile.text(sentences)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(document(input: input, t, sentences, cues, files: files, loadSec: loadSec)), as: UTF8.self) + "\n"
        }
    }

    private func document(input: String, _ t: VozTranscriber.Transcription, _ sentences: [Sentence], _ cues: [Caption],
                          files: [String: String], loadSec: Double) -> Document {
        Document(
            input: input, text: t.text, durationSec: t.durationSec, loadSec: loadSec, processingSec: t.processingSec,
            words: t.words.map { Span(start: $0.start, end: $0.end, text: $0.text.trimmingCharacters(in: .whitespaces)) },
            sentences: sentences.map { Span(start: $0.start, end: $0.end, text: $0.text) },
            captions: cues, files: files)
    }
}
#endif
