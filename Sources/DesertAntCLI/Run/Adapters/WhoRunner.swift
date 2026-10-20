import Foundation
import Transcript
import Who

// Who: who spoke when in a recording, and with a transcript, who said each line.

struct WhoRunner: ModelRunner {
    let id = "who"
    let inputKind = RunInputKind.file
    let emits: String? = "speakers"
    let accepts = [Intake(kind: "transcript", option: "transcript")]
    let options = [
        RunOption(name: "names", help: "Names for the speakers in the order they first speak, such as \"Anna,Ben\"."),
        RunOption(name: "min-share", help: "Leave out a voice that takes up less than this share of the recording, from 0 to 1, such as a laugh or a jingle. Default 0."),
        RunOption(name: "join", help: "Join a speaker's turns across pauses up to this many seconds. Default 1."),
        RunOption(name: "transcript", help: "A transcript to label line by line: the --json of voz, or an .srt or .vtt file. Pass - to read it from stdin."),
        RunOption(name: "format", help: "The format to print: text, json, rttm, and with a transcript, srt, vtt, or txt. Default text."),
        RunOption(name: "output", help: "Write one file at this path. Its extension sets the format: rttm, json, and with a transcript, srt, vtt, or txt."),
        RunOption(name: "force", help: "Replace an existing file instead of writing name-2.ext."),
    ]

    private let model = Who()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Document: Encodable {
        let input: String
        let durationSec: Double
        let loadSec: Double
        let processingSec: Double
        let speakerCount: Int
        let speakers: [SpeakerSummary]
        let turns: [SpeakerTurn]
        /// With --transcript only.
        let lines: [SpokenLine]?
        let files: [String: String]
    }

    enum Kind: String, CaseIterable {
        case text, json, rttm, srt, vtt, txt
        var needsTranscript: Bool { [.srt, .vtt, .txt].contains(self) }
    }

    private struct Settings {
        let names: [String]
        let minShare: Double
        let join: Double
        let format: Kind?
        let output: (path: String, kind: Kind)?
    }

    private func settings(_ arguments: RunArguments) throws -> Settings {
        let minShare = arguments.double("min-share") ?? 0
        guard (0...1).contains(minShare) else { throw RunError("min-share must be between 0 and 1.") }
        let join = arguments.double("join") ?? Speakers.defaultJoin
        guard join >= 0 else { throw RunError("join must be 0 seconds or more.") }
        let transcript = arguments["transcript"] != nil
        let format = try arguments["format"].map { try kind($0, transcript: transcript) }
        let output = try arguments["output"].map { path -> (String, Kind) in
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            guard let k = Kind(rawValue: ext), k != .text else {
                throw RunError("--output needs an extension that names the format: rttm, json, srt, vtt, or txt.")
            }
            return (path, try kind(ext, transcript: transcript))
        }
        return Settings(names: Speakers.names(arguments["names"]), minShare: minShare, join: join, format: format, output: output)
    }

    private func kind(_ name: String, transcript: Bool) throws -> Kind {
        guard let k = Kind(rawValue: name.lowercased()) else {
            throw RunError("format must be one of \(Kind.allCases.map(\.rawValue).joined(separator: ", ")), not \(name).")
        }
        if k.needsTranscript, !transcript {
            throw RunError("\(k.rawValue) is a transcript format. Pass --transcript, or run `desertant voz --speakers` to transcribe and label in one go.")
        }
        return k
    }

