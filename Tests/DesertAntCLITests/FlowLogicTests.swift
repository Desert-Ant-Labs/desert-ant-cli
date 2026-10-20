import XCTest
@testable import DesertAntCLI

final class FlowLogicTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("flow-logic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func context(_ type: String, options: FlowOptions = FlowOptions(), binding: Binding? = nil) throws -> StepContext {
        let flow = try FlowFile.read("flow: 1\nsteps:\n  - type: textlist\n  - { type: \(type), uses: {} }")
        let progress = Progress(palette: Palette.resolve(noColor: true, json: true), quiet: true)
        let run = try FlowRun(flow: flow, binding: binding, options: options, models: FlowModels(), progress: progress)
        return StepContext(run: run, step: flow.steps[1], position: 2)
    }

    private func run(_ def: StepDef, _ inputs: [String: Value], _ params: Params = [:], context: StepContext? = nil) async throws -> [String: Value] {
        try await Engine.runOne(def, inputs: inputs, params: def.defaults.merging(params) { $1 }, context: context ?? self.context(def.type))
    }

    private func texts(_ v: Value?) -> [String?] { (v?.items ?? []).map { $0?.asText } }

    func testConditions() {
        XCTAssertTrue(Condition.equals.test(.text("EN"), "en"))
        XCTAssertTrue(Condition.oneOf.test(.text("fr"), "en, fr"))
        XCTAssertTrue(Condition.contains.test(.text("Receipt photo"), "receipt"))
        XCTAssertTrue(Condition.above.test(.number(0.7), "0.5"))
        XCTAssertFalse(Condition.below.test(.text("n/a"), "0.5"))
        XCTAssertTrue(Condition.truthy.test(.bool(true), ""))
        XCTAssertTrue(Condition.falsy.test(.text("false"), ""))
        XCTAssertTrue(Condition.empty.test(.number(0), ""))
        XCTAssertFalse(Condition.truthy.test(nil, ""))
    }

    func testIfSplitsAStreamAndMergeJoinsItAligned() async throws {
        let values: Value = .stream([.text("a"), .text("b"), nil, .text("d")])
        let tests: Value = .stream([.text("en"), .text("fr"), nil, .text("en")])
        let split = try await run(LogicSteps.ifElse, ["value": values, "test": tests], ["operand": "en"])
        XCTAssertEqual(texts(split["yes"]), ["a", nil, nil, "d"])
        XCTAssertEqual(texts(split["no"]), [nil, "b", nil, nil])
        let merged = try await run(LogicSteps.merge, ["a": split["yes"]!, "b": split["no"]!])
        XCTAssertEqual(texts(merged["value"]), ["a", "b", nil, "d"])
        let single = try await run(LogicSteps.ifElse, ["value": .text("x")], ["op": "empty"])
        XCTAssertEqual(single["no"]?.asText, "x")
        XCTAssertNil(single["yes"])
    }

    func testListOperations() {
        let items: [Value?] = [.text("b"), .text("a"), nil, .text("b"), .text("c")]
        XCTAssertEqual(ListOp.count.run(items, n: 0, by: nil)?.asNumber, 4)
        XCTAssertEqual(ListOp.sort.run(items, n: 0, by: nil)?.items.map { $0?.asText }, ["a", "b", "b", "c"])
        XCTAssertEqual(ListOp.most.run(items, n: 1, by: nil)?.items.map { $0?.asText }, ["b"])
        XCTAssertEqual(ListOp.unique.run(items, n: 0, by: nil)?.items.map { $0?.asText }, ["b", "a", "c"])
        XCTAssertEqual(ListOp.item.run(items, n: 2, by: nil)?.asText, "a")
        XCTAssertNil(ListOp.item.run(items, n: 9, by: nil))
        let scores: [Value?] = [.number(0.2), .number(0.9), nil, .number(0.5), .number(0.1)]
        XCTAssertEqual(ListOp.desc.run(items, n: 2, by: scores)?.items.map { $0?.asText }, ["a", "b"])
    }

    func testBestPicksTheHighestScoreAndSkipsHoles() async throws {
        let out = try await run(LogicSteps.best, ["items": .stream([.text("x"), nil, .text("z")]),
                                                  "scores": .stream([.number(0.3), .number(0.9), .number(0.5)])])
        XCTAssertEqual(out["best"]?.asText, "z")
        XCTAssertEqual(out["score"]?.asNumber, 0.5)
    }

    func testConvertWritesTextAndTables() async throws {
        let ctx = try context("convert")
        let text = try await run(LogicSteps.convert, ["value": .text("# Notes\nline")], ["to": "md"], context: ctx)
        guard case .file(let path)? = text["file"] else { return XCTFail("expected a file") }
        XCTAssertTrue(path.hasSuffix("Notes.md"), path)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "# Notes\nline")
        let table = try await run(LogicSteps.convert, ["value": .list([.record([("a", .number(1))])])], context: ctx)
        XCTAssertEqual(table["file"]?.path.map { try? String(contentsOfFile: $0, encoding: .utf8) }, "a\n1\n")
        do {
            _ = try await run(LogicSteps.convert, ["value": .text("x")], ["to": "png"], context: ctx)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue("\(error)".contains("text converts to txt or md"), "\(error)")
        }
    }

    // MARK: Files

    private func touch(_ name: String, _ contents: String = "x") throws -> String {
        let path = folder.appendingPathComponent(name).path
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testNamesFromAPattern() throws {
        let paths = try (1...10).map { try touch("IMG_\($0).JPG") }
        let names = FileOps.names(for: paths, pattern: "{{a}}-{{n}}", a: paths.map { _ in .text("trip: day 1") })
        XCTAssertEqual(names.first, "trip- day 1-01.jpg")
        XCTAssertEqual(names.last, "trip- day 1-10.jpg")
        XCTAssertEqual(FileOps.names(for: [paths[0], paths[1]], pattern: "same"), ["same.jpg", "same-2.jpg"])
        XCTAssertEqual(FileOps.fill("{{a}}/{{name}}", path: paths[0], a: .text("..")), "IMG_1")
    }

    func testCopyShowsThePlanUntilApplied() async throws {
        let a = try touch("a.jpg"), b = try touch("b.jpg")
        var options = FlowOptions()
        options.outputDir = folder.path
        let dry = try context("copy", options: options)
        _ = try await run(FileSteps.copy, ["files": .list([.image(a), .image(b)]), "a": .list([.text("one"), .text("two")])],
                          ["subfolder": "{{a}}"], context: dry)
        XCTAssertEqual(dry.run.shown.first?.text, ["would copy \(a) to \(folder.path)/one/a.jpg", "would copy \(b) to \(folder.path)/two/b.jpg"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("one").path))

        options.apply = true
        let applied = try context("copy", options: options)
        _ = try await run(FileSteps.copy, ["files": .list([.image(a), .image(b)]), "a": .list([.text("one"), .text("two")])],
                          ["subfolder": "{{a}}"], context: applied)
        XCTAssertEqual(applied.run.files, ["\(folder.path)/one/a.jpg", "\(folder.path)/two/b.jpg"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: a))
    }

    func testApplyNeverOverwritesAndSkipsAnIdenticalCopy() throws {
        let a = try touch("in/a.txt", "new")
        let taken = try touch("out/a.txt", "old")
        XCTAssertEqual(try FileOps.apply([a], to: [taken], .copy), [folder.appendingPathComponent("out/a-2.txt").path])
        XCTAssertEqual(try String(contentsOfFile: taken, encoding: .utf8), "old")
        XCTAssertEqual(try FileOps.apply([a], to: [folder.appendingPathComponent("out/a-2.txt").path], .copy), [])
        let moved = try FileOps.apply([a], to: [folder.appendingPathComponent("moved/z.txt").path], .move)
        XCTAssertEqual(moved, [folder.appendingPathComponent("moved/z.txt").path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: a))
    }

    // MARK: Eye fields

    func testEyeSubjectAndReason() {
        XCTAssertEqual(EyeFields.subject(["Dog": 0.9, "Beach": 0.8, "Drawing": 0.95, "Sky": 0.6]), ["Dog", "Beach"])
        XCTAssertEqual(EyeFields.reason(["keeper": 0.7, "forgettable": 0.9], blur: [:]), "keeper")
        XCTAssertEqual(EyeFields.reason(["keeper": 0.2, "forgettable": 0.9], blur: [:]), "nothing special")
        XCTAssertEqual(EyeFields.reason(["keeper": 0.1, "technical_flaw": 0.95], blur: ["motion": 0.8, "none": 0.2]), "blurry")
    }

    func testJSONBecomesValues() throws {
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"b": [1, true, null], "a": "x"}"#.utf8)).value
        XCTAssertEqual(v?.json(pretty: false), #"{"a":"x","b":[1,true,null]}"#)
        if case .bool? = v?["b"]?.items[1] {} else { XCTFail("true is a bool") }
    }
}
