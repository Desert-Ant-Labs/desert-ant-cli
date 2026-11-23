import Foundation
import Redact

// Redact: personal data replaced with restorable placeholders.

struct RedactRunner: ModelRunner {
    let id = "redact"
    let inputKind = RunInputKind.text
    let options = [
        RunOption(name: "min-confidence", help: "Redact only what scores above this confidence, from 0 to 1. Default 0.6."),
    ]

    private let model = Redact()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Result: Encodable {
        let redacted: String
        let items: [Item]
        let notes: [String]?
    }
    struct Item: Encodable {
        let label: String
        let original: String
        let placeholder: String
        let confidence: Double
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        // `Options` is module-level in Redact; the class shadows the module name, so
        // `Redact.Options` does not resolve.
        var opts = Options()
        if let min = arguments.double("min-confidence") { opts.minimumConfidence = min }
        let redaction = try await model.redaction(of: input, options: opts)
        let notes = Advice.notes(for: id, text: input)
        if out.isJSON {
            out.emit(Result(
                redacted: redaction.redactedText,
                items: redaction.items.map {
                    Item(label: $0.label.rawValue, original: $0.original,
                         placeholder: $0.placeholder, confidence: $0.confidence)
                },
                notes: notes.isEmpty ? nil : notes
            ))
        } else {
            out.line(redaction.redactedText)
            notes.forEach(out.note)
        }
    }
}
