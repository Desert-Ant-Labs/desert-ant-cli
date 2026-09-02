import ArgumentParser

// `desertant schema`. The tool catalog for a coding agent: every shipping model, its
// input and options, the global flags, and the exit codes. The Claude, Codex, and Pi
// adapters under integrations/ point at it. Every fact comes from the manifest or the
// runners, so the schema cannot drift from what the CLI does.

struct Schema: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Emit the tool catalog for agents, as JSON."
    )

    @OptionGroup var options: GlobalOptions

    struct Catalog: Encodable {
        let tool: String
        let version: String
        let coreVersion: String
        let invocation: String
        let composition: String
        let globalFlags: [Flag]
        let exitCodes: [Code]
        let models: [Entry]
    }
    struct Flag: Encodable { let flag: String; let help: String }
    struct Code: Encodable { let code: Int; let meaning: String }
    struct Entry: Encodable {
        let id: String
        let summary: String
        let verb: String
        let input: String?
        let runnableHere: Bool
        let options: [Opt]
        /// The document kind the --json result is, when another command can read it.
        let emits: String?
        /// Documents this command takes from another, and the option that takes each.
        let accepts: [Accepts]
    }
    struct Opt: Encodable { let name: String; let help: String }
    struct Accepts: Encodable { let kind: String; let option: String }

    func run() throws {
        let entries = Manifest.shared.byID.filter(\.ships).map { m -> Entry in
            let runner = Runners.runner(for: m.id)
            return Entry(
                id: m.id, summary: m.summary, verb: m.id,
                input: runner?.inputKind.rawValue,
                runnableHere: runner != nil,
                options: (runner?.options ?? []).map { Opt(name: $0.name, help: $0.help) },
                emits: runner?.emits,
                accepts: (runner?.accepts ?? []).map { Accepts(kind: $0.kind, option: $0.option) }
            )
        }

        let catalog = Catalog(
            tool: "desertant",
            version: Version.cli,
            coreVersion: Version.core,
            invocation: "desertant <verb> <input> [--json]  |  desertant run <id> --input <text> | --file <path> [--option k=v]",
            composition: "A command whose `emits` matches another's `accepts.kind` feeds it: pass the --json output as a file through that option, or `-` to read it from stdin. desertant docs pipelines explains the rest.",
            globalFlags: [
                Flag(flag: "--json", help: "Machine-readable JSON output."),
                Flag(flag: "--quiet", help: "Result only, no notes or progress."),
                Flag(flag: "--no-color", help: "Never colorize."),
            ],
            exitCodes: [
                Code(code: 0, meaning: "success"),
                Code(code: 1, meaning: "runtime error, message on stderr"),
                Code(code: 64, meaning: "usage error, message on stderr"),
            ],
            models: entries
        )

        // The catalog is JSON whether or not --json is set: it exists to be parsed.
        Output(options: options).emit(catalog)
    }
}
