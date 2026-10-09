import InkhashCore
import XCTest
@testable import Inkhash

@MainActor
final class NoteLibraryTests: LibraryTestCase {
    private func conflicted() throws -> (local: Note, server: Note) {
        let local = try syncedText("# Plan\nlokal\n", revision: 2)
        var server = local
        server.applyMarkdown("# Plan\nserver\n")
        server.revision = 4
        try makeConflict(local, server: server)
        return (local, server)
    }

    func testTypingKeepsTheConflict() throws {
        let (local, server) = try conflicted()
        library.updateMarkdown(id: local.id, markdown: "# Plan\nlokal und mehr\n")
        let record = try XCTUnwrap(library.record(local.id))
        XCTAssertTrue(record.conflict)
        XCTAssertTrue(record.dirty)
        XCTAssertEqual(try store.meta(for: local.id).conflict, true)
        XCTAssertEqual(try store.conflictNote(id: local.id)?.markdown, server.markdown)
    }

    func testConflictShowsBothVersions() throws {
        let (local, server) = try conflicted()
        let conflict = try XCTUnwrap(library.conflict(local.id))
        XCTAssertEqual(conflict.local.markdown, local.markdown)
        XCTAssertEqual(conflict.server.markdown, server.markdown)
        XCTAssertNil(library.conflict(UUID()))
    }

    func testKeepMineGoesUpOnTheServerRevision() throws {
        let (local, _) = try conflicted()
        var told = 0
        library.changed = { told += 1 }
        XCTAssertEqual(library.resolveConflict(id: local.id, choice: .mine), local.id)
        let record = try XCTUnwrap(library.record(local.id))
        XCTAssertFalse(record.conflict)
        XCTAssertTrue(record.dirty)
        XCTAssertEqual(record.note.revision, 4)
        XCTAssertEqual(record.note.markdown, local.markdown)
        XCTAssertNil(try store.conflictNote(id: local.id))
        XCTAssertEqual(told, 1)
    }

    func testTakeServerIsClean() throws {
        let (local, server) = try conflicted()
        library.resolveConflict(id: local.id, choice: .server)
        let stored = try XCTUnwrap(store.note(id: local.id))
        XCTAssertEqual(stored, server)
        XCTAssertEqual(try store.meta(for: local.id), .clean)
        XCTAssertNil(library.conflict(local.id))
    }

    func testKeepBothAddsTheServerVersionAsANewNote() throws {
        let (local, server) = try conflicted()
        library.resolveConflict(id: local.id, choice: .both)
        XCTAssertEqual(library.records.count, 2)
        let copy = try XCTUnwrap(library.records.first { $0.id != local.id })
        XCTAssertEqual(copy.note.markdown, server.markdown)
        XCTAssertEqual(copy.note.title, "Plan (Server)")
        XCTAssertEqual(copy.note.revision, 0)
        XCTAssertTrue(copy.dirty)
        XCTAssertEqual(try store.note(id: copy.id)?.markdown, server.markdown)
        XCTAssertEqual(library.record(local.id)?.note.markdown, local.markdown)
        XCTAssertEqual(library.record(local.id)?.conflict, false)
    }

    func testResolvingWithoutConflictDoesNothing() throws {
        let note = try syncedText("# Ruhig\n")
        XCTAssertNil(library.resolveConflict(id: note.id, choice: .mine))
        XCTAssertEqual(library.records.count, 1)
    }

    func testEditsKeepTheirConflictToo() throws {
        let (local, _) = try conflicted()
        library.rename(id: local.id, title: "Neu")
        library.toggleFavorite(id: local.id)
        XCTAssertEqual(library.record(local.id)?.conflict, true)
    }

    func testEmptyTrashRemovesOnlyWhatIsSettled() throws {
        var gone = try syncedText("# Weg\n")
        gone.deletedAt = "2026-10-02T08:00:00Z"
        try store.save(note: gone, meta: .clean)
        var waiting = try syncedText("# Wartet\n")
        waiting.deletedAt = "2026-10-02T08:00:00Z"
        try store.save(note: waiting, meta: LocalMeta(dirty: true, conflict: false))
        library.reload()
        library.emptyTrash(syncs: true)
        XCTAssertNil(library.record(gone.id))
        XCTAssertNotNil(library.record(waiting.id))
    }
}
