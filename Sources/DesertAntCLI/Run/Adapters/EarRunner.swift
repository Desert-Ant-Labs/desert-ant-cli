import AudioIO
import Ear
import Foundation

// Ear: the language spoken in a recording.

struct EarRunner: ModelRunner {
    let id = "ear"
    let inputKind = RunInputKind.file
    let options = [RunOption(name: "top", help: "How many candidate languages to show. Default 3.")]

    private let model = Ear()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Document: Encodable {
        let input: String
        let language: String?
        let confidence: Double
        let candidates: [Candidate]
    }
    struct Candidate: Encodable {
        let language: String
        let probability: Double
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else { throw RunError("no file at \(input)") }
        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        progress.update(nil, label: "reading audio")
        let samples = try await AudioIO.decode(path: input, sampleRate: 16_000)
        progress.update(nil, label: "listening")
        let detection = try await model.identify(samples: samples, sampleRate: 16_000)
        progress.finish()

        // Candidates under 1% are noise on the screen.
        let top = arguments.int("top") ?? 3
        let candidates = Array(detection.candidates.prefix(top).filter { $0.probability >= 0.01 })
        if out.isJSON {
            out.emit(Document(input: input, language: detection.language, confidence: detection.confidence,
                              candidates: candidates.map { Candidate(language: $0.language, probability: $0.probability) }))
            return
        }
        let p = out.palette
        guard let first = candidates.first else {
            out.line(p.dim("no speech to listen to"))
            return
        }
        out.line("\(p.bold(first.language))  \(p.dim(String(format: "%.2f", first.probability)))")
        for c in candidates.dropFirst() {
            out.line(p.dim("\(c.language)  \(String(format: "%.2f", c.probability))"))
        }
    }
}
