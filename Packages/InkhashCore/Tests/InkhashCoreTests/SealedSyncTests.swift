import XCTest
@testable import InkhashCore

/// A server workspace with a vault, by the rules in API.md: sealed notes only, plain notes from
/// before stay readable, blobs named by their own hash are refused.
final class FakeSealedServer: SealedWire, @unchecked Sendable {
    var notes: [UUID: WireNote] = [:]
    var blobs: [String: Data] = [:]
    var cursor = 0
    var log: [ChangeEntry] = []

    func seedPlain(_ note: Note) {
        var stored = note
        cursor += 1
        stored.revision = max(note.revision, 1)
        notes[note.id] = .plain(stored)
        log.append(ChangeEntry(cursor: cursor, noteId: note.id, revision: stored.revision, deleted: note.deletedAt != nil))
    }

    func changes(after cursor: Int) async throws -> ChangePage {
        var latest: [UUID: ChangeEntry] = [:]
        for entry in log where entry.cursor > cursor { latest[entry.noteId] = entry }
        return ChangePage(cursor: self.cursor, changes: latest.values.sorted { $0.cursor < $1.cursor })
    }

    func fetchWire(id: UUID) async throws -> WireNote {
        guard let note = notes[id] else { throw APIError.notFound }
        return note
    }

    func putSealed(_ upload: SealedUpload, baseRevision: Int) async throws -> WireNote {
        let existing = notes[upload.id]
        let revision = existing.map(Self.revision) ?? 0
        if existing == nil, baseRevision != 0 { throw APIError.notFound }
        if existing != nil, revision != baseRevision {
            if case .sealed(let sealed) = existing!, sealed.sealed == upload.sealed, (sealed.deletedAt != nil) == upload.deleted {
                return existing!
            }
            switch existing! {
            case .plain(let note): throw APIError.conflict(note)
            case .sealed(let sealed): throw APIError.sealedConflict(sealed)
            }
        }
        cursor += 1
        let deletedAt = upload.deleted ? "2026-10-09T12:00:00Z" : nil
        let stored = SealedNote(id: upload.id, revision: revision + 1, updatedAt: "2026-10-09T12:00:00Z", deletedAt: deletedAt, sealed: upload.sealed)
        notes[upload.id] = .sealed(stored)
        log.append(ChangeEntry(cursor: cursor, noteId: upload.id, revision: stored.revision, deleted: upload.deleted))
        return .sealed(stored)
    }

    func deleteWire(id: UUID, baseRevision: Int) async throws -> WireNote {
        guard case .sealed(var sealed) = notes[id] else { throw APIError.notFound }
        guard sealed.revision == baseRevision else { throw APIError.sealedConflict(sealed) }
        cursor += 1
        sealed.revision += 1
        sealed.deletedAt = "2026-10-09T12:00:00Z"
        notes[id] = .sealed(sealed)
        log.append(ChangeEntry(cursor: cursor, noteId: id, revision: sealed.revision, deleted: true))
        return .sealed(sealed)
    }

