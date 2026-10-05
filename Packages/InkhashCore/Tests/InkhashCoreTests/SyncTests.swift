import XCTest
@testable import InkhashCore

@MainActor
final class SyncTests: XCTestCase {
    func testPushCreateAndPull() async throws {
        let store = try freshStore()
        var note = Note.newText(now: "2026-09-30T06:00:00Z")
        note.applyMarkdown("# Hallo\n")
        try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        let transport = FakeTransport()
        let report = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(report.pushed, 1)
        let saved = try XCTUnwrap(store.note(id: note.id))
        XCTAssertEqual(saved.revision, 1)
        XCTAssertEqual(try store.meta(for: note.id).dirty, false)
        XCTAssertEqual(try store.cursor(), 1)

        let other = try freshStore()
        _ = try await Syncer.sync(store: other, transport: transport)
        let pulled = try XCTUnwrap(other.note(id: note.id))
        XCTAssertEqual(pulled.markdown, saved.markdown)
        XCTAssertEqual(pulled.tags, saved.tags)
    }

    func testConflictKeepsBoth() async throws {
        let store = try freshStore()
        var local = Note.newText(now: "2026-09-30T06:00:00Z")
        local.revision = 1
        local.applyMarkdown("lokal #eins\n")
        try store.save(note: local, meta: LocalMeta(dirty: true, conflict: false))
        try store.setCursor(1)
        let transport = FakeTransport()
        var server = local
        server.applyMarkdown("server #zwei\n")
        server.revision = 2
        transport.seed(server, cursor: 2)
        let report = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(report.conflicts, 1)
        XCTAssertEqual(try store.note(id: local.id)?.markdown, local.markdown)
        XCTAssertEqual(try store.conflictNote(id: local.id)?.markdown, server.markdown)
        XCTAssertEqual(try store.meta(for: local.id).conflict, true)
    }

    func testInkUploadsBlobBeforeNote() async throws {
        let store = try freshStore()
        let data = Data("stroke".utf8)
        let sha = try store.putBlob(data)
        let page = InkPage(blob: sha, transcript: "Reise #alpen", tags: ["alpen"])
        var note = Note.newInk(page: page, now: "2026-09-30T06:00:00Z")
        note.transcript = "Reise #alpen"
        note.tags = ["alpen"]
        try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        let transport = FakeTransport()
        _ = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(transport.events.prefix(2), ["blob", "put"])
        let saved = try XCTUnwrap(transport.notes[note.id])
        XCTAssertEqual(saved.tags, ["alpen"])
        XCTAssertEqual(saved.transcript, "Reise #alpen")
    }

    func testInkUploadsPhotoBlobsBeforeNote() async throws {
        let store = try freshStore()
        let drawing = try store.putBlob(Data("stroke".utf8))
        let photo = try store.putBlob(Data("jpeg".utf8))
        let image = PageElement(kind: .image, x: 100, y: 100, width: 200, height: 150, blob: photo, frame: .classic)
        let page = InkPage(blob: drawing, elements: [image])
        let note = Note.newInk(page: page, now: "2026-09-30T06:00:00Z")
        try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        let transport = FakeTransport()
        _ = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(transport.events.prefix(3), ["blob", "blob", "put"])
        XCTAssertEqual(transport.notes[note.id]?.pages?.first?.elements, [image])
    }

