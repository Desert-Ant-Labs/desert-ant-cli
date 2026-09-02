import Transcript
import XCTest
@testable import DesertAntCLI

// Captions follow the broadcast rules whatever the sentences look like.

final class CaptionsTests: XCTestCase {
    /// Words at a steady pace, with a sentence per period.
    private func speak(_ text: String, wordsPerSecond: Double = 2.5) -> ([TimedWord], [Sentence]) {
        var words: [TimedWord] = []
        var t = 0.0
        for (i, w) in text.split(separator: " ").enumerated() {
            words.append(TimedWord(text: (i == 0 ? "" : " ") + w, start: t, end: t + 1 / wordsPerSecond))
            t += 1 / wordsPerSecond
        }
        return (words, Sentence.sentences(from: words))
    }

    func testShortSentenceIsOneCue() {
        let (w, s) = speak("We build small models.")
        let cues = Captions.captions(from: w, sentences: s)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "We build small models.")
    }

    func testLongSentenceWrapsToTwoLinesWithinLimits() {
        let (w, s) = speak("Every developer I met at the conference this week had a wish list of on-device features they would build if cost was not an issue.")
        let cues = Captions.captions(from: w, sentences: s)
        for cue in cues {
            let lines = cue.text.split(separator: "\n")
            XCTAssertLessThanOrEqual(lines.count, Captions.maxLines)
            for line in lines { XCTAssertLessThanOrEqual(line.count, Captions.lineLength, String(line)) }
            XCTAssertLessThanOrEqual(cue.end - cue.start, Captions.maxDuration + 0.01)
        }
        XCTAssertGreaterThan(cues.count, 1)
    }

    func testCuesNeverOverlapAndAShortOneIsHeldIntoThePause() {
        // "Yes." lasts 0.4s, then a 3s pause, then a long sentence.
        var words = [TimedWord(text: "Yes.", start: 0, end: 0.4)]
        var t = 3.4
        for w in "Maybe so, but only if the numbers hold up over the whole quarter and nobody objects.".split(separator: " ") {
            words.append(TimedWord(text: " " + w, start: t, end: t + 0.4)); t += 0.4
        }
        let cues = Captions.captions(from: words, sentences: Sentence.sentences(from: words))
        for (a, b) in zip(cues, cues.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start + 0.001) }
        XCTAssertEqual(cues[0].text, "Yes.")
        XCTAssertGreaterThanOrEqual(cues[0].end - cues[0].start, Captions.minDuration - 0.001)
        XCTAssertLessThanOrEqual(cues[0].end, 3.4)
    }

    func testSRTAndVTTRoundTripThroughTheLoader() throws {
        let cues = [Caption(start: 1, end: 4.5, text: "One line."), Caption(start: 62.25, end: 65, text: "Two\nlines.")]
        for (ext, body) in [("srt", TranscriptFile.srt(cues)), ("vtt", TranscriptFile.vtt(cues))] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try body.write(to: url, atomically: true, encoding: .utf8)
            let back = try TranscriptFile.load(url)
            XCTAssertEqual(back.count, 2, ext)
            XCTAssertEqual(back[1].start, 62.25, ext)
            XCTAssertEqual(back[1].text, "Two lines.", ext)
        }
        XCTAssertTrue(TranscriptFile.vtt(cues).hasPrefix("WEBVTT\n\n"))
        XCTAssertTrue(TranscriptFile.vtt(cues).contains("00:00:01.000 --> 00:00:04.500"))
    }

    func testStampsReadLikeAClock() {
        XCTAssertEqual(Format.stamp(67), "1:07")
        XCTAssertEqual(Format.stamp(3847), "1:04:07")
        XCTAssertEqual(Format.stamp(0), "0:00")
    }
}
