import XCTest
@testable import DesertAntCLI

// The CLI must not drift from the vendored manifest. These pin the contract between
// the two, and the pieces of the terminal layer that are easy to get subtly wrong.

final class CatalogTests: XCTestCase {
    func testManifestDecodes() {
        let m = Manifest.shared
        XCTAssertEqual(m.schemaVersion, 1)
        XCTAssertFalse(m.models.isEmpty)
        XCTAssertFalse(m.sdkVersion.isEmpty)
    }

    func testModelsAreOrderedAndUnique() {
        let ids = Manifest.shared.byID.map(\.id)
        XCTAssertEqual(ids, ids.sorted(), "byID must be A-Z ordered")
        XCTAssertEqual(Set(ids).count, ids.count, "no duplicate ids")
    }

    func testEveryRunnerHasALiveSwiftManifestEntry() {
        for (id, runner) in Runners.all {
            XCTAssertEqual(id, runner.id, "registry key must be the runner's id")
            let model = Manifest.shared.model(id)
            XCTAssertNotNil(model, "runner \(id) has no manifest entry")
            XCTAssertEqual(model?.swift?.status, .live, "\(id) has a runner but no live Swift SDK")
        }
    }

    func testRunnerOptionNamesAreUnique() {
        for runner in Runners.all.values {
            let names = runner.options.map(\.name)
            XCTAssertEqual(Set(names).count, names.count, "\(runner.id) declares a duplicate option")
        }
    }

    func testGroupMapsPipelineTagsToHubs() {
        XCTAssertEqual(Manifest.shared.model("clear").map(Group.of), .audio)
        XCTAssertEqual(Manifest.shared.model("ear").map(Group.of), .audio)
        XCTAssertEqual(Manifest.shared.model("emo").map(Group.of), .text)
        XCTAssertEqual(Manifest.shared.model("moderator").map(Group.of), .vision)
    }

    func testUnknownEnumValuesDecodeToOther() throws {
        let json = #"{"status":"someday"}"#.data(using: .utf8)!
        let sdk = try JSONDecoder().decode(Model.SDK.self, from: json)
        XCTAssertEqual(sdk.status, .other)
    }

    func testRunArgumentsParseAndRead() {
        var args = RunArguments(["limit=5", "Top=2", "novalue"])
        XCTAssertEqual(args.int("limit"), 5)
        XCTAssertEqual(args.int("top"), 2)
        XCTAssertNil(args["novalue"])
        args.set("output", "x.wav")
        args.set("skipped", nil as String?)
        XCTAssertEqual(args["output"], "x.wav")
        XCTAssertNil(args["skipped"])
    }

    func testTruncateKeepsShortStringsAndMarksLongOnes() {
        XCTAssertEqual(truncate("short", to: 10), "short")
        XCTAssertTrue(truncate("a much longer sentence than the limit", to: 12).hasSuffix("\u{2026}"))
    }


    func testDocsAreEmbeddedWithTitles() {
        let names = Embedded.docs.map(\.name)
        XCTAssertEqual(names.first, "index")
        for page in ["agents", "json", "files", "clips", "pipelines", "performance"] {
            XCTAssertTrue(names.contains(page), "docs/\(page).md is not embedded")
        }
        for doc in Embedded.docs {
            XCTAssertFalse(Docs.title(of: doc.markdown).isEmpty, "\(doc.name) has no title heading")
        }
    }

    func testWrapBreaksAtSpacesAndKeepsLongWords() {
        XCTAssertEqual(wrap("short", width: 20), ["short"])
        XCTAssertEqual(wrap("one two three four", width: 9), ["one two", "three", "four"])
        XCTAssertEqual(wrap("supercalifragilistic is long", width: 8), ["supercalifragilistic", "is long"])
        XCTAssertEqual(wrap("", width: 8), [""])
    }

    func testColumnIndentsContinuationLinesUnderTheText() {
        let plain = Palette(enabled: false)
        // keyWidth 6 + 2 leaves 24 for the text, the column's minimum width.
        let text = "one two three four five six seven eight nine ten eleven twelve"
        let lines = column("emo", keyWidth: 6, text: text, width: 32, palette: plain)
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines[0].hasPrefix("emo     one"))
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.hasPrefix("        ") && !$0.hasPrefix("         ") })
        XCTAssertTrue(lines.allSatisfy { $0.count <= 32 })
        let tagged = column("emo", keyWidth: 3, text: "short", width: 40, tag: "closed beta", palette: plain)
        XCTAssertEqual(tagged, ["emo  short", "     closed beta"])
    }

    func testSetupSectionIsAppendedOnceAndReplacedInPlace() {
        let first = Setup.withSection("# My project\n\nRules.\n", body: "v1")
        XCTAssertTrue(first.hasPrefix("# My project\n\nRules.\n\n<!-- desertant start -->\nv1\n<!-- desertant end -->"))
        let second = Setup.withSection(first, body: "v2")
        XCTAssertEqual(second.components(separatedBy: "desertant start").count, 2, "one section")
        XCTAssertTrue(second.contains("v2") && !second.contains("v1"))
        XCTAssertTrue(second.hasPrefix("# My project\n\nRules."))
        XCTAssertTrue(Setup.withSection("", body: "v1").hasPrefix("<!-- desertant start -->"))
    }

    func testHumanBytesPutUnitAgainstNumber() {
        XCTAssertEqual(CacheLocation.human(608_000_000), "608MB")
        XCTAssertEqual(CacheLocation.human(2_000_000_000), "2GB")
        XCTAssertEqual(CacheLocation.human(500), "500B")
    }
}

final class LoaderTests: XCTestCase {
    func testTheAsteriskPulsesThroughTheCycle() {
        let p = Palette(enabled: false)
        let frames = stride(from: 0.0, to: Loader.cycle, by: Loader.cycle / 8).map { Loader().frame(at: $0, palette: p) }
        XCTAssertEqual(Set(frames).count, 5, "\(frames)")
        XCTAssertEqual(frames.first, "+")
        XCTAssertEqual(frames[4], "\u{2217}")
    }
}
