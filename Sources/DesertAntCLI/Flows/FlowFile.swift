import Foundation
import Yams

/// An output of an earlier step, as `uses` names it: `voz.words`.
struct Wire: Hashable, Sendable {
    let step: String
    let port: String

    var text: String { "\(step).\(port)" }
}

struct FlowStep: Sendable {
    let id: String
    let type: String
    /// The id was written in the file, not taken from the type.
    let named: Bool
    /// The settings as written.
    var with: Params
    /// Every input's source, by input port.
    var uses: [String: Wire]
    /// The inputs wired by the reader rather than by the file.
    var implied: Set<String>

    var def: StepDef? { Steps.byType[type] }

    /// The settings with the step's defaults under them.
    var params: Params { (def?.defaults ?? [:]).merging(with) { _, given in given } }
}

/// Something that keeps a flow from running here, by step.
struct FlowProblem: Sendable, Equatable {
    let step: String?
    let message: String
}

struct Flow: Sendable {
    var title = ""
    var description = ""
    var summary = ""
    var steps: [FlowStep] = []
    var problems: [FlowProblem] = []

    func step(_ id: String) -> FlowStep? { steps.first { $0.id == id } }

    /// The step that takes the paths on the command line: the first input step.
    var input: FlowStep? { steps.first { $0.def?.category == .input } }
}

enum FlowFile {
    static let header = "# A desertant flow. `desertant docs flows` explains the format.\n"

    /// Hours of transcribed words stay well under these. YAML can repeat a part by
    /// name, so a few lines can stand for billions of values; the count stops long
    /// before that.
    static let maxBytes = 8 << 20
    static let maxValues = 1_000_000

    struct ReadError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func read(_ text: String) throws -> Flow {
        guard text.utf8.count <= maxBytes else { throw ReadError("the flow file is over 8MB.") }
        let tree: Yams.Node?
        do {
            tree = try Yams.compose(yaml: text)
        } catch {
            throw ReadError("the flow file is not valid YAML: \(error)")
        }
        guard let tree, case .mapping(let root) = tree else { throw ReadError("a flow file is a YAML mapping with `flow: 1` and `steps`.") }
        guard count(tree, upTo: maxValues) <= maxValues else { throw ReadError("the flow file holds over a million values.") }
        func field(_ key: String) -> Yams.Node? { root[Yams.Node(key)] }

        guard let version = field("flow") else { throw ReadError("the file has no `flow: 1` line, so it is not a flow file.") }
        guard version.int == 1 else { throw ReadError("this is a version \(version.string ?? "?") flow file, and desertant reads version 1.") }
        guard case .sequence(let list)? = field("steps") else { throw ReadError("the flow file has no list of `steps`.") }

        var flow = Flow()
        flow.title = field("title")?.string ?? ""
        flow.description = field("description")?.string ?? ""
        flow.summary = field("summary")?.string ?? ""

        struct Raw {
            let index: Int
            let id: String?
            let type: String
            let with: Params
            let uses: [(String, String)]
        }
        var raws: [Raw] = []
        for (i, node) in list.enumerated() {
            guard case .mapping(let m) = node else { throw ReadError("step \(i + 1) is not a mapping.") }
            guard let type = m[Yams.Node("type")]?.string, !type.isEmpty else { throw ReadError("step \(i + 1) has no type.") }
            if Steps.ignored.contains(type) { continue }
            var with: Params = [:]
            if case .mapping(let w)? = m[Yams.Node("with")] {
                for (k, v) in w { with[k.string ?? ""] = Param(v) }
            }
            var uses: [(String, String)] = []
            if case .mapping(let u)? = m[Yams.Node("uses")] {
                for (k, v) in u { uses.append((k.string ?? "", v.string ?? "")) }
            }
            let id = m[Yams.Node("id")].flatMap { $0.string }.flatMap { $0.isEmpty ? nil : $0 }
            raws.append(Raw(index: i + 1, id: id, type: type, with: with, uses: uses))
        }

