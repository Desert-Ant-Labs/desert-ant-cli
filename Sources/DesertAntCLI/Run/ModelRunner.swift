import Foundation

// The per-model layer. Discovery reads the manifest; running is the one place a
// model's own API shows through, so each model contributes a small runner. A model
// with no runner is still discoverable; `run` says it has no runner on this platform.

/// What a model takes on the command line.
enum RunInputKind: String, Sendable {
    /// A string: read from the argument, or stdin when piped.
    case text
    /// A path to an audio or video file.
    case file
    /// A path to an image file.
    case image
    /// A path to an image or a video file.
    case visual
}

/// One option a runner accepts, e.g. `limit`. Declared once on the runner so the verb,
/// the generic `run --option`, and `schema` all read the same list.
struct RunOption: Sendable {
    let name: String
    let help: String
}

/// A document one command writes and another can read. `schema` publishes the kinds,
/// and an agent plans a chain from them.
struct Intake: Sendable {
    /// The document kind, e.g. "transcript".
    let kind: String
    /// The option that takes it, e.g. "transcript" for `--transcript`. `-` reads stdin.
    let option: String
}

/// One model's command-line adapter.
protocol ModelRunner: Sendable {
    /// The manifest id, e.g. "emo".
    var id: String { get }
    /// Whether the model reads text or a file.
    var inputKind: RunInputKind { get }
    /// The options this runner reads from `RunArguments`. Empty by default.
    var options: [RunOption] { get }
    /// The kind of document the `--json` result is, when another command can read
    /// it: "transcript", "spans", "clips", "file". Nil for a plain result.
    var emits: String? { get }
    /// Documents this runner takes from another command. Empty by default.
    var accepts: [Intake] { get }

    /// Reject bad options before any download or run. Nothing to check by default.
    func validate(_ arguments: RunArguments) throws

    /// Whether the weights are on disk already.
    func isDownloaded() -> Bool
    /// Fetch and verify the weights, reporting progress 0...1.
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws

    /// Run the model. `input` is the text or the file path; `arguments` carries the
    /// `--option k=v` pairs and verb flags. The adapter writes its own result through `out`.
    func run(_ input: String, arguments: RunArguments, out: Output) async throws
}

extension ModelRunner {
    func validate(_ arguments: RunArguments) throws {}
    var options: [RunOption] { [] }
    var emits: String? { nil }
    var accepts: [Intake] { [] }
}

/// A runner that can also answer a question about its inputs together: which photos in
/// a folder are near-duplicates, the best of a burst. With none of those options set, it
/// runs one file at a time like any other runner.
protocol SetRunner: ModelRunner {
    /// Whether these options ask about the inputs together.
    func wantsSet(_ arguments: RunArguments) -> Bool
    /// Run every input, then answer about the set. `inputs` are already expanded;
    /// `batch` is whether they came as several paths or a folder rather than one file.
    func runSet(_ inputs: [String], batch: Bool, arguments: RunArguments, out: Output) async throws
}

/// The parsed options a runner receives: string key-value pairs, with typed readers.
struct RunArguments: Sendable {
    private(set) var values: [String: String] = [:]

    init(_ pairs: [String] = []) {
        for pair in pairs {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            values[String(pair[..<eq]).lowercased()] = String(pair[pair.index(after: eq)...])
        }
    }

    /// Set one value, for a verb mapping its typed flag onto the shared shape.
    mutating func set(_ key: String, _ value: Any?) {
        guard let value else { return }
        values[key.lowercased()] = "\(value)"
    }

    subscript(_ key: String) -> String? { values[key.lowercased()] }
    func int(_ key: String) -> Int? { self[key].flatMap(Int.init) }
    func double(_ key: String) -> Double? { self[key].flatMap(Double.init) }
}

/// Thrown when a runner cannot proceed, with a message the CLI prints plainly.
struct RunError: Error, CustomStringConvertible {
    let description: String
    init(_ m: String) { description = m }
}

extension RunInputKind {
    /// How the input is shown in help and on the home screen.
    var placeholder: String {
        switch self {
        case .text: "\"<text>\""
        case .file: "<file>"
        case .image: "<image>"
        case .visual: "<photo or video>"
        }
    }

    /// What a folder is filtered by, lowercase, no dot.
    var extensions: Set<String> {
        switch self {
        case .text: []
        case .file: ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac", "mp4", "mov", "m4v"]
        case .image: ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]
        case .visual: Self.image.extensions.union(Self.videoExtensions)
        }
    }

    /// The video containers a visual model samples frames from.
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// Whether `path` names a video by its extension.
    static func isVideo(_ path: String) -> Bool {
        videoExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// The files in a folder, in a message: "no audio or video files in ...".
    var noun: String {
        switch self {
        case .text: "text"
        case .file: "audio or video"
        case .image: "image"
        case .visual: "image or video"
        }
    }

    /// Why a file in a folder was skipped: "Skipped notes.txt, not an image."
    var rejected: String {
        switch self {
        case .text: "not text"
        case .file: "not audio or video"
        case .image: "not an image"
        case .visual: "not an image or video"
        }
    }
}
