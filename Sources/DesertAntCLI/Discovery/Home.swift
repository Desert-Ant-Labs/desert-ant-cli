import ArgumentParser

// `desertant` on its own: what you can do on this machine, built from the registry
// and each verb's own help so the screen cannot drift from the commands.

struct Home: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "home",
        abstract: "What you can do on this machine.",
        shouldDisplay: false
    )

    @OptionGroup var options: GlobalOptions

    struct Entry: Encodable {
        let command: String
        let input: String
        let does: String
    }

    /// The verbs with a runner on this machine, in the order the root lists them.
    static func verbs() -> [Entry] {
        DesertAnt.configuration.subcommands.compactMap { type in
            let c = type.configuration
            guard let name = c.commandName, let runner = Runners.runner(for: name) else { return nil }
            return Entry(command: name, input: runner.inputKind == .file ? "<file>" : "\"<text>\"", does: c.abstract)
        }
    }

    func run() async throws {
        let out = Output(options: options)
        let verbs = Self.verbs()
        if out.isJSON {
            out.emit(verbs)
            return
        }

        Brand.header(out)
        let p = out.palette
        let me = Invocation.name
        let others: [(String, String)] = [
            ("models", "the models on this machine, --all for the catalog"),
            ("info <model>", "a model's card"),
            ("docs", "the docs, offline; docs pipelines for how commands fit"),
            ("--help", "every command and flag"),
        ]
        let keys = verbs.map { "\(me) \($0.command) \($0.input)" } + others.map { "\(me) \($0.0)" }
        let keyWidth = (keys.map(\.count).max() ?? 0) + 2
        let width = min(Terminal.columns, 110) - 2
        let indent = "  "

        // Verbs grouped by what they take.
        let groups: [(String, String)] = [("Text", "\"<text>\""), ("Recordings", "<file>")]
        for (label, input) in groups {
            let members = verbs.filter { $0.input == input }
            guard !members.isEmpty else { continue }
            out.line(p.faint(label))
            for entry in members {
                let key = "\(me) \(entry.command) \(entry.input)"
                let painted = "\(me) \(p.model(entry.command)) \(p.faint(entry.input))"
                let lines = column(key, keyWidth: keyWidth, text: entry.does, width: width, palette: p,
                                   keyStyle: { _ in painted + String(repeating: " ", count: keyWidth - key.count) })
                for line in lines { out.line(indent + line) }
            }
            out.line()
        }

        out.line(p.faint("Chain"))
        out.line(indent + "\(me) \(p.model("voz")) talk.mp4 --json | \(me) \(p.model("clips")) talk.mp4 --transcript -")
        out.line(indent + p.dim("transcribe once, then cut"))
        out.line()

        out.line(p.faint("Help"))
        for (i, other) in others.enumerated() {
            let key = keys[verbs.count + i]
            for line in column(key, keyWidth: keyWidth, text: other.1, width: width, palette: p) {
                out.line(indent + p.dim(line))
            }
        }
        out.line()
        out.line(p.faint("\(me) \(Version.cli), desert-ant-core \(Version.core)"))
        if let notice = await UpdateCheck.notice(interactive: p.enabled) { out.line(p.faint(notice)) }
        out.line()
    }
}
