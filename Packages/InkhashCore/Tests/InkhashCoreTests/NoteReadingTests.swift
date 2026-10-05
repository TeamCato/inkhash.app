import XCTest
@testable import InkhashCore

final class NoteReadingTests: XCTestCase {
    func testEmptyReadingOfInkedPageKeepsTranscript() {
        let page = InkPage(blob: String(repeating: "a", count: 64))
        var note = Note.newInk(page: page)
        XCTAssertTrue(note.applyInkReading(pageID: page.id, transcript: "Einkauf #liste", tags: ["liste"], pageHasInk: true))
        XCTAssertFalse(note.applyInkReading(pageID: page.id, transcript: "", tags: [], pageHasInk: true), "recognition failed")
        XCTAssertEqual(note.transcript, "Einkauf #liste")
        XCTAssertEqual(note.tags, ["liste"])
        XCTAssertTrue(note.applyInkReading(pageID: page.id, transcript: "", tags: [], pageHasInk: false), "page erased")
        XCTAssertEqual(note.transcript, "")
        XCTAssertEqual(note.tags, [])
    }
}

final class LimitsTests: XCTestCase {
    func testClippingCountsUTF16AndKeepsWholeCharacters() {
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(family.utf16.count, 11)
        XCTAssertEqual(String(repeating: family, count: 3).clippedUTF16(30), family + family)
        XCTAssertEqual("abc".clippedUTF16(200), "abc")
        XCTAssertEqual("äöü".clippedUTF16(2), "äö")
    }

    func testTitleFitsTheServer() {
        var note = Note.newText(now: "2026-10-04T10:00:00Z")
        note.setTitle(String(repeating: "👨‍👩‍👧‍👦", count: 120))
        XCTAssertLessThanOrEqual(note.title.utf16.count, Limits.title)
        note.applyMarkdown("# " + String(repeating: "👨‍👩‍👧‍👦", count: 80) + "\n")
        note.setTitle("")
        XCTAssertLessThanOrEqual(note.title.utf16.count, Limits.title)
    }

    func testAtMostFiftyTagsFirstOnesWin() {
        let text = (1...60).map { "#t\($0)" }.joined(separator: " ")
        let tags = Hashtags.inText(text, mode: .markdown)
        XCTAssertEqual(tags.count, Limits.tagsPerNote)
        XCTAssertEqual(tags.first, "t1")
        XCTAssertEqual(tags.last, "t50")
    }

    func testFolderSegmentsFitTheServer() {
        let segment = Folders.segment(String(repeating: "👨‍👩‍👧‍👦", count: 40))
        XCTAssertNotNil(segment)
        XCTAssertLessThanOrEqual(segment?.utf16.count ?? 0, Folders.maxSegment)
        XCTAssertTrue(Folders.isValid(segment ?? ""))
    }
}
