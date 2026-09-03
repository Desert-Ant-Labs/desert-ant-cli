import Clear
import Foundation

// Clear: denoise and dereverb an audio or video file, written beside the input.

struct ClearRunner: ModelRunner {
    let id = "clear"
    let inputKind = RunInputKind.file
    let emits: String? = "file"
    let options = [
        RunOption(name: "output", help: "Where to write. Default: the input with a _clear suffix."),
        RunOption(name: "force", help: "Replace an existing output instead of stepping aside to a new name."),
    ]

    private let model = Clear()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Result: Encodable {
        let input: String
        let output: String
        let durationSec: Double
        let processingSec: Double
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        guard FileManager.default.fileExists(atPath: input) else {
            throw RunError("no file at \(input)")
        }
        let output = try Destination.resolve(
            requested: arguments["output"],
            default: Destination.sibling(of: input, suffix: "_clear",
                                         extension: MediaFormat.outputExtension(for: input, hasVideo: false)),
            input: input,
            force: arguments["force"] == "true"
        )

        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        let result = try await model.enhance(path: input, to: output) { p in
            switch p.phase {
            case .loadingModel: progress.update(nil, label: FirstLoad.label("clear"))
            case .analyzing: progress.update(p.fraction, label: "analyzing")
            case .enhancing: progress.update(p.fraction, label: "enhancing")
            }
        }
        progress.finish()
        FirstLoad.done("clear")

        if out.isJSON {
            out.emit(Result(input: input, output: output,
                            durationSec: result.durationSec, processingSec: result.processingSec))
            return
        }
        out.line(output)
        if let note = MediaFormat.changeNote(from: input, to: output) { out.note(note) }
        out.note("\(Format.spoken(result.durationSec)) of audio in \(Format.elapsed(result.processingSec)), "
                 + Format.realtime(material: result.durationSec, elapsed: result.processingSec) + ".")
    }
}
