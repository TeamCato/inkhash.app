import Foundation

public struct ChangeEntry: Equatable, Sendable {
    public var cursor: Int
    public var noteId: UUID
    public var revision: Int
    public var deleted: Bool

    public init(cursor: Int, noteId: UUID, revision: Int, deleted: Bool) {
        self.cursor = cursor
        self.noteId = noteId
        self.revision = revision
        self.deleted = deleted
    }
}

extension ChangeEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case cursor, noteId, revision, deleted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decode(Int.self, forKey: .cursor)
        let idString = try container.decode(String.self, forKey: .noteId)
        guard let noteId = UUID(uuidString: idString) else { throw InkhashError.invalidID }
        self.noteId = noteId
        revision = try container.decode(Int.self, forKey: .revision)
        deleted = try container.decode(Bool.self, forKey: .deleted)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(noteId.uuidString.lowercased(), forKey: .noteId)
        try container.encode(revision, forKey: .revision)
        try container.encode(deleted, forKey: .deleted)
    }
}

public struct ChangePage: Codable, Equatable, Sendable {
    public var cursor: Int
    public var changes: [ChangeEntry]
    /// More entries follow after `cursor`. Servers before paging omit it.
    public var hasMore: Bool

    public init(cursor: Int, changes: [ChangeEntry], hasMore: Bool = false) {
        self.cursor = cursor
        self.changes = changes
        self.hasMore = hasMore
    }

    enum CodingKeys: String, CodingKey {
        case cursor, changes, hasMore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decode(Int.self, forKey: .cursor)
        changes = try container.decode([ChangeEntry].self, forKey: .changes)
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

public struct SyncReport: Equatable, Sendable {
    public var pushed: Int
    public var pulled: Int
    public var conflicts: Int
    /// Notes the server refused (400, 413). They stay dirty on the device and are tried again next time.
    public var rejected: [UUID]

    public init(pushed: Int, pulled: Int, conflicts: Int, rejected: [UUID] = []) {
        self.pushed = pushed
        self.pulled = pulled
        self.conflicts = conflicts
        self.rejected = rejected
    }
}

public enum SyncDecision: Equatable, Sendable {
    case unchanged
    case takeServer
    case pushLocal
    case conflict
}

public func decide(local: Note, dirty: Bool, server: Note) -> SyncDecision {
    if server.revision == local.revision {
        return dirty ? .pushLocal : .unchanged
    }
    // Same words on both sides, e.g. after returning to an earlier account: nothing to choose between.
    if dirty && local.sameContent(as: server) { return .takeServer }
    return dirty ? .conflict : .takeServer
}

public func keepingMine(local: Note, server: Note) -> (Note, LocalMeta) {
    var note = local
    note.revision = server.revision
    return (note, LocalMeta(dirty: true, conflict: false))
}

public func takingServer(_ server: Note) -> (Note, LocalMeta) {
    (server, .clean)
}

public protocol NoteTransport: Sendable {
    func changes(after cursor: Int) async throws -> ChangePage
    func fetchNote(id: UUID) async throws -> Note
    func putNote(_ note: Note, baseRevision: Int) async throws -> Note
    func deleteNote(id: UUID, baseRevision: Int) async throws -> Note
    func putBlob(sha256: String, data: Data) async throws
    func fetchBlob(sha256: String) async throws -> Data
}

public enum APIError: Error, Equatable {
    case conflict(Note)
    case unauthorized
    case slowDown
    case notFound
    case badStatus(Int, String)
    case invalidResponse
}

@MainActor
public enum Syncer {
    /// Pulls first, then pushes dirty notes that are not in conflict.
    /// Ink blobs are uploaded before the note that references them.
    public static func sync(store: LocalStore, transport: any NoteTransport) async throws -> SyncReport {
        var report = SyncReport(pushed: 0, pulled: 0, conflicts: 0)
        try await pull(into: &report, store: store, transport: transport)
        let records = try store.list()
        for (note, meta) in records where meta.dirty && !meta.conflict {
            do {
                if let saved = try await push(note, store: store, transport: transport) {
                    try store.save(note: saved, meta: .clean)
                    try store.clearConflict(id: saved.id)
                    report.pushed += 1
                }
            } catch let APIError.conflict(server) {
                // Someone wrote between pull and push, or the note already exists in a newly bound account.
                try await ensureBlobs(of: server, store: store, transport: transport)
                try store.saveConflict(server)
                try store.save(note: note, meta: LocalMeta(dirty: true, conflict: true))
                report.conflicts += 1
            } catch let APIError.badStatus(code, _) where code == 400 || code == 413 {
                // One note the server refuses must not hold back the others. See PITFALLS P-045.
                report.rejected.append(note.id)
            }
        }
        // The push is itself a change. A second pull advances the cursor past it.
        try await pull(into: &report, store: store, transport: transport)
        return report
    }

