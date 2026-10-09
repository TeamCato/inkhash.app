import XCTest
@testable import InkhashCore

final class PaperTests: XCTestCase {
    private func inkNote(pages count: Int) -> (Note, [InkPage]) {
        let pages = (0..<count).map { index in
            InkPage(blob: String(repeating: "a", count: 64), transcript: "Seite \(index) #s\(index)", tags: ["s\(index)"])
        }
        var note = Note.newInk(page: pages[0])
        note.pages = pages
        return (note, pages)
    }

    func testStandardPaperIsLeftOutAndRoundTrips() throws {
        var note = Note.newText(now: "2026-10-05T10:00:00Z")
        let plain = String(decoding: try InkhashJSON.encode(note), as: UTF8.self)
        XCTAssertFalse(plain.contains("paper"), "standard paper stays off the wire")

        XCTAssertTrue(note.setPaper(Paper(color: "#faf5e8", pattern: .grid)))
        XCTAssertEqual(note.paper, Paper(color: "#FAF5E8", pattern: .blank), "a text note has only a colour")
        let decoded = try InkhashJSON.decode(Note.self, from: try InkhashJSON.encode(note))
        XCTAssertEqual(decoded.paper, note.paper)

        XCTAssertTrue(note.setPaper(.standard))
        XCTAssertNil(note.paper)
        XCTAssertFalse(note.setPaper(.standard))
    }

    func testInkPaperKeepsPatternAndCountsAsContent() {
        let (note, _) = inkNote(pages: 1)
        var lined = note
        XCTAssertTrue(lined.setPaper(Paper(color: "#FDFDFC", pattern: .lines)))
        XCTAssertEqual(lined.paper?.pattern, .lines)
        XCTAssertFalse(lined.sameContent(as: note))
    }

    func testUnknownPatternReadsAsBlank() throws {
        let json = ##"{"color":"#ecf4ea","pattern":"hexagons"}"##
        let paper = try InkhashJSON.decode(Paper.self, from: Data(json.utf8))
        XCTAssertEqual(paper, Paper(color: "#ECF4EA", pattern: .blank))
        XCTAssertEqual(Paper.standard.components?.red ?? 0, 253.0 / 255, accuracy: 0.0001)
        XCTAssertNil(Paper(color: "blau").components)
    }

    func testSpacingIsNormalizedAndRoundTrips() throws {
        XCTAssertNil(Paper(color: "#FDFDFC", pattern: .grid, spacing: 32).spacing, "the default is not stored")
        XCTAssertNil(Paper(color: "#FDFDFC", pattern: .blank, spacing: 40).spacing, "blank paper has no spacing")
        XCTAssertEqual(Paper(color: "#FDFDFC", pattern: .lines, spacing: 4).spacing, 20)
        XCTAssertEqual(Paper(color: "#FDFDFC", pattern: .dots, spacing: 900).spacing, 64)
        XCTAssertEqual(Paper(color: "#FDFDFC", pattern: .lines).shownSpacing, 36)

        let wide = Paper(color: "#FDFDFC", pattern: .dots, spacing: 48)
        XCTAssertEqual(wide.shownSpacing, 48)
        let plain = String(decoding: try InkhashJSON.encode(Paper(color: "#FDFDFC", pattern: .dots)), as: UTF8.self)
        XCTAssertFalse(plain.contains("spacing"), "the default spacing stays off the wire")
        XCTAssertEqual(try InkhashJSON.decode(Paper.self, from: try InkhashJSON.encode(wide)), wide)

        let odd = ##"{"color":"#FDFDFC","pattern":"grid","spacing":500}"##
        XCTAssertNil(try InkhashJSON.decode(Paper.self, from: Data(odd.utf8)).spacing, "out of range reads as default")
        let fraction = ##"{"color":"#FDFDFC","pattern":"grid","spacing":30.5}"##
        XCTAssertNil(try InkhashJSON.decode(Paper.self, from: Data(fraction.utf8)).spacing)
    }

    func testSpacingCountsAsContentAndTextNotesDropIt() {
        let (note, _) = inkNote(pages: 1)
        var dotted = note
        XCTAssertTrue(dotted.setPaper(Paper(color: "#FDFDFC", pattern: .dots)))
        var wide = dotted
        XCTAssertTrue(wide.setPaper(Paper(color: "#FDFDFC", pattern: .dots, spacing: 48)))
        XCTAssertFalse(wide.sameContent(as: dotted))

        var text = Note.newText(now: "2026-10-09T10:00:00Z")
        XCTAssertTrue(text.setPaper(Paper(color: "#FAF5E8", pattern: .lines, spacing: 48)))
        XCTAssertEqual(text.paper, Paper(color: "#FAF5E8"))
    }

    func testReorderAndMoveFollowTranscriptAndTags() {
        var (note, pages) = inkNote(pages: 3)
        XCTAssertTrue(note.reorderPages([pages[2].id, pages[0].id, pages[1].id]))
        XCTAssertEqual(note.pages?.map(\.id), [pages[2].id, pages[0].id, pages[1].id])
        XCTAssertEqual(note.transcript, "Seite 2 #s2\n\nSeite 0 #s0\n\nSeite 1 #s1")
        XCTAssertEqual(note.tags, ["s2", "s0", "s1"])

        XCTAssertFalse(note.reorderPages([pages[0].id, pages[1].id]), "every page must be named")
        XCTAssertFalse(note.reorderPages([pages[2].id, pages[0].id, pages[1].id]), "same order is no change")

        XCTAssertTrue(note.movePage(pages[2].id, by: 5))
        XCTAssertEqual(note.pages?.map(\.id), [pages[0].id, pages[1].id, pages[2].id])
        XCTAssertFalse(note.movePage(pages[2].id, by: 1), "already last")
        XCTAssertTrue(note.movePage(pages[1].id, by: -1))
        XCTAssertEqual(note.pages?.first?.id, pages[1].id)
    }

    func testRemovingAPageKeepsTheLastOne() {
        var (note, pages) = inkNote(pages: 2)
        XCTAssertTrue(note.removePage(pages[0].id))
        XCTAssertEqual(note.pages?.map(\.id), [pages[1].id])
        XCTAssertEqual(note.transcript, "Seite 1 #s1")
        XCTAssertEqual(note.tags, ["s1"])
        XCTAssertFalse(note.removePage(pages[1].id), "a note keeps one page")
        XCTAssertFalse(note.removePage(UUID()))
    }
}
