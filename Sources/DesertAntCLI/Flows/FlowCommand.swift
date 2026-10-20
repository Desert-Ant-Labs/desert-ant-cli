import ArgumentParser
import Foundation

struct FlowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flow",
        abstract: "Run flow files, which chain models step by step.",
        discussion: """
        A flow file lists steps in YAML: an input, models, logic, and outputs. Start from a \
        template with `flow templates` and `flow new`, check a file with `flow check`, and run \
        it on your files with `flow run`. `desertant docs flows` explains the format.
        """,
        subcommands: [FlowRunCommand.self, FlowTemplatesCommand.self, FlowShowCommand.self, FlowNewCommand.self, FlowCheckCommand.self]
    )
}

/// A flow named on the command line: a file, or failing that a template.
struct FlowSource {
    let name: String
    let yaml: String
    let template: Bool

    static func load(_ argument: String) throws -> FlowSource {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: argument, isDirectory: &isDir), !isDir.boolValue {
            guard let text = try? String(contentsOfFile: argument, encoding: .utf8) else {
                throw RunError("could not read \(argument) as UTF-8 text.")
            }
            return FlowSource(name: argument, yaml: text, template: false)
        }
        if let t = Templates.named(argument) { return FlowSource(name: t.name, yaml: t.yaml, template: true) }
        throw RunError("no flow file or template named \(argument). `desertant flow templates` lists the templates.")
    }

    func flow() throws -> Flow {
        do {
            return try FlowFile.read(yaml)
        } catch let error as FlowFile.ReadError {
            throw RunError("\(name): \(error.description)")
        }
    }
}

enum Templates {
    struct Entry {
        let name: String
        let yaml: String

        var flow: Flow? { try? FlowFile.read(yaml) }
    }

    static var all: [Entry] { Embedded.templates.map { Entry(name: $0.name, yaml: $0.yaml) } }

    static func named(_ name: String) -> Entry? {
        let key = name.lowercased().replacingOccurrences(of: ".yml", with: "")
        return all.first { $0.name == key }
    }
}

