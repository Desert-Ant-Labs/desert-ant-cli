import XCTest
@testable import DesertAntCLI

final class FlowFileTests: XCTestCase {
    private func read(_ yaml: String) throws -> Flow { try FlowFile.read(yaml) }

    private func error(_ yaml: String) -> String {
        do {
            _ = try FlowFile.read(yaml)
            return ""
        } catch {
            return "\(error)"
        }
    }

    func testVersionIsRequired() {
        XCTAssertTrue(error("steps: []").contains("no `flow: 1`"))
        XCTAssertTrue(error("flow: 2\nsteps: []").contains("version 2"))
        XCTAssertTrue(error("flow: 1").contains("no list of `steps`"))
        XCTAssertTrue(error("- a\n- b").contains("YAML mapping"))
    }

    func testTitleDescriptionAndSummary() throws {
        let flow = try read("flow: 1\ntitle: Notes\ndescription: Long.\nsummary: Short.\nsteps: []")
        XCTAssertEqual(flow.title, "Notes")
        XCTAssertEqual(flow.description, "Long.")
        XCTAssertEqual(flow.summary, "Short.")
    }

    func testDuplicateIdsAreAnError() {
        let e = error("""
        flow: 1
        steps:
          - { id: a, type: text }
          - { id: a, type: view }
        """)
        XCTAssertTrue(e.contains("two steps have the id a"), e)
    }

    func testAStepWithoutAnIdTakesItsType() throws {
        let flow = try read("flow: 1\nsteps:\n  - type: text\n  - type: view")
        XCTAssertEqual(flow.steps.map(\.id), ["text", "view"])
        XCTAssertEqual(flow.steps.map(\.named), [false, false])
    }

    func testARepeatedTypeNeedsAllButOneId() throws {
        let e = error("flow: 1\nsteps:\n  - type: text\n  - type: view\n  - type: view")
        XCTAssertTrue(e.contains("steps 2 and 3 are view steps without an id"), e)
        let flow = try read("flow: 1\nsteps:\n  - type: text\n  - type: view\n  - { id: again, type: view }")
        XCTAssertEqual(flow.steps.map(\.id), ["text", "view", "again"])
    }

    func testAnExplicitIdThatTakesAnotherStepsDefaultIsADuplicate() {
        let e = error("flow: 1\nsteps:\n  - { id: view, type: text }\n  - type: view")
        XCTAssertTrue(e.contains("two steps have the id view"), e)
    }

    func testUsesCanOnlyPointBackward() {
        let forward = error("""
        flow: 1
        steps:
          - { id: show, type: view, uses: { value: in.text } }
          - { id: in, type: text }
        """)
        XCTAssertTrue(forward.contains("in comes later"), forward)
        let unknown = error("flow: 1\nsteps:\n  - { id: show, type: view, uses: { value: nowhere.text } }")
        XCTAssertTrue(unknown.contains("no step nowhere"), unknown)
        let own = error("flow: 1\nsteps:\n  - { id: show, type: view, uses: { value: show.text } }")
        XCTAssertTrue(own.contains("show comes later") || own.contains("no step show"), own)
    }

    func testUsesNamesRealPorts() {
        let input = error("flow: 1\nsteps:\n  - { id: in, type: text }\n  - { id: show, type: view, uses: { what: in.text } }")
        XCTAssertTrue(input.contains("show has no input what"), input)
        let output = error("flow: 1\nsteps:\n  - { id: in, type: text }\n  - { id: show, type: view, uses: { value: in.words } }")
        XCTAssertTrue(output.contains("text has no output words"), output)
        let shape = error("flow: 1\nsteps:\n  - { id: in, type: text }\n  - { id: show, type: view, uses: { value: intext } }")
        XCTAssertTrue(shape.contains("a step id and an output"), shape)
    }

    func testStepsThatCannotRunAreListedTogether() throws {
        let flow = try read("""
        flow: 1
        steps:
          - { id: in, type: photos }
          - { id: odd, type: teleport, uses: { photos: in.photos } }
          - { id: other, type: nosuchstep }
          - { id: words, type: note }
        """)
        XCTAssertEqual(flow.steps.map(\.id), ["in", "odd", "other"])
        XCTAssertEqual(flow.problems.map(\.step), ["odd", "other"])
        XCTAssertEqual(flow.problems[0].message, "odd: desertant has no teleport step.")
    }

    func testTheFileIsCapped() {
        let big = "flow: 1\nsteps: []\n#" + String(repeating: "x", count: FlowFile.maxBytes)
        XCTAssertTrue(error(big).contains("over 8MB"))
        // An alias repeated by name stands for far more values than the text holds.
        var yaml = "flow: 1\nsteps: []\na0: &a0 [x, x, x, x, x, x, x, x, x, x]\n"
        for i in 1...6 { yaml += "a\(i): &a\(i) [" + Array(repeating: "*a\(i - 1)", count: 10).joined(separator: ", ") + "]\n" }
        XCTAssertTrue(error(yaml).contains("over a million values"), error(yaml))
    }

    func testAtIsIgnored() throws {
        let flow = try read("flow: 1\nsteps:\n  - { id: in, type: text, at: [10, 20] }")
        XCTAssertEqual(flow.steps.count, 1)
    }

