import XCTest
@testable import InkhashCore

final class CreatedAtTests: XCTestCase {
    func testNewNoteCarriesItsCreationDateOnTheWire() throws {
        let note = Note.newText(now: "2026-10-09T10:00:00Z")
        XCTAssertEqual(note.createdAt, "2026-10-09T10:00:00Z")
        let decoded = try InkhashJSON.decode(Note.self, from: try InkhashJSON.encode(note))
        XCTAssertEqual(decoded.createdAt, "2026-10-09T10:00:00Z")
    }

    func testOldNoteFallsBackToUpdatedAtAndKeepsItOnTheNextChange() throws {
        var old = Note.newText(now: "2026-01-02T08:00:00Z")
        old.createdAt = nil
        let json = String(decoding: try InkhashJSON.encode(old), as: UTF8.self)
        XCTAssertFalse(json.contains("createdAt"), "a missing date stays off the wire")

        var note = try InkhashJSON.decode(Note.self, from: Data(json.utf8))
        XCTAssertNil(note.createdAt)
        XCTAssertEqual(note.shownCreatedAt, "2026-01-02T08:00:00Z")

        note.touch("2026-10-09T10:00:00Z")
        XCTAssertEqual(note.createdAt, "2026-01-02T08:00:00Z")
        XCTAssertEqual(note.updatedAt, "2026-10-09T10:00:00Z")

        note.touch("2026-10-09T11:00:00Z")
        XCTAssertEqual(note.createdAt, "2026-01-02T08:00:00Z", "the date does not move with later edits")
    }

    func testSetByHandIsContentButAMissingDateIsNot() {
        var note = Note.newText(now: "2026-10-09T10:00:00Z")
        XCTAssertFalse(note.setCreatedAt("2026-10-09T10:00:00Z"), "same date, no change")
        XCTAssertFalse(note.setCreatedAt("gestern"))
        let before = note
        XCTAssertTrue(note.setCreatedAt("2026-09-01T09:30:00Z"))
        XCTAssertEqual(note.createdAt, "2026-09-01T09:30:00Z")
        XCTAssertFalse(note.sameContent(as: before))

        var old = before
        old.createdAt = nil
        XCTAssertTrue(old.sameContent(as: before))
    }
}
