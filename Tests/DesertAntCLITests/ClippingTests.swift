import XCTest
@testable import DesertAntCLI

// The parts of the clips pipeline that need no model or media: reading a transcript
// file, and the timestamps a person reads.

final class ClippingTests: XCTestCase {
    private func write(_ name: String, _ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testSRTBlocksBecomeTimedSentences() throws {
        let url = try write("talk.srt", """
        1
        00:00:01,000 --> 00:00:04,500
        We built a small model.

        2
        00:01:02,250 --> 00:01:05,000
        It runs on the phone,
        so there is no wait.

        """)
        let sentences = try TranscriptFile.load(url)
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0].start, 1.0)
        XCTAssertEqual(sentences[0].end, 4.5)
        XCTAssertEqual(sentences[1].start, 62.25)
        XCTAssertEqual(sentences[1].text, "It runs on the phone, so there is no wait.")
        XCTAssertEqual(sentences.map(\.id), [0, 1])
    }

    func testVTTPeriodsAndShortStampsParse() {
        XCTAssertEqual(TranscriptFile.seconds("00:00:01.500"), 1.5)
        XCTAssertEqual(TranscriptFile.seconds("01:02.000"), 62)
        XCTAssertEqual(TranscriptFile.seconds("01:00:00,000"), 3600)
        XCTAssertNil(TranscriptFile.seconds("nope"))
    }

    func testJSONCuesLoad() throws {
        let url = try write("talk.json", #"[{"start": 0, "end": 2.5, "text": "Hello."}, {"start": 3, "end": 5, "text": "Again."}]"#)
        let sentences = try TranscriptFile.load(url)
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[1].text, "Again.")
    }

    func testUnknownTranscriptFormatIsRefusedPlainly() throws {
        let url = try write("talk.txt", "no times here")
        XCTAssertThrowsError(try TranscriptFile.load(url)) { error in
            XCTAssertTrue("\(error)".contains(".srt, .vtt, or .json"))
        }
    }

}
