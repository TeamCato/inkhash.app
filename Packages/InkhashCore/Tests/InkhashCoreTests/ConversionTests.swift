import Foundation
import XCTest
@testable import InkhashCore

/// Encrypted workspaces become plain ones, and other devices follow, without losing notes (ADR 0077).
@MainActor
final class ConversionTests: XCTestCase {
    private let server = UUID()

    private func remote(_ id: String, _ name: String, sealed: Bool, storage: String? = nil, moving: Bool = false) -> RemoteWorkspace {
        RemoteWorkspace(
            id: id, name: name, sealed: sealed, storageId: storage,
            move: moving ? RemoteMove(to: "x", state: "running") : nil)
    }

    private func step(
        remotes: [RemoteWorkspace], readable: Bool = true, canPlain: Bool = true, overlap: [String: Int] = [:],
        hasSyncedNotes: Bool = true, taken: Set<String> = []
    ) -> ConversionStep {
        ConversionPlanner.step(
            name: "Arbeit", link: WorkspaceLink(server: server, remote: "old"), remotes: remotes, taken: taken,
            readable: readable, canPlain: canPlain, overlap: overlap, hasSyncedNotes: hasSyncedNotes)
    }

    // MARK: Planner

    func testADeviceWithTheNewestStateConverts() {
        XCTAssertEqual(step(remotes: [remote("old", "Arbeit", sealed: true)]), .convert)
    }

    func testWithoutTheKeyAndWithUnreadNotesItWaits() {
        XCTAssertEqual(step(remotes: [remote("old", "Arbeit", sealed: true)], readable: false), .waitForKey)
    }

    func testAKennelWithoutPlainWorkspacesOrAMoveMakesItWait() {
        XCTAssertEqual(step(remotes: [remote("old", "Arbeit", sealed: true)], canPlain: false), .waitForKennel)
        XCTAssertEqual(step(remotes: [remote("old", "Arbeit", sealed: true, moving: true)]), .waitForKennel)
    }

    func testOnceTheOldIsGoneTheNamesakeWithSharedNotesIsFollowed() {
        let other = remote("b", "Arbeit", sealed: false)
        let successor = remote("a", " arbeit ", sealed: false)
        XCTAssertEqual(step(remotes: [other, successor], overlap: ["a": 3, "b": 0]), .follow(successor))
    }

    func testANamesakeSharingNoNotesIsNoSuccessor() {
        XCTAssertEqual(step(remotes: [remote("a", "Arbeit", sealed: false)], overlap: ["a": 0]), .keepHere)
    }

    func testAnEmptyWorkspaceFollowsItsOnlyNamesake() {
        let only = remote("a", "Arbeit", sealed: false)
        XCTAssertEqual(step(remotes: [only], hasSyncedNotes: false), .follow(only))
        XCTAssertEqual(step(remotes: [only, remote("b", "Arbeit", sealed: false)], hasSyncedNotes: false), .keepHere)
    }

    func testEncryptedOrTakenNamesakesDoNotCount() {
        let sealed = remote("a", "Arbeit", sealed: true)
        let taken = remote("b", "Arbeit", sealed: false)
        XCTAssertEqual(step(remotes: [sealed, taken], overlap: ["a": 5, "b": 5], taken: ["b"]), .keepHere)
    }

    func testTheConvertingDeviceJoinsATwinOnTheSameStorage() {
        let old = remote("old", "Arbeit", sealed: true, storage: "nas")
        let elsewhere = remote("a", "Arbeit", sealed: false)
        let twin = remote("b", "Arbeit", sealed: false, storage: "nas")
        XCTAssertEqual(ConversionPlanner.twin(of: old, named: "Arbeit", among: [old, elsewhere, twin], taken: []), twin)
        XCTAssertNil(ConversionPlanner.twin(of: old, named: "Arbeit", among: [old, elsewhere], taken: []))
    }

    // MARK: Relinker

