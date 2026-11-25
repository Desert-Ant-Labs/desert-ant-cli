import Foundation

enum PortType: String, Sendable, Encodable {
    case text, audio, image, any

    func fits(_ input: PortType) -> Bool {
        self == input || self == .any || input == .any
    }
}

struct Port: Sendable {
    let id: String
    let type: PortType
    var list = false
    var optional = false
    var each = false
}

enum StepCategory: String, Sendable, Encodable {
    case input, model, logic, output
}

struct StepDef: Sendable {
    let type: String
    let summary: String
    let category: StepCategory
    var model: String? = nil
    var inputs: [Port] = []
    /// The first is the one an input wired by type takes when several fit.
    var outputs: [Port] = []
    var defaults: Params = [:]
    var noMap = false
    var anyInput = false
    var unavailable: String? = nil
    let run: @Sendable (StepRun) async throws -> [String: Value]
}

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

    static let ignored: Set<String> = ["note"]

    static func problem(_ type: String) -> String? {
        if let def = byType[type] { return def.unavailable }
        return "desertant has no \(type) step"
    }
}
