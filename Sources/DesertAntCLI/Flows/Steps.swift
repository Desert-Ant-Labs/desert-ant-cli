import Foundation

/// What a port carries. `any` fits everything; a video travels on an `audio` port.
enum PortType: String, Sendable, Encodable {
    case text, audio, image, any

    func fits(_ input: PortType) -> Bool {
        self == input || self == .any || input == .any
    }
}

struct Port: Sendable {
    let id: String
    let type: PortType
    /// Takes a whole list at once rather than running once per item.
    var list = false
    /// May be left unwired.
    var optional = false
    /// A list that goes on item by item: a step after it that takes one item runs
    /// once per item, and one that takes a list gets them all.
    var each = false
}

enum StepCategory: String, Sendable, Encodable {
    case input, model, logic, output
}

/// A kind of step: its ports, its settings, and how it runs.
struct StepDef: Sendable {
    let type: String
    let summary: String
    let category: StepCategory
    /// The manifest id of the model the step loads.
    var model: String? = nil
    var inputs: [Port] = []
    var outputs: [Port] = []
    var defaults: Params = [:]
    /// The output an input wired by type takes when a step has several that fit.
    var primary: String? = nil
    /// Takes a stream whole instead of running once per item.
    var noMap = false
    /// Runs when either of its inputs brings something.
    var anyInput = false
    /// Why the step does not run on this platform, if it does not.
    var unavailable: String? = nil
    let run: @Sendable (StepRun) async throws -> [String: Value]

    var primaryOutput: String? { primary ?? outputs.first?.id }
}

/// What one run of one step gets.
struct StepRun: Sendable {
    var inputs: [String: Value]
    var params: Params
    let context: StepContext
}

struct StepError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum Steps {
    static let all: [StepDef] = InputSteps.all + ModelSteps.all + PhotoSteps.all + LogicSteps.all + OutputSteps.all + FileSteps.all

    static let byType: [String: StepDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.type, $0) })

    /// Steps a flow file can hold that need a screen, a microphone, a person, or a
    /// clock, with what each does.
    static let elsewhere: [String: String] = [
        "sketch": "draws with a pointer",
        "whiteboard": "draws with a pointer",
        "shapes": "turns pen strokes into shapes",
        "cleanboard": "draws shapes on a board",
        "gallery": "shows photos in a grid",
        "speak": "reads text aloud",
        "ask": "waits for a person to answer",
        "record": "records from the microphone",
        "call": "records calls as they happen",
        "schedule": "runs the flow at set times",
        "shortcut": "runs the flow from a key press",
    ]

    /// Comments on the canvas. They hold nothing to run, so a run passes over them.
    static let ignored: Set<String> = ["note"]

    /// Why a step of this type cannot run here, or nil when it can.
    static func problem(_ type: String) -> String? {
        if let def = byType[type] { return def.unavailable }
        if let what = elsewhere[type] { return "the \(type) step \(what), which desertant does not do" }
        return "desertant has no \(type) step"
    }
}
