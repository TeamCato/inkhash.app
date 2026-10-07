import ImageIO
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

    func testSetupWithoutIconDecodes() throws {
        let id = "11111111-2222-4333-8444-555555555555"
        let json = """
        {"servers":[],"workspaces":[{"id":"\(id)","name":"Privat","symbol":"house"}],"current":"\(id)"}
        """
        let setup = try InkhashJSON.decode(DeviceSetup.self, from: Data(json.utf8))
        XCTAssertNil(setup.workspaces.first?.icon)
        XCTAssertEqual(setup.workspaces.first?.symbol, "house")
    }

    func testWorkspacesMove() {
        let a = Workspace(name: "A"), b = Workspace(name: "B"), c = Workspace(name: "C"), d = Workspace(name: "D")
        var setup = DeviceSetup(servers: [], workspaces: [a, b, c, d], current: a.id)
        setup.moveWorkspaces(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(setup.workspaces.map(\.name), ["B", "C", "A", "D"])
        setup.moveWorkspaces(fromOffsets: [3], toOffset: 0)
        XCTAssertEqual(setup.workspaces.map(\.name), ["D", "B", "C", "A"])
        setup.moveWorkspaces(fromOffsets: [0, 2], toOffset: 4)
        XCTAssertEqual(setup.workspaces.map(\.name), ["B", "A", "D", "C"])
        setup.moveWorkspaces(fromOffsets: [9], toOffset: 0)
        XCTAssertEqual(setup.workspaces.map(\.name), ["B", "A", "D", "C"])

        setup.moveWorkspace(c.id, by: -1)
        XCTAssertEqual(setup.workspaces.map(\.name), ["B", "A", "C", "D"])
        setup.moveWorkspace(b.id, by: -1)
        XCTAssertEqual(setup.workspaces.map(\.name), ["B", "A", "C", "D"])
        setup.moveWorkspace(b.id, by: 1)
        XCTAssertEqual(setup.workspaces.map(\.name), ["A", "B", "C", "D"])
        XCTAssertEqual(setup.current, a.id)
    }

    func testIconIsTheMiddleSquare() throws {
        // 300 x 100: red, green, blue thirds. Only green may survive the crop.
        let width = 300, height = 100
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for (index, color) in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)].enumerated() {
            context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
            context.fill(CGRect(x: index * 100, y: 0, width: 100, height: height))
        }
        let picture = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(picture, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let png = try WorkspaceImage.normalize(picture as Data)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let icon = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(icon.width, WorkspaceImage.side)
        XCTAssertEqual(icon.height, WorkspaceImage.side)

        let pixel = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for x in [2, WorkspaceImage.side / 2, WorkspaceImage.side - 3] {
            pixel.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            pixel.draw(icon, in: CGRect(x: -x, y: -WorkspaceImage.side / 2, width: WorkspaceImage.side, height: WorkspaceImage.side))
            let rgba = try XCTUnwrap(pixel.data).assumingMemoryBound(to: UInt8.self)
            XCTAssertLessThan(rgba[0], 20, "x \(x)")
            XCTAssertGreaterThan(rgba[1], 235, "x \(x)")
            XCTAssertLessThan(rgba[2], 20, "x \(x)")
        }
    }

    func testUnreadableIconFails() {
        XCTAssertThrowsError(try WorkspaceImage.normalize(Data("kein Bild".utf8))) { error in
            XCTAssertEqual(error as? WorkspaceImageError, .unreadable)
        }
    }

    func testIconFilesAreNamedByContent() throws {
        let base = freshBase()
        let first = try Workspaces.saveIcon(Data([1, 2, 3]), base: base)
        XCTAssertEqual(first, sha256Hex(Data([1, 2, 3])))
        XCTAssertEqual(try Workspaces.saveIcon(Data([1, 2, 3]), base: base), first)
        let second = try Workspaces.saveIcon(Data([4]), base: base)
        XCTAssertEqual(try Data(contentsOf: Workspaces.iconURL(first, base: base)), Data([1, 2, 3]))

        let kept = Workspace(name: "A", icon: second)
        try Workspaces.pruneIcons(keeping: DeviceSetup(servers: [], workspaces: [kept], current: kept.id), base: base)
        XCTAssertFalse(FileManager.default.fileExists(atPath: Workspaces.iconURL(first, base: base).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: Workspaces.iconURL(second, base: base).path))
    }

    func testFirstDeviceSetsTheLookAndOrder() async throws {
        let base = freshBase()
        let server = UUID()
        let icon = try Workspaces.saveIcon(Data("bild".utf8), base: base)
        let home = Workspace(name: "Zuhause", symbol: "house", icon: icon, link: WorkspaceLink(server: server, remote: "main"))
        let local = Workspace(name: "Nur hier")
        let work = Workspace(name: "Arbeit", symbol: "briefcase", link: WorkspaceLink(server: server, remote: "w1"))
        let setup = DeviceSetup(servers: [], workspaces: [work, local, home], current: home.id)
        let remote = FakeWorkspaceServer([
            RemoteWorkspace(id: "main", name: "Privat"),
            RemoteWorkspace(id: "w1", name: "Arbeit"),
        ], ordered: false)

        let synced = try await LookSyncer.sync(setup, server: server, base: base, transport: remote)
        XCTAssertEqual(synced, setup)
        let looks = await remote.looks
        XCTAssertEqual(looks["main"], WorkspaceLook(name: "Zuhause", symbol: "house", icon: icon))
        XCTAssertEqual(looks["w1"], WorkspaceLook(name: "Arbeit", symbol: "briefcase", icon: nil))
        let blobs = await remote.blobs
        XCTAssertEqual(blobs["main/\(icon)"], Data("bild".utf8))
        let order = await remote.order
        XCTAssertEqual(order, ["w1", "main"])
    }

    func testOtherDeviceTakesLookAndOrderFromTheServer() async throws {
        let base = freshBase()
        let server = UUID()
        let picture = Data("bild".utf8)
        let icon = sha256Hex(picture)
        let a = Workspace(name: "Privat", link: WorkspaceLink(server: server, remote: "main"))
        let local = Workspace(name: "Nur hier")
        let b = Workspace(name: "Arbeit", link: WorkspaceLink(server: server, remote: "w1"))
        let other = Workspace(name: "Anderer Server", link: WorkspaceLink(server: UUID(), remote: "main"))
        let setup = DeviceSetup(servers: [], workspaces: [a, local, b, other], current: a.id)
        let remote = FakeWorkspaceServer([
            RemoteWorkspace(id: "w1", name: "Büro", symbol: "briefcase", icon: icon, updatedAt: "2026-10-07T08:00:00Z"),
            RemoteWorkspace(id: "main", name: "Zuhause", symbol: "house", updatedAt: "2026-10-07T08:00:00Z"),
        ], ordered: true, blobs: ["w1/\(icon)": picture])

        let synced = try await LookSyncer.sync(setup, server: server, base: base, transport: remote)
        XCTAssertEqual(synced.workspaces.map(\.name), ["Büro", "Nur hier", "Zuhause", "Anderer Server"])
        XCTAssertEqual(synced.workspaces.map(\.symbol), ["briefcase", "tray", "house", "tray"])
        XCTAssertEqual(synced.workspaces.first?.icon, icon)
        XCTAssertEqual(try Data(contentsOf: Workspaces.iconURL(icon, base: base)), picture)
        let looks = await remote.looks
        XCTAssertTrue(looks.isEmpty)
    }

    func testPendingLookAndOrderGoToTheServer() async throws {
        let base = freshBase()
        let server = UUID()
        var a = Workspace(name: "Privat", symbol: "leaf", link: WorkspaceLink(server: server, remote: "main"))
        a.lookPending = true
        let b = Workspace(name: "Arbeit", link: WorkspaceLink(server: server, remote: "w1"))
        let setup = DeviceSetup(servers: [], workspaces: [b, a], current: a.id, orderPending: [server])
        let remote = FakeWorkspaceServer([
            RemoteWorkspace(id: "main", name: "Privat", symbol: "house", icon: "ab", updatedAt: "2026-10-07T08:00:00Z"),
            RemoteWorkspace(id: "w1", name: "Arbeit", symbol: "tray", updatedAt: "2026-10-07T08:00:00Z"),
        ], ordered: true)

        let synced = try await LookSyncer.sync(setup, server: server, base: base, transport: remote)
        XCTAssertFalse(synced.workspaces[1].lookPending)
        XCTAssertEqual(synced.workspaces[1].symbol, "leaf")
        XCTAssertTrue(synced.orderPending.isEmpty)
        let looks = await remote.looks
        XCTAssertEqual(looks["main"], WorkspaceLook(name: "Privat", symbol: "leaf", icon: nil))
        let order = await remote.order
        XCTAssertEqual(order, ["w1", "main"])
    }

    func testServerWithoutLooksChangesNothing() async throws {
        let server = UUID()
        var a = Workspace(name: "Privat", link: WorkspaceLink(server: server, remote: "main"))
        a.lookPending = true
        let setup = DeviceSetup(servers: [], workspaces: [a], current: a.id, orderPending: [server])
        let remote = FakeWorkspaceServer([RemoteWorkspace(id: "main", name: "Privat")], ordered: nil)
        let synced = try await LookSyncer.sync(setup, server: server, base: freshBase(), transport: remote)
        XCTAssertEqual(synced, setup)
    }

    func testAdoptKeepsWhatChangedDuringTheSync() {
        let a = Workspace(name: "A"), b = Workspace(name: "B"), c = Workspace(name: "C")
        let server = UUID()
        let snapshot = DeviceSetup(servers: [], workspaces: [a, b, c], current: a.id, orderPending: [server])
        var synced = snapshot
        synced.workspaces = [c, b, a]
        synced.workspaces[0].name = "C vom Server"
        synced.workspaces[2].name = "A vom Server"
        synced.orderPending = []

        var current = snapshot
        current.workspaces[0].name = "A hier umbenannt"
        current.adopt(synced, since: snapshot)
        XCTAssertEqual(current.workspaces.map(\.name), ["C vom Server", "B", "A hier umbenannt"])
        XCTAssertEqual(current.orderPending, [])

        var moved = snapshot
        moved.moveWorkspace(c.id, by: -1)
        moved.adopt(synced, since: snapshot)
        XCTAssertEqual(moved.workspaces.map(\.id), [a.id, c.id, b.id])
    }

    func testSetupWithoutPendingFieldsDecodes() throws {
        let id = "11111111-2222-4333-8444-555555555555"
        let json = """
        {"servers":[],"workspaces":[{"id":"\(id)","name":"Privat","symbol":"house"}],"current":"\(id)"}
        """
        let setup = try InkhashJSON.decode(DeviceSetup.self, from: Data(json.utf8))
        XCTAssertEqual(setup.orderPending, [])
        XCTAssertEqual(setup.workspaces.first?.lookPending, false)
    }

    private func freshBase() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private actor FakeWorkspaceServer: WorkspaceTransport {
    var workspaces: [RemoteWorkspace]
    var ordered: Bool?
    var looks: [String: WorkspaceLook] = [:]
    var blobs: [String: Data]
    var order: [String]?

    init(_ workspaces: [RemoteWorkspace], ordered: Bool?, blobs: [String: Data] = [:]) {
        self.workspaces = workspaces
        self.ordered = ordered
        self.blobs = blobs
    }

    func workspaceList() async throws -> RemoteWorkspaceList {
        RemoteWorkspaceList(workspaces: workspaces, ordered: ordered)
    }

    func updateWorkspace(id: String, look: WorkspaceLook) async throws -> RemoteWorkspace {
        looks[id] = look
        return RemoteWorkspace(id: id, name: look.name, symbol: look.symbol, icon: look.icon, updatedAt: "2026-10-07T09:00:00Z")
    }

    func orderWorkspaces(ids: [String]) async throws -> RemoteWorkspaceList {
        order = ids
        ordered = true
        return RemoteWorkspaceList(workspaces: workspaces, ordered: true)
    }

    func putIcon(workspace: String, sha256: String, data: Data) async throws {
        blobs["\(workspace)/\(sha256)"] = data
    }

    func fetchIcon(workspace: String, sha256: String) async throws -> Data {
        guard let data = blobs["\(workspace)/\(sha256)"] else { throw APIError.notFound }
        return data
    }
}
