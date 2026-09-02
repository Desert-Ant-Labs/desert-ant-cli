import XCTest
@testable import DesertAntCLI

// The file-writing policy and the brand's time formatting, both easy to get subtly
// wrong and both visible to every reader.

final class OutputTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func touch(_ name: String) -> String {
        let path = dir.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: Data())
        return path
    }

    func testDefaultSiblingKeepsTheContainer() {
        XCTAssertEqual(Destination.sibling(of: "/a/talk.mp4", suffix: "_clear"), "/a/talk_clear.mp4")
        XCTAssertEqual(Destination.sibling(of: "/a/talk", suffix: "_clear"), "/a/talk_clear")
    }

    func testOutputNeverReplacesTheInput() {
        let input = touch("talk.wav")
        XCTAssertThrowsError(try Destination.resolve(requested: input, default: "", input: input, force: true))
        // The same file spelled differently still counts as the input.
        let roundabout = dir.path + "/../" + dir.lastPathComponent + "/talk.wav"
        XCTAssertThrowsError(try Destination.resolve(requested: roundabout, default: "", input: input, force: false))
    }

    func testExistingOutputStepsAside() throws {
        let input = touch("talk.wav")
        let taken = touch("talk_clear.wav")
        let landed = try Destination.resolve(requested: nil, default: taken, input: input, force: false)
        XCTAssertEqual(URL(fileURLWithPath: landed).lastPathComponent, "talk_clear-2.wav")
        _ = touch("talk_clear-2.wav")
        let next = try Destination.resolve(requested: nil, default: taken, input: input, force: false)
        XCTAssertEqual(URL(fileURLWithPath: next).lastPathComponent, "talk_clear-3.wav")
    }

    func testForceReplacesInPlace() throws {
        let input = touch("talk.wav")
        let taken = touch("talk_clear.wav")
        XCTAssertEqual(try Destination.resolve(requested: nil, default: taken, input: input, force: true), taken)
    }

    func testOutputKeepsTheInputContainerWhenWritable() {
        XCTAssertEqual(MediaFormat.outputExtension(for: "/a/talk.mov", hasVideo: true), "mov")
        XCTAssertEqual(MediaFormat.outputExtension(for: "/a/talk.wav", hasVideo: false), "wav")
        XCTAssertEqual(MediaFormat.outputExtension(for: "/a/talk.mp3", hasVideo: false), "m4a")
        XCTAssertEqual(MediaFormat.outputExtension(for: "/a/talk.mkv", hasVideo: true), "mp4")
        XCTAssertNil(MediaFormat.changeNote(from: "/a/talk.wav", to: "/a/talk_clear.wav"))
        XCTAssertEqual(MediaFormat.changeNote(from: "/a/talk.mp3", to: "/a/talk_clear.m4a"),
                       "Written as m4a: this machine cannot write mp3.")
    }

    func testElapsedUsesCompactUnits() {
        XCTAssertEqual(Format.elapsed(41), "41s")
        XCTAssertEqual(Format.elapsed(5.6), "5.6s")
        XCTAssertEqual(Format.elapsed(130), "2m 10s")
        XCTAssertEqual(Format.elapsed(3780), "1h 03m")
    }

    func testSpokenKeepsMaterialInWords() {
        XCTAssertEqual(Format.spoken(12), "12 seconds")
        XCTAssertEqual(Format.spoken(48 * 60), "48 minutes")
        XCTAssertEqual(Format.spoken(72 * 60), "1 hour 12 minutes")
        XCTAssertEqual(Format.realtime(material: 2880, elapsed: 41), "70x realtime")
    }
}
