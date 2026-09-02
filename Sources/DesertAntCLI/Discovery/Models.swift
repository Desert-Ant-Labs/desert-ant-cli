import ArgumentParser

// `desertant models` (alias `ls`). The models this CLI runs on this machine, one
// paragraph each. `--all` adds the rest of the catalog with a tag saying why each is
// out of the list.

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List the models you can run on this machine.",
        aliases: ["ls"]
    )

    @Option(name: .long, help: "Only one hub: audio, text, or vision.")
    var group: Group?

    @Flag(name: .long, help: "Every model in the catalog, with why each isn't runnable on this machine.")
    var all = false

    @OptionGroup var options: GlobalOptions

    /// A model row as it leaves the process under --json.
    struct Row: Encodable {
        let id: String
        let name: String
        let tagline: String
        let summary: String
        let category: String
        let group: String
        let lifecycle: String
        let runtime: [String]
        let platforms: [String]
        let ships: Bool
        let runnableHere: Bool
    }

    /// Why a model is out of the default list, or nil when it runs on this machine.
    private func tag(_ m: Model) -> String? {
        if Runners.runner(for: m.id) != nil { return nil }
        if !m.ships { return "closed beta" }
        if let reason = Runners.excluded[m.id] { return reason }
        return m.swiftPlatforms == [.apple] && !Doctor.hasCoreML ? "Apple platforms only" : "not in the CLI yet"
    }

    private func selected() -> [Model] {
        Manifest.shared.byID.filter { m in
            if let group, Group.of(m) != group { return false }
            return all || tag(m) == nil
        }
    }

    func run() throws {
        let out = Output(options: options)
        let models = selected()

        if out.isJSON {
            out.emit(models.map { m in
                Row(id: m.id, name: m.name, tagline: m.tagline, summary: m.summary,
                    category: m.category, group: Group.of(m).rawValue,
                    lifecycle: m.lifecycle.rawValue, runtime: m.runtime.map(\.rawValue),
                    platforms: m.swiftPlatforms.map(\.rawValue), ships: m.ships,
                    runnableHere: Runners.runner(for: m.id) != nil)
            })
            return
        }

        Brand.header(out)
        let p = out.palette
        let idWidth = models.map(\.id.count).max() ?? 0
        let width = min(Terminal.columns, 100)

        // A model that does not run on this machine is set in dim, its reason last.
        for m in models {
            let tag = tag(m)
            let lines = column(m.id, keyWidth: idWidth, text: m.summary, width: width, tag: tag,
                               palette: p, keyStyle: { tag == nil ? p.model($0) : p.dim($0) })
            for line in lines { out.line(tag == nil ? line : p.dim(line)) }
        }

        let me = Invocation.name
        let hints = [("\(me) info <model>", "the model's card"), ("\(me) <model>", "run it")]
            + (all ? [] : [("\(me) models --all", "the whole catalog")])
        let hintWidth = (hints.map(\.0.count).max() ?? 0) + 4
        out.line()
        for (key, what) in hints {
            out.line(p.dim(key.padding(toLength: hintWidth, withPad: " ", startingAt: 0) + what))
        }
    }
}
