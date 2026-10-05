import XCTest
@testable import InkhashCore

final class FixtureTests: XCTestCase {
    func testFixturesDecodeAndIdsStayLowercase() throws {
        let text = try load("note-text.json")
        let ink = try load("note-ink.json")
        XCTAssertEqual(text.kind, .text)
        XCTAssertEqual(text.tags, ["eigen"])
        XCTAssertEqual(text.displayTitle, "Inkhash")
        XCTAssertNil(text.transcript)
        XCTAssertEqual(ink.kind, .ink)
        XCTAssertEqual(ink.tags, ["alpen"])
        XCTAssertEqual(ink.displayTitle, "Reise #alpen")
        XCTAssertEqual(ink.pages?.first?.blob.count, 64)

        let encoded = try InkhashJSON.decode(Note.self, from: InkhashJSON.encode(text))
        let json = try XCTUnwrap(String(data: InkhashJSON.encode(encoded), encoding: .utf8))
        XCTAssertTrue(json.contains(text.id.uuidString.lowercased()))
        XCTAssertFalse(json.contains(text.id.uuidString.lowercased().uppercased()))
    }

    func testApplyMarkdownExtractsTagsWithoutTouchingInkTitleRule() {
        var note = Note.newText(now: "2026-09-30T06:00:00Z")
        XCTAssertTrue(note.applyMarkdown("# Plan\n\nSiehe #launch\n"))
        XCTAssertEqual(note.title, "Plan")
        XCTAssertEqual(note.tags, ["launch"])
        XCTAssertFalse(note.applyMarkdown("# Plan\n\nSiehe #launch\n"))
    }

    private func load(_ name: String) throws -> Note {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let fixture = url.appendingPathComponent("docs/fixtures").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: fixture.path) {
                return try InkhashJSON.decode(Note.self, from: Data(contentsOf: fixture))
            }
        }
        XCTFail("fixture missing: \(name)")
        throw InkhashError.invalidID
    }
}
