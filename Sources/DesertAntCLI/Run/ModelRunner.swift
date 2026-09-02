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

    /// Whether the weights are on disk already.
    func isDownloaded() -> Bool
    /// Fetch and verify the weights, reporting progress 0...1.
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws

    /// Run the model. `input` is the text or the file path; `arguments` carries the
    /// `--option k=v` pairs and verb flags. The adapter writes its own result through `out`.
    func run(_ input: String, arguments: RunArguments, out: Output) async throws
}

extension ModelRunner {
    var options: [RunOption] { [] }
    var emits: String? { nil }
    var accepts: [Intake] { [] }
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
