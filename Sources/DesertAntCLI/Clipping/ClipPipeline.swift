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
        #if canImport(CoreML) && canImport(AVFoundation)
        return VozTranscriber()
        #else
        return nil
        #endif
    }

    var cutter: (any MediaCutter)? {
        #if canImport(AVFoundation)
        return AVFoundationCutter()
        #else
        return nil
        #endif
    }

    struct Request {
        let media: URL
        /// A transcript file instead of running the recognizer.
        var transcript: URL?
        /// How many clips to look for; nil lets the model size it to the material.
        var count: Int?
        /// Where the clip files go. Default: beside the input.
        var outputDirectory: URL?
        /// Report the moments without writing files.
        var selectOnly = false
        var force = false
    }

    func run(_ request: Request, progress: @escaping @Sendable (ClipPhase) -> Void) async throws -> ClipReport {
        // Probe first: a recording with no audio track should fail before any download.
        let info = try await cutter?.probe(request.media)
        if let info, request.transcript == nil, !info.hasAudio {
            throw RunError("\(request.media.lastPathComponent) has no audio track, so there is nothing to transcribe.")
        }

        var transcribeSec = 0.0
        let sentences: [Sentence]
        if let file = request.transcript {
            sentences = try TranscriptFile.load(file)
        } else {
            guard let transcriber else {
                throw RunError("transcribing needs Voz, which runs on Apple platforms. Pass --transcript with an .srt or .json file instead.")
            }
            let model = transcriber.name
            if !transcriber.isDownloaded() {
                try await transcriber.prepare { progress(.downloading(model: model, $0)) }
            }
            progress(.loading(model: model))
            try await transcriber.prepare { _ in }
            let started = Date()
            let words = try await transcriber.transcribe(request.media) { progress(.transcribing($0)) }
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
        if !request.selectOnly, !picks.isEmpty {
            guard let cutter else {
                throw RunError("cutting needs AVFoundation, which runs on Apple platforms. Pass --select-only to get the moments as timestamps.")
            }
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
                try await cutter.cut(request.media, ranges: clip.ranges(in: sentences),
                                     to: URL(fileURLWithPath: destination))
                picks[index].file = destination
            }
            progress(.cutting(done: chosen.count, of: chosen.count))
            cutSec = Date().timeIntervalSince(cutting)
        }

        return ClipReport(
            input: request.media.path, transcript: request.transcript?.path,
            sentences: sentences.count, materialSec: info?.durationSec ?? sentences.last?.end ?? 0,
            transcribeSec: transcribeSec, selectSec: selectSec, cutSec: cutSec, clips: picks
        )
    }
}
