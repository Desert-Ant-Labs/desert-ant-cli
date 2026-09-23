import Tongue

// Tongue: the language a short text is written in. The model ships inside the SDK,
// so there is nothing to download.

struct TongueRunner: ModelRunner {
    let id = "tongue"
    let inputKind = RunInputKind.text
    let options = [RunOption(name: "top", help: "How many candidate languages to show. Default 3.")]

    func isDownloaded() -> Bool { true }
    func download(_ progress: @escaping @Sendable (Double) -> Void) async throws { progress(1) }

    struct Document: Encodable {
        let language: String?
        let reliability: String
        let tooCloseToCall: Bool
        let candidates: [Candidate]
    }
    struct Candidate: Encodable {
        let language: String
        let probability: Double
    }

    func run(_ input: String, arguments: RunArguments, out: Output) async throws {
        let top = max(arguments.int("top") ?? 3, 1)
        // Loading is a 2MB read from the package bundle, so the runner does not keep one.
        let detection = try Tongue().detect(input, topK: top)
        let candidates = detection.candidates.map { Candidate(language: $0.language, probability: $0.probability) }
        if out.isJSON {
            out.emit(Document(language: detection.language, reliability: detection.reliability.rawValue,
                              tooCloseToCall: detection.isTooCloseToCall, candidates: candidates))
            return
        }
        let p = out.palette
        guard let first = candidates.first else {
            out.line(p.dim("nothing to read"))
            return
        }
        out.line("\(p.bold(first.language))  \(p.dim(String(format: "%.2f", first.probability)))  \(p.dim(detection.reliability.rawValue))")
        for c in candidates.dropFirst() {
            out.line(p.dim("\(c.language)  \(String(format: "%.2f", c.probability))"))
        }
        if detection.isTooCloseToCall, candidates.count > 1 {
            out.note("Too close to call between \(candidates[0].language) and \(candidates[1].language).")
        }
    }
}