struct FlowRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a flow file or a template on your files.",
        discussion: """
        Paths fill the flow's input step. A step that takes a list, such as photos or files, \
        gets every path in one run; otherwise the flow runs once per file, with each model \
        loaded once. A text input also reads stdin. What the flow saves goes beside the first \
        input, or into --output-dir, and never replaces a file.
        """)

    @Argument(help: "A flow file, or the name of a template.") var flow: String
    @Argument(help: "The files or folders the flow runs on.") var inputs: [String] = []
    @Option(name: .customLong("output-dir"), help: "Where saved files go. Default: beside the first input.") var outputDir: String?
    @Option(name: .customLong("set"), help: "Change a step's setting for this run, as step.setting=value. Repeatable.") var sets: [String] = []
    @Flag(help: "Let rename and copy steps change files. Without it they print what they would do.") var apply = false
    @Flag(help: "Replace existing files instead of stepping aside to new names.") var force = false
    @Flag(help: "Also take the files in a folder's subfolders.") var recursive = false
    @OptionGroup var global: GlobalOptions

    func run() async throws {
        let out = Output(options: global)
        let source = try FlowSource.load(flow)
        let parsed = try source.flow()
        if !parsed.problems.isEmpty {
            throw RunError("\(source.name) cannot run here:\n" + parsed.problems.map { "  \($0.message)" }.joined(separator: "\n"))
        }
        var options = FlowOptions(outputDir: outputDir, force: force, apply: apply)
        options.sets = try Self.settings(sets, in: parsed)
        let bindings = try self.bindings(parsed, sets: options.sets, out: out)

        for model in Self.models(parsed) {
            try await Execute.ensureDownloaded(Execute.resolveRunner(model), out: out)
        }

        let models = FlowModels()
        var reports: [FlowReport] = []
        out.space()
        for (i, binding) in bindings.enumerated() {
            let progress = Progress(palette: out.palette, quiet: out.options.quiet)
            let run = try FlowRun(flow: parsed, binding: binding, options: options, models: models, progress: progress)
            if bindings.count > 1, let first = binding?.paths.first {
                if i > 0 { out.line() }
                out.line("\(out.palette.bold(first))  \(out.palette.dim("\(i + 1)/\(bindings.count)"))")
            }
            let report = await Engine.run(run, name: source.name)
            reports.append(report)
            show(run, report, out: bindings.count > 1 ? indented(out) : out)
        }
        if out.isJSON {
            if reports.count == 1 { out.emit(reports[0]) } else { out.emit(reports) }
        }
        out.space()
        let failed = reports.reduce(0) { $0 + $1.failed.count }
        if failed > 0 {
            throw RunError("\(failed) step\(failed == 1 ? "" : "s") failed. The messages are above.")
        }
    }

    private func indented(_ out: Output) -> Output {
        var each = out
        each.indent = "  "
        return each
    }

    private func show(_ run: FlowRun, _ report: FlowReport, out: Output) {
        for step in report.failed {
            let note = step.note ?? "no message"
            out.warn("\(step.id) failed: \(note)\(note.hasSuffix(".") ? "" : ".")")
        }
        guard !out.isJSON else { return }
        for (i, shown) in run.shown.enumerated() {
            if i > 0 { out.line() }
            for line in shown.text { out.line(line) }
        }
        let shown = Set(run.shown.flatMap(\.text))
        let files = report.files.filter { !shown.contains($0) }
        if !run.shown.isEmpty, !files.isEmpty { out.line() }
        for file in files { out.line(file) }
        for step in report.steps where step.status == "done" { if let note = step.note { out.note("\(step.id): \(note)") } }
        if run.shown.isEmpty, report.files.isEmpty, report.failed.isEmpty {
            out.note("The flow ran. It has no view, table, or folder step, so it shows and saves nothing.")
        }
    }

    /// `--set clips.count=3` as settings by step, each checked against the step's own.
    static func settings(_ pairs: [String], in flow: Flow) throws -> [String: Params] {
        var sets: [String: Params] = [:]
        for pair in pairs {
            guard let eq = pair.firstIndex(of: "="), let dot = pair[..<eq].firstIndex(of: ".") else {
                throw RunError("--set takes step.setting=value, as clips.count=3, not \(pair).")
            }
            let id = String(pair[..<dot]), key = String(pair[pair.index(after: dot)..<eq])
            guard let step = flow.step(id) else {
                throw RunError("--set \(pair) names step \(id), and the flow has no step \(id). Its steps are \(list: flow.steps.map(\.id)).")
            }
            let known = (step.def?.defaults.keys).map { Array($0).sorted() } ?? []
            guard known.contains(key) else {
                throw RunError(known.isEmpty
                    ? "--set \(pair): the \(step.type) step has no settings."
                    : "--set \(pair): the \(step.type) step has no setting \(key). Its settings are \(list: known).")
            }
            sets[id, default: [:]][key] = Param.parse(String(pair[pair.index(after: eq)...]))
        }
        return sets
    }

    /// One binding per run: every path at once for an input that takes a list, one
    /// path per run otherwise, stdin for a text input, or nil to run on the flow's own
    /// settings.
    func bindings(_ flow: Flow, sets: [String: Params], out: Output) throws -> [Binding?] {
        guard let input = flow.input else {
            if !inputs.isEmpty { throw RunError("this flow has no input step, so it takes no files.") }
            return [nil]
        }
        if inputs.isEmpty {
            let own = input.params.merging(sets[input.id] ?? [:]) { _, set in set }
            let hasOwn = InputSteps.given(own["file"]) != nil || InputSteps.given(own["folder"]) != nil
                || !(own["files"]?.strings ?? []).isEmpty || !(own["folders"]?.strings ?? []).isEmpty
                || !(own["text"]?.string ?? "").isEmpty || !(own["items"]?.strings ?? []).isEmpty
            if hasOwn { return [nil] }
            if ["text", "textlist"].contains(input.type), let text = readStdin() { return [.text(text)] }
            let what = ["text", "textlist"].contains(input.type) ? "text on stdin, or a file" : "a file or a folder"
            let article = "aeiou".contains(input.type.prefix(1)) ? "an" : "a"
            throw RunError("this flow starts with \(article) \(input.type) step. Pass \(what) after the flow's name.")
        }
        let expanded = try Inputs.expand(inputs, extensions: InputSteps.extensions(for: input.type),
                                         noun: input.type == "audio" ? "audio or video" : input.type == "image" || input.type == "photos" ? "image" : "",
                                         recursive: recursive)
        if !expanded.skipped.isEmpty, !out.options.quiet {
            out.warn("Skipped \(expanded.skipped.count) file\(expanded.skipped.count == 1 ? "" : "s") the \(input.type) step does not take: \(expanded.skipped.prefix(5).joined(separator: ", "))\(expanded.skipped.count > 5 ? ", and more" : "").")
        }
        if InputSteps.takesList(input.type) { return [.paths(expanded.files)] }
        return expanded.files.map { .paths([$0]) }
    }

    static func models(_ flow: Flow) -> [String] {
        var seen: [String] = []
        for step in flow.steps {
            if let m = step.def?.model, !seen.contains(m) { seen.append(m) }
        }
        return seen
    }
}

