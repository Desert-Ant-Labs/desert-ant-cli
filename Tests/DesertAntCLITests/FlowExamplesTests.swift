import XCTest
@testable import DesertAntCLI

/// Every flow file either reads as runnable, or names each step that cannot run. The
/// fixtures are in the repo; `DESERTANT_FLOW_EXAMPLES` adds a folder of flow files
/// from elsewhere.
final class FlowExamplesTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/flows")

    private func files(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { ["yml", "yaml", "flow"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func check(_ url: URL) throws -> Flow {
        let flow = try FlowFile.read(String(contentsOf: url, encoding: .utf8))
        for problem in flow.problems {
            let step = try XCTUnwrap(problem.step, "\(url.lastPathComponent): \(problem.message)")
            XCTAssertNotNil(flow.step(step), url.lastPathComponent)
            XCTAssertTrue(problem.message.hasPrefix("\(step): "), problem.message)
        }
        return flow
    }

    func testTheFixturesReadAndNameWhatCannotRun() throws {
        let flows = try Dictionary(uniqueKeysWithValues: files(in: Self.fixtures).map { ($0.deletingPathExtension().lastPathComponent, try check($0)) })
        XCTAssertEqual(flows["sort-photos"]?.steps.map(\.id), ["in", "eye", "copy", "grid"])
        XCTAssertEqual(flows["sort-photos"]?.problems.map(\.step), ["grid"])
        XCTAssertEqual(flows["route-tickets"]?.problems, [])
        XCTAssertEqual(flows["call-notes"]?.problems.map(\.step), ["in", "ask", "say"])
    }

    func testTheTemplatesRunHere() throws {
        XCTAssertFalse(Templates.all.isEmpty)
        for t in Templates.all {
            let flow = try FlowFile.read(t.yaml)
            XCTAssertFalse(flow.title.isEmpty, t.name)
            XCTAssertFalse(flow.summary.isEmpty, t.name)
            XCTAssertFalse(flow.description.isEmpty, t.name)
            XCTAssertNotNil(flow.input, t.name)
            #if canImport(CoreML)
            XCTAssertEqual(flow.problems, [], t.name)
            #else
            XCTAssertTrue(flow.problems.allSatisfy { $0.message.contains("macOS only") }, t.name)
            #endif
            // What `flow new` writes reads back the same.
            let again = try FlowFile.read(FlowFile.write(flow))
            XCTAssertEqual(again.steps.map(\.id), flow.steps.map(\.id), t.name)
            XCTAssertEqual(again.steps.map(\.uses), flow.steps.map(\.uses), t.name)
        }
    }

    func testAFolderOfFlowFilesFromElsewhere() throws {
        guard let folder = ProcessInfo.processInfo.environment["DESERTANT_FLOW_EXAMPLES"] else {
            throw XCTSkip("Set DESERTANT_FLOW_EXAMPLES to a folder of flow files.")
        }
        for url in try files(in: URL(fileURLWithPath: folder)) {
            XCTAssertNoThrow(try check(url), url.lastPathComponent)
        }
    }
}
