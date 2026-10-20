import ArgumentParser

// `desertant run <model>` and `desertant pull <model>`. The uniform shape for scripts
// and agents; the per-model verbs reach the same executor.

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run any model by its id, with the same flags for every model.",
        discussion: "`desertant schema` lists each model's options."
    )

    @Argument(help: "The model id, such as emo.")
    var model: String

    @Option(name: .long, help: "Text for a text model. Without it, desertant reads stdin.")
    var input: String?

    @Option(name: .long, help: "A file for an audio, video, or image model, or a folder of them. Pass --file once per file.")
    var file: [String] = []

    @Flag(help: "Also include the files in subfolders.")
    var recursive = false

    @Option(name: .customLong("option"), help: "A model option as key=value. Pass --option once per option.")
    var options: [String] = []

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        if file.isEmpty {
            try await Execute.run(id: model, rawInput: input,
                                  arguments: RunArguments(options), out: Output(options: global))
        } else {
            try await Execute.run(id: model, rawInputs: file, recursive: recursive,
                                  arguments: RunArguments(options), out: Output(options: global))
        }
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
