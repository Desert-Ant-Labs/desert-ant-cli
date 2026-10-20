import Clips
import Foundation
import Transcript

// The clips pipeline: transcribe, select, cut. Each step sits behind its own type so
// a platform can swap one.

/// One chosen moment, with where it landed on disk.
struct Pick: Encodable, Sendable {
    let id: Int
    let start: Double
    let end: Double
    let durationSec: Double
    let text: String
    let score: Double
    var file: String?
    /// The .srt file beside the clip, with `--captions srt`.
    var captions: String?
}

/// Everything the run produced, as the JSON result and the source for the summary.
struct ClipReport: Encodable, Sendable {
    let input: String
    let transcript: String?
    let sentences: Int
    let materialSec: Double
    let transcribeSec: Double
    let selectSec: Double
    let cutSec: Double
    let clips: [Pick]
    /// What changed from what was asked, as captions written as .srt for audio.
    var notes: [String]?
}

/// Where a run has got to, for a progress line.
enum ClipPhase: Sendable {
    case downloading(model: String, Double)
    /// Weights on disk, loading. The first load also specializes the model for the
    /// Neural Engine, which takes a while.
    case loading(model: String)
    case transcribing(Double)
    case selecting
    case cutting(done: Int, of: Int)
}

struct ClipPipeline {
    let clips = Clips()

    var transcriber: (any Transcriber)? {
        #if canImport(Voz)
        return VozTranscriber()
        #else
        return nil
        #endif
    }

    var cutter: (any MediaCutter)? {
        #if canImport(AVFoundation)
        return AVFoundationCutter()
        #else
        return FFmpeg.tools.map(FFmpegCutter.init)
        #endif
    }

    struct Request {
        let media: URL
        /// A transcript file instead of running the recognizer.
        var transcript: URL?
        /// How many clips to look for; nil lets the model size it to the material.
        var count: Int?
        /// Where the clip files go, or nil for beside the input.
        var outputDirectory: URL?
        /// Report the moments without writing files.
        var selectOnly = false
        var force = false
        /// Words already transcribed, instead of running the recognizer.
        var words: [TimedWord]?
        var captions = CaptionMode.off
        var style = CaptionStyle()
    }

    func run(_ request: Request, progress: @escaping @Sendable (ClipPhase) -> Void) async throws -> ClipReport {
        // Probe first: a recording with no audio track should fail before any download.
        let info = try await cutter?.probe(request.media)
        if let info, request.transcript == nil, request.words == nil, !info.hasAudio {
            throw RunError("\(request.media.lastPathComponent) has no audio track, so there is nothing to transcribe.")
        }

        if !request.selectOnly, cutter == nil {
            throw RunError("cutting clips needs ffmpeg, which is not installed. Install ffmpeg with \(FFmpeg.installHint), or pass --select-only to get the moments as timestamps.")
        }
        var notes: [String] = []
        var captions = request.selectOnly ? .off : request.captions
        if captions == .burn, info?.hasVideo == false {
            captions = .srt
            notes.append("\(request.media.lastPathComponent) has no picture, so the captions are written as .srt files beside the clips.")
        }
        var font: CaptionFont?
        if captions == .burn {
            font = try CaptionFont.resolve(request.style.font, weight: request.style.weight)
            #if !canImport(AVFoundation)
            if let tools = FFmpeg.tools, !FFmpeg.hasSubtitles(tools) {
                throw RunError("burning captions needs an ffmpeg built with libass, and this one is not. Pass --captions srt to write the captions beside each clip instead.")
            }
            #endif
        }

        var transcribeSec = 0.0
        let sentences: [Sentence]
        var words: [TimedWord] = []
        if let file = request.transcript {
            sentences = try TranscriptFile.load(file)
            words = TranscriptFile.words(file) ?? ClipCaptions.words(spreading: sentences)
        } else if let given = request.words {
            words = given
            sentences = Sentence.sentences(from: given)
        } else {
            guard let transcriber else {
                throw RunError("transcribing needs Voz, which does not run here. Pass --transcript with an .srt, .vtt, or .json file instead.")
            }
            let model = transcriber.name
            if !transcriber.isDownloaded() {
                try await transcriber.prepare { progress(.downloading(model: model, $0)) }
            }
            progress(.loading(model: model))
            try await transcriber.prepare { _ in }
            let started = Date()
            words = try await transcriber.transcribe(request.media) { progress(.transcribing($0)) }
            sentences = Sentence.sentences(from: words)
            transcribeSec = Date().timeIntervalSince(started)
        }
        guard sentences.count >= 3 else {
            throw RunError("only \(sentences.count) sentences; the clips model needs at least three.")
        }

        // The first call loads the model, so the label goes up first.
        progress(.loading(model: "clips"))
        let selecting = Date()
        let chosen = try await clips.clips(in: sentences.map(\.text), limit: request.count)
        progress(.selecting)
        let selectSec = Date().timeIntervalSince(selecting)
        var picks = chosen.enumerated().map { index, clip -> Pick in
            let ranges = clip.ranges(in: sentences)
            return Pick(id: index + 1, start: ranges.first?.start ?? 0, end: ranges.last?.end ?? 0,
                        durationSec: clip.duration(in: sentences), text: clip.text, score: clip.score)
        }

        var cutSec = 0.0
        if !request.selectOnly, !picks.isEmpty, let cutter {
            let cutting = Date()
            let ext = MediaFormat.outputExtension(for: request.media.path, hasVideo: info?.hasVideo ?? false)
            let stem = request.media.deletingPathExtension().lastPathComponent
            let folder = request.outputDirectory ?? request.media.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, clip) in chosen.enumerated() {
                progress(.cutting(done: index, of: chosen.count))
                let wanted = folder.appendingPathComponent("\(stem)_clip-\(index + 1).\(ext)").path
                let destination = try Destination.resolve(requested: nil, default: wanted,
                                                          input: request.media.path, force: request.force)
                let ranges = clip.ranges(in: sentences)
                let shifted = ClipCaptions.shift(words, into: ranges)
                switch captions {
                case .burn:
                    let frame = CaptionFrame(width: info?.width ?? 0, height: info?.height ?? 0, style: request.style)
                    let burned = BurnedCaptions(cues: ClipCaptions.social(shifted, pacing: frame.pacing),
                                                style: request.style, font: font!)
                    try await cutter.cut(request.media, ranges: ranges, burning: burned, frame: frame, to: URL(fileURLWithPath: destination))
                case .srt:
                    try await cutter.cut(request.media, ranges: ranges, to: URL(fileURLWithPath: destination))
                    let cues = Captions.captions(from: shifted, sentences: Sentence.sentences(from: shifted))
                    let path = try Destination.resolve(requested: nil, default: Destination.sibling(of: destination, suffix: "", extension: "srt"),
                                                       input: request.media.path, force: request.force)
                    try TranscriptFile.srt(cues).write(toFile: path, atomically: true, encoding: .utf8)
                    picks[index].captions = path
                case .off:
                    try await cutter.cut(request.media, ranges: ranges, to: URL(fileURLWithPath: destination))
                }
                picks[index].file = destination
            }
            progress(.cutting(done: chosen.count, of: chosen.count))
            cutSec = Date().timeIntervalSince(cutting)
        }

        return ClipReport(
            input: request.media.path, transcript: request.transcript?.path,
            sentences: sentences.count, materialSec: info?.durationSec ?? sentences.last?.end ?? 0,
            transcribeSec: transcribeSec, selectSec: selectSec, cutSec: cutSec, clips: picks,
            notes: notes.isEmpty ? nil : notes
        )
    }
}
