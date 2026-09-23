import XCTest
@testable import DesertAntCLI

// Several inputs in one process: what a folder expands to, and how the results are
// collected into one array.

final class BatchTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        for name in ["a.jpg", "B.PNG", "notes.txt", ".hidden.png", "sub/c.jpg"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func names(_ files: [String]) -> [String] {
        files.map { String($0.dropFirst(dir.path.count + 1)) }
    }

    func testFolderIsFilteredAndOrdered() throws {
        let flat = try Inputs.expand([dir.path], kind: .image, recursive: false)
        XCTAssertEqual(names(flat.files), ["B.PNG", "a.jpg"], "images only, A-Z, hidden and folders left out")
        XCTAssertEqual(flat.skipped, ["notes.txt"])
        XCTAssertTrue(flat.isBatch)

        let deep = try Inputs.expand([dir.path], kind: .image, recursive: true)
        XCTAssertEqual(names(deep.files), ["B.PNG", "a.jpg", "sub/c.jpg"])
    }

    func testFolderPathIsJoinedAsTyped() throws {
        let cwd = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(dir.deletingLastPathComponent().path)
        defer { FileManager.default.changeCurrentDirectoryPath(cwd) }
        let relative = try Inputs.expand([dir.lastPathComponent], kind: .image, recursive: false)
        XCTAssertEqual(relative.files.first, "\(dir.lastPathComponent)/B.PNG")
    }

    func testOnePathIsNotABatchAndTwoAre() throws {
        let one = try Inputs.expand(["talk.mp4"], kind: .file, recursive: false)
        XCTAssertEqual(one.files, ["talk.mp4"])
        XCTAssertFalse(one.isBatch)
        let two = try Inputs.expand(["a.mp4", "b.mp4"], kind: .file, recursive: false)
        XCTAssertEqual(two.files, ["a.mp4", "b.mp4"], "explicit paths keep their order")
        XCTAssertTrue(two.isBatch)
    }

    func testFolderWithNothingToRunThrows() {
        XCTAssertThrowsError(try Inputs.expand([dir.path], kind: .file, recursive: true))
        // The --recursive hint only when there was a folder to look inside.
        XCTAssertThrowsError(try Inputs.expand([dir.path], kind: .file, recursive: false)) { error in
            XCTAssertTrue("\(error)".contains("--recursive"))
        }
        XCTAssertThrowsError(try Inputs.expand([dir.appendingPathComponent("sub").path], kind: .file, recursive: false)) { error in
            XCTAssertFalse("\(error)".contains("--recursive"))
        }
    }

    #if canImport(ImageIO)
    func testModeratorRejectsBadOptionsBeforeAnyWork() {
        let runner = ModeratorRunner()
        XCTAssertThrowsError(try runner.validate(RunArguments(["threshold=2"])))
        XCTAssertThrowsError(try runner.validate(RunArguments(["policy=nope"])))
        XCTAssertThrowsError(try runner.validate(RunArguments(["quality=slow"])))
        XCTAssertNoThrow(try runner.validate(RunArguments(["threshold=0.3", "policy=ALLOW-TOPLESS", "quality=fast"])))
    }
    #endif

    func testBatchCollectsResultsInOrder() throws {
        let batch = Batch()
        batch.append(["a": 1])
        batch.append(["b": 2])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(batch.all), as: UTF8.self)
        XCTAssertEqual(json, #"[{"a":1},{"b":2}]"#)
    }
}
