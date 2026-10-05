import XCTest
@testable import InkhashCore

final class MarkdownTests: XCTestCase {
    func testRoundtripDocument() {
        let markdown = """
        # Inkhash

        Gedanken mit **fett** und *kursiv* und `code`.

        - eins
        - zwei

        1. zuerst
        2. danach

        - [ ] offen
        - [x] erledigt

        ```swift
        let x = 1
        ```

        Zeile mit #eigen

        """
        let blocks = MarkdownCodec.parse(markdown)
        let serialized = MarkdownCodec.serialize(blocks)
        let again = MarkdownCodec.parse(serialized)
        XCTAssertEqual(snapshots(blocks), snapshots(again))
        XCTAssertEqual(MarkdownCodec.title(for: markdown), "Inkhash")
        XCTAssertEqual(Hashtags.inText(markdown, mode: .markdown), ["eigen"])
    }

    func testHashTagIsNotAHeading() {
        let blocks = MarkdownCodec.parse("#eigen\n")
        XCTAssertEqual(blocks.first?.type, .paragraph)
        XCTAssertEqual(blocks.first?.plain, "#eigen")
    }

    func testHeadingNeedsASpace() {
        let blocks = MarkdownCodec.parse("# Titel\n")
        XCTAssertEqual(blocks.first?.type, .heading1)
        XCTAssertEqual(blocks.first?.plain, "Titel")
    }

    func testInlineMarkers() {
        let bold = MarkdownCodec.parseInline("**hallo**")
        XCTAssertEqual(bold.plain, "hallo")
        XCTAssertEqual(bold.spans.first?.bold, true)

        let italic = MarkdownCodec.parseInline("*hallo*")
        XCTAssertEqual(italic.plain, "hallo")
        XCTAssertEqual(italic.spans.first?.italic, true)

        let both = MarkdownCodec.parseInline("***beides***")
        XCTAssertEqual(both.plain, "beides")
        XCTAssertEqual(both.spans.first?.bold, true)
        XCTAssertEqual(both.spans.first?.italic, true)

        let code = MarkdownCodec.parseInline("`x`")
        XCTAssertEqual(code.spans.first?.code, true)
        XCTAssertEqual(code.plain, "x")
    }

    func testLinks() {
        let parsed = MarkdownCodec.parseInline("siehe [**die** Seite](https://example.org/a?b=1) dort")
        XCTAssertEqual(parsed.plain, "siehe die Seite dort")
        XCTAssertEqual(parsed.spans.map(\.link), [nil, "https://example.org/a?b=1", "https://example.org/a?b=1", nil])
        XCTAssertEqual(parsed.spans[1].bold, true)
        XCTAssertEqual(parsed.spans[2].bold, false)
        XCTAssertEqual(MarkdownCodec.serializeInline(parsed.spans), "siehe [**die** Seite](https://example.org/a?b=1) dort")

        // Cursor behind the closing bracket lands behind the label.
        let typed = MarkdownCodec.parseInline("[ab](x)", cursorUTF16: 7)
        XCTAssertEqual(typed.cursorUTF16, 2)
    }

    func testBracketsWithoutTargetStayText() {
        for source in ["[ab]", "[ab] (x)", "[](x)", "[ab]()", "[a b](mit leer)"] {
            let parsed = MarkdownCodec.parseInline(source)
            XCTAssertEqual(parsed.plain, source, source)
            XCTAssertTrue(parsed.spans.allSatisfy { $0.link == nil }, source)
        }
        // The inner bracket wins, as in Markdown.
        let nested = MarkdownCodec.parseInline("[a[b](x)")
        XCTAssertEqual(nested.plain, "[ab")
        XCTAssertEqual(nested.spans.map(\.link), [nil, "x"])
        let round = MarkdownCodec.parseInline(MarkdownCodec.serializeInline([InlineSpan(text: "[x](y)")]))
        XCTAssertEqual(round.plain, "[x](y)")
        XCTAssertNil(round.spans.first?.link)
    }

    func testTableRoundtrip() {
        let source = "Vorher\n\n| Name | Wert |\n| --- | --- |\n| **a** | 1 \\| 2 |\n| b |  |\n\nNachher\n"
        let blocks = MarkdownCodec.parse(source)
        XCTAssertEqual(blocks.map(\.type), [.paragraph, .tableRow, .tableRow, .tableRow, .paragraph])
        XCTAssertEqual(blocks[1].plain, "Name\tWert")
        XCTAssertEqual(blocks[2].plain, "a\t1 | 2")
        XCTAssertEqual(blocks[2].spans.first?.bold, true)
        XCTAssertEqual(MarkdownCodec.serialize(blocks), source)
    }

    func testTableRowsArePaddedToTheWidestRow() {
        let blocks = [
            Block(type: .tableRow, spans: [InlineSpan(text: "a\tb\tc")]),
            Block(type: .tableRow, spans: [InlineSpan(text: "d")]),
        ]
        XCTAssertEqual(MarkdownCodec.serialize(blocks), "| a | b | c |\n| --- | --- | --- |\n| d |  |  |\n")
    }

    func testBarsWithoutSeparatorStayText() {
        let blocks = MarkdownCodec.parse("| nur | Text |\n")
        XCTAssertEqual(blocks.map(\.type), [.paragraph])
    }

    func testXStartsATask() {
        XCTAssertEqual(BlockShortcut.type(forToken: "x"), .checkbox)
    }

    func testUnclosedMarkerStays() {
        let parsed = MarkdownCodec.parseInline("hello *wor")
        XCTAssertEqual(parsed.plain, "hello *wor")
        XCTAssertEqual(parsed.spans.first?.italic, false)
    }

    func testEscape() {
        let parsed = MarkdownCodec.parseInline(#"a \* b"#)
        XCTAssertEqual(parsed.plain, "a * b")
        let round = MarkdownCodec.parseInline(MarkdownCodec.serializeInline(parsed.spans))
        XCTAssertEqual(round.plain, "a * b")
    }

    func testCursorLandsAfterConsumedMarker() {
        let parsed = MarkdownCodec.parseInline("**ab**", cursorUTF16: 6)
        XCTAssertEqual(parsed.plain, "ab")
        XCTAssertEqual(parsed.cursorUTF16, 2)
    }

    func testEmptyDocument() {
        XCTAssertEqual(MarkdownCodec.serialize(MarkdownCodec.parse("")), "")
        XCTAssertEqual(MarkdownCodec.parse("").count, 1)
    }

    func testShortcut() {
        XCTAssertEqual(BlockShortcut.type(forToken: "#"), .heading1)
        XCTAssertEqual(BlockShortcut.type(forToken: "- [ ]"), .checkbox)
        XCTAssertEqual(BlockShortcut.type(forToken: "1."), .numbered)
        XCTAssertNil(BlockShortcut.type(forToken: "wort"))
    }

    func testSplitKeepsFormatting() {
        let block = Block(type: .paragraph, spans: [InlineSpan(text: "abcd", bold: true)])
        let (left, right) = MarkdownCodec.split(block, atUTF16: 2)
        XCTAssertEqual(left.plain, "ab")
        XCTAssertEqual(right.plain, "cd")
        XCTAssertEqual(right.type, .paragraph)
        XCTAssertTrue(left.spans[0].bold)
        XCTAssertEqual(left.id, block.id)
    }

    private func snapshots(_ blocks: [Block]) -> [String] {
        blocks.map { "\($0.type)|\($0.checked)|\($0.language)|\(MarkdownCodec.serializeInline($0.spans))" }
    }
}
