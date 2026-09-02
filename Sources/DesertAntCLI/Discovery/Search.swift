import ArgumentParser

// `desertant search <query>`. Matches a query against id, name, tagline, summary,
// category, and Hub tags.

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Find a model by name, task, or tag."
    )

    @Argument(help: "What to look for.")
    var query: String

    @OptionGroup var options: GlobalOptions

    struct Hit: Encodable {
        let id: String
        let name: String
        let tagline: String
        let summary: String
    }

    func run() throws {
        let out = Output(options: options)
        let needle = query.lowercased()
        let hits = Manifest.shared.byID.filter { $0.searchHaystack.contains(needle) }

        if out.isJSON {
            out.emit(hits.map { Hit(id: $0.id, name: $0.name, tagline: $0.tagline, summary: $0.summary) })
            return
        }

        let p = out.palette
        guard !hits.isEmpty else {
            out.line("No model matches \(p.bold(query)).")
            out.note("`desertant models --all` lists the whole catalog.")
            return
        }
        out.line()
        for m in hits {
            out.line(p.model(m.id))
            out.line("  \(m.tagline)")
        }
        out.note("\n\(hits.count) of \(Manifest.shared.models.count) models match.")
    }
}
