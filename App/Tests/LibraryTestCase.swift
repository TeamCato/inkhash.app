import InkhashCore
import XCTest
@testable import Inkhash

/// A note library on a registry in its own temporary folder, without a server.
@MainActor
class LibraryTestCase: XCTestCase {
    var base: URL!
    var status: StatusLine!
    var registry: WorkspaceRegistry!
    var library: NoteLibrary!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("inkhash-tests-\(UUID().uuidString)", isDirectory: true)
        status = StatusLine()
        registry = try WorkspaceRegistry(base: base, legacy: nil, status: status)
        library = NoteLibrary(registry: registry, status: status)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    var store: LocalStore { registry.currentStore }

    /// A text note in the library as if it had synced at `revision`.
    @discardableResult
    func syncedText(_ markdown: String, revision: Int = 1) throws -> Note {
        var note = Note.newText(now: "2026-10-01T08:00:00Z")
        note.applyMarkdown(markdown)
        note.revision = revision
        try store.save(note: note, meta: .clean)
        library.reload()
        return note
    }

    /// Puts `note` in conflict with `server`, the way `Syncer` leaves it.
    func makeConflict(_ note: Note, server: Note) throws {
        try store.saveConflict(server)
        try store.save(note: note, meta: LocalMeta(dirty: true, conflict: true))
        library.reload()
    }
}
