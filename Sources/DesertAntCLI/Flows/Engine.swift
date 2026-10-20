import Foundation

/// What the command line hands the flow's input step.
enum Binding: Sendable {
    case paths([String])
    case text(String)

    var paths: [String] {
        if case .paths(let p) = self { p } else { [] }
    }
}

struct FlowOptions: Sendable {
    var outputDir: String?
    var force = false
    /// Lets rename and copy steps touch the files they were given.
    var apply = false
    /// `--set step.param=value`, by step.
    var sets: [String: Params] = [:]
}

/// One flow run: the files it wrote and the values it shows, its scratch folder, and
/// the models it shares with the other runs of the same command.
final class FlowRun: @unchecked Sendable {
    let flow: Flow
    let binding: Binding?
    let options: FlowOptions
    let models: FlowModels
    let temp: URL
    let progress: Progress
    private let lock = NSLock()
    private var written: [String] = []
    private var shownValues: [(step: String, value: Value, text: [String])] = []

    init(flow: Flow, binding: Binding?, options: FlowOptions, models: FlowModels, progress: Progress) throws {
        self.flow = flow
        self.binding = binding
        self.options = options
        self.models = models
        self.progress = progress
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("desertant-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: temp) }

    /// The input the run is about, for naming what it writes.
    var firstInput: String? { binding?.paths.first }

    /// Where outputs go unless a step names a folder of its own: `--output-dir`, else
    /// beside the first input, else the current folder.
    var outputRoot: URL {
        if let dir = options.outputDir { return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath) }
        if let first = firstInput { return URL(fileURLWithPath: first).deletingLastPathComponent() }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func wrote(_ path: String) { lock.withLock { written.append(path) } }
    var files: [String] { lock.withLock { written } }

    func show(_ step: String, _ value: Value, text: [String]) { lock.withLock { shownValues.append((step, value, text)) } }
    var shown: [(step: String, value: Value, text: [String])] { lock.withLock { shownValues } }
}

/// What a step sees of the run while it works.
final class StepContext: @unchecked Sendable {
    let run: FlowRun
    let step: FlowStep
    let position: Int
    private let lock = NSLock()
    private var remark: String?
    private var items: Int?

    init(run: FlowRun, step: FlowStep, position: Int) {
        self.run = run
        self.step = step
        self.position = position
    }

    /// The command line's paths or text, when this is the flow's input step.
    var bound: Binding? { run.flow.input?.id == step.id ? run.binding : nil }

    var note: String? {
        get { lock.withLock { remark } }
        set { lock.withLock { remark = newValue } }
    }

    var count: Int? {
        get { lock.withLock { items } }
        set { lock.withLock { items = newValue } }
    }

    /// `step 2 of 6, voz: transcribing`.
    func progress(_ label: String? = nil, _ fraction: Double? = nil) {
        let total = run.flow.steps.count
        run.progress.update(fraction, label: "step \(position) of \(total), \(step.id)" + (label.map { ": \($0)" } ?? ""))
    }

    /// A fresh path in the run's scratch folder, keeping `name` as the file's name.
    func scratch(_ name: String) throws -> URL {
        let folder = run.temp.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }
}

struct FlowReport: Encodable {
    struct Step: Encodable {
        let id: String
        let type: String
        /// done, skipped, or failed.
        let status: String
        let ms: Int?
        let note: String?
    }

    let flow: String
    let title: String
    let inputs: [String]
    let steps: [Step]
    let outputs: [String: Value]
    let files: [String]

    var failed: [Step] { steps.filter { $0.status == "failed" } }
}

enum Engine {
    /// Runs every step in file order, which is an order where each step comes after
    /// what it uses. A step whose wired input brought nothing is skipped. A step that
    /// fails leaves its outputs empty, so the steps after it are skipped too.
    static func run(_ run: FlowRun, name: String) async -> FlowReport {
        var produced: [String: [String: Value]] = [:]
        var reports: [FlowReport.Step] = []
        for (i, step) in run.flow.steps.enumerated() {
            guard let def = step.def else { continue }
            var inputs: [String: Value] = [:]
            for (handle, wire) in step.uses {
                if let v = produced[wire.step]?[wire.port] { inputs[handle] = v }
            }
            let wired = Set(step.uses.keys)
            let empty = def.anyInput ? !wired.isEmpty && inputs.isEmpty : wired.contains { inputs[$0] == nil }
            if empty || def.inputs.contains(where: { !$0.optional && inputs[$0.id] == nil }) {
                reports.append(.init(id: step.id, type: step.type, status: "skipped", ms: nil, note: nil))
                continue
            }
            let context = StepContext(run: run, step: step, position: i + 1)
            context.progress()
            let params = step.params.merging(run.options.sets[step.id] ?? [:]) { _, set in set }
            let started = Date()
            do {
                let outputs = try await runOne(def, inputs: inputs, params: params, context: context)
                produced[step.id] = spread(def, outputs)
                reports.append(.init(id: step.id, type: step.type, status: "done",
                                     ms: Int(Date().timeIntervalSince(started) * 1000), note: context.note))
            } catch {
                reports.append(.init(id: step.id, type: step.type, status: "failed",
                                     ms: Int(Date().timeIntervalSince(started) * 1000), note: message(error)))
            }
        }
        run.progress.finish()
        return FlowReport(
            flow: name, title: run.flow.title, inputs: run.binding?.paths ?? [], steps: reports,
            outputs: Dictionary(run.shown.map { ($0.step, $0.value) }, uniquingKeysWith: { _, last in last }),
            files: run.files)
    }

    /// A stream arriving at an input that takes one value runs the step once per item.
    /// Other stream inputs of the same length are read at the same index, and a hole
    /// stays a hole. One item that fails leaves a hole; the step fails when all do.
    static func runOne(_ def: StepDef, inputs: [String: Value], params: Params, context: StepContext) async throws -> [String: Value] {
        let loop = def.noMap ? nil : def.inputs.first { !$0.list && inputs[$0.id]?.isStream == true }
        guard let loop, case .stream(let items) = inputs[loop.id] else {
            return try await def.run(StepRun(inputs: inputs, params: params, context: context))
        }
        let aligned = def.inputs.filter { p in
            p.id != loop.id && !p.list && inputs[p.id]?.isStream == true && inputs[p.id]!.items.count == items.count
        }
        var results = [[String: Value]?](repeating: nil, count: items.count)
        let todo = items.count { $0 != nil }
        context.count = todo
        var done = 0
        var firstError: Error?
        var failed = 0
        for (i, item) in items.enumerated() {
            guard let item else { continue }
            done += 1
            context.progress("\(done) of \(todo)", Double(done - 1) / Double(todo))
            var one = inputs
            one[loop.id] = item
            for p in aligned { one[p.id] = inputs[p.id]!.items[i] }
            do {
                results[i] = try await def.run(StepRun(inputs: one, params: params, context: context))
            } catch {
                firstError = firstError ?? error
                failed += 1
            }
        }
        if let firstError, !results.contains(where: { $0 != nil }) { throw firstError }
        if let firstError, failed > 0 { context.note = "\(failed) of \(todo) items failed. The first: \(message(firstError))" }
        var outputs: [String: Value] = [:]
        for port in def.outputs {
            outputs[port.id] = .stream(results.map { $0?[port.id] })
        }
        return outputs
    }

    /// A list output marked `each` goes on item by item.
    static func spread(_ def: StepDef, _ outputs: [String: Value]) -> [String: Value] {
        var out = outputs
        for port in def.outputs where port.each {
            if case .list(let items) = outputs[port.id] { out[port.id] = .stream(items) }
        }
        return out
    }

    static func message(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription { return text }
        return String(describing: error)
    }
}

/// The models a command loads, each once, shared by every run and every item.
actor FlowModels {
    private var loaded: [String: any Sendable] = [:]

    func model<T: Sendable>(_ key: String, make: () throws -> T) rethrows -> T {
        if let m = loaded[key] as? T { return m }
        let m = try make()
        loaded[key] = m
        return m
    }
}
