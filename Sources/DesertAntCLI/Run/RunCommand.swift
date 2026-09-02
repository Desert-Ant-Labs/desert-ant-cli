import ArgumentParser

// `desertant run <model>` and `desertant pull <model>`. The uniform shape for scripts
// and agents; the per-model verbs reach the same executor.

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run any model uniformly, for scripts and agents.",
        discussion: "Options per model are listed by `desertant schema`."
    )

    @Argument(help: "The model id, e.g. emo.")
    var model: String

    @Option(name: .long, help: "Text input for a text model. Omit to read stdin.")
    var input: String?

    @Option(name: .long, help: "File path for an audio or video model.")
    var file: String?

    @Option(name: .customLong("option"), help: "A k=v option, repeatable.")
    var options: [String] = []

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        try await Execute.run(id: model, rawInput: input ?? file,
                              arguments: RunArguments(options), out: Output(options: global))
    }
}

struct Pull: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Download a model's weights to the cache."
    )

    @Argument(help: "The model id.")
    var model: String

    @OptionGroup var global: GlobalOptions

    struct Report: Encodable {
        let model: String
        let downloaded: Bool
    }

    func run() async throws {
        let out = Output(options: global)
        let runner = try Execute.resolveRunner(model)
        let already = runner.isDownloaded()
        if !already {
            try await Execute.ensureDownloaded(runner, out: out)
        }
        if out.isJSON {
            out.emit(Report(model: runner.id, downloaded: true))
        } else if already {
            out.line("\(out.palette.dim("ready"))  \(runner.id) was already downloaded.")
        } else {
            out.line("\(out.palette.accent("ready"))  \(runner.id) is downloaded.")
        }
    }
}
