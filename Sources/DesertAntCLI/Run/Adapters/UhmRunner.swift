#if canImport(CoreML)
import AudioIO
import Foundation
import Uhm

// Uhm: the "uh", "um", and "hmm" in a recording, with frame-precise spans.

struct UhmRunner: ModelRunner {
    let id = "uhm"
    let inputKind = RunInputKind.file
    let emits: String? = "spans"

    private let model = Uhm()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Document: Encodable {
        let input: String
        let durationSec: Double
        let fillers: [Filler]
    }
    struct Filler: Encodable {
        let start: Double
        let end: Double
        let durationSec: Double
        let type: String?
        let confidence: Double
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input)") }
        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        progress.update(nil, label: "reading audio")
        let samples = try await AudioIO.decode(path: input, sampleRate: 16_000)
        progress.update(nil, label: FirstLoad.label("uhm"))
        let result = try await model.analyze(samples: samples, sampleRate: 16_000) {
            progress.update($0, label: "listening")
        }
        progress.finish()
        FirstLoad.done("uhm")

        if out.isJSON {
            out.emit(Document(input: input, durationSec: result.audioDuration, fillers: result.fillers.map {
                Filler(start: $0.start, end: $0.end, durationSec: $0.duration,
                       type: $0.type?.rawValue, confidence: $0.confidence)
            }))
            return
        }
        let p = out.palette
        for f in result.fillers {
            out.line("\(p.time(Format.stamp(f.start)))  \(f.type?.rawValue ?? "filler")  \(p.dim(Format.elapsed(f.duration)))")
        }
        let count = result.fillers.count
        out.note("\n\(count == 0 ? "No fillers" : "\(count) filler\(count == 1 ? "" : "s")") in \(Format.spoken(result.audioDuration)) of audio.")
    }
}
#endif
