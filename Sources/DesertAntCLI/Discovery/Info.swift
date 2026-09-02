import ArgumentParser

// `desertant info <model>`. The model card: what it is, how it runs, where its
// weights live, its state on this machine, and how to reach it.

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show one model's card."
    )

    @Argument(help: "The model id, e.g. emo.")
    var model: String

    @OptionGroup var options: GlobalOptions

    struct Card: Encodable {
        let id: String
        let name: String
        let tagline: String
        let summary: String
        let category: String
        let group: String
        let lifecycle: String
        let runtime: [String]
        let platforms: [String]
        let languages: Int?
        let variants: [String]
        let weightsRepo: String?
        let weightsRevision: String?
        let weightsURL: String?
        let demo: String?
        let sdks: [String: String]
        let runnableHere: Bool
        let downloaded: Bool?
    }

    func run() throws {
        let out = Output(options: options)
        guard let m = Manifest.shared.model(model) else {
            throw ValidationError("No model named \(model). Try `desertant models`.")
        }
        let runner = Runners.runner(for: m.id)
        let downloaded = runner?.isDownloaded()

        if out.isJSON {
            let sdks = m.sdks.compactMapValues { $0.status == .live ? $0.package : nil }
            out.emit(Card(
                id: m.id, name: m.name, tagline: m.tagline, summary: m.summary,
                category: m.category, group: Group.of(m).rawValue, lifecycle: m.lifecycle.rawValue,
                runtime: m.runtime.map(\.rawValue), platforms: m.swiftPlatforms.map(\.rawValue),
                languages: m.languages?.count, variants: m.variants.map(\.id),
                weightsRepo: m.weights.repo, weightsRevision: m.weights.revision,
                weightsURL: m.weights.url, demo: m.demo?.page, sdks: sdks,
                runnableHere: runner != nil, downloaded: downloaded
            ))
            return
        }

        let p = out.palette
        let width = min(Terminal.columns, 80)
        out.line()
        out.line(p.model(m.id))
        out.line(p.dim(m.tagline))
        out.line()
        for line in wrap(m.summary, width: width) { out.line(line) }
        out.line()

        func field(_ label: String, _ value: String) {
            out.line("  \(p.dim(label.padding(toLength: 11, withPad: " ", startingAt: 0)))\(value)")
        }
        field("category", m.category)
        field("lifecycle", m.lifecycle.rawValue)
        field("runtime", m.runtime.map(\.label).joined(separator: ", "))
        if !m.swiftPlatforms.isEmpty {
            field("platform", m.swiftPlatforms.map(\.rawValue).joined(separator: ", "))
        }
        if let langs = m.languages?.count { field("languages", "\(langs)") }
        if !m.variants.isEmpty {
            field("variants", m.variants.map { $0.default ? "\($0.id) (default)" : $0.id }
                .joined(separator: ", "))
        }
        if let repo = m.weights.repo, let rev = m.weights.revision {
            field("weights", "\(repo) @ \(rev)")
        }
        if let demo = m.demo?.page { field("demo", demo) }

        // State on this machine.
        out.line()
        if let runner {
            let state = downloaded == true ? p.accent("downloaded") : p.dim("not downloaded yet, fetched on first run")
            field("machine", state)
            field("run", "desertant \(m.id) \(runner.inputKind == .file ? "<file>" : "\"<text>\"")")
        } else if m.ships {
            field("machine", p.dim("no runner on this platform"))
        } else {
            field("machine", p.dim("no SDK ships this model yet, ask us about early access"))
        }
        if let pkg = m.swift?.package, m.swift?.status == .live {
            field("swift", "import \(pkg)")
        }
        out.line()
    }
}
