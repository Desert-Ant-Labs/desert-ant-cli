import Gist

// Gist: what a passage of text is about, from a 36-topic taxonomy.

struct GistRunner: ModelRunner {
    let id = "gist"
    let inputKind = RunInputKind.text
    let options = [RunOption(name: "top", help: "How many topics to return. Default 3.")]

    private let model = Gist()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Topic: Encodable {
        let slug: String
        let name: String
        let score: Double
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        let topK = arguments.int("top") ?? 3
        let topics = try await model.classify(input, topK: topK)
        if out.isJSON {
            out.emit(topics.map { Topic(slug: $0.slug, name: $0.name, score: $0.score) })
        } else {
            for t in topics {
                out.line("\(t.name)  \(out.palette.dim(String(format: "%.2f", t.score)))")
            }
        }
    }
}
