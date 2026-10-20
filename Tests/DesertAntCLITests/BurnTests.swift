import Transcript
import XCTest
@testable import DesertAntCLI

final class BurnTests: XCTestCase {
    private static let fonts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fonts")

    /// Words at a steady pace from `start`.
    private func speak(_ text: String, from start: Double = 0, pace: Double = 0.4) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { i, w in
            TimedWord(text: (i == 0 ? "" : " ") + w, start: start + Double(i) * pace, end: start + Double(i + 1) * pace)
        }
    }

    func testWordsMoveOntoTheClipsTimeline() {
        let words = speak("one two three four five six seven eight", pace: 1)
        // Two ranges played end to end: 1-3s, then 5-7s.
        let shifted = ClipCaptions.shift(words, into: [TimeRange(start: 1, end: 3), TimeRange(start: 5, end: 7)])
        XCTAssertEqual(shifted.map { $0.text.trimmingCharacters(in: .whitespaces) }, ["two", "three", "six", "seven"])
        XCTAssertEqual(shifted.map(\.start), [0, 1, 2, 3])
        XCTAssertEqual(shifted.map(\.end), [1, 2, 3, 4])
    }

    func testAWordBelongsToTheRangeItsMiddleFallsIn() {
        let words = [TimedWord(text: "edge", start: 0.8, end: 1.6), TimedWord(text: " out", start: 2.8, end: 3.6)]
        let shifted = ClipCaptions.shift(words, into: [TimeRange(start: 1, end: 3)])
        XCTAssertEqual(shifted.count, 1)
        XCTAssertEqual(shifted[0].start, 0)
        XCTAssertEqual(shifted[0].end, 0.6, accuracy: 1e-9)
    }

    func testSocialCuesAreShort() {
        let words = speak("Small brains can do precise work when the method is simple, and that is the idea behind small models that run on your own device without a cloud bill. Then one more.")
        let pacing = Pacing(lines: 2, lineLength: 24, words: nil, maxDuration: 3.5, pause: 0.7)
        let cues = ClipCaptions.social(words, pacing: pacing)
        XCTAssertGreaterThan(cues.count, 3)
        for cue in cues {
            let lines = cue.text.split(separator: "\n")
            XCTAssertLessThanOrEqual(lines.count, 2, cue.text)
            for line in lines { XCTAssertLessThanOrEqual(line.count, 24, String(line)) }
        }
        XCTAssertTrue(cues.contains { $0.text.hasSuffix("cloud bill.") || $0.text.hasSuffix("bill.") }, "\(cues.map(\.text))")
        XCTAssertEqual(cues.last?.text, "Then one more.")
        for (a, b) in zip(cues, cues.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start + 1e-9) }
    }

    func testAGapUnderHalfASecondIsHeldToTheNextCaption() {
        let cues = ClipCaptions.settle([Caption(start: 0, end: 1, text: "a"), Caption(start: 1.4, end: 2.4, text: "b")])
        XCTAssertEqual(cues[0].end, 1.4)
    }

    func testACaptionClearsHalfASecondAfterTheSpeech() {
        let cues = ClipCaptions.settle([Caption(start: 0, end: 1, text: "a"), Caption(start: 3, end: 4, text: "b")])
        XCTAssertEqual(cues[0].end, 1.5)
        XCTAssertEqual(cues[1].end, 4.5)
    }

    func testACaptionStaysUpAtLeastPointEightSeconds() {
        let alone = ClipCaptions.settle([Caption(start: 2, end: 2.1, text: "Yes."), Caption(start: 5, end: 6, text: "b")])
        XCTAssertEqual(alone[0].end, 2.8, accuracy: 1e-9)
        // Never past the next caption's start.
        let crowded = ClipCaptions.settle([Caption(start: 2, end: 2.1, text: "Yes."), Caption(start: 2.5, end: 3.5, text: "b")])
        XCTAssertEqual(crowded[0].end, 2.5)
        XCTAssertEqual(crowded[1].start, 2.5)
    }

    func testTheFrameSetsSizeAndMarginsFromItsShortSide() {
        let wide = CaptionFrame(width: 1920, height: 1080, style: CaptionStyle())
        let tall = CaptionFrame(width: 1080, height: 1920, style: CaptionStyle())
        XCTAssertEqual(wide.lineHeight, tall.lineHeight)
        XCTAssertEqual(wide.lineHeight, 76)
        XCTAssertEqual(wide.marginY, 86)
        XCTAssertEqual(tall.marginY, 307)
        var big = CaptionStyle()
        big.size = 0.1
        XCTAssertEqual(CaptionFrame(width: 1920, height: 1080, style: big).lineHeight, 108)
    }

    func testPacingFollowsTheShapeOfTheFrame() {
        let tall = CaptionFrame(width: 1080, height: 1920, style: CaptionStyle())
        XCTAssertEqual(tall.shape, .vertical)
        XCTAssertEqual(tall.pacing, Pacing(lines: 1, lineLength: 20, words: 5, maxDuration: 1.5, pause: 0.4))
        let square = CaptionFrame(width: 1080, height: 1080, style: CaptionStyle())
        XCTAssertEqual(square.shape, .square)
        // 25 characters fit across 1080 pixels at the default size, one short of the shape's 26.
        XCTAssertEqual(square.pacing, Pacing(lines: 2, lineLength: 25, words: nil, maxDuration: 2.5, pause: 0.7))
        XCTAssertEqual(CaptionFrame(width: 1000, height: 800, style: CaptionStyle()).shape, .square)
        let wide = CaptionFrame(width: 1920, height: 1080, style: CaptionStyle())
        XCTAssertEqual(wide.shape, .landscape)
        XCTAssertEqual(wide.pacing, Pacing(lines: 2, lineLength: 42, words: nil, maxDuration: 5, pause: 0.7))
        // A large size fits fewer characters across the frame than the shape allows.
        var big = CaptionStyle()
        big.size = 0.12
        XCTAssertEqual(CaptionFrame(width: 1920, height: 1080, style: big).pacing.lineLength, 26)
    }

    func testLinesAndWordsOverrideTheShape() throws {
        let style = try CaptionStyle.parse(position: nil, align: nil, font: nil, size: nil, weight: nil, color: nil, look: nil,
                                           quality: nil, lines: "2", words: "3")
        let tall = CaptionFrame(width: 1080, height: 1920, style: style)
        XCTAssertEqual(tall.pacing.lines, 2)
        XCTAssertEqual(tall.pacing.words, 3)
        XCTAssertThrowsError(try CaptionStyle.parse(position: nil, align: nil, font: nil, size: nil, weight: nil, color: nil, look: nil,
                                                    quality: nil, lines: "3"))
        XCTAssertThrowsError(try CaptionStyle.parse(position: nil, align: nil, font: nil, size: nil, weight: nil, color: nil, look: nil,
                                                    quality: nil, words: "0"))
    }

    func testAVerticalCaptionIsOneShortLine() {
        let words = speak("Small brains can do precise work when the method is simple and that is the whole idea.", pace: 0.25)
        let cues = ClipCaptions.social(words, pacing: CaptionFrame(width: 1080, height: 1920, style: CaptionStyle()).pacing)
        for cue in cues {
            XCTAssertFalse(cue.text.contains("\n"), cue.text)
            XCTAssertLessThanOrEqual(cue.text.count, 20, cue.text)
            XCTAssertLessThanOrEqual(cue.text.split(separator: " ").count, 5, cue.text)
        }
        let paused = speak("One two.", pace: 0.3) + speak("three four", from: 1.1, pace: 0.3)
        // 0.5s of silence is past a vertical clip's 0.4s, so the words after it start a new caption.
        XCTAssertEqual(ClipCaptions.social(paused, pacing: CaptionFrame(width: 1080, height: 1920, style: CaptionStyle()).pacing).count, 2)
    }

    func testALandscapeCaptionTakesUpToFortyTwoCharactersALine() {
        let words = speak("Small brains can do precise work when the method is simple, and that is the idea behind small models.", pace: 0.2)
        let cues = ClipCaptions.social(words, pacing: CaptionFrame(width: 1920, height: 1080, style: CaptionStyle()).pacing)
        XCTAssertTrue(cues.contains { $0.text.split(separator: "\n").contains { $0.count > 32 } }, "\(cues.map(\.text))")
        for cue in cues {
            for line in cue.text.split(separator: "\n") { XCTAssertLessThanOrEqual(line.count, 42, String(line)) }
        }
    }

    func testStylesParseAndExplainBadValues() throws {
        let s = try CaptionStyle.parse(position: "top", align: "LEFT", font: nil, size: "0.05", weight: "semibold",
                                       color: "#ffcc0080", look: "box", quality: "low")
        XCTAssertEqual(s.position, .top)
        XCTAssertEqual(s.align, .left)
        XCTAssertEqual(s.size, 0.05)
        XCTAssertEqual(s.weight, 600)
        XCTAssertEqual(s.color.a, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(s.look, .box)
        XCTAssertEqual(s.quality, .low)
        XCTAssertEqual(CaptionStyle.RGBA("yellow"), CaptionStyle.RGBA.named["yellow"])
        XCTAssertNil(CaptionStyle.RGBA("#12"))
        XCTAssertThrowsError(try CaptionStyle.parse(position: "middle", align: nil, font: nil, size: nil, weight: nil, color: nil, look: nil, quality: nil)) {
            XCTAssertEqual("\($0)", "caption-position is bottom, center, or top, not middle.")
        }
        XCTAssertThrowsError(try CaptionStyle.parse(position: nil, align: nil, font: nil, size: nil, weight: "heavy", color: nil, look: nil, quality: nil))
        XCTAssertThrowsError(try CaptionStyle.parse(position: nil, align: nil, font: nil, size: "0", weight: nil, color: nil, look: nil, quality: nil))
    }

    func testTheShippedFontsReadWithTheirMetrics() throws {
        let bold = try CaptionFont.read(Self.fonts.appendingPathComponent("InclusiveSans-Bold.ttf"), index: 0)
        let regular = try CaptionFont.read(Self.fonts.appendingPathComponent("InclusiveSans-Regular.ttf"), index: 0)
        XCTAssertEqual(bold.family, CaptionFont.bundledName)
        XCTAssertEqual(regular.family, CaptionFont.bundledName)
        XCTAssertEqual(bold.weight, 700)
        XCTAssertEqual(regular.weight, 400)
        XCTAssertGreaterThan(bold.unitsPerEm, 0)
        // libass fills a line with the Windows ascent and descent, so the em is smaller than the line.
        XCTAssertLessThan(bold.emSize(lineHeight: 100), 100)
        XCTAssertEqual(bold.baseline(lineHeight: 100), 100 * bold.ascent / (bold.ascent + bold.descent), accuracy: 1e-9)
        XCTAssertThrowsError(try CaptionFont.read(Self.fonts.appendingPathComponent("OFL.txt"), index: 0))
    }

    func testTheSubtitleFileMatchesTheStyle() throws {
        let font = try CaptionFont.read(Self.fonts.appendingPathComponent("InclusiveSans-Bold.ttf"), index: 0)
        var style = CaptionStyle()
        style.position = .top
        style.align = .right
        style.look = .box
        let frame = CaptionFrame(width: 1920, height: 1080, style: style)
        let ass = ASS.file([Caption(start: 1.25, end: 61, text: "Two {lines}\nof text")], frame: frame, style: style, font: font)
        XCTAssertTrue(ass.contains("PlayResX: 1920\nPlayResY: 1080\nWrapStyle: 2"), ass)
        XCTAssertTrue(ass.contains("Style: Default,Inclusive Sans,76,&H00FFFFFF,&H00FFFFFF,&H4C000000,&H4C000000,-1,"), ass)
        // Box (3), padding 15px, no shadow, top right (9), margins 115, 115, 86.
        XCTAssertTrue(ass.contains(",3,15,0,9,115,115,86,1\n"), ass)
        XCTAssertTrue(ass.contains("Dialogue: 0,0:00:01.25,0:01:01.00,Default,,0,0,0,,Two \\{lines}\\Nof text\n"), ass)
        XCTAssertEqual(ASS.color(.init(r: 1, g: 0.8, b: 0, a: 1)), "&H0000CCFF")
    }

    func testSentencesWithoutWordTimesSpreadTheirWords() {
        let words = ClipCaptions.words(spreading: [Sentence(id: 0, text: "One two three four.", start: 2, end: 4)])
        XCTAssertEqual(words.map(\.text), ["One", " two", " three", " four."])
        XCTAssertEqual(words.map(\.start), [2, 2.5, 3, 3.5])
    }
}