    func testAdoptingAnEmptySuccessorSendsEverythingAndKeepsTheTrash() async throws {
        let store = try freshStore()
        let kept = try note("# Bleibt\n", revision: 4, in: store)
        var trashed = try note("# Weg\n", revision: 2, in: store)
        trashed.deletedAt = "2026-10-02T08:00:00Z"
        try store.save(note: trashed, meta: .clean)
        try store.setBoundAccount("acc/old")

        try await Relinker.adopt(store, from: FakeTransport(), bindingKey: "acc/new")

        XCTAssertEqual(store.boundAccount(), "acc/new")
        XCTAssertEqual(try store.note(id: kept.id)?.revision, 0)
        XCTAssertEqual(try store.meta(for: kept.id).dirty, true, "goes up to the new workspace")
        XCTAssertNotNil(try store.note(id: trashed.id), "the trash stays on this device")
        XCTAssertEqual(try store.meta(for: trashed.id).dirty, false)

        let successor = FakeTransport()
        let report = try await Syncer.sync(store: store, transport: successor)
        XCTAssertEqual(report.conflicts, 0)
        XCTAssertEqual(successor.notes[kept.id]?.markdown, "# Bleibt\n")
        XCTAssertNil(successor.notes[trashed.id])
    }

    func testFollowingKeepsLocalEditsAndTakesTheRest() async throws {
        let store = try freshStore()
        let untouched = try note("# Alt\n", revision: 3, in: store)
        var edited = try note("# Vorher\n", revision: 3, in: store)
        edited.applyMarkdown("# Hier geändert\n")
        try store.save(note: edited, meta: LocalMeta(dirty: true, conflict: false))
        let onlyHere = try note("# Nur hier\n", revision: 0, in: store, dirty: true)
        try store.setBoundAccount("acc/old")

        // The converting device uploaded its state, which is newer for `untouched` and older for `edited`.
        let successor = FakeTransport()
        var newer = untouched
        newer.applyMarkdown("# Anderswo geändert\n")
        newer.revision = 1
        successor.seed(newer, cursor: 1)
        var older = edited
        older.applyMarkdown("# Vorher\n")
        older.revision = 1
        successor.seed(older, cursor: 2)
        let theirs = Note.newText(now: "2026-10-01T08:00:00Z")
        var remoteOnly = theirs
        remoteOnly.revision = 1
        successor.seed(remoteOnly, cursor: 3)

        try await Relinker.adopt(store, from: successor, bindingKey: "acc/new")
        XCTAssertEqual(try store.note(id: untouched.id)?.markdown, "# Anderswo geändert\n")
        XCTAssertEqual(try store.meta(for: untouched.id), .clean)
        XCTAssertEqual(try store.note(id: edited.id)?.revision, 1)
        XCTAssertEqual(try store.meta(for: edited.id).dirty, true)
        XCTAssertNotNil(try store.note(id: remoteOnly.id))
        XCTAssertEqual(try store.cursor(), 3)

        let report = try await Syncer.sync(store: store, transport: successor)
        XCTAssertEqual(report.conflicts, 0)
        XCTAssertEqual(successor.notes[edited.id]?.markdown, "# Hier geändert\n", "the local edit wins")
        XCTAssertEqual(successor.notes[onlyHere.id]?.markdown, "# Nur hier\n")
    }

    func testAdoptingTwiceDoesNothing() async throws {
        let store = try freshStore()
        let synced = try note("# Da\n", revision: 2, in: store)
        try store.setBoundAccount("acc/new")
        try await Relinker.adopt(store, from: FakeTransport(), bindingKey: "acc/new")
        XCTAssertEqual(try store.note(id: synced.id)?.revision, 2)
        XCTAssertEqual(try store.meta(for: synced.id), .clean)
    }