    func putBlob(sha256: String, data: Data) async throws {
        if sha256Hex(data) == sha256 { throw APIError.badStatus(400, #"{"reason":"sealed"}"#) }
        blobs[sha256] = data
    }

    func fetchBlob(sha256: String) async throws -> Data {
        guard let data = blobs[sha256] else { throw APIError.notFound }
        return data
    }

    var plainCount: Int {
        notes.values.filter { if case .plain = $0 { true } else { false } }.count
    }

    private static func revision(_ note: WireNote) -> Int {
        switch note {
        case .plain(let note): note.revision
        case .sealed(let sealed): sealed.revision
        }
    }
}

@MainActor
final class SealedSyncTests: XCTestCase {
    private var key: VaultKey!

    override func setUp() async throws {
        key = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: testRounds).0
    }

    private func freshStore() throws -> LocalStore {
        try LocalStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func transport(_ server: FakeSealedServer) -> SealedTransport {
        SealedTransport(wire: server, sealer: Sealer(key))
    }

    /// A server from before the vault: a text note, an ink note with a photo, a note in the trash.
    /// The device has synced them all.
    private func plainWorld() throws -> (server: FakeSealedServer, store: LocalStore, ids: [UUID]) {
        let server = FakeSealedServer()
        let store = try freshStore()
        var text = Note.newText(now: "2026-10-01T08:00:00Z")
        text.applyMarkdown("# Plan\n")
        text.revision = 1
        let drawing = Data("strokes".utf8)
        let photo = Data("jpeg".utf8)
        server.blobs[sha256Hex(drawing)] = drawing
        server.blobs[sha256Hex(photo)] = photo
        var page = InkPage(blob: try store.putBlob(drawing), transcript: "Skizze")
        page.elements = [PageElement(kind: .image, x: 1, y: 1, width: 2, height: 2, blob: try store.putBlob(photo))]
        var ink = Note.newInk(page: page, now: "2026-10-01T08:00:00Z")
        ink.revision = 1
        var trashed = Note.newText(now: "2026-10-01T08:00:00Z")
        trashed.applyMarkdown("# Weg\n")
        trashed.revision = 2
        trashed.deletedAt = "2026-10-02T08:00:00Z"
        for note in [text, ink, trashed] {
            server.seedPlain(note)
            try store.save(note: note, meta: .clean)
        }
        try store.setCursor(server.cursor)
        return (server, store, [text.id, ink.id, trashed.id])
    }

    func testFirstSyncWithTheVaultSealsEverythingOnTheServer() async throws {
        let (server, store, ids) = try plainWorld()
        let report = try await Syncer.sync(store: store, transport: transport(server), sealedWith: key.keyId)
        XCTAssertEqual(report.pushed, 3)
        XCTAssertEqual(report.conflicts, 0)
        XCTAssertEqual(server.plainCount, 0)
        XCTAssertEqual(store.sealedKey(), key.keyId)
        // The trashed note went up sealed and stayed in the trash.
        guard case .sealed(let trashed) = server.notes[ids[2]] else { return XCTFail("not sealed") }
        XCTAssertNotNil(trashed.deletedAt)
        XCTAssertNotNil(try store.note(id: ids[2])?.deletedAt)
        // Blobs went up under sealed names.
        let sealer = Sealer(key)
        let page = try XCTUnwrap(store.note(id: ids[1])?.pages?.first)
        for plain in page.blobNames {
            XCTAssertNotNil(server.blobs[sealer.blobName(plain)])
        }
        // Nothing is left dirty, and the next sync does nothing.
        XCTAssertTrue(try store.list().allSatisfy { !$0.meta.dirty })
        let again = try await Syncer.sync(store: store, transport: transport(server), sealedWith: key.keyId)
        XCTAssertEqual(again, SyncReport(pushed: 0, pulled: 0, conflicts: 0))
    }

    func testASecondDeviceReadsTheSealedNotes() async throws {
        let (server, store, ids) = try plainWorld()
        _ = try await Syncer.sync(store: store, transport: transport(server), sealedWith: key.keyId)
        // Plain blobs are gone from the server once all is sealed.
        for name in server.blobs.keys where server.blobs[name].map(sha256Hex) == name {
            server.blobs[name] = nil
        }
        let other = try freshStore()
        _ = try await Syncer.sync(store: other, transport: transport(server), sealedWith: key.keyId)
        for id in ids {
            let mine = try XCTUnwrap(store.note(id: id))
            let theirs = try XCTUnwrap(other.note(id: id))
            XCTAssertTrue(theirs.sameContent(as: mine), "\(id)")
        }
        let page = try XCTUnwrap(other.note(id: ids[1])?.pages?.first)
        for name in page.blobNames {
            XCTAssertEqual(try other.blob(name), try store.blob(name))
        }
        XCTAssertEqual(other.sealedKey(), key.keyId)
    }

    func testAnInterruptedMoveStartsOverAndFinishes() async throws {
        let (server, store, _) = try plainWorld()
        // Another device already sealed one of them; this one never finished its move.
        try store.setCursor(server.cursor)
        let report = try await Syncer.sync(store: store, transport: transport(server), sealedWith: key.keyId)
        XCTAssertEqual(server.plainCount, 0)
        XCTAssertEqual(report.pushed, 3)
        XCTAssertEqual(try store.cursor(), server.cursor)
    }

    func testLocalEditsDuringTheMoveGoUpSealedToo() async throws {
        let (server, store, ids) = try plainWorld()
        var edited = try XCTUnwrap(store.note(id: ids[0]))
        edited.applyMarkdown("# Plan\nneu\n")
        try store.save(note: edited, meta: LocalMeta(dirty: true, conflict: false))
        _ = try await Syncer.sync(store: store, transport: transport(server), sealedWith: key.keyId)
        guard case .sealed(let sealed) = server.notes[ids[0]] else { return XCTFail("not sealed") }
        XCTAssertEqual(try Sealer(key).open(sealed).markdown, "# Plan\nneu\n")
    }

    func testAConflictWithASealedNoteOpensForTheComparison() async throws {
        let (server, store, ids) = try plainWorld()
        _ = try await Syncer.sync(store: store, transport: transport(server), sealedWith: key.keyId)
        // Another device changes the note.
        var theirs = try XCTUnwrap(store.note(id: ids[0]))
        theirs.applyMarkdown("# Plan\nvon dort\n")
        let base = theirs.revision
        _ = try await server.putSealed(try Sealer(key).seal(theirs), baseRevision: base)
        // This one too, without having pulled.
        var mine = try XCTUnwrap(store.note(id: ids[0]))
        mine.applyMarkdown("# Plan\nvon hier\n")
        try store.save(note: mine, meta: LocalMeta(dirty: true, conflict: false))
        let report = try await Syncer.sync(store: store, transport: transport(server), sealedWith: key.keyId)
        XCTAssertEqual(report.conflicts, 1)
        XCTAssertEqual(try store.conflictNote(id: ids[0])?.markdown, "# Plan\nvon dort\n")
        XCTAssertEqual(try store.note(id: ids[0])?.markdown, "# Plan\nvon hier\n")
    }

    func testNewNotesGoUpSealedWithoutAMove() async throws {
        let server = FakeSealedServer()
        let store = try freshStore()
        var note = Note.newText(now: "2026-10-01T08:00:00Z")
        note.applyMarkdown("# Neu\n")
        try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        let report = try await Syncer.sync(store: store, transport: transport(server), sealedWith: key.keyId)
        XCTAssertEqual(report.pushed, 1)
        guard case .sealed = server.notes[note.id] else { return XCTFail("not sealed") }
        // Deleting it later is a plain tombstone over sealed content.
        var trashed = try XCTUnwrap(store.note(id: note.id))
        trashed.deletedAt = "2026-10-03T08:00:00Z"
        try store.save(note: trashed, meta: LocalMeta(dirty: true, conflict: false))
        _ = try await Syncer.sync(store: store, transport: transport(server), sealedWith: key.keyId)
        guard case .sealed(let stored) = server.notes[note.id] else { return XCTFail("not sealed") }
        XCTAssertNotNil(stored.deletedAt)
    }

    func testAPlainBlobIsFoundUnderItsOldName() async throws {
        let server = FakeSealedServer()
        let data = Data("alt".utf8)
        server.blobs[sha256Hex(data)] = data
        let fetched = try await transport(server).fetchBlob(sha256: sha256Hex(data))
        XCTAssertEqual(fetched, data)
        server.blobs[sha256Hex(data)] = Data("falsch".utf8)
        do {
            _ = try await transport(server).fetchBlob(sha256: sha256Hex(data))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SealError, .wrongBlob)
        }
    }
}

@MainActor
final class SealedLooksTests: XCTestCase {
    private func base() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testAPictureGoesUpSealedAndComesBackPlainOnTheNextDevice() async throws {
        let key = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: testRounds).0
        let sealer = Sealer(key)
        let server = UUID()
        let first = base()
        let icon = try Workspaces.saveIcon(Data("bild".utf8), base: first)
        var home = Workspace(name: "Zuhause", symbol: "house", icon: icon, link: WorkspaceLink(server: server, remote: "main"))
        home.lookPending = true
        let remote = FakeWorkspaceServer([RemoteWorkspace(id: "main", name: "Privat")], ordered: true)
        _ = try await LookSyncer.sync(
            DeviceSetup(servers: [], workspaces: [home], current: home.id), server: server, base: first,
            transport: SealedLooks(inner: remote, sealer: sealer, icons: [icon])
        )
        let looks = await remote.looks
        XCTAssertEqual(looks["main"]?.icon, sealer.blobName(icon))
        let blobs = await remote.blobs
        let stored = try XCTUnwrap(blobs["main/\(sealer.blobName(icon))"])
        XCTAssertNotEqual(stored, Data("bild".utf8))