        // A step without an id takes its type, while that type is the only one unnamed.
        let unnamed = Dictionary(grouping: raws.filter { $0.id == nil }, by: \.type)
        for (type, group) in unnamed.sorted(by: { $0.key < $1.key }) where group.count > 1 {
            let positions = group.map { String($0.index) }
            throw ReadError("steps \(list: positions) are \(type) steps without an id. Give all but one of them an id.")
        }
        var seen = Set<String>()
        for raw in raws {
            let id = raw.id ?? raw.type
            guard seen.insert(id).inserted else { throw ReadError("two steps have the id \(id). Each step needs its own.") }
        }

        var earlier: [FlowStep] = []
        for raw in raws {
            let id = raw.id ?? raw.type
            var step = FlowStep(id: id, type: raw.type, named: raw.id != nil, with: raw.with, uses: [:], implied: [])
            let def = step.def
            if let why = Steps.problem(raw.type) {
                flow.problems.append(FlowProblem(step: id, message: "\(id): \(why)."))
            }
            for (handle, source) in raw.uses.sorted(by: { $0.0 < $1.0 }) {
                let parts = source.split(separator: ".", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    throw ReadError("\(id) uses \(handle): \(source). A source is a step id and an output, as voz.words.")
                }
                let wire = Wire(step: parts[0], port: parts[1])
                guard let from = earlier.first(where: { $0.id == wire.step }) else {
                    let later = raws.contains { ($0.id ?? $0.type) == wire.step }
                    throw ReadError(later
                        ? "\(id) uses \(wire.text), and \(wire.step) comes later. A step can only use the steps before it."
                        : "\(id) uses \(wire.text), and the flow has no step \(wire.step).")
                }
                if let def, !def.inputs.contains(where: { $0.id == handle }) {
                    throw ReadError("\(id) has no input \(handle). Its inputs are \(list: def.inputs.map(\.id), or: false).")
                }
                if let fromDef = from.def, !fromDef.outputs.contains(where: { $0.id == wire.port }) {
                    throw ReadError("\(id) uses \(wire.text), and \(from.type) has no output \(wire.port). Its outputs are \(list: fromDef.outputs.map(\.id), or: false).")
                }
                step.uses[handle] = wire
            }
            if let def {
                for port in def.inputs where step.uses[port.id] == nil {
                    switch implied(port, before: earlier) {
                    case .wire(let wire):
                        step.uses[port.id] = wire
                        step.implied.insert(port.id)
                    case .ambiguous(let options):
                        flow.problems.append(FlowProblem(step: id, message:
                            "\(id): its \(port.id) could come from \(list: options.map(\.text)). Name one in `uses`."))
                    case .none:
                        if !port.optional {
                            flow.problems.append(FlowProblem(step: id, message:
                                "\(id): no step before it gives its \(port.id). Add a step that does, or name one in `uses`."))
                        }
                    }
                }
            }
            earlier.append(step)
        }
        flow.steps = earlier
        return flow
    }

    enum Implied: Equatable {
        case wire(Wire)
        case ambiguous([Wire])
        case none
    }

    /// The source of an input the file leaves unwired: the nearest earlier step with an
    /// output of the same name, else for a required input the nearest with an output of
    /// the same type. A step with several outputs of that type gives its first output,
    /// when that is one of them.
    static func implied(_ port: Port, before earlier: [FlowStep], defs: [String: StepDef] = Steps.byType) -> Implied {
        for step in earlier.reversed() {
            guard let def = defs[step.type], let out = def.outputs.first(where: { $0.id == port.id }), out.type.fits(port.type) else { continue }
            return .wire(Wire(step: step.id, port: out.id))
        }
        guard !port.optional else { return .none }
        for step in earlier.reversed() {
            guard let def = defs[step.type] else { continue }
            let fit = def.outputs.filter { port.type == .any || $0.type == port.type }
            if fit.isEmpty { continue }
            if fit.count == 1 { return .wire(Wire(step: step.id, port: fit[0].id)) }
            if let first = def.outputs.first, fit.contains(where: { $0.id == first.id }) {
                return .wire(Wire(step: step.id, port: first.id))
            }
            return .ambiguous(fit.map { Wire(step: step.id, port: $0.id) })
        }
        return .none
    }

