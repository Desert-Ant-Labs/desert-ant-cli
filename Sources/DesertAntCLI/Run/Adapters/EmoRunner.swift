import Emo

// Emo: emoji suggestions for a line of text.

struct EmoRunner: ModelRunner {
    let id = "emo"
    let inputKind = RunInputKind.text
    let options = [RunOption(name: "limit", help: "How many emoji to suggest. Default 3.")]

    private let model = Emo()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Suggestion: Encodable {
        let emoji: String
        let confidence: Double
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        let limit = arguments.int("limit") ?? 3
        let suggestions = try await model.suggestions(for: input, limit: limit)
        if out.isJSON {
            out.emit(suggestions.map { Suggestion(emoji: $0.emoji, confidence: $0.confidence) })
        } else {
            out.line(suggestions.map(\.emoji).joined(separator: " "))
        }
    }
}
