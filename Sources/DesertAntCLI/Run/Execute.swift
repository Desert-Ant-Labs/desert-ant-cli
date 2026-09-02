import Foundation

// Shared execution: resolve the input, make sure the weights are present, run.

enum Execute {
    /// Run a model by id. `rawInput` is the argument the user gave (text or a path),
    /// or nil to fall back to stdin for a text model. Downloads the weights first if
    /// they are missing, with live progress on stderr.
    static func run(id: String, rawInput: String?, arguments: RunArguments, out: Output) async throws {
        let runner = try resolveRunner(id)

        let input: String
        switch runner.inputKind {
        case .text:
            guard let text = rawInput ?? readStdin() else {
                throw RunError("\(id) needs text. Pass it as an argument or pipe it in.")
            }
            input = text
        case .file:
            guard let path = rawInput else { throw RunError("\(id) needs a file path.") }
            input = path
        }

        try await ensureDownloaded(runner, out: out)
        out.space()
        try await runner.run(input, arguments: arguments, out: out)
        out.space()
    }

    /// The runner for an id, or a message that says why there is none.
    static func resolveRunner(_ id: String) throws -> any ModelRunner {
        if let runner = Runners.runner(for: id) { return runner }
        if Manifest.shared.model(id) != nil {
            throw RunError("\(id) has no runner on this platform. `desertant info \(id)` shows where it runs.")
        }
        throw RunError("no model named \(id). Try `desertant models`.")
    }

    /// Download the weights if they are not on disk, showing progress on stderr.
    static func ensureDownloaded(_ runner: any ModelRunner, out: Output) async throws {
        guard !runner.isDownloaded() else { return }
        let progress = Progress(palette: out.palette, quiet: out.options.quiet)
        try await runner.download { fraction in progress.update(fraction, label: "downloading \(runner.id)") }
        progress.finish()
    }
}