    func testElementsRoundTripAndOldPagesHaveNone() throws {
        let link = PageElement(kind: .link, x: 10, y: 20, width: 30, height: 40, link: NoteLink.target(for: UUID()))
        let shape = PageElement(kind: .shape, x: 1, y: 2, width: 3, height: 4, shape: .ellipse, stroke: "#1C1D20", strokeWidth: 4)
        let masked = PageElement(kind: .image, x: 1, y: 2, width: 3, height: 4, blob: String(repeating: "a", count: 64),
                                 frame: PageElement.Frame(style: .polaroid), mask: .init(kind: .freehand, points: [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 0.5, y: 1)]))
        let page = InkPage(blob: String(repeating: "b", count: 64), elements: [link, shape, masked])
        let decoded = try InkhashJSON.decode(InkPage.self, from: try InkhashJSON.encode(page))
        XCTAssertEqual(decoded, page)
        let json = String(decoding: try InkhashJSON.encode(shape), as: UTF8.self)
        XCTAssertTrue(json.contains("\"fill\" : null"))
        let old = #"{"id":"11111111-2222-4333-8444-555555555555","blob":"\#(String(repeating: "a", count: 64))","width":768,"height":1024}"#
        XCTAssertEqual(try InkhashJSON.decode(InkPage.self, from: Data(old.utf8)).elements, [])
        XCTAssertEqual(NoteLink.noteID(in: NoteLink.target(for: page.id)), page.id)
    }

    /// Older versions stored typed addresses as is; the server refuses them. See ADR 0031.
    func testStoredLinksWithoutSchemeAreRepaired() throws {
        let page = InkPage(blob: String(repeating: "b", count: 64), elements: [
            PageElement(kind: .link, x: 1, y: 2, width: 3, height: 4, link: "example.com/a(b)"),
            PageElement(kind: .link, x: 1, y: 2, width: 3, height: 4, link: "Treffen am Montag"),
            PageElement(kind: .tape, x: 1, y: 2, width: 3, height: 4, color: "#F2D16B", link: "Treffen am Montag"),
            PageElement(kind: .link, x: 1, y: 2, width: 3, height: 4, link: "https://example.com/a(b)"),
        ])
        let decoded = try InkhashJSON.decode(InkPage.self, from: try InkhashJSON.encode(page))
        XCTAssertEqual(decoded.elements.map(\.kind), [.link, .tape, .link])
        XCTAssertEqual(decoded.elements.map(\.link), ["https://example.com/a(b)", nil, "https://example.com/a(b)"])
    }

    func testDecide() {
        var local = Note.newText(now: "2026-09-30T06:00:00Z")
        local.revision = 1
        var server = local
        XCTAssertEqual(decide(local: local, dirty: false, server: server), .unchanged)
        XCTAssertEqual(decide(local: local, dirty: true, server: server), .pushLocal)
        server.revision = 2
        XCTAssertEqual(decide(local: local, dirty: false, server: server), .takeServer)
        XCTAssertEqual(decide(local: local, dirty: true, server: server), .takeServer, "same content")
        server.markdown = "anders"
        XCTAssertEqual(decide(local: local, dirty: true, server: server), .conflict)
    }

    func testPullFollowsPages() async throws {
        let transport = FakeTransport()
        transport.pageSize = 2
        var ids: [UUID] = []
        for index in 1...5 {
            var note = Note.newText(now: "2026-09-30T06:00:00Z")
            note.applyMarkdown("Notiz \(index)\n")
            note.revision = 1
            transport.seed(note, cursor: index)
            ids.append(note.id)
        }
        let store = try freshStore()
        let report = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(report.pulled, 5)
        XCTAssertEqual(try store.cursor(), 5)
        for id in ids {
            XCTAssertNotNil(try store.note(id: id))
        }
    }

    func testPageWithoutHasMoreDecodes() throws {
        let data = Data(#"{"cursor":3,"changes":[]}"#.utf8)
        let page = try InkhashJSON.decode(ChangePage.self, from: data)
        XCTAssertEqual(page, ChangePage(cursor: 3, changes: []))
    }

    func testPushRecreatesNoteTheServerLost() async throws {
        let store = try freshStore()
        var note = Note.newText(now: "2026-09-30T06:00:00Z")
        note.revision = 4
        note.applyMarkdown("nach dem Restore\n")
        try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        let transport = FakeTransport()
        let report = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(report.pushed, 1)
        XCTAssertEqual(transport.notes[note.id]?.markdown, note.markdown)
        XCTAssertEqual(try store.note(id: note.id)?.revision, 1)
        XCTAssertEqual(try store.meta(for: note.id).dirty, false)
    }

    func testDeleteOfNoteTheServerLostStaysInTheLocalTrash() async throws {
        let store = try freshStore()
        var note = Note.newText(now: "2026-09-30T06:00:00Z")
        note.revision = 2
        note.deletedAt = "2026-09-30T07:00:00Z"
        try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        _ = try await Syncer.sync(store: store, transport: FakeTransport())
        XCTAssertEqual(try store.note(id: note.id)?.revision, 0)
        XCTAssertNotNil(try store.note(id: note.id)?.deletedAt)
        XCTAssertEqual(try store.meta(for: note.id).dirty, false)
    }

    func testRestoredLocalNoteIsCreatedOnTheServer() async throws {
        let store = try freshStore()
        var note = Note.newText(now: "2026-09-30T06:00:00Z")
        note.applyMarkdown("zurück\n")
        note.folder = "Reisen"
        note.favorite = true
        note.deletedAt = "2026-09-30T07:00:00Z"
        try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        let transport = FakeTransport()
        _ = try await Syncer.sync(store: store, transport: transport)
        XCTAssertNil(transport.notes[note.id], "a note that never left the device is not sent while in the trash")
        note.deletedAt = nil
        try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        _ = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(transport.notes[note.id]?.folder, "Reisen")
        XCTAssertEqual(transport.notes[note.id]?.favorite, true)
    }

    func testSameContentOnBothSidesIsNoConflict() async throws {
        let store = try freshStore()
        var local = Note.newText(now: "2026-09-30T06:00:00Z")
        local.applyMarkdown("gleich\n")
        try store.save(note: local, meta: LocalMeta(dirty: true, conflict: false))
        var server = local
        server.revision = 4
        let transport = FakeTransport()
        transport.seed(server, cursor: 9)
        let report = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(report.conflicts, 0)
        XCTAssertEqual(try store.note(id: local.id)?.revision, 4)
        XCTAssertEqual(try store.meta(for: local.id).dirty, false)
    }

    func testConflictOnPushKeepsBothAndContinues() async throws {
        let store = try freshStore()
        var local = Note.newText(now: "2026-09-30T06:00:00Z")
        local.applyMarkdown("lokal\n")
        try store.save(note: local, meta: LocalMeta(dirty: true, conflict: false))
        var other = Note.newText(now: "2026-09-30T06:00:00Z")
        other.applyMarkdown("zweite\n")
        try store.save(note: other, meta: LocalMeta(dirty: true, conflict: false))
        let transport = FakeTransport()
        var server = local
        server.applyMarkdown("server\n")
        server.revision = 1
        transport.seed(server, cursor: 1)
        try store.setCursor(1)
        let report = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(report.conflicts, 1)
        XCTAssertEqual(report.pushed, 1, "the other note still goes up")
        XCTAssertEqual(try store.meta(for: local.id).conflict, true)
        XCTAssertEqual(try store.conflictNote(id: local.id)?.markdown, "server\n")
    }

    func testRejectedNoteDoesNotBlockOthers() async throws {
        let store = try freshStore()
        var refused = Note.newText(now: "2026-09-30T06:00:00Z")
        refused.applyMarkdown("abgelehnt\n")
        try store.save(note: refused, meta: LocalMeta(dirty: true, conflict: false))
        var other = Note.newText(now: "2026-09-30T06:00:00Z")
        other.applyMarkdown("geht hoch\n")
        try store.save(note: other, meta: LocalMeta(dirty: true, conflict: false))
        let transport = FakeTransport()
        transport.refuse = [refused.id]
        let report = try await Syncer.sync(store: store, transport: transport)
        XCTAssertEqual(report.rejected, [refused.id])
        XCTAssertEqual(report.pushed, 1)
        XCTAssertNotNil(transport.notes[other.id])
        XCTAssertEqual(try store.meta(for: refused.id).dirty, true, "tried again next time")
    }

    private func freshStore() throws -> LocalStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try LocalStore(root: root)
    }
}

