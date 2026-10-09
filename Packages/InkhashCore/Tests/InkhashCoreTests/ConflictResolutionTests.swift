import XCTest
@testable import InkhashCore

final class ConflictResolutionTests: XCTestCase {
    private let now = "2026-10-09T10:00:00Z"

    private func pair() -> NoteConflict {
        var local = Note.newText(now: "2026-10-01T08:00:00Z")
        local.applyMarkdown("# Plan\nlokal\n")
        local.revision = 3
        var server = local
        server.applyMarkdown("# Plan\nserver\n")
        server.revision = 5
        server.updatedAt = "2026-10-02T08:00:00Z"
        return NoteConflict(local: local, server: server)
    }

    func testMineGoesUpOnTopOfTheServerRevision() throws {
        let conflict = pair()
        let resolution = try XCTUnwrap(conflict.resolve(.mine, now: now))
        XCTAssertEqual(resolution.kept.note.markdown, conflict.local.markdown)
        XCTAssertEqual(resolution.kept.note.revision, 5)
        XCTAssertEqual(resolution.kept.meta, LocalMeta(dirty: true, conflict: false))
        XCTAssertNil(resolution.copy)
    }

    func testServerReplacesMineClean() throws {
        let conflict = pair()
        let resolution = try XCTUnwrap(conflict.resolve(.server, now: now))
        XCTAssertEqual(resolution.kept.note, conflict.server)
        XCTAssertEqual(resolution.kept.meta, .clean)
        XCTAssertNil(resolution.copy)
    }

    func testBothKeepsMineAndAddsTheServerVersionAsANewNote() throws {
        let conflict = pair()
        let resolution = try XCTUnwrap(conflict.resolve(.both, now: now))
        XCTAssertEqual(resolution.kept.note.markdown, conflict.local.markdown)
        XCTAssertEqual(resolution.kept.note.revision, 5)
        let copy = try XCTUnwrap(resolution.copy)
        XCTAssertNotEqual(copy.note.id, conflict.local.id)
        XCTAssertEqual(copy.note.revision, 0)
        XCTAssertEqual(copy.note.markdown, conflict.server.markdown)
        XCTAssertEqual(copy.note.title, "Plan (Server)")
        XCTAssertFalse(copy.note.hasAutomaticTitle)
        XCTAssertEqual(copy.note.folder, conflict.server.folder)
        XCTAssertEqual(copy.note.updatedAt, now)
        XCTAssertEqual(copy.meta, LocalMeta(dirty: true, conflict: false))
    }

    func testBothIsNotOfferedWhenOneSideDeleted() {
        var conflict = pair()
        conflict.server.deletedAt = "2026-10-02T09:00:00Z"
        XCTAssertFalse(conflict.canKeepBoth)
        XCTAssertEqual(conflict.choices, [.mine, .server])
        XCTAssertNil(conflict.resolve(.both, now: now))

        conflict = pair()
        conflict.local.deletedAt = "2026-10-02T09:00:00Z"
        XCTAssertNil(conflict.resolve(.both, now: now))
    }

    func testCopyTitleStaysWithinTheLimit() {
        var server = Note.newText(now: now)
        server.setTitle(String(repeating: "x", count: Limits.title))
        let copy = NoteConflict.copy(of: server, now: now)
        XCTAssertLessThanOrEqual(copy.title.utf16.count, Limits.title)
        XCTAssertTrue(copy.title.hasSuffix(" (Server)"))
    }

    func testCopyOfInkKeepsPagesAndBlobs() {
        let page = InkPage(blob: String(repeating: "a", count: 64), transcript: "Reise")
        var server = Note.newInk(page: page, now: now)
        server.transcript = "Reise"
        let copy = NoteConflict.copy(of: server, now: now)
        XCTAssertEqual(copy.pages, server.pages)
        XCTAssertEqual(copy.title, "Reise (Server)")
    }
}

final class LineDiffTests: XCTestCase {
    func testEqualTextsShareEveryLine() {
        XCTAssertEqual(LineDiff.compare("a\nb\n", "a\nb\n"), [.init("a", .both), .init("b", .both)])
    }

    func testChangedLineShowsOnBothSides() {
        XCTAssertEqual(
            LineDiff.compare("# Plan\nlokal\nende", "# Plan\nserver\nende"),
            [.init("# Plan", .both), .init("lokal", .left), .init("server", .right), .init("ende", .both)]
        )
    }

    func testAddedAndRemovedLines() {
        XCTAssertEqual(LineDiff.compare("a\nc", "a\nb\nc"), [.init("a", .both), .init("b", .right), .init("c", .both)])
        XCTAssertEqual(LineDiff.compare("a\nb\nc", "a\nc"), [.init("a", .both), .init("b", .left), .init("c", .both)])
    }

    func testEmptySides() {
        XCTAssertEqual(LineDiff.compare("", ""), [])
        XCTAssertEqual(LineDiff.compare("", "x"), [.init("x", .right)])
        XCTAssertEqual(LineDiff.compare("x\n", ""), [.init("x", .left)])
    }

    func testEmptyLinesInTheMiddleCount() {
        XCTAssertEqual(LineDiff.compare("a\n\nb", "a\nb"), [.init("a", .both), .init("", .left), .init("b", .both)])
    }

    func testVeryLongTextsAreShownWithoutMatching() {
        let long = Array(repeating: "x", count: LineDiff.limit + 1).joined(separator: "\n")
        let lines = LineDiff.compare(long, "x")
        XCTAssertEqual(lines.filter { $0.side == .both }.count, 0)
        XCTAssertEqual(lines.count, LineDiff.limit + 2)
    }
}
