import ArgumentParser

// `desertant schema`. The tool catalog for a coding agent: every shipping model, its
// input and options, the global flags, and the exit codes. The Claude, Codex, and Pi
// adapters under integrations/ point at it. Every fact comes from the manifest or the
// runners, so the schema cannot drift from what the CLI does.

struct Schema: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Print the tool catalog for agents, as JSON."
    )

    @OptionGroup var options: GlobalOptions

    struct Catalog: Encodable {
        let tool: String
        let version: String
        let coreVersion: String
        let invocation: String
        let folders: String
        let composition: String
        let flows: String
        let globalFlags: [Flag]
        let exitCodes: [Code]
        let models: [Entry]
        let flowSteps: [FlowStepEntry]
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
    struct FlowStepEntry: Encodable {
        let type: String
        let summary: String
        let category: StepCategory
        let model: String?
        let inputs: [FlowPort]
        let outputs: [FlowPort]
        /// Each setting and its default; null where it has none.
        let settings: [String: Param]
        let runsHere: Bool
    }
    struct FlowPort: Encodable {
        let id: String
        let type: PortType
        /// Takes a whole list at once.
        let list: Bool?
        let optional: Bool?
        /// A list that goes on item by item.
        let each: Bool?
    }
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
            folders: "A file or image verb takes several paths, or a folder (--recursive walks its folders). The --json result is then an array of the single-file documents, in order. A file that fails is left out and its message goes to stderr. The exit code is 1 after the rest have run.",
            composition: "A command whose `emits` matches another's `accepts.kind` feeds it: pass the --json output as a file through that option, or `-` to read it from stdin. desertant docs pipelines explains the rest.",
            flows: "A flow file chains steps in YAML: `flow: 1`, then `steps`, each with a `type`, an optional `id`, `uses` mapping its inputs to earlier outputs as step.output, and `with` for its settings. `flowSteps` lists the types. `desertant flow run <file> <inputs>` runs a flow, and `desertant docs flows` explains the rest.",
            globalFlags: [
                Flag(flag: "--json", help: "Print the result as JSON, for scripts and agents."),
                Flag(flag: "--quiet", help: "Print only the result, without headings, notes, or progress."),
                Flag(flag: "--no-color", help: "Print without color, even on a terminal."),
            ],
            exitCodes: [
                Code(code: 0, meaning: "success"),
                Code(code: 1, meaning: "runtime error, message on stderr"),
                Code(code: 64, meaning: "usage error, message on stderr"),
            ],
            models: entries,
            flowSteps: Steps.all.map { d in
                FlowStepEntry(
                    type: d.type, summary: d.summary, category: d.category, model: d.model,
                    inputs: d.inputs.map { FlowPort(id: $0.id, type: $0.type, list: $0.list ? true : nil, optional: $0.optional ? true : nil, each: nil) },
                    outputs: d.outputs.map { FlowPort(id: $0.id, type: $0.type, list: nil, optional: nil, each: $0.each ? true : nil) },
                    settings: d.defaults, runsHere: d.unavailable == nil)
            }
        )

        // The catalog is JSON whether or not --json is set: it exists to be parsed.
        Output(options: options).emit(catalog)
    }
}
