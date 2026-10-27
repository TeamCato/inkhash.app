import XCTest
@testable import InkhashCore

/// Nested list items: Tab indents, the Markdown keeps it. See ADR 0086.
final class NestedListTests: XCTestCase {
    func testNestedItemsRoundTrip() {
        let markdown = """
        - eins
          - unter eins
            - ganz unten
        - zwei
          1. erster Schritt
          2. zweiter Schritt
             - [ ] Aufgabe darunter
        - drei

        """
        let blocks = MarkdownCodec.parse(markdown)
        XCTAssertEqual(blocks.map(\.indent), [0, 1, 2, 0, 1, 1, 2, 0])
        XCTAssertEqual(blocks.map(\.type), [.bullet, .bullet, .bullet, .bullet, .numbered, .numbered, .checkbox, .bullet])
        XCTAssertEqual(MarkdownCodec.serialize(blocks), markdown)
    }

    func testNumbersCountPerLevel() {
        let blocks = [
            Block(type: .numbered, spans: [InlineSpan(text: "a")]),
            Block(type: .numbered, spans: [InlineSpan(text: "a1")], indent: 1),
            Block(type: .numbered, spans: [InlineSpan(text: "a2")], indent: 1),
            Block(type: .numbered, spans: [InlineSpan(text: "b")]),
        ]
        XCTAssertEqual(MarkdownCodec.serialize(blocks), "1. a\n   1. a1\n   2. a2\n2. b\n")
    }

    func testIndentNeverSkipsALevel() {
        let blocks = [
            Block(type: .bullet, spans: [InlineSpan(text: "oben")]),
            Block(type: .bullet, spans: [InlineSpan(text: "zu tief")], indent: 3),
        ]
        XCTAssertEqual(MarkdownCodec.serialize(blocks), "- oben\n  - zu tief\n")
    }

    func testOnlyListItemsIndent() {
        XCTAssertEqual(Block(type: .paragraph, spans: [], indent: 2).indent, 0)
        XCTAssertEqual(Block(type: .bullet, spans: [], indent: 9).indent, Block.maxIndent)
    }

    func testTabsAndFourSpacesNestToo() {
        XCTAssertEqual(MarkdownCodec.parse("- a\n\t- b\n\t\t- c\n").map(\.indent), [0, 1, 2])
        XCTAssertEqual(MarkdownCodec.parse("- a\n    - b\n    - c\n").map(\.indent), [0, 1, 1])
    }

    func testParagraphEndsTheNesting() {
        let blocks = MarkdownCodec.parse("- a\n  - b\n\nText\n\n  - c\n")
        XCTAssertEqual(blocks.map(\.indent), [0, 1, 0, 0])
    }
}
