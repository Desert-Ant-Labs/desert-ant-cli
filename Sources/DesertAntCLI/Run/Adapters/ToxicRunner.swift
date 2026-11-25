import Toxic

// The flow steps cannot import Toxic: its Options clashes with Redact's.
typealias ToxicClassifier = Toxic

struct ToxicRunner: ModelRunner {
    let id = "toxic"
    let inputKind = RunInputKind.text

    private let model = Toxic()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Document: Encodable {
        let toxic: Bool
        let flags: [String]
        let targets: [String]
        let scores: [String: Double]
        let thresholds: [String: Double]
        let notes: [String]?
    }

    static func name(_ label: Label) -> String {
        switch label {
        case .nationalOrEthnicOrigin: "national or ethnic origin"
        case .sexualOrientation: "sexual orientation"
        default: label.rawValue.lowercased()
        }
    }

    static func check(_ text: String, with model: ToxicClassifier) async throws -> (toxic: Bool, flags: [String], targets: [String]) {
        let result = try await model.analyze(text)
        return (result.isToxic, result.content.map(name), result.targets.map(name))
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        let result = try await model.analyze(input)
        let notes = Advice.notes(for: id, text: input)
        if out.isJSON {
            func keyed(_ values: [Label: Double]) -> [String: Double] {
                Dictionary(uniqueKeysWithValues: values.map { ("\($0.key)", $0.value) })
            }
            out.emit(Document(
                toxic: result.isToxic,
                flags: result.content.map { "\($0)" },
                targets: result.targets.map { "\($0)" },
                scores: keyed(result.scores),
                thresholds: keyed(result.thresholds),
                notes: notes.isEmpty ? nil : notes))
            return
        }
        let p = out.palette
        let scored = { (label: Label) in "\(Self.name(label)) \(String(format: "%.2f", result.score(label)))" }
        out.line(result.isToxic ? "\(p.accent("toxic"))  \(result.content.map(Self.name).joined(separator: ", "))" : p.bold("clean"))
        out.line(p.dim(Label.content.map(scored).joined(separator: "  ")))
        if !result.targets.isEmpty {
            out.line(p.dim("targets " + result.targets.map(scored).joined(separator: "  ")))
        }
        notes.forEach(out.note)
    }
}
