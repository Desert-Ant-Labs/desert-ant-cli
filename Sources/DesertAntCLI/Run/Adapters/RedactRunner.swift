#if canImport(CoreML)
import CoreML
#endif
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

    /// Redact's Core ML export finds names on the Neural Engine only. Without it, the SDK
    /// falls back to pattern matches and reports no error. Linux runs the LiteRT export,
    /// which finds names everywhere.
    static let offNeuralEngine: Bool = {
        #if canImport(CoreML)
        switch ProcessInfo.processInfo.environment["DAL_COREML_COMPUTE_UNITS"] {
        case "cpu", "cpuOnly", "cpuAndGPU": return true
        default:
            return !MLModel.availableComputeDevices.contains { device in
                if case .neuralEngine = device { return true }
                return false
            }
        }
        #else
        return false
        #endif
    }()

    func isDownloaded() -> Bool { model.isDownloaded() }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws {
        try await model.download(progress: progress)
    }

    struct Result: Encodable {
        let redacted: String
        let items: [Item]
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
        if Self.offNeuralEngine {
            out.warn("Redact runs without the Neural Engine on this Mac, so it does not detect names, addresses, or cities. Emails, cards, and IBANs are still redacted.")
        }
        let redaction = try await model.redaction(of: input, options: opts)
        if out.isJSON {
            out.emit(Result(
                redacted: redaction.redactedText,
                items: redaction.items.map {
                    Item(label: $0.label.rawValue, original: $0.original,
                         placeholder: $0.placeholder, confidence: $0.confidence)
                }
            ))
        } else {
            out.line(redaction.redactedText)
        }
    }
}