    // MARK: Implied wiring

    func testAnInputWiresToTheNearestOutputOfTheSameName() throws {
        let flow = try read("""
        flow: 1
        steps:
          - { id: first, type: text }
          - { id: second, type: text }
          - { id: show, type: view }
          - { id: table, type: table, uses: { a: first.text } }
        """)
        XCTAssertEqual(flow.step("show")?.uses["value"], Wire(step: "second", port: "text"))
        XCTAssertEqual(flow.step("show")?.implied, ["value"])
        XCTAssertEqual(flow.step("table")?.implied, [])
    }

    func testFailingAName_AnInputWiresByTypeToThePrimaryOutput() throws {
        // A view's value matches no output by name, and text's outputs are all text.
        let flow = try read("flow: 1\nsteps:\n  - type: text\n  - type: view")
        XCTAssertEqual(flow.step("view")?.uses["value"], Wire(step: "text", port: "text"))
    }

    func testAnOptionalInputWiresByNameOnly() throws {
        let flow = try read("flow: 1\nsteps:\n  - type: text\n  - { type: table, uses: { a: text.lines } }")
        XCTAssertEqual(flow.step("table")?.uses.keys.sorted(), ["a"])
        XCTAssertTrue(flow.problems.isEmpty)
    }

    func testARequiredInputWithNoSourceIsAProblem() throws {
        let flow = try read("flow: 1\nsteps:\n  - type: view")
        XCTAssertEqual(flow.problems.first?.step, "view")
        XCTAssertTrue(flow.problems.first?.message.contains("no step before it gives its value") ?? false)
    }

    func testTwoEquallyNearMatchesAreAProblem() {
        let port = Port(id: "x", type: .text)
        // The registry has no steps like these, so the rule is checked on its own.
        let earlier = [FlowStep(id: "p", type: "pair", named: true, with: [:], uses: [:], implied: [])]
        let firstFits = StepDef(type: "pair", summary: "", category: .logic,
                                outputs: [Port(id: "one", type: .text), Port(id: "two", type: .text)]) { _ in [:] }
        XCTAssertEqual(FlowFile.implied(port, before: earlier, defs: ["pair": firstFits]), .wire(Wire(step: "p", port: "one")))
        let firstDoesNot = StepDef(type: "pair", summary: "", category: .logic,
                                   outputs: [Port(id: "n", type: .any), Port(id: "one", type: .text), Port(id: "two", type: .text)]) { _ in [:] }
        XCTAssertEqual(FlowFile.implied(port, before: earlier, defs: ["pair": firstDoesNot]),
                       .ambiguous([Wire(step: "p", port: "one"), Wire(step: "p", port: "two")]))
    }

    // MARK: Writing

    func testWritingNamesEveryStepAndWire() throws {
        let flow = try read("flow: 1\ntitle: Echo\nsummary: \"Say: it back\"\nsteps:\n  - type: text\n  - type: view")
        let yaml = FlowFile.write(flow)
        XCTAssertTrue(yaml.hasPrefix(FlowFile.header))
        XCTAssertTrue(yaml.contains("- id: view\n  type: view\n  uses:\n    value: text.text"), yaml)
        XCTAssertTrue(yaml.contains("summary: 'Say: it back'") || yaml.contains("summary: \"Say: it back\""), yaml)
        let again = try read(yaml)
        XCTAssertEqual(again.steps.map(\.id), flow.steps.map(\.id))
        XCTAssertEqual(again.step("view")?.uses, flow.step("view")?.uses)
        XCTAssertEqual(again.step("view")?.implied, [])
    }

    func testWritingLeavesOutNullAndPrivateSettings() throws {
        let flow = try read("flow: 1\nsteps:\n  - { type: audio, with: { _seen: 1, file: null, keep: \"0.5\", n: 3 } }")
        let yaml = FlowFile.write(flow)
        XCTAssertFalse(yaml.contains("_seen"))
        XCTAssertFalse(yaml.contains("file:"))
        XCTAssertTrue(yaml.contains("keep: \"0.5\""), yaml)
        XCTAssertTrue(yaml.contains("n: 3"), yaml)
    }

    // MARK: Settings from the command line

    func testSetParsesNumbersFlagsAndText() throws {
        XCTAssertEqual(Param.parse("3"), .number(3))
        XCTAssertEqual(Param.parse("0.5"), .number(0.5))
        XCTAssertEqual(Param.parse("true"), .bool(true))
        XCTAssertEqual(Param.parse("Hello: there"), .string("Hello: there"))
        XCTAssertEqual(Param.parse(""), .string(""))
        let flow = try read("flow: 1\nsteps:\n  - type: text\n  - type: view")
        XCTAssertEqual(try FlowRunCommand.settings(["text.text=Hi"], in: flow), ["text": ["text": .string("Hi")]])
        XCTAssertThrowsError(try FlowRunCommand.settings(["view.limit=3"], in: flow))
        XCTAssertThrowsError(try FlowRunCommand.settings(["nope.text=3"], in: flow))
        XCTAssertThrowsError(try FlowRunCommand.settings(["text=3"], in: flow))
    }
}
