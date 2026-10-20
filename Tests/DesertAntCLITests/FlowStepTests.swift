import Transcript
import XCTest
@testable import DesertAntCLI

final class FlowStepTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("flow-steps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func run(_ yaml: String, binding: Binding? = nil, options: FlowOptions = FlowOptions()) async throws -> (FlowReport, FlowRun) {
        let flow = try FlowFile.read(yaml)
        XCTAssertEqual(flow.problems, [])
        let progress = Progress(palette: Palette.resolve(noColor: true, json: true), quiet: true)
        let run = try FlowRun(flow: flow, binding: binding, options: options, models: FlowModels(), progress: progress)
        return (await Engine.run(run, name: "test"), run)
    }

    /// The context of step `index` of a flow, to run one step on its own.
    private func context(_ yaml: String, step index: Int) throws -> StepContext {
        let flow = try FlowFile.read(yaml)
        let progress = Progress(palette: Palette.resolve(noColor: true, json: true), quiet: true)
        let run = try FlowRun(flow: flow, binding: nil, options: FlowOptions(), models: FlowModels(), progress: progress)
        return StepContext(run: run, step: flow.steps[index], position: index + 1)
    }

    // MARK: Placeholders

    func testTemplatesFillValuesDatesAndLanguageNames() {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let filled = Placeholders.fill("{{a}} in {{b|lang}} on {{date}} at {{time}}, {{zz}}", at: { moment }) { key in
            ["a": "Hello", "b": "fr"][key]
        }
        XCTAssertEqual(filled, "Hello in French on \(Placeholders.stamp("date", moment)) at \(Placeholders.stamp("time", moment)), {{zz}}")
        XCTAssertTrue(Placeholders.stamp("date", moment).contains(#/^\d{4}-\d\d-\d\d$/#))
        XCTAssertTrue(Placeholders.stamp("time", moment).contains(#/^\d\d\.\d\d\.\d\d$/#))
    }

    func testATemplateRunsItemByItemOverAStream() async throws {
        let context = try context("flow: 1\nsteps:\n  - type: template", step: 0)
        let out = try await Engine.runOne(LogicSteps.template, inputs: [
            "a": .stream([.text("one"), nil, .text("three")]), "b": .text("x"),
        ], params: ["template": "{{a}}-{{b}}"], context: context)
        XCTAssertEqual(out["text"]?.items.map { $0?.asText }, ["one-x", nil, "three-x"])
    }

    func testPlaceholdersKeepOneTagPerName() {
        var n = Placeholders.Numbering()
        XCTAssertEqual(n.tag("GIVEN_NAME", "Anna"), "[GIVEN_NAME_1]")
        XCTAssertEqual(n.tag("GIVEN_NAME", "Ben"), "[GIVEN_NAME_2]")
        XCTAssertEqual(n.tag("GIVEN_NAME", "anna"), "[GIVEN_NAME_1]")
        XCTAssertEqual(n.tag("EMAIL", "a@b.c"), "[EMAIL_1]")
    }

    func testJoinSeparators() async throws {
        let context = try context("flow: 1\nsteps:\n  - type: join", step: 0)
        let items: Value = .stream([.text("a"), nil, .text("b")])
        let lines = try await Engine.runOne(LogicSteps.join, inputs: ["items": items], params: ["separator": "paragraph"], context: context)
        XCTAssertEqual(lines["text"]?.asText, "a\n\nb")
        do {
            _ = try await Engine.runOne(LogicSteps.join, inputs: ["items": items], params: ["separator": "tab"], context: context)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue("\(error)".contains("not tab"))
        }
    }

    // MARK: Saving

    func testFileNamesFillTheInputNameAndLoseSlashes() {
        XCTAssertEqual(FolderWriter.fileName("{{name}}_notes", a: nil, input: "/work/talk.final.mp4"), "talk.final_notes")
        XCTAssertEqual(FolderWriter.fileName("{{a}}", a: .text("a/b: c"), input: nil), "a-b- c")
        XCTAssertEqual(FolderWriter.fileName("{{name}}", a: nil, input: nil), "result")
    }

    func testTextKeepsItsFormat() {
        XCTAssertEqual(FolderWriter.textExtension("WEBVTT\n\n00:00.000 --> 00:01.000\nHi\n"), "vtt")
        XCTAssertEqual(FolderWriter.textExtension("1\n00:00:00,000 --> 00:00:01,000\nHi\n"), "srt")
        XCTAssertEqual(FolderWriter.textExtension("# Notes\n\nText."), "md")
        XCTAssertEqual(FolderWriter.textExtension("Just text."), "txt")
    }

    func testTheFolderStepNeverReplacesAFile() async throws {
        let input = folder.appendingPathComponent("talk.txt").path
        try "Spoken words.".write(toFile: input, atomically: true, encoding: .utf8)
        let yaml = "flow: 1\nsteps:\n  - type: text\n  - type: folder\n    with: { name: \"{{name}}\" }"
        let (first, _) = try await run(yaml, binding: .paths([input]))
        XCTAssertEqual(first.files, [folder.appendingPathComponent("talk-2.txt").path])
        let (second, _) = try await run(yaml, binding: .paths([input]))
        XCTAssertEqual(second.files, [folder.appendingPathComponent("talk-3.txt").path])
        var force = FlowOptions()
        force.force = true
        let (forced, _) = try await run(yaml, binding: .paths([input]), options: force)
        XCTAssertEqual(forced.files, [folder.appendingPathComponent("talk-4.txt").path])
        XCTAssertEqual(try String(contentsOfFile: input, encoding: .utf8), "Spoken words.")
    }

    func testTheFolderStepWritesIntoASubfolderOfTheOutputDir() async throws {
        var options = FlowOptions()
        options.outputDir = folder.path
        let (report, _) = try await run("""
        flow: 1
        steps:
          - { type: textlist, with: { items: [a, b] } }
          - { type: folder, with: { folder: Lists, name: words } }
        """, options: options)
        let path = folder.appendingPathComponent("Lists/words.txt").path
        XCTAssertEqual(report.files, [path])
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "a\nb")
    }

    func testRecordsSaveAsCSV() throws {
        let rows: [Value] = [.record([("name", .text("a, b")), ("score", .number(0.5))]), .record([("name", .text("c")), ("extra", .bool(true))])]
        XCTAssertEqual(CSV.text(rows), "name,score,extra\n\"a, b\",0.5,\nc,,true\n")
        let written = try FolderWriter.write(.list(rows), to: folder, name: "rows", force: false)
        XCTAssertEqual(written, [folder.appendingPathComponent("rows.csv").path])
    }

    func testMediaIsCopiedUnderItsOwnName() throws {
        let source = folder.appendingPathComponent("in/talk_clear.wav")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: source)
        let written = try FolderWriter.write(.audio(source.path), to: folder, name: "ignored", force: false)
        XCTAssertEqual(written, [folder.appendingPathComponent("talk_clear.wav").path])
        // A file already where it would go is not copied onto itself.
        XCTAssertEqual(try FolderWriter.write(.audio(source.path), to: source.deletingLastPathComponent(), name: "", force: false), [])
    }

    // MARK: Tables and captions

    func testATableOfRecordsHasAColumnPerField() async throws {
        let (_, run) = try await run("""
        flow: 1
        steps:
          - { type: textlist, with: { items: [x] } }
          - { type: table, uses: { a: textlist.items }, with: { columns: Word } }
        """)
        XCTAssertEqual(run.shown.first?.text, ["Word", "x"])
        let rows = OutputSteps.align([["type", "start"], ["um", "1.5"], ["😀", "12"]])
        XCTAssertEqual(rows, ["type  start", "um    1.5", "😀    12"])
    }

    func testCaptionsFromWordsAndFromSpeakers() async throws {
        let words: Value = .list([
            .record([("text", .text("Hello")), ("start", .number(0)), ("end", .number(0.5))]),
            .record([("text", .text("there.")), ("start", .number(0.5)), ("end", .number(1))]),
            .record([("text", .text("Hi.")), ("start", .number(1.5)), ("end", .number(2))]),
        ])
        let ctx = try context("flow: 1\nsteps:\n  - type: textlist\n  - { type: captions, uses: { words: textlist.items } }", step: 1)
        let plain = try await Engine.runOne(ModelSteps.captions, inputs: ["words": words], params: [:], context: ctx)
        XCTAssertEqual(plain["srt"]?.asText, "1\n00:00:00,000 --> 00:00:01,000\nHello there.\n\n2\n00:00:01,500 --> 00:00:02,500\nHi.\n")
        let turns: Value = .list([
            .record([("speaker", .text("Anna")), ("start", .number(0)), ("end", .number(1.2))]),
            .record([("speaker", .text("Ben")), ("start", .number(1.3)), ("end", .number(2))]),
        ])
        let named = try await Engine.runOne(ModelSteps.captions, inputs: ["words": words, "turns": turns], params: [:], context: ctx)
        XCTAssertTrue(named["vtt"]?.asText.contains("<v Anna>Hello there.") ?? false, named["vtt"]?.asText ?? "")
        XCTAssertTrue(named["vtt"]?.asText.contains("<v Ben>Hi.") ?? false)
    }

    func testWordsGetTheirSpacesBack() {
        let words = ModelSteps.timedWords(.list([
            .record([("text", .text("Hi")), ("start", .number(0)), ("end", .number(1))]),
            .record([("text", .text("you")), ("start", .number(1)), ("end", .number(2))]),
        ]))
        XCTAssertEqual(words.map(\.text), ["Hi", " you"])
    }

    func testEveryDocumentedEyeOutputExists() throws {
        // docs/flows.md names the eye step's outputs; a renamed output breaks every flow that uses it.
        let documented = ["subject", "scenes", "type", "animal", "people", "pets", "keeper", "reason", "aesthetic", "cover", "sharp",
                          "blur", "sensitive", "faces", "smile", "eyesOpen", "looking", "expression", "shot", "crop", "detail"]
        let eye = try XCTUnwrap(Steps.byType["eye"])
        XCTAssertEqual(Set(documented).subtracting(eye.outputs.map(\.id)), [])
    }
}