    /// How many values a YAML tree holds, each use of a repeated part counted again.
    /// Stops once past `limit`.
    private static func count(_ tree: Yams.Node, upTo limit: Int) -> Int {
        var count = 0
        var stack = [tree]
        while count <= limit, let node = stack.popLast() {
            count += 1
            switch node {
            case .mapping(let m): for pair in m { stack += [pair.key, pair.value] }
            case .sequence(let s): stack += Array(s)
            default: break
            }
        }
        return count
    }

    /// The flow as YAML with every id and wire written out, so any reader opens it.
    static func write(_ flow: Flow) -> String {
        var root: [(Yams.Node, Yams.Node)] = [(Yams.Node("flow"), Yams.Node("1", Tag(.int)))]
        if !flow.title.isEmpty { root.append((Yams.Node("title"), string(flow.title))) }
        if !flow.description.isEmpty { root.append((Yams.Node("description"), string(flow.description))) }
        if !flow.summary.isEmpty { root.append((Yams.Node("summary"), string(flow.summary))) }
        root.append((Yams.Node("steps"), .sequence(.init(flow.steps.map(step)))))
        let yaml = (try? Yams.serialize(node: .mapping(.init(root)), width: 100, allowUnicode: true)) ?? ""
        return header + yaml
    }

    private static func step(_ s: FlowStep) -> Yams.Node {
        var pairs: [(Yams.Node, Yams.Node)] = [(Yams.Node("id"), string(s.id)), (Yams.Node("type"), string(s.type))]
        if !s.uses.isEmpty {
            pairs.append((Yams.Node("uses"), .mapping(.init(s.uses.keys.sorted().map { (Yams.Node($0), string(s.uses[$0]!.text)) }))))
        }
        let settings = s.params.filter {
            if case .null = $0.value { return false }
            return !$0.key.hasPrefix("_")
        }
        if !settings.isEmpty {
            pairs.append((Yams.Node("with"), .mapping(.init(settings.keys.sorted().map { (Yams.Node($0), node(settings[$0]!)) }))))
        }
        return .mapping(.init(pairs))
    }

    /// Text that YAML would read back as something else, a number or a flag, is quoted.
    private static func string(_ s: String) -> Yams.Node {
        if s.contains("\n") { return Yams.Node(s, Tag(.str), .literal) }
        return Yams.Node(s, Tag(.str), Yams.Node(s).tag == Tag(.str) ? .any : .doubleQuoted)
    }

    private static func node(_ p: Param) -> Yams.Node {
        switch p {
        case .null: Yams.Node("null", Tag(.null))
        case .bool(let b): Yams.Node(b ? "true" : "false", Tag(.bool))
        case .number(let n): Yams.Node(n.whole.map(String.init) ?? String(n), Tag(n.whole == nil ? .float : .int))
        case .string(let s): string(s)
        case .array(let a): .sequence(.init(a.map(node)))
        case .object(let o): .mapping(.init(o.keys.sorted().map { (Yams.Node($0), node(o[$0]!)) }))
        }
    }
}

extension DefaultStringInterpolation {
    /// "1, 2, and 3", or with `or`, "1, 2, or 3".
    mutating func appendInterpolation(list items: [String], or: Bool = false) {
        let last = or ? "or" : "and"
        switch items.count {
        case 0: appendLiteral("")
        case 1: appendLiteral(items[0])
        case 2: appendLiteral("\(items[0]) \(last) \(items[1])")
        default: appendLiteral(items.dropLast().joined(separator: ", ") + ", \(last) " + items.last!)
        }
    }
}
