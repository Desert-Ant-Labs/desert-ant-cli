import Foundation
import Transcript
import XCTest
@testable import DesertAntCLI

// Who's turns shaped for a reader: joined, summed, matched to a transcript, and
// written as RTTM and speaker-labeled captions.

final class SpeakersTests: XCTestCase {
    private func turn(_ start: Double, _ end: Double, _ speaker: Int) -> SpeakerTurn {
        SpeakerTurn(start: start, end: end, speaker: speaker)
    }

    /// Words at a steady pace, each with its leading space as Voz's transcriber writes them.
    private func words(_ text: String, from start: Double, perWord: Double = 0.4) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { i, w in
            TimedWord(text: " " + w, start: start + Double(i) * perWord, end: start + Double(i + 1) * perWord)
        }
    }

    func testJoinMergesShortPausesButKeepsAnInterjection() {
        let turns = [turn(0, 2, 0), turn(2.5, 4, 0), turn(4.2, 4.6, 1), turn(4.8, 8, 0), turn(10, 12, 0)]
        let joined = Speakers.join(turns, gap: 1)
        XCTAssertEqual(joined, [turn(0, 4, 0), turn(4.2, 4.6, 1), turn(4.8, 8, 0), turn(10, 12, 0)])
        XCTAssertEqual(Speakers.join(turns, gap: 0).count, turns.count)
    }

    func testSummaryIsMostHeardFirstWithShares() {
        let turns = [turn(0, 2, 0), turn(2, 8, 1), turn(8, 9, 0)]
        let summary = Speakers.summary(turns, joined: turns, duration: 10, names: ["Anna"])
        XCTAssertEqual(summary.map(\.speaker), [1, 0])
        XCTAssertEqual(summary.map(\.name), ["Speaker 2", "Anna"])
        XCTAssertEqual(summary[0].share, 0.6, accuracy: 1e-9)
        XCTAssertEqual(summary[1].seconds, 3, accuracy: 1e-9)
        XCTAssertEqual(summary[1].turns, 2)
    }

    func testNamesParseAndFallBack() {
        XCTAssertEqual(Speakers.names(" Anna , Ben,,"), ["Anna", "Ben"])
        XCTAssertEqual(Speakers.names(nil), [])
        XCTAssertEqual(Speakers.name(2, names: ["Anna", "Ben"]), "Speaker 3")
    }

    func testLinesSplitASentenceWhereTheSpeakerChanges() {
        // "Is it on the phone" is speaker 0, the answer speaker 1, with no period between.
        let w = words("Is it on the phone yes it runs there.", from: 0)
        let turns = [turn(0, 2.0, 0), turn(2.0, 4.0, 1)]
        let lines = Speakers.lines(words: w, turns: turns)
        XCTAssertEqual(lines.map(\.speaker), [0, 1])
        XCTAssertEqual(lines.map(\.text), ["Is it on the phone", "yes it runs there."])
    }

    func testOneStrayWordStaysWithTheSpeakerAroundIt() {
        let w = words("We build small models that run on the device.", from: 0, perWord: 0.25)
        // The diarizer hands "models" to speaker 1 for a quarter second.
        let turns = [turn(0, 0.75, 0), turn(0.75, 1.0, 1), turn(1.0, 3, 0)]
        let lines = Speakers.lines(words: w, turns: turns)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.speaker, 0)
    }

    func testSentencesWithoutWordsGoToTheMostHeardSpeaker() {
        let sentences = [Sentence(id: 0, text: "Hello there.", start: 0, end: 2),
                         Sentence(id: 1, text: "Hi.", start: 2.2, end: 3),
                         Sentence(id: 2, text: "In the gap.", start: 20, end: 21)]
        let turns = [turn(0, 1.5, 0), turn(1.5, 3, 1)]
        XCTAssertEqual(Speakers.lines(sentences: sentences, turns: turns).map(\.speaker), [0, 1, 1])
    }

    func testACueGoesToTheSpeakerHeardMostAcrossTheirTurns() {
        // Speaker 0 speaks 2.4s in three short turns, speaker 1 1.5s in one.
        let turns = [turn(0, 0.8, 0), turn(1, 1.8, 0), turn(2, 2.8, 0), turn(2.8, 4.3, 1)]
        XCTAssertEqual(Speakers.speaker(at: 0, 4.3, in: turns), 0)
    }

    func testRTTMHasOneSpeakerLinePerTurn() {
        let rttm = SpeakerFile.rttm([turn(0, 1.5, 0), turn(2, 3.25, 1)], input: "/work/team call.m4a", names: ["Anna Lee"])
        XCTAssertEqual(rttm, """
        SPEAKER team_call 1 0.000 1.500 <NA> <NA> Anna_Lee <NA> <NA>
        SPEAKER team_call 1 2.000 1.250 <NA> <NA> Speaker_2 <NA> <NA>

        """)
    }

    func testCaptionsNameTheSpeakerOnChangeAndVTTUsesVoices() {
        let lines = [SpokenLine(start: 0, end: 1, speaker: 0, text: "Welcome back."),
                     SpokenLine(start: 1.2, end: 2, speaker: 0, text: "Today, small models."),
                     SpokenLine(start: 2.5, end: 3.5, speaker: 1, text: "Thanks for having me.")]
        let srt = SpeakerFile.srt(lines, words: nil, names: ["Sam"])
        XCTAssertTrue(srt.contains("Sam: Welcome back."))
        XCTAssertTrue(srt.contains("\nToday, small models."), "the same speaker is not named again")
        XCTAssertTrue(srt.contains("Speaker 2: Thanks for having me."))
        let vtt = SpeakerFile.vtt(lines, words: nil, names: ["Sam"])
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
        XCTAssertTrue(vtt.contains("<v Sam>Today, small models."))
        XCTAssertEqual(SpeakerFile.text(lines, names: ["Sam"]),
                       "Sam: Welcome back. Today, small models.\n\nSpeaker 2: Thanks for having me.\n")
    }

    func testVozDocumentGivesItsWordsBack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("desertant-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"sentences": [{"start": 0, "end": 1, "text": "Hi there."}], "words": [{"start": 0, "end": 0.4, "text": "Hi"}, {"start": 0.5, "end": 1, "text": "there."}]}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let words = try XCTUnwrap(TranscriptFile.words(url))
        XCTAssertEqual(words.map(\.text), ["Hi", " there."])
        XCTAssertNil(TranscriptFile.words(URL(fileURLWithPath: "/work/talk.srt")))
    }
}
