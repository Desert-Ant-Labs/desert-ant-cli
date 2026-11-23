import XCTest
@testable import DesertAntCLI

final class AdviceTests: XCTestCase {
    func testATextInsideWhatAModelReadsGetsNoNote() {
        XCTAssertEqual(Advice.notes(for: "toxic", text: "Have a lovely day, see you at the match."), [])
        XCTAssertEqual(Advice.notes(for: "gist", text: "The central bank raised interest rates again"), [])
        XCTAssertEqual(Advice.notes(for: "emo", text: "pay my bills"), [])
    }

    func testShortAndLongTextsGetANote() {
        XCTAssertEqual(Advice.notes(for: "gist", text: "money").count, 1)
        let long = "I need to remember to call my mother tomorrow morning before work because it is her birthday and I want to ask about dinner"
        XCTAssertEqual(Advice.notes(for: "emo", text: long).count, 1)
    }

    func testALanguageTheModelDoesNotListGetsANote() {
        let swahili = "Wewe ni mtu mbaya sana na sitaki kukuona tena hapa kijijini kwetu"
        XCTAssertEqual(Advice.notes(for: "toxic", text: swahili), ["Toxic does not read Swahili, so the result may not mean anything."])
        XCTAssertEqual(Advice.notes(for: "tongue", text: swahili), [])
    }
}
