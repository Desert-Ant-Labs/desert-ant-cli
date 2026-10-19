#if canImport(Voz)
import Foundation
import Transcript
import Who

// Voz: a transcript with a time on every word. Sentences on stdout, captions and
// transcripts as files, the document under --json (which `clips --transcript` reads).
// With --speakers, Who labels each line with who said it.

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
        RunOption(name: "speakers", help: "Label each line with who said it, through Who: names in captions and the transcript."),
        RunOption(name: "names", help: "With --speakers, names in the order the speakers first speak, comma-separated: \"Anna,Ben\"."),
    ]

    private let transcriber = VozTranscriber()
    private let who = Who()

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
        /// With --speakers.
        let speakers: [SpeakerSummary]?
        let turns: [SpeakerTurn]?
    }
    struct Span: Encodable {
        let start: Double
        let end: Double
        let text: String
        /// With --speakers, on sentences.
        var speaker: Int? = nil
    }

    private struct Voices {
        let turns: LabeledTurns
        let lines: [SpokenLine]
        let names: [String]
    }

    enum Kind: String, CaseIterable {
        case text, srt, vtt, txt, json
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input)") }
        let format = try kind(arguments["format"] ?? (out.isJSON ? "json" : "text"))

        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        progress.update(nil, label: FirstLoad.label("voz"))
        let loading = Date()
        try await transcriber.prepare { _ in }
        let loadSec = Date().timeIntervalSince(loading)
        FirstLoad.done("voz")
        let t = try await transcriber.transcription(of: URL(fileURLWithPath: input)) {
            progress.update($0, label: "transcribing")
        }
        let voices = arguments["speakers"] == "true" ? try await label(input, t, names: Speakers.names(arguments["names"]), progress) : nil
        progress.finish()
        let sentences = t.sentences
        let cues = voices.map { SpeakerFile.captions($0.lines, words: t.words).map(\.0) } ?? Captions.captions(from: t.words, sentences: sentences)
        let force = arguments["force"] == "true"

        // Files: the flags write beside the input, --output writes one path.
        var files: [String: String] = [:]
        for ext in ["srt", "vtt", "txt"] where arguments[ext] == "true" {
            let path = try Destination.resolve(requested: nil, default: Destination.sibling(of: input, suffix: "", extension: ext),
                                               input: input, force: force)
            try render(input: input, try kind(ext), t, sentences, cues, voices, files: [:], loadSec: loadSec).write(toFile: path, atomically: true, encoding: .utf8)
            files[ext] = path
        }
        if let wanted = arguments["output"] {
            let ext = URL(fileURLWithPath: wanted).pathExtension.lowercased()
            guard let k = Kind(rawValue: ext), k != .text else {
                throw RunError("--output needs an extension that names the format: srt, vtt, txt, or json.")
            }
            let path = try Destination.resolve(requested: wanted, default: wanted, input: input, force: force)
            try render(input: input, k, t, sentences, cues, voices, files: files, loadSec: loadSec).write(toFile: path, atomically: true, encoding: .utf8)
            files[ext] = path
        }

        // Stdout.
        if format == .json {
            out.emit(document(input: input, t, sentences, cues, voices, files: files, loadSec: loadSec))
            return
        }
        if format == .text, let voices {
            out.speakerSummary(voices.turns.summary, duration: t.durationSec)
            out.line()
            out.script(voices.lines, names: voices.names)
        } else if format == .text {
            let width = min(Terminal.columns, 100)
            let show = arguments["timestamps"] == "true"
            let keyWidth = Format.stamp(sentences.last?.start ?? 0).count
            for s in sentences {
                if show {
                    let stamp = Format.stamp(s.start)
                    for line in column(stamp, keyWidth: keyWidth, text: s.text, width: width, palette: out.palette,
                                       keyStyle: { out.palette.time($0) }) { out.line(line) }
                } else {
                    for line in wrap(s.text, width: width) { out.line(line) }
                }
            }
        } else {
            print(try render(input: input, format, t, sentences, cues, voices, files: files, loadSec: loadSec), terminator: "")
        }
        out.space()
        for (ext, path) in files.sorted(by: { $0.key < $1.key }) { out.note("\(ext)  \(path)") }
        out.note("Voz loaded in \(Format.elapsed(loadSec)). Transcribed \(Format.spoken(t.durationSec)) of audio in "
                 + "\(Format.elapsed(t.processingSec)), \(Format.realtime(material: t.durationSec, elapsed: t.processingSec)).")
    }

    private func kind(_ name: String) throws -> Kind {
        guard let k = Kind(rawValue: name.lowercased()) else {
            throw RunError("format must be one of \(Kind.allCases.map(\.rawValue).joined(separator: ", ")), not \(name).")
        }
        return k
    }

    /// Who spoke when, matched to the words.
    private func label(_ input: String, _ t: VozTranscriber.Transcription, names: [String], _ progress: Progress) async throws -> Voices {
        if !who.isDownloaded() {
            try await who.download { progress.update($0, label: "downloading who") }
        }
        progress.update(nil, label: "listening for speakers")
        let result = try await who.labels(of: input)
        FirstLoad.done("who")
        let turns = result.turns.map { SpeakerTurn(start: $0.start, end: $0.end, speaker: $0.speaker) }
        return Voices(turns: LabeledTurns(turns, duration: result.duration, join: Speakers.defaultJoin, names: names),
                      lines: Speakers.lines(words: t.words, turns: turns), names: names)
    }

    private func render(input: String, _ kind: Kind, _ t: VozTranscriber.Transcription, _ sentences: [Sentence], _ cues: [Caption],
                        _ voices: Voices?, files: [String: String], loadSec: Double) throws -> String {
        switch kind {
        case .srt: return voices.map { SpeakerFile.srt($0.lines, words: t.words, names: $0.names) } ?? TranscriptFile.srt(cues)
        case .vtt: return voices.map { SpeakerFile.vtt($0.lines, words: t.words, names: $0.names) } ?? TranscriptFile.vtt(cues)
        case .txt, .text: return voices.map { SpeakerFile.text($0.lines, names: $0.names) } ?? TranscriptFile.text(sentences)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(document(input: input, t, sentences, cues, voices, files: files, loadSec: loadSec)), as: UTF8.self) + "\n"
        }
    }

    private func document(input: String, _ t: VozTranscriber.Transcription, _ sentences: [Sentence], _ cues: [Caption],
                          _ voices: Voices?, files: [String: String], loadSec: Double) -> Document {
        // A sentence two people share is split where the speaker changes.
        let spans = voices.map { $0.lines.map { Span(start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker) } }
            ?? sentences.map { Span(start: $0.start, end: $0.end, text: $0.text) }
        return Document(
            input: input, text: t.text, durationSec: t.durationSec, loadSec: loadSec, processingSec: t.processingSec,
            words: t.words.map { Span(start: $0.start, end: $0.end, text: $0.text.trimmingCharacters(in: .whitespaces)) },
            sentences: spans, captions: cues, files: files,
            speakers: voices?.turns.summary, turns: voices?.turns.joined)
    }
}
#endif