final class FakeTransport: NoteTransport, @unchecked Sendable {
    var notes: [UUID: Note] = [:]
    var blobs: [String: Data] = [:]
    var cursor = 0
    var log: [ChangeEntry] = []
    var events: [String] = []
    var pageSize = Int.max
    var refuse: Set<UUID> = []

    func seed(_ note: Note, cursor: Int) {
        notes[note.id] = note
        self.cursor = cursor
        log.append(ChangeEntry(cursor: cursor, noteId: note.id, revision: note.revision, deleted: note.deletedAt != nil))
    }

    func changes(after cursor: Int) async throws -> ChangePage {
        var latest: [UUID: ChangeEntry] = [:]
        for entry in log where entry.cursor > cursor { latest[entry.noteId] = entry }
        let pending = latest.values.sorted { $0.cursor < $1.cursor }
        let page = Array(pending.prefix(pageSize))
        let hasMore = pending.count > page.count
        return ChangePage(cursor: hasMore ? page.last?.cursor ?? self.cursor : self.cursor, changes: page, hasMore: hasMore)
    }

    func fetchNote(id: UUID) async throws -> Note {
        guard let note = notes[id] else { throw APIError.notFound }
        return note
    }

    func putNote(_ note: Note, baseRevision: Int) async throws -> Note {
        events.append("put")
        if refuse.contains(note.id) { throw APIError.badStatus(400, #"{"error":"bad-request","reason":"tags"}"#) }
        if let existing = notes[note.id] {
            guard existing.revision == baseRevision else { throw APIError.conflict(existing) }
            var saved = note
            saved.revision = existing.revision + 1
            notes[note.id] = saved
            append(saved)
            return saved
        }
        guard baseRevision == 0 else { throw APIError.notFound }
        var saved = note
        saved.revision = 1
        notes[note.id] = saved
        append(saved)
        return saved
    }

    func deleteNote(id: UUID, baseRevision: Int) async throws -> Note {
        guard var existing = notes[id] else { throw APIError.notFound }
        guard existing.revision == baseRevision else { throw APIError.conflict(existing) }
        existing.deletedAt = "2026-09-30T06:00:00Z"
        existing.revision += 1
        notes[id] = existing
        append(existing)
        return existing
    }

    func putBlob(sha256: String, data: Data) async throws {
        events.append("blob")
        blobs[sha256] = data
    }

    func fetchBlob(sha256: String) async throws -> Data {
        guard let data = blobs[sha256] else { throw APIError.notFound }
        return data
    }

    private func append(_ note: Note) {
        cursor += 1
        log.append(ChangeEntry(cursor: cursor, noteId: note.id, revision: note.revision, deleted: note.deletedAt != nil))
    }
}
