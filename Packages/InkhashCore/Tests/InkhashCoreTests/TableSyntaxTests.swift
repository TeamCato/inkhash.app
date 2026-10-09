import XCTest
@testable import InkhashCore

final class TableSyntaxTests: XCTestCase {
    func testHeaderLines() {
        XCTAssertEqual(TableSyntax.headerCells("| a | b |"), ["a", "b"])
        XCTAssertEqual(TableSyntax.headerCells("  |Name|Wert"), ["Name", "Wert"])
        XCTAssertEqual(TableSyntax.headerCells("| eins |"), ["eins"])
        XCTAssertNil(TableSyntax.headerCells("a | b"))
        XCTAssertNil(TableSyntax.headerCells("| nur ein Strich"))
        XCTAssertNil(TableSyntax.headerCells(""))
    }

    func testCellsAndColumns() {
        XCTAssertEqual(TableSyntax.cellCount("a\tb\tc"), 3)
        XCTAssertEqual(TableSyntax.cellCount(""), 1)
        XCTAssertEqual(TableSyntax.column(before: "a\tb"), 1)
        XCTAssertEqual(TableSyntax.column(before: ""), 0)
        XCTAssertEqual(TableSyntax.emptyRow(columns: 3), "\t\t")
        XCTAssertEqual(TableSyntax.emptyRow(columns: 0), "")
    }

    func testEmptyRows() {
        XCTAssertTrue(TableSyntax.isEmptyRow("\t \t"))
        XCTAssertTrue(TableSyntax.isEmptyRow(""))
        XCTAssertFalse(TableSyntax.isEmptyRow("\tx\t"))
    }
}
