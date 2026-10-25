import XCTest
@testable import InkhashCore

final class NoteFindTests: XCTestCase {
    func testFindsEveryPlaceIgnoringCaseAndAccents() {
        let text = "Über den Pass, über die Brücke. ÜBER alles."
        let ranges = NoteFind.ranges(of: "uber", in: text)
        XCTAssertEqual(ranges.map { (text as NSString).substring(with: $0) }, ["Über", "über", "ÜBER"])
    }

    func testEmptyOrBlankQueryFindsNothing() {
        XCTAssertTrue(NoteFind.ranges(of: "", in: "abc").isEmpty)
        XCTAssertTrue(NoteFind.ranges(of: "  ", in: "a  b").isEmpty)
    }

    func testMatchesDoNotOverlap() {
        XCTAssertEqual(NoteFind.ranges(of: "aa", in: "aaaa"), [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2)])
    }

    func testRangesAreUTF16Offsets() {
        let text = "📅 Termin, Termin"
        let ranges = NoteFind.ranges(of: "termin", in: text)
        XCTAssertEqual(ranges.first?.location, 3)
        XCTAssertEqual(ranges.count, 2)
    }

    func testCurrentStartsAtAnchorAndWraps() {
        var find = NoteFind()
        find.update(query: "a", in: "a b a b a", anchor: 3)
        XCTAssertEqual(find.current, 1)
        XCTAssertEqual(find.countLabel, "2 von 3")
        find.next()
        find.next()
        XCTAssertEqual(find.current, 0)
        find.previous()
        XCTAssertEqual(find.current, 2)
    }

    func testAnchorAfterLastMatchWrapsToFirst() {
        var find = NoteFind()
        find.update(query: "a", in: "a b a", anchor: 5)
        XCTAssertEqual(find.current, 0)
    }

    func testNoMatchSaysSo() {
        var find = NoteFind()
        find.update(query: "zebra", in: "a b", anchor: 0)
        XCTAssertNil(find.current)
        XCTAssertNil(find.currentRange)
        XCTAssertEqual(find.countLabel, "Keine Treffer")
        find.next()
        XCTAssertNil(find.current)
        find.update(query: "", in: "a b", anchor: 0)
        XCTAssertEqual(find.countLabel, "")
    }
}