        // The next device sees the sealed name and keeps the plain picture.
        let second = base()
        let there = Workspace(name: "Privat", link: WorkspaceLink(server: server, remote: "main"))
        let listed = FakeWorkspaceServer(
            [RemoteWorkspace(id: "main", name: "Zuhause", symbol: "house", icon: sealer.blobName(icon), updatedAt: "2026-10-09T10:00:00Z")],
            ordered: true, blobs: blobs
        )
        let synced = try await LookSyncer.sync(
            DeviceSetup(servers: [], workspaces: [there], current: there.id), server: server, base: second,
            transport: SealedLooks(inner: listed, sealer: sealer, icons: [])
        )
        XCTAssertEqual(synced.workspaces[0].icon, icon)
        XCTAssertEqual(try Data(contentsOf: Workspaces.iconURL(icon, base: second)), Data("bild".utf8))
    }

    func testAPlainPictureFromBeforeTheVaultIsTakenAndPutUpSealed() async throws {
        let key = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: testRounds).0
        let sealer = Sealer(key)
        let server = UUID()
        let picture = Data("altes bild".utf8)
        let plain = sha256Hex(picture)
        let device = base()
        let home = Workspace(name: "Privat", link: WorkspaceLink(server: server, remote: "main"))
        let remote = FakeWorkspaceServer(
            [RemoteWorkspace(id: "main", name: "Zuhause", symbol: "house", icon: plain, updatedAt: "2026-10-01T10:00:00Z")],
            ordered: true, blobs: ["main/\(plain)": picture]
        )
        let synced = try await LookSyncer.sync(
            DeviceSetup(servers: [], workspaces: [home], current: home.id), server: server, base: device,
            transport: SealedLooks(inner: remote, sealer: sealer, icons: [])
        )
        XCTAssertEqual(synced.workspaces[0].icon, plain)
        XCTAssertEqual(synced.workspaces[0].name, "Zuhause")
        XCTAssertFalse(synced.workspaces[0].lookPending)
        let looks = await remote.looks
        XCTAssertEqual(looks["main"]?.icon, sealer.blobName(plain))
        let blobs = await remote.blobs
        XCTAssertEqual(try sealer.openBlob(XCTUnwrap(blobs["main/\(sealer.blobName(plain))"]), plain: plain), picture)
    }
}
