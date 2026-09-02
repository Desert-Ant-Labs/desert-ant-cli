import ArgumentParser

// The per-model verbs (`desertant emo "..."`), reaching the same executor as `run`.
// A verb's typed flags map onto the names in its runner's `options` list.

struct EmoVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "emo", abstract: Manifest.summary("emo"))
    @Argument(help: "The text. Omit to read stdin.") var text: String?
    @Option(help: "How many to suggest.") var limit: Int?
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("limit", limit)
        try await Execute.run(id: "emo", rawInput: text, arguments: args, out: Output(options: global))
    }
}

struct RedactVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "redact", abstract: Manifest.summary("redact"))
    @Argument(help: "The text. Omit to read stdin.") var text: String?
    @Option(name: .customLong("min-confidence"), help: "Only redact above this confidence, 0...1.")
    var minConfidence: Double?
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("min-confidence", minConfidence)
        try await Execute.run(id: "redact", rawInput: text, arguments: args, out: Output(options: global))
    }
}

struct GistVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gist", abstract: Manifest.summary("gist"))
    @Argument(help: "The text. Omit to read stdin.") var text: String?
    @Option(help: "How many topics.") var top: Int?
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("top", top)
        try await Execute.run(id: "gist", rawInput: text, arguments: args, out: Output(options: global))
    }
}

#if TITLE
struct TitleVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "title", abstract: Manifest.summary("title"))
    @Argument(help: "The text. Omit to read stdin.") var text: String?
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        try await Execute.run(id: "title", rawInput: text, arguments: RunArguments(), out: Output(options: global))
    }
}
#endif

struct VozVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "voz", abstract: Manifest.summary("voz"))
    @Argument(help: "The audio or video file.") var file: String
    @Flag(name: [.short, .long], help: "A time before each sentence.") var timestamps = false
    @Flag(help: "Also write captions as <input>.srt beside the input.") var srt = false
    @Flag(help: "Also write captions as <input>.vtt beside the input.") var vtt = false
    @Flag(help: "Also write the transcript as <input>.txt beside the input.") var txt = false
    @Option(name: [.short, .long], help: "Write one file here; the format comes from its extension: srt, vtt, txt, or json.")
    var output: String?
    @Option(help: "What stdout carries: text, srt, vtt, txt, or json.") var format: String?
    @Flag(help: "Replace an existing file instead of stepping aside.") var force = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("timestamps", timestamps ? "true" : nil)
        args.set("srt", srt ? "true" : nil)
        args.set("vtt", vtt ? "true" : nil)
        args.set("txt", txt ? "true" : nil)
        args.set("output", output)
        args.set("format", format)
        args.set("force", force ? "true" : nil)
        try await Execute.run(id: "voz", rawInput: file, arguments: args, out: Output(options: global))
    }
}

struct UhmVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uhm", abstract: Manifest.summary("uhm"))
    @Argument(help: "The audio or video file.") var file: String
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        try await Execute.run(id: "uhm", rawInput: file, arguments: RunArguments(), out: Output(options: global))
    }
}

struct EarVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ear", abstract: Manifest.summary("ear"))
    @Argument(help: "The audio or video file.") var file: String
    @Option(help: "How many candidate languages to show.") var top: Int?
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("top", top)
        try await Execute.run(id: "ear", rawInput: file, arguments: args, out: Output(options: global))
    }
}

struct ClipsVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clips", abstract: Manifest.summary("clips"),
        discussion: "Transcribes with Voz, picks the moments with Clips, and writes one file per clip beside the input. Pass a transcript to skip transcribing, or --select-only for timestamps alone.")
    @Argument(help: "The video or audio file.") var file: String
    @Option(help: "How many clips to look for. Default: the model sizes it to the recording.") var count: Int?
    @Option(name: .customLong("output-dir"), help: "Where the clip files go. Default: beside the input.") var outputDir: String?
    @Option(help: "An .srt, .vtt, or .json transcript instead of transcribing; `-` reads one from stdin.") var transcript: String?
    @Flag(name: .customLong("select-only"), help: "Report the moments as timestamps without writing files.") var selectOnly = false
    @Flag(help: "Replace existing clip files instead of stepping aside to new names.") var force = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("count", count)
        args.set("output-dir", outputDir)
        args.set("transcript", transcript)
        args.set("select-only", selectOnly ? "true" : nil)
        args.set("force", force ? "true" : nil)
        try await Execute.run(id: "clips", rawInput: file, arguments: args, out: Output(options: global))
    }
}

struct ClearVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear", abstract: Manifest.summary("clear"))
    @Argument(help: "The input file.") var file: String
    @Option(help: "Where to write. Default: the input with a _clear suffix.") var output: String?
    @Flag(help: "Replace an existing output instead of stepping aside to a new name.") var force = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("output", output)
        args.set("force", force ? "true" : nil)
        try await Execute.run(id: "clear", rawInput: file, arguments: args, out: Output(options: global))
    }
}
