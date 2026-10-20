import XCTest
@testable import DesertAntCLI

final class FlowEngineTests: XCTestCase {
    private func run(_ yaml: String, binding: Binding? = nil, options: FlowOptions = FlowOptions()) async throws -> (FlowReport, FlowRun) {
        let flow = try FlowFile.read(yaml)
        XCTAssertEqual(flow.problems, [])
        let progress = Progress(palette: Palette.resolve(noColor: true, json: true), quiet: true)
        let run = try FlowRun(flow: flow, binding: binding, options: options, models: FlowModels(), progress: progress)
        return (await Engine.run(run, name: "test"), run)
    }

    private func context() throws -> StepContext {
        let flow = try FlowFile.read("flow: 1\nsteps:\n  - type: text")
        let progress = Progress(palette: Palette.resolve(noColor: true, json: true), quiet: true)
        let run = try FlowRun(flow: flow, binding: nil, options: FlowOptions(), models: FlowModels(), progress: progress)
        return StepContext(run: run, step: flow.steps[0], position: 1)
    }

    /// Doubles a number, and fails on 3.
    private let double = StepDef(
        type: "double", summary: "", category: .logic,
        inputs: [Port(id: "n", type: .any), Port(id: "label", type: .any, optional: true)],
        outputs: [Port(id: "n", type: .any), Port(id: "label", type: .any)]
    ) { run in
        let n = run.inputs["n"]?.asNumber ?? 0
        if n == 3 { throw StepError("three") }
        return ["n": .number(n * 2), "label": run.inputs["label"] ?? .text("")]
    }

    func testAStreamRunsTheStepOncePerItemAndKeepsHoles() async throws {
        let out = try await Engine.runOne(double, inputs: ["n": .stream([.number(1), nil, .number(2)])], params: [:], context: context())
        XCTAssertEqual(out["n"]?.items.map { $0?.asNumber }, [2, nil, 4])
        XCTAssertTrue(out["n"]?.isStream ?? false)
    }

    func testStreamsOfTheSameLengthAreReadTogether() async throws {
        let out = try await Engine.runOne(double, inputs: [
            "n": .stream([.number(1), .number(2)]),
            "label": .stream([.text("a"), .text("b")]),
        ], params: [:], context: context())
        XCTAssertEqual(out["label"]?.items.map { $0?.asText }, ["a", "b"])
    }

    func testAFailedItemLeavesAHoleAndANote() async throws {
        let ctx = try context()
        let out = try await Engine.runOne(double, inputs: ["n": .stream([.number(1), .number(3), .number(4)])], params: [:], context: ctx)
        XCTAssertEqual(out["n"]?.items.map { $0?.asNumber }, [2, nil, 8])
        XCTAssertEqual(ctx.note, "1 of 3 items failed. The first error was three")
    }

    func testTheStepFailsWhenEveryItemFails() async throws {
        do {
            _ = try await Engine.runOne(double, inputs: ["n": .stream([.number(3), nil])], params: [:], context: context())
            XCTFail("expected the step to fail")
        } catch {
            XCTAssertEqual("\(error)", "three")
        }
    }

    func testAListOutputMarkedEachGoesOnItemByItem() {
        let spread = Engine.spread(InputSteps.text, ["text": .text("A. B."), "lines": .list([.text("A. B.")])])
        XCTAssertTrue(spread["lines"]?.isStream ?? false)
        XCTAssertFalse(spread["text"]?.isStream ?? true)
    }

    func testAFlowRunsInOrderAndShowsWhatViewsShow() async throws {
        let (report, run) = try await run("""
        flow: 1
        steps:
          - type: textlist
            with: { items: [one, two] }
          - type: view
        """)
        XCTAssertEqual(report.steps.map(\.status), ["done", "done"])
        XCTAssertEqual(run.shown.first?.text, ["one", "two"])
        XCTAssertEqual(report.outputs["view"]?.items.map { $0?.asText }, ["one", "two"])
    }

    func testAnEmptyWiredInputSkipsTheStep() async throws {
        // An empty list of items gives the textlist step no output at all.
        let (report, _) = try await run("""
        flow: 1
        steps:
          - type: textlist
            with: { items: [" "] }
          - type: view
        """)
        XCTAssertEqual(report.steps.map(\.status), ["done", "skipped"])
    }

    func testTheBindingFillsTheInputStep() async throws {
        let (report, _) = try await run("flow: 1\nsteps:\n  - type: text\n  - type: view", binding: .text("From stdin."))
        XCTAssertEqual(report.outputs["view"]?.asText, "From stdin.")
    }

    func testSetChangesASettingForTheRun() async throws {
        var options = FlowOptions()
        options.sets = ["text": ["text": .string("Set.")]]
        let (report, _) = try await run("flow: 1\nsteps:\n  - { type: text, with: { text: Own. } }\n  - type: view", options: options)
        XCTAssertEqual(report.outputs["view"]?.asText, "Set.")
    }

    func testAFailedStepSkipsWhatComesAfter() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("flow-\(UUID().uuidString)")
        let (report, _) = try await run("flow: 1\nsteps:\n  - type: text\n  - type: view", binding: .paths([dir.appendingPathComponent("missing.txt").path]))
        XCTAssertEqual(report.steps.map(\.status), ["failed", "skipped"])
        XCTAssertTrue(report.steps[0].note?.hasPrefix("no file at") ?? false)
    }

    func testValuesEncodeMediaAsObjects() throws {
        let value = Value.record([("clip", .video("/a/b.mp4")), ("n", .number(2)), ("x", .number(0.5)), ("gone", .list([nil, .text("t")]))])
        XCTAssertEqual(value.json(pretty: false), #"{"clip":{"video":"/a/b.mp4"},"gone":[null,"t"],"n":2,"x":0.5}"#)
    }

    func testSentencesSplitWithoutNaturalLanguage() {
        let pieces = Segment.sentences("It works. Does it? Yes! \"Quoted.\" Then 3 more.\nNew line").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertEqual(pieces, ["It works.", "Does it?", "Yes!", "\"Quoted.\"", "Then 3 more.", "New line"])
    }
}
