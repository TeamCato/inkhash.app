import XCTest
@testable import InkhashCore

final class HashtagTests: XCTestCase {
    func testMarkdownHeadingIsNotATag() {
        XCTAssertEqual(Hashtags.inText("# Titel\nmehr Text", mode: .markdown), [])
        XCTAssertEqual(Hashtags.inText("## Kapitel", mode: .markdown), [])
    }

    func testMarkdownGluedTag() {
        XCTAssertEqual(Hashtags.inText("Treffen #Launch heute", mode: .markdown), ["launch"])
        XCTAssertEqual(Hashtags.inText("#eigen\n", mode: .markdown), ["eigen"])
    }

    func testMarkdownHashWithSpaceIsHeading() {
        XCTAssertEqual(Hashtags.inText("# urlaub", mode: .markdown), [])
    }

    func testHandwritingAllowsASpace() {
        XCTAssertEqual(Hashtags.inText("# urlaub", mode: .handwriting), ["urlaub"])
        XCTAssertEqual(Hashtags.inText("#urlaub", mode: .handwriting), ["urlaub"])
    }

    func testDoesNotSplitWords() {
        XCTAssertEqual(Hashtags.inText("C# und foo#bar", mode: .markdown), [])
    }

    func testUniqueAndOrder() {
        XCTAssertEqual(Hashtags.inText("#Alpen und nochmal #alpen #See", mode: .handwriting), ["alpen", "see"])
    }

    func testSeparatedHashMarkJoinsTheWordToTheRight() {
        let hash = RecognizedWord(text: "#", minX: 0.10, minY: 0.20, maxX: 0.14, maxY: 0.28)
        let word = RecognizedWord(text: "Reise", minX: 0.16, minY: 0.20, maxX: 0.34, maxY: 0.28)
        XCTAssertEqual(Hashtags.inObservations([word, hash]), ["reise"])
    }

    func testDistantHashDoesNotJoin() {
        let hash = RecognizedWord(text: "#", minX: 0.10, minY: 0.20, maxX: 0.14, maxY: 0.28)
        let word = RecognizedWord(text: "Reise", minX: 0.70, minY: 0.20, maxX: 0.90, maxY: 0.28)
        XCTAssertEqual(Hashtags.inObservations([hash, word]), [])
    }

    func testTranscriptGroupsALine() {
        let left = RecognizedWord(text: "gute", minX: 0.10, minY: 0.10, maxX: 0.24, maxY: 0.16)
        let right = RecognizedWord(text: "Reise", minX: 0.26, minY: 0.10, maxX: 0.42, maxY: 0.16)
        let below = RecognizedWord(text: "#alpen", minX: 0.10, minY: 0.30, maxX: 0.28, maxY: 0.36)
        XCTAssertEqual(Hashtags.transcript(from: [below, right, left]), "gute Reise\n#alpen")
        XCTAssertEqual(Hashtags.inObservations([left, right, below]), ["alpen"])
    }
}