    func testAnOldConflictBecomesANoteOfItsOwn() async throws {
        let store = try freshStore()
        let mine = try note("# Meins\n", revision: 2, in: store)
        var server = mine
        server.applyMarkdown("# Seins\n")
        server.revision = 3
        try store.saveConflict(server)
        try store.save(note: mine, meta: LocalMeta(dirty: true, conflict: true))

        try await Relinker.adopt(store, from: FakeTransport(), bindingKey: "acc/new")
        let notes = try store.list()
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.allSatisfy { !$0.meta.conflict && $0.meta.dirty })
        XCTAssertTrue(notes.contains { $0.note.markdown == "# Seins\n" })
    }

    func testLateNotesInTheOldWorkspaceComeAlong() async throws {
        let store = try freshStore()
        let clean = try note("# A\n", revision: 1, in: store)
        let dirty = try note("# B hier\n", revision: 1, in: store, dirty: true)

        let old = FakeTransport()
        var lateA = clean
        lateA.applyMarkdown("# A von woanders\n")
        lateA.revision = 7
        old.seed(lateA, cursor: 11)
        var lateB = dirty
        lateB.applyMarkdown("# B von woanders\n")
        lateB.revision = 7
        old.seed(lateB, cursor: 12)
        var lateNew = Note.newText(now: "2026-10-01T08:00:00Z")
        lateNew.applyMarkdown("# Neu\n")
        lateNew.revision = 1
        old.seed(lateNew, cursor: 13)

        let cursor = try await Relinker.takeLate(from: old, after: 10, into: store)
        XCTAssertEqual(cursor, 13)
        XCTAssertEqual(try store.note(id: clean.id)?.markdown, "# A von woanders\n")
        XCTAssertEqual(try store.note(id: clean.id)?.revision, 1, "on top of the successor's revision")
        XCTAssertEqual(try store.meta(for: clean.id).dirty, true)
        XCTAssertEqual(try store.note(id: dirty.id)?.markdown, "# B hier\n", "a local edit stays")
        XCTAssertTrue(try store.list().contains { $0.note.markdown == "# B von woanders\n" && $0.note.id != dirty.id })
        XCTAssertEqual(try store.note(id: lateNew.id)?.revision, 0)
        XCTAssertEqual(try store.meta(for: lateNew.id).dirty, true)
    }

    func testNothingAfterTheCursorMeansTheOldCanGo() async throws {
        let old = FakeTransport()
        old.seed(Note.newText(now: "2026-10-01T08:00:00Z"), cursor: 5)
        let nothing = try await Conversion.hasChanges(after: 5, in: old)
        let something = try await Conversion.hasChanges(after: 4, in: old)
        XCTAssertFalse(nothing)
        XCTAssertTrue(something)
    }

    // MARK: One Kennel

    func testOneKennelStaysTheSignedInOneWithMostWorkspaces() {
        let a = ServerEntry(url: "http://a", accountID: "1")
        let b = ServerEntry(url: "http://b", accountID: "2")
        let c = ServerEntry(url: "http://c", accountID: "3")
        let workspaces = [
            Workspace(name: "1", link: WorkspaceLink(server: a.id, remote: "main")),
            Workspace(name: "2", link: WorkspaceLink(server: b.id, remote: "main")),
            Workspace(name: "3", link: WorkspaceLink(server: b.id, remote: "x"), lookPending: true),
            Workspace(name: "4", link: WorkspaceLink(server: c.id, remote: "main")),
            Workspace(name: "5"),
        ]
        var setup = DeviceSetup(servers: [a, b, c], workspaces: workspaces, current: workspaces[0].id, orderPending: [a.id, c.id])
        let gone = setup.keepOneKennel { $0 != b.id }
        XCTAssertEqual(setup.servers, [a])
        XCTAssertEqual(Set(gone.map(\.id)), [b.id, c.id])
        XCTAssertEqual(setup.workspaces.map { $0.link?.server }, [a.id, nil, nil, nil, nil])
        XCTAssertEqual(setup.workspaces.count, 5, "no workspace goes")
        XCTAssertFalse(setup.workspaces[2].lookPending)
        XCTAssertEqual(setup.orderPending, [a.id])

        var signedOut = DeviceSetup(servers: [a, b, c], workspaces: workspaces, current: workspaces[0].id)
        signedOut.keepOneKennel { _ in false }
        XCTAssertEqual(signedOut.servers, [b], "most workspaces")
    }

    func testOneServerIsLeftAlone() {
        let a = ServerEntry(url: "http://a")
        var setup = DeviceSetup(servers: [a], workspaces: [Workspace(name: "1")], current: UUID())
        XCTAssertEqual(setup.keepOneKennel { _ in false }, [])
        XCTAssertEqual(setup.servers, [a])
    }

    func testRetiringSurvivesTheSetupFile() throws {
        let workspace = Workspace(name: "Arbeit", retiring: RetiringRemote(remote: "old", cursor: 9, deletes: true))
        let decoded = try InkhashJSON.decode(Workspace.self, from: InkhashJSON.encode(workspace))
        XCTAssertEqual(decoded.retiring, workspace.retiring)
    }

    // MARK: Helpers

    private func freshStore() throws -> LocalStore {
        try LocalStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @discardableResult
    private func note(_ markdown: String, revision: Int, in store: LocalStore, dirty: Bool = false) throws -> Note {
        var note = Note.newText(now: "2026-10-01T08:00:00Z")
        note.applyMarkdown(markdown)
        note.revision = revision
        try store.save(note: note, meta: LocalMeta(dirty: dirty, conflict: false))
        return note
    }
}
