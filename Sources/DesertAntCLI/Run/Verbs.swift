import ArgumentParser

// The per-model verbs (`desertant emo "..."`), reaching the same executor as `run`.
// A verb's typed flags map onto the names in its runner's `options` list.

struct EmoVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "emo", abstract: Manifest.summary("emo"))
    @Argument(help: "The text. Without it, desertant reads stdin.") var text: String?
    @Option(help: "How many emoji to suggest. Default 3.") var limit: Int?
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
    @Argument(help: "The text. Without it, desertant reads stdin.") var text: String?
    @Option(name: .customLong("min-confidence"), help: "Redact only what scores above this confidence, from 0 to 1. Default 0.6.")
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
    @Argument(help: "The text. Without it, desertant reads stdin.") var text: String?
    @Option(help: "How many topics to list. Default 3.") var top: Int?
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("top", top)
        try await Execute.run(id: "gist", rawInput: text, arguments: args, out: Output(options: global))
    }
}

struct TongueVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tongue", abstract: Manifest.summary("tongue"))
    @Argument(help: "The text. Without it, desertant reads stdin.") var text: String?
    @Option(help: "How many candidate languages to show. Default 3.") var top: Int?
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("top", top)
        try await Execute.run(id: "tongue", rawInput: text, arguments: args, out: Output(options: global))
    }
}

struct ModeratorVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "moderator", abstract: Manifest.summary("moderator"))
    @Argument(help: "The image files, or a folder of them.") var files: [String]
    @Option(help: "Flag an image when its score reaches this value, from 0 to 1. Default 0.5.") var threshold: Double?
    @Option(help: "standard, or allow-topless to allow a bare chest. Default standard.") var policy: String?
    @Option(help: "How many crops Moderator scores: fast, balanced, or accurate. Default accurate.") var quality: String?
    @Flag(help: "Also include the files in subfolders.") var recursive = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("threshold", threshold)
        args.set("policy", policy)
        args.set("quality", quality)
        try await Execute.run(id: "moderator", rawInputs: files, recursive: recursive, arguments: args, out: Output(options: global))
    }
}

struct EyeVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eye", abstract: Manifest.summary("eye"),
        discussion: """
        One photo prints what it is, its scores, its tags, and its faces. Several photos or a folder \
        answer one question together: --has and --not filter, --duplicates groups near-duplicates, \
        --best picks the keeper, --similar-to and --sort rank. A video is sampled into frames: the \
        frame for a thumbnail, the tags that hold, and with --has, the moments that match.
        """)
    @Argument(help: "The photos or videos, or a folder of them.") var files: [String]
    @Option(help: "Keep only the photos with all of these tags, comma-separated, such as \"dog,beach\".") var has: String?
    @Option(help: "Leave out the photos with any of these tags, such as \"blurry,screenshot\".") var not: String?
    @Flag(help: "Count a tag only at confidence 0.9 instead of 0.5. Use it before moving or deleting files.") var strict = false
    @Flag(help: "Group near-duplicate photos, the photo to keep first in each group.") var duplicates = false
    @Flag(help: "Pick the photo to keep from the set.") var best = false
    @Option(name: .customLong("similar-to"), help: "Rank the photos by how alike they are to this photo.") var similarTo: String?
    @Option(help: "Rank the photos by aesthetic, keeper, cover, sharpness, or a tag's confidence.") var sort: String?
    @Option(help: "With --sort or --similar-to, how many photos to list.") var limit: Int?
    @Option(help: "Also write the best crop at this aspect ratio, such as 1:1, 16:9, or 4:5.") var crop: String?
    @Flag(help: "On a video, also write the frame that makes the best thumbnail.") var thumbnail = false
    @Option(help: "On a video, the seconds between the frames Eye analyzes. Default 1, at most 100 frames.") var every: Double?
    @Option(name: .customLong("output-dir"), help: "Where crops and thumbnails go. By default, they go beside the input.") var outputDir: String?
    @Flag(help: "Replace an existing file instead of writing name-2.ext.") var force = false
    @Option(help: "What Eye computes, comma-separated: photo, layout, faces, or sharpness. Default all four.") var parts: String?
    @Option(name: .customLong("max-faces"), help: "The most faces to analyze per photo. Default 20.") var maxFaces: Int?
    @Option(help: "How many tags to print per photo. Default 8.") var tags: Int?
    @Flag(name: .customLong("all-tags"), help: "Put every tag's confidence in the JSON.") var allTags = false
    @Flag(help: "Put the 512-number embedding in the JSON.") var embedding = false
    @Flag(help: "Also include the files in subfolders.") var recursive = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("has", has)
        args.set("not", not)
        args.set("strict", strict ? "true" : nil)
        args.set("duplicates", duplicates ? "true" : nil)
        args.set("best", best ? "true" : nil)
        args.set("similar-to", similarTo)
        args.set("sort", sort)
        args.set("limit", limit)
        args.set("crop", crop)
        args.set("thumbnail", thumbnail ? "true" : nil)
        args.set("every", every)
        args.set("output-dir", outputDir)
        args.set("force", force ? "true" : nil)
        args.set("parts", parts)
        args.set("max-faces", maxFaces)
        args.set("tags", tags)
        args.set("all-tags", allTags ? "true" : nil)
        args.set("embedding", embedding ? "true" : nil)
        try await Execute.run(id: "eye", rawInputs: files, recursive: recursive, arguments: args, out: Output(options: global))
    }
}

