import XCTest
@testable import InkhashCore

@MainActor
final class LibraryTests: XCTestCase {
    private let accountA = "aaaaaaaa-1111-4111-8111-111111111111"
    private let accountB = "bbbbbbbb-2222-4222-8222-222222222222"

    func testFreshLibraryWorksWithoutAccount() throws {
        let base = freshBase()
        let library = try Library.open(base: base, signedInAccount: nil)
        var note = Note.newText(now: "2026-10-01T06:00:00Z")
        note.applyMarkdown("nur hier\n")
        try library.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        XCTAssertNil(library.boundAccount())
        let reopened = try Library.open(base: base, signedInAccount: nil)
        XCTAssertEqual(try reopened.note(id: note.id)?.markdown, "nur hier\n")
    }

    func testSidebarPrefsStayOnTheDevice() throws {
        let base = freshBase()
        let library = try Library.open(base: base, signedInAccount: nil)
        XCTAssertEqual(library.sidebar(), SidebarPrefs())
        try library.setSidebar(SidebarPrefs(collapsed: ["Reisen"]))
        let reopened = try Library.open(base: base, signedInAccount: nil)
        XCTAssertEqual(reopened.sidebar(), SidebarPrefs(collapsed: ["Reisen"]))
    }

    func testMigrationKeepsSignedInAccountAndAddsSignedOutNotes() throws {
        let base = freshBase()
        let accounts = base.appendingPathComponent("accounts")
        let old = try LocalStore(root: accounts.appendingPathComponent(accountA))
        var synced = Note.newText(now: "2026-10-01T06:00:00Z")
        synced.applyMarkdown("vom server\n")
        synced.revision = 3
        try old.save(note: synced, meta: .clean)
        try old.setCursor(7)

        let signedOut = try LocalStore(root: base.appendingPathComponent("signed-out"))
        let sha = try signedOut.putBlob(Data("stroke".utf8))
        let loose = Note.newInk(page: InkPage(blob: sha), now: "2026-10-01T06:00:00Z")
        try signedOut.save(note: loose, meta: LocalMeta(dirty: true, conflict: false))

        let foreign = try LocalStore(root: accounts.appendingPathComponent(accountB))
        try foreign.save(note: Note.newText(now: "2026-10-01T06:00:00Z"), meta: .clean)

        let library = try Library.open(base: base, signedInAccount: accountA)
        XCTAssertEqual(library.boundAccount(), accountA)
        XCTAssertEqual(try library.cursor(), 7)
        XCTAssertEqual(try library.note(id: synced.id)?.revision, 3)
        XCTAssertEqual(try library.meta(for: synced.id).dirty, false)
        XCTAssertEqual(try library.note(id: loose.id)?.revision, 0)
        XCTAssertEqual(try library.meta(for: loose.id).dirty, true)
        XCTAssertEqual(try library.blob(sha), Data("stroke".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("signed-out/notes").path))
        XCTAssertEqual(try LocalStore(root: accounts.appendingPathComponent(accountB)).list().count, 1, "other accounts stay untouched")
    }

    func testBindingTheSameAccountResumes() throws {
        let library = try Library.open(base: freshBase(), signedInAccount: nil)
        try library.setBoundAccount(accountA)
        var note = Note.newText(now: "2026-10-01T06:00:00Z")
        note.revision = 2
        try library.save(note: note, meta: .clean)
        try library.setCursor(4)
        XCTAssertFalse(try Library.bind(library, to: accountA))
        XCTAssertEqual(try library.note(id: note.id)?.revision, 2)
        XCTAssertEqual(try library.cursor(), 4)
    }

    func testBindingAnotherAccountTurnsEverythingIntoNewNotes() throws {
        let library = try Library.open(base: freshBase(), signedInAccount: nil)
        try library.setBoundAccount(accountA)
        try library.setCursor(5)
        var kept = Note.newText(now: "2026-10-01T06:00:00Z")
        kept.applyMarkdown("bleibt\n")
        kept.revision = 2
        try library.save(note: kept, meta: .clean)
        var gone = Note.newText(now: "2026-10-01T06:00:00Z")
        gone.revision = 3
        gone.deletedAt = "2026-10-01T07:00:00Z"
        try library.save(note: gone, meta: .clean)
        var mine = Note.newText(now: "2026-10-01T06:00:00Z")
        mine.applyMarkdown("meine fassung\n")
        mine.revision = 1
        var theirs = mine
        theirs.applyMarkdown("server fassung\n")
        theirs.revision = 2
        try library.save(note: mine, meta: LocalMeta(dirty: true, conflict: true))
        try library.saveConflict(theirs)

        XCTAssertTrue(try Library.bind(library, to: accountB))
        XCTAssertEqual(library.boundAccount(), accountB)
        XCTAssertEqual(try library.cursor(), 0)
        XCTAssertNil(try library.note(id: gone.id))
        let notes = try library.list()
        XCTAssertEqual(notes.count, 3)
        XCTAssertTrue(notes.allSatisfy { $0.note.revision == 0 && $0.meta.dirty && !$0.meta.conflict })
        XCTAssertEqual(Set(notes.compactMap(\.note.markdown)), ["bleibt\n", "meine fassung\n", "server fassung\n"])
        XCTAssertNil(try library.conflictNote(id: mine.id))
    }

    func testSwitchingAccountsUploadsEverything() async throws {
        let library = try Library.open(base: freshBase(), signedInAccount: nil)
        var note = Note.newText(now: "2026-10-01T06:00:00Z")
        note.applyMarkdown("lokal geschrieben\n")
        try library.save(note: note, meta: LocalMeta(dirty: true, conflict: false))

        let serverA = FakeTransport()
        try Library.bind(library, to: accountA)
        _ = try await Syncer.sync(store: library, transport: serverA)
        XCTAssertEqual(serverA.notes[note.id]?.markdown, "lokal geschrieben\n")

        let serverB = FakeTransport()
        var other = Note.newText(now: "2026-10-01T06:00:00Z")
        other.applyMarkdown("schon in b\n")
        other.revision = 1
        serverB.seed(other, cursor: 1)
        try Library.bind(library, to: accountB)
        let report = try await Syncer.sync(store: library, transport: serverB)
        XCTAssertEqual(report.conflicts, 0)
        XCTAssertEqual(serverB.notes[note.id]?.markdown, "lokal geschrieben\n")
        XCTAssertEqual(try library.note(id: other.id)?.markdown, "schon in b\n")
    }

    private func freshBase() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