struct FlowTemplatesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "templates", abstract: "List the flow templates in desertant.")
    @OptionGroup var global: GlobalOptions

    struct Entry: Encodable {
        let name: String
        let title: String
        let summary: String
        let steps: [String]
        let runsHere: Bool
    }

    func run() throws {
        let out = Output(options: global)
        let entries = Templates.all.compactMap { t -> Entry? in
            guard let flow = t.flow else { return nil }
            return Entry(name: t.name, title: flow.title, summary: flow.summary, steps: flow.steps.map(\.type), runsHere: flow.problems.isEmpty)
        }
        if out.isJSON {
            out.emit(entries)
            return
        }
        let p = out.palette
        let width = entries.map(\.name.count).max() ?? 0
        out.space()
        for e in entries {
            let name = e.name.padding(toLength: width, withPad: " ", startingAt: 0)
            out.line("\(p.model(name))  \(e.summary)\(e.runsHere ? "" : p.dim("  macOS only"))")
        }
        out.note("\nRun one with `desertant flow run <name> <files>`, or copy one to edit with `desertant flow new <name>`.")
        out.space()
    }
}

struct FlowShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show", abstract: "Print a template's YAML.")
    @Argument(help: "The template's name.") var template: String
    @OptionGroup var global: GlobalOptions

    struct Shown: Encodable {
        let name: String
        let yaml: String
    }

    func run() throws {
        let out = Output(options: global)
        guard let t = Templates.named(template) else {
            throw RunError("no template named \(template). `desertant flow templates` lists them.")
        }
        if out.isJSON {
            out.emit(Shown(name: t.name, yaml: t.yaml))
        } else {
            print(t.yaml.hasSuffix("\n") ? t.yaml : t.yaml + "\n", terminator: "")
        }
    }
}

struct FlowNewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new", abstract: "Copy a template to a flow file you can edit.",
        discussion: "The copy names every step and every wire, and lists each step's settings with their defaults.")
    @Argument(help: "The template's name.") var template: String
    @Argument(help: "Where to write it. Default: <template>.flow in the current folder.") var path: String?
    @Flag(help: "Replace an existing file instead of stepping aside to a new name.") var force = false
    @OptionGroup var global: GlobalOptions

    struct Written: Encodable {
        let template: String
        let file: String
    }

    func run() throws {
        let out = Output(options: global)
        guard let t = Templates.named(template) else {
            throw RunError("no template named \(template). `desertant flow templates` lists them.")
        }
        let flow = try FlowFile.read(t.yaml)
        let wanted = path ?? "\(t.name).flow"
        let file = try Destination.resolve(requested: wanted, default: wanted, input: "", force: force)
        do {
            try FlowFile.write(flow).write(toFile: file, atomically: true, encoding: .utf8)
        } catch {
            throw RunError("could not write \(file): \(error.localizedDescription)")
        }
        if out.isJSON {
            out.emit(Written(template: t.name, file: file))
            return
        }
        out.line(file)
        out.note("Run it with `desertant flow run \(file) <files>`.")
    }
}

struct FlowCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check", abstract: "Check a flow file: its steps, how they connect, and what runs here.",
        discussion: "Exits 1 when a step cannot run on this machine or an input has no source.")
    @Argument(help: "A flow file, or the name of a template.") var flow: String
    @OptionGroup var global: GlobalOptions

    struct Checked: Encodable {
        let flow: String
        let title: String
        let runnable: Bool
        let steps: [Step]
        let problems: [String]
    }
    struct Step: Encodable {
        let id: String
        let type: String
        let uses: [String: String]
        /// The inputs wired by desertant rather than by the file.
        let implied: [String]
        let problem: String?
    }

    func run() throws {
        let out = Output(options: global)
        let source = try FlowSource.load(flow)
        let parsed = try source.flow()
        let steps = parsed.steps.map { s in
            Step(id: s.id, type: s.type, uses: s.uses.mapValues(\.text), implied: s.implied.sorted(),
                 problem: parsed.problems.first { $0.step == s.id }?.message)
        }
        if out.isJSON {
            out.emit(Checked(flow: source.name, title: parsed.title, runnable: parsed.problems.isEmpty,
                             steps: steps, problems: parsed.problems.map(\.message)))
        } else {
            let p = out.palette
            out.space()
            if !parsed.title.isEmpty { out.line(p.bold(parsed.title)) }
            let rows = parsed.steps.map { s -> [String] in
                let wires = s.uses.keys.sorted().map { "\($0) from \(s.uses[$0]!.text)" }
                return [s.id, s.type, wires.joined(separator: ", ")]
            }
            for (row, s) in zip(OutputSteps.align(rows), parsed.steps) {
                out.line(Steps.problem(s.type) == nil ? row : p.dim(row))
            }
            if !parsed.steps.flatMap(\.implied).isEmpty {
                out.note("\nInputs without `uses` take the nearest earlier output of the same name, else of the same type.")
            }
            if !parsed.problems.isEmpty {
                out.line()
                for problem in parsed.problems { out.line(problem.message) }
            }
            out.space()
        }
        if !parsed.problems.isEmpty {
            throw RunError("\(source.name) cannot run here. The steps above say why.")
        }
    }
}