#if TITLE
struct TitleVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "title", abstract: Manifest.summary("title"))
    @Argument(help: "The text. Without it, desertant reads stdin.") var text: String?
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        try await Execute.run(id: "title", rawInput: text, arguments: RunArguments(), out: Output(options: global))
    }
}
#endif

struct VozVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "voz", abstract: Manifest.summary("voz"))
    @Argument(help: "The audio or video files, or a folder of them.") var files: [String]
    @Flag(name: [.short, .long], help: "Print a time before each sentence.") var timestamps = false
    @Flag(help: "Also write captions as <input>.srt beside the input.") var srt = false
    @Flag(help: "Also write captions as <input>.vtt beside the input.") var vtt = false
    @Flag(help: "Also write the transcript as <input>.txt beside the input.") var txt = false
    @Option(name: [.short, .long], help: "Write one file at this path. Its extension sets the format: srt, vtt, txt, or json.")
    var output: String?
    @Option(help: "The format to print: text, srt, vtt, txt, or json. Default text.") var format: String?
    @Flag(help: "Replace an existing file instead of writing name-2.ext.") var force = false
    @Flag(help: "Label each line with its speaker, using Who.") var speakers = false
    @Option(help: "With --speakers, names in the order the speakers first speak, such as \"Anna,Ben\".") var names: String?
    @Flag(help: "Also include the files in subfolders.") var recursive = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("speakers", speakers ? "true" : nil)
        args.set("names", names)
        args.set("timestamps", timestamps ? "true" : nil)
        args.set("srt", srt ? "true" : nil)
        args.set("vtt", vtt ? "true" : nil)
        args.set("txt", txt ? "true" : nil)
        args.set("output", output)
        args.set("format", format)
        args.set("force", force ? "true" : nil)
        try await Execute.run(id: "voz", rawInputs: files, recursive: recursive, arguments: args, out: Output(options: global))
    }
}

struct UhmVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uhm", abstract: Manifest.summary("uhm"))
    @Argument(help: "The audio or video files, or a folder of them.") var files: [String]
    @Flag(help: "Also include the files in subfolders.") var recursive = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        try await Execute.run(id: "uhm", rawInputs: files, recursive: recursive, arguments: RunArguments(), out: Output(options: global))
    }
}

struct EarVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ear", abstract: Manifest.summary("ear"))
    @Argument(help: "The audio or video files, or a folder of them.") var files: [String]
    @Option(help: "How many candidate languages to show. Default 3.") var top: Int?
    @Flag(help: "Also include the files in subfolders.") var recursive = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("top", top)
        try await Execute.run(id: "ear", rawInputs: files, recursive: recursive, arguments: args, out: Output(options: global))
    }
}

struct WhoVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "who", abstract: Manifest.summary("who"),
        discussion: "Prints each speaker's time and the turns. Pass a transcript to label it line by line, or run `voz --speakers` to transcribe and label in one go.")
    @Argument(help: "The audio or video files, or a folder of them.") var files: [String]
    @Option(help: "Names for the speakers in the order they first speak, such as \"Anna,Ben\".") var names: String?
    @Option(name: .customLong("min-share"), help: "Leave out a voice that takes up less than this share of the recording, from 0 to 1. Default 0.") var minShare: Double?
    @Option(help: "Join a speaker's turns across pauses up to this many seconds. Default 1.") var join: Double?
    @Option(help: "A transcript to label line by line: the --json of voz, or an .srt or .vtt file. Pass - to read it from stdin.") var transcript: String?
    @Option(help: "The format to print: text, json, rttm, and with a transcript, srt, vtt, or txt. Default text.") var format: String?
    @Option(name: [.short, .long], help: "Write one file at this path. Its extension sets the format: rttm, json, and with a transcript, srt, vtt, or txt.")
    var output: String?
    @Flag(help: "Replace an existing file instead of writing name-2.ext.") var force = false
    @Flag(help: "Also include the files in subfolders.") var recursive = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("names", names)
        args.set("min-share", minShare)
        args.set("join", join)
        args.set("transcript", transcript)
        args.set("format", format)
        args.set("output", output)
        args.set("force", force ? "true" : nil)
        try await Execute.run(id: "who", rawInputs: files, recursive: recursive, arguments: args, out: Output(options: global))
    }
}

