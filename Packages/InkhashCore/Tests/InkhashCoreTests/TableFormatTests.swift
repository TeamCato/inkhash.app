import XCTest
@testable import InkhashCore

/// ADR 0036: table alignment, widths, header and zebra.
final class TableFormatTests: XCTestCase {
    func testPlainTableStaysAsBefore() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let blocks = MarkdownCodec.parse(source)
        XCTAssertNil(blocks[0].table)
        XCTAssertEqual(MarkdownCodec.serialize(blocks), source)
    }

    func testAlignmentIsMarkdown() {
        let source = "| A | B | C |\n| --- | :---: | ---: |\n| 1 | 2 | 3 |\n"
        let blocks = MarkdownCodec.parse(source)
        XCTAssertEqual(blocks[0].table?.alignments, [.left, .center, .right])
        XCTAssertEqual(MarkdownCodec.serialize(blocks), source)
        // A leading colon alone is left, as in Markdown.
        XCTAssertNil(MarkdownCodec.parse("| A |\n| :--- |\n").first?.table)
    }

    func testCommentCarriesWidthsHeaderAndZebra() {
        let source = "| A | B |\n| --- | --- |\n| 1 | 2 |\n<!-- inkhash:table widths=30,70 header=off zebra -->\n\nDanach\n"
        let blocks = MarkdownCodec.parse(source)
        XCTAssertEqual(blocks.map(\.type), [.tableRow, .tableRow, .paragraph])
        let style = blocks[0].table
        XCTAssertEqual(style?.widths, [30, 70])
        XCTAssertEqual(style?.header, false)
        XCTAssertEqual(style?.zebra, true)
        XCTAssertEqual(MarkdownCodec.serialize(blocks), source)
    }

    func testUnknownWordsInTheCommentAreIgnored() {
        let blocks = MarkdownCodec.parse("| A |\n| --- |\n<!-- inkhash:table zebra future=1 -->\n")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].table?.zebra, true)
    }

    func testCommentElsewhereStaysText() {
        let blocks = MarkdownCodec.parse("Text\n\n<!-- inkhash:table zebra -->\n")
        XCTAssertEqual(blocks.map(\.type), [.paragraph, .paragraph])
    }

    func testWidthsThatDoNotFitTheColumnsAreEqual() {
        let style = TableFormat(widths: [30, 70])
        XCTAssertEqual(style.shares(columns: 3), [1 / 3.0, 1 / 3.0, 1 / 3.0])
        XCTAssertNil(TableFormat.plain.comment(columns: 2))
    }

    func testResizingTakesFromTheOthers() {
        let wider = TableFormat.plain.resizing(column: 0, by: 0.1, columns: 2)
        XCTAssertEqual(wider.widths, [0.6, 0.4])
        let narrowest = TableFormat.plain.resizing(column: 0, by: -1, columns: 2)
        XCTAssertEqual(narrowest.widths, [0.08, 0.92])
        let shares = TableFormat.plain.resizing(column: 1, by: 0.2, columns: 3).shares(columns: 3)
        XCTAssertEqual(shares.reduce(0, +), 1, accuracy: 0.001)
        XCTAssertGreaterThan(shares[1], shares[0])
    }
}
