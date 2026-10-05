import XCTest
@testable import InkhashCore

@MainActor
final class WorkspaceTests: XCTestCase {
    private let account = "aaaaaaaa-1111-4111-8111-111111111111"

    func testOldLibraryBecomesPrivatAndKeepsItsBinding() throws {
        let base = freshBase()
        let old = try Library.open(base: base, signedInAccount: account)
        try Library.bind(old, to: account)
        var note = Note.newText(now: "2026-10-01T06:00:00Z")
        note.applyMarkdown("vorher\n")
        note.revision = 3
        try old.save(note: note, meta: .clean)
        try old.setCursor(9)

        let legacy = LegacySignIn(url: "http://nas:8787", accountName: "ada", accountID: account)
        let (setup, server) = try Workspaces.open(base: base, legacy: legacy)
        XCTAssertEqual(setup.workspaces.map(\.name), ["Privat"])
        XCTAssertEqual(server?.url, "http://nas:8787")
        XCTAssertEqual(setup.workspaces.first?.link, WorkspaceLink(server: try XCTUnwrap(server).id, remote: "main"))
        let store = try Workspaces.store(of: setup.current, base: base)
        XCTAssertEqual(try store.note(id: note.id)?.revision, 3)
        XCTAssertEqual(try store.cursor(), 9)
        XCTAssertEqual(store.boundAccount(), Workspaces.bindingKey(accountID: account, remote: "main"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("library").path))

        let (again, migrated) = try Workspaces.open(base: base, legacy: legacy)
        XCTAssertEqual(again, setup)
        XCTAssertNil(migrated)
    }

    func testFreshDeviceHasOneLocalWorkspace() throws {
        let (setup, server) = try Workspaces.open(base: freshBase(), legacy: nil)
        XCTAssertNil(server)
        XCTAssertEqual(setup.workspaces.count, 1)
        XCTAssertNil(setup.workspaces.first?.link)
    }

    func testInterruptedMoveIsFinished() throws {
        let base = freshBase()
        let privat = Workspace(name: "Privat")
        try Workspaces.save(DeviceSetup(servers: [], workspaces: [privat], current: privat.id), base: base)
        let library = try LocalStore(root: base.appendingPathComponent("library"))
        let note = Note.newText(now: "2026-10-01T06:00:00Z")
        try library.save(note: note, meta: .clean)
        _ = try Workspaces.open(base: base, legacy: nil)
        XCTAssertNotNil(try Workspaces.store(of: privat.id, base: base).note(id: note.id))
    }

    func testBindingKeySeparatesWorkspacesOfOneAccount() {
        XCTAssertEqual(Workspaces.bindingKey(accountID: account, remote: "main"), account)
        XCTAssertNotEqual(
            Workspaces.bindingKey(accountID: account, remote: "11111111-2222-4333-8444-555555555555"),
            account
        )
    }

    func testNoteWithoutFolderFieldsDecodes() throws {
        let json = """
        {"schemaVersion":1,"id":"6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10","kind":"text","title":"A","revision":1,
         "updatedAt":"2026-09-30T06:00:00Z","deletedAt":null,"markdown":"A\\n","transcript":null,"tags":[],"pages":null}
        """
        let note = try InkhashJSON.decode(Note.self, from: Data(json.utf8))
        XCTAssertEqual(note.folder, "")
        XCTAssertFalse(note.favorite)
        var moved = note
        moved.folder = "Reisen"
        XCTAssertFalse(moved.sameContent(as: note))
    }

    func testFolderTree() {
        XCTAssertEqual(
            Folders.tree(kept: ["Rezepte"], used: ["Reisen/Dänemark", "", "Ideen", "bad//path"]),
            ["Ideen", "Reisen", "Reisen/Dänemark", "Rezepte"]
        )
        XCTAssertEqual(Folders.moved("Reisen/Dänemark", from: "Reisen", to: "Urlaub"), "Urlaub/Dänemark")
        XCTAssertEqual(Folders.moved("Reisenplan", from: "Reisen", to: "Urlaub"), "Reisenplan")
        XCTAssertEqual(Folders.segment(" a/b \n"), "a-b")
        XCTAssertNil(Folders.segment("   "))
        XCTAssertEqual(Folders.parent(of: "Reisen/Dänemark"), "Reisen")
        XCTAssertEqual(Folders.depth(of: "Reisen/Dänemark"), 1)
    }

    func testTypedPath() {
        XCTAssertEqual(Folders.path(" project xy / meeting z / "), "project xy/meeting z")
        XCTAssertEqual(Folders.path("a//b"), "a/b")
        XCTAssertEqual(Folders.path(""), "")
        XCTAssertEqual(Folders.path("   "), "")
        XCTAssertNil(Folders.path(Array(repeating: String(repeating: "a", count: 50), count: 5).joined(separator: "/")))
        XCTAssertEqual(Folders.display("project xy/meeting z"), "project xy / meeting z")
    }

    private func freshBase() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