    private static func pull(into report: inout SyncReport, store: LocalStore, transport: any NoteTransport) async throws {
        var page: ChangePage
        repeat {
            let before = try store.cursor()
            page = try await transport.changes(after: before)
            // A page that claims more but does not move the cursor would loop forever.
            if page.hasMore && page.cursor <= before { throw APIError.invalidResponse }
            try await apply(page, into: &report, store: store, transport: transport)
            try store.setCursor(page.cursor)
        } while page.hasMore
    }

    private static func apply(_ page: ChangePage, into report: inout SyncReport, store: LocalStore, transport: any NoteTransport) async throws {
        var seen = Set<UUID>()
        for change in page.changes where seen.insert(change.noteId).inserted {
            let server = try await transport.fetchNote(id: change.noteId)
            try await ensureBlobs(of: server, store: store, transport: transport)
            if let local = try store.note(id: server.id) {
                let meta = try store.meta(for: local.id)
                switch decide(local: local, dirty: meta.dirty, server: server) {
                case .unchanged, .pushLocal:
                    break
                case .takeServer:
                    try store.save(note: server, meta: .clean)
                    try store.clearConflict(id: server.id)
                    report.pulled += 1
                case .conflict:
                    try store.saveConflict(server)
                    try store.save(note: local, meta: LocalMeta(dirty: true, conflict: true))
                    report.conflicts += 1
                }
            } else {
                try store.save(note: server, meta: .clean)
                report.pulled += 1
            }
        }
    }

    private static func push(_ note: Note, store: LocalStore, transport: any NoteTransport) async throws -> Note? {
        if note.deletedAt != nil {
            if note.revision == 0 {
                // Never reached the server. It stays in the trash on this device only.
                try store.save(note: note, meta: .clean)
                return nil
            }
            do {
                return try await transport.deleteNote(id: note.id, baseRevision: note.revision)
            } catch APIError.notFound {
                // The server never had it, e.g. after a restore. It stays in the local trash.
                var local = note
                local.revision = 0
                try store.save(note: local, meta: .clean)
                return nil
            }
        }
        if note.kind == .ink {
            for page in note.pages ?? [] {
                for name in page.blobNames {
                    guard let data = try store.blob(name) else { throw InkhashError.missingBlob(name) }
                    try await transport.putBlob(sha256: name, data: data)
                }
            }
        }
        do {
            return try await transport.putNote(note, baseRevision: note.revision)
        } catch APIError.notFound where note.revision > 0 {
            // The server lost this note, e.g. after a restore from an older backup. Create it again.
            return try await transport.putNote(note, baseRevision: 0)
        }
    }

    private static func ensureBlobs(of note: Note, store: LocalStore, transport: any NoteTransport) async throws {
        guard note.kind == .ink else { return }
        for page in note.pages ?? [] {
            for name in page.blobNames {
                if try store.blob(name) != nil { continue }
                let data = try await transport.fetchBlob(sha256: name)
                try store.putBlob(data, expected: name)
            }
        }
    }
}