    func validate(_ arguments: RunArguments) throws { _ = try settings(arguments) }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input).") }
        let settings = try settings(arguments)
        let transcript = try arguments["transcript"].map(TranscriptFile.url(option:))
        defer { if arguments["transcript"] == "-", let transcript { try? FileManager.default.removeItem(at: transcript) } }
        let sentences = try transcript.map(TranscriptFile.load)
        let words = transcript.flatMap(TranscriptFile.words)

        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        progress.update(nil, label: FirstLoad.label(id))
        let loading = Date()
        try await model.download { _ in }
        let loadSec = Date().timeIntervalSince(loading)
        FirstLoad.done(id)
        progress.update(nil, label: "analyzing")
        let started = Date()
        let result = try await model.labels(of: input)
        let processingSec = Date().timeIntervalSince(started)
        progress.finish()

        let kept = result.keepingSpeakers(minimumShare: settings.minShare)
        let speakers = LabeledTurns(kept.turns.map { SpeakerTurn(start: $0.start, end: $0.end, speaker: $0.speaker) },
                                    duration: result.duration, join: settings.join, names: settings.names)
        let lines = words.map { Speakers.lines(words: $0, turns: speakers.raw) }
            ?? sentences.map { Speakers.lines(sentences: $0, turns: speakers.raw) }
        func document(files: [String: String]) -> Document {
            Document(input: input, durationSec: result.duration, loadSec: loadSec, processingSec: processingSec,
                     speakerCount: speakers.summary.count, speakers: speakers.summary, turns: speakers.joined,
                     lines: lines, files: files)
        }
        func render(_ kind: Kind, files: [String: String]) throws -> String {
            switch kind {
            case .rttm: return SpeakerFile.rttm(speakers.joined, input: input, names: settings.names)
            case .srt: return SpeakerFile.srt(lines ?? [], words: words, names: settings.names)
            case .vtt: return SpeakerFile.vtt(lines ?? [], words: words, names: settings.names)
            case .txt: return SpeakerFile.text(lines ?? [], names: settings.names)
            case .json, .text: return try pretty(document(files: files))
            }
        }

        var files: [String: String] = [:]
        if let (wanted, kind) = settings.output {
            let path = try Destination.resolve(requested: wanted, default: wanted, input: input, force: arguments["force"] == "true")
            try render(kind, files: files).write(toFile: path, atomically: true, encoding: .utf8)
            files[kind.rawValue] = path
        }

        let format = settings.format ?? (out.isJSON ? .json : .text)
        if format == .json {
            out.emit(document(files: files))
            return
        }
        guard format == .text else {
            out.text(try render(format, files: files))
            return
        }
        show(speakers, lines: lines, duration: result.duration, names: settings.names, out: out)
        out.space()
        for (ext, path) in files.sorted(by: { $0.key < $1.key }) { out.note("\(ext)  \(path)") }
        out.note("Who labeled \(Format.spoken(result.duration)) in \(Format.elapsed(processingSec)), "
                 + "\(Format.realtime(material: result.duration, elapsed: processingSec)).")
    }

    private func show(_ speakers: LabeledTurns, lines: [SpokenLine]?, duration: Double, names: [String], out: Output) {
        let p = out.palette
        guard !speakers.summary.isEmpty else {
            out.line(p.dim("no speech to label"))
            return
        }
        out.speakerSummary(speakers.summary, duration: duration)
        out.line()
        if let lines {
            out.script(lines, names: names)
            return
        }
        let stampWidth = Format.stamp(speakers.joined.last?.end ?? 0).count
        for turn in speakers.joined {
            let span = "\(Format.stamp(turn.start).leftPadded(to: stampWidth)) to \(Format.stamp(turn.end).leftPadded(to: stampWidth))"
            out.line("\(p.time(span))  \(Speakers.name(turn.speaker, names: names))  \(p.dim(Format.elapsed(turn.end - turn.start)))")
        }
    }

    private func pretty<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }
}

extension Who {
    /// Who spoke when in an audio or video file. The CLI decodes the file, so ffmpeg reads
    /// what core's WAV reader cannot off Apple platforms.
    func labels(of input: String) async throws -> Diarization {
        let samples: [Float]
        do {
            samples = try await Media.decodeMono(input, sampleRate: 16_000)
        } catch let error as RunError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch {
            throw RunError("could not read the audio in \(input).")
        }
        do {
            return try await diarize(samples: samples, sampleRate: 16_000)
        } catch let error as WhoError {
            throw RunError("could not label the speakers in \(input): \(error.message)")
        }
    }
}
