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
        case .file, .image:
            guard let path = rawInput else { throw RunError("\(id) needs a file path.") }
            input = path
        }

        try runner.validate(arguments)
        try await ensureDownloaded(runner, out: out)
        out.space()
        try await runner.run(input, arguments: arguments, out: out)
        out.space()
    }

    /// Run a file or image model over several paths, or a folder. One plain path takes
    /// the single-input route above, so its result keeps today's shape; otherwise every
    /// file runs in turn with the model loaded once, `--json` collects the results in
    /// one array, and a file that fails is reported on stderr without stopping the rest.
    static func run(id: String, rawInputs: [String], recursive: Bool, arguments: RunArguments, out: Output) async throws {
        let runner = try resolveRunner(id)
        guard runner.inputKind != .text else {
            throw RunError("\(id) takes text, not files. Pass the text as --input, or pipe it in.")
        }
        let expanded = try Inputs.expand(rawInputs, kind: runner.inputKind, recursive: recursive)
        guard expanded.isBatch else {
            try await run(id: id, rawInput: expanded.files.first, arguments: arguments, out: out)
            return
        }
        // Options that name one input's companion have no meaning across many.
        if arguments["output"] != nil {
            throw RunError("--output names one file. Run one input at a time, or let each output land beside its input.")
        }
        if arguments["transcript"] != nil {
            throw RunError("--transcript belongs to one recording. Run one input at a time.")
        }
        if arguments["format"] != nil {
            throw RunError("--format writes one document to stdout. Pass --json for one array, or run one input at a time.")
        }
        try runner.validate(arguments)

        try await ensureDownloaded(runner, out: out)
        // A skipped file is a note, so --quiet drops it; a failed file below is not.
        if !expanded.skipped.isEmpty, !out.options.quiet {
            let shown = expanded.skipped.prefix(5).joined(separator: ", ")
            let more = expanded.skipped.count > 5 ? ", and \(expanded.skipped.count - 5) more" : ""
            if expanded.skipped.count == 1 {
                out.warn("Skipped \(shown), \(runner.inputKind.rejected).")
            } else {
                out.warn("Skipped \(expanded.skipped.count) files, \(runner.inputKind.rejected): \(shown)\(more).")
            }
        }

        let batch = Batch()
        var each = out
        each.batch = batch
        each.indent = "  "
        let p = out.palette
        var failed: [String] = []
        out.space()
        for (i, file) in expanded.files.enumerated() {
            out.line("\(p.bold(file))  \(p.dim("\(i + 1)/\(expanded.files.count)"))")
            do {
                try await runner.run(file, arguments: arguments, out: each)
            } catch {
                failed.append(file)
                let text = message(of: error)
                out.warn(text.contains(file) ? text : "\(file): \(text)")
            }
            if i + 1 < expanded.files.count { out.line() }
        }
        if out.isJSON { out.emit(batch.all) }
        out.space()
        if !failed.isEmpty {
            throw RunError("\(failed.count) of \(expanded.files.count) files failed. The messages are above.")
        }
    }

    /// The same text the CLI prints for the error on a single run.
    private static func message(of error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription { return text }
        return String(describing: error)
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
