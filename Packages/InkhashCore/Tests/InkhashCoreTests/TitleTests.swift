import XCTest
@testable import InkhashCore

final class TitleTests: XCTestCase {
    func testTitleFollowsTheTextUntilSetByHand() {
        var note = Note.newText(now: "2026-10-01T06:00:00Z")
        note.applyMarkdown("# Einkauf\nMilch\n")
        XCTAssertEqual(note.title, "Einkauf")
        XCTAssertTrue(note.hasAutomaticTitle)

        note.applyMarkdown("# Wocheneinkauf\nMilch\n")
        XCTAssertEqual(note.title, "Wocheneinkauf")

        XCTAssertTrue(note.setTitle("Samstag"))
        XCTAssertFalse(note.hasAutomaticTitle)
        note.applyMarkdown("# Ganz anders\n")
        XCTAssertEqual(note.title, "Samstag", "a typed title stays")
    }

    func testEmptyTitleHandsItBackToTheText() {
        var note = Note.newText(now: "2026-10-01T06:00:00Z")
        note.applyMarkdown("Erste Zeile\nzweite\n")
        note.setTitle("Fest")
        note.setTitle("   ")
        XCTAssertEqual(note.title, "Erste Zeile")
        XCTAssertTrue(note.hasAutomaticTitle)
    }

    func testInkTitleFallsBackToTranscript() {
        var note = Note.newInk(page: InkPage(blob: String(repeating: "a", count: 64)), now: "2026-10-01T06:00:00Z")
        note.transcript = "Reise nach Wien\nmehr"
        XCTAssertTrue(note.hasAutomaticTitle)
        XCTAssertEqual(note.automaticTitle, "Reise nach Wien")
        XCTAssertEqual(note.displayTitle, "Reise nach Wien")
        note.setTitle("Wien")
        XCTAssertEqual(note.displayTitle, "Wien")
        XCTAssertFalse(note.hasAutomaticTitle)
    }

    func testHandTitleSurvivesSyncRoundtrip() throws {
        var note = Note.newText(now: "2026-10-01T06:00:00Z")
        note.applyMarkdown("# Auto\n")
        note.setTitle("Hand")
        let decoded = try InkhashJSON.decode(Note.self, from: InkhashJSON.encode(note))
        var other = decoded
        other.applyMarkdown("# Auto\nmehr\n")
        XCTAssertEqual(other.title, "Hand")
    }
}