struct ClipsVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clips", abstract: Manifest.summary("clips"),
        discussion: "Transcribes with Voz, picks the moments with Clips, and writes one file per clip beside the input. Pass a transcript to skip transcribing, or --select-only for timestamps alone. --captions burn draws the words into each clip, styled with the --caption options.")
    @Argument(help: "The video or audio files, or a folder of them.") var files: [String]
    @Option(help: "How many clips to look for. By default, Clips sizes the search to the recording.") var count: Int?
    @Option(name: .customLong("output-dir"), help: "Where the clip files go. By default, they go beside the input.") var outputDir: String?
    @Option(help: "An .srt, .vtt, or .json transcript to use instead of transcribing. Pass - to read it from stdin.") var transcript: String?
    @Flag(name: .customLong("select-only"), help: "Report the moments as timestamps without writing files.") var selectOnly = false
    @Flag(help: "Replace existing clip files instead of writing name-2.ext.") var force = false
    @Option(help: "burn draws captions into each clip, srt writes <clip>.srt beside each clip, and off writes none. Default off.") var captions: String?
    @Option(name: .customLong("caption-position"), help: "Where burned captions go: bottom, center, or top. Default bottom.") var captionPosition: String?
    @Option(name: .customLong("caption-align"), help: "How burned caption lines align: left, center, or right. Default center.") var captionAlign: String?
    @Option(name: .customLong("caption-font"), help: "A font family, or a .ttf or .otf file. Default Inclusive Sans, which comes with desertant.") var captionFont: String?
    @Option(name: .customLong("caption-size"), help: "The text's height as a share of the frame's height, such as 0.06. Default 7% of the frame's short side.") var captionSize: String?
    @Option(name: .customLong("caption-weight"), help: "The text's weight: regular, medium, semibold, bold, black, or 100 to 900. Default bold.") var captionWeight: String?
    @Option(name: .customLong("caption-color"), help: "The text's color: a name such as white or yellow, or a hex color such as #ffcc00. Default white.") var captionColor: String?
    @Option(name: .customLong("caption-lines"), help: "Caption lines on screen at once, 1 or 2. Default 1 on a vertical clip and 2 on a square or wide clip.") var captionLines: String?
    @Option(name: .customLong("caption-words"), help: "The most words in one caption. Default 5 on a vertical clip, and as many as fit the line on a square or wide clip.") var captionWords: String?
    @Option(name: .customLong("caption-style"), help: "How the text stands out from the picture: outline, box, or shadow. Default outline.") var captionStyle: String?
    @Option(help: "The video quality of a clip with burned captions: high, medium, or low. Default high. Every level keeps the source's size and frame rate.") var quality: String?
    @Flag(help: "Also include the files in subfolders.") var recursive = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("captions", captions)
        args.set("caption-position", captionPosition)
        args.set("caption-align", captionAlign)
        args.set("caption-font", captionFont)
        args.set("caption-size", captionSize)
        args.set("caption-weight", captionWeight)
        args.set("caption-color", captionColor)
        args.set("caption-style", captionStyle)
        args.set("caption-lines", captionLines)
        args.set("caption-words", captionWords)
        args.set("quality", quality)
        args.set("count", count)
        args.set("output-dir", outputDir)
        args.set("transcript", transcript)
        args.set("select-only", selectOnly ? "true" : nil)
        args.set("force", force ? "true" : nil)
        try await Execute.run(id: "clips", rawInputs: files, recursive: recursive, arguments: args, out: Output(options: global))
    }
}

struct ClearVerb: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear", abstract: Manifest.summary("clear"))
    @Argument(help: "The input files, or a folder of them.") var files: [String]
    @Option(help: "Where to write the result. By default, Clear adds _clear to the input's name.") var output: String?
    @Flag(help: "Replace an existing file instead of writing name-2.ext.") var force = false
    @Flag(help: "Also include the files in subfolders.") var recursive = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        var args = RunArguments()
        args.set("output", output)
        args.set("force", force ? "true" : nil)
        try await Execute.run(id: "clear", rawInputs: files, recursive: recursive, arguments: args, out: Output(options: global))
    }
}
