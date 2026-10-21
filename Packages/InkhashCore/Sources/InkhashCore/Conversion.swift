import Foundation

/// What happens next with a workspace that syncs with an encrypted Kennel workspace. inkhash offers no vault anymore;
/// encrypted workspaces become plain ones on the same storage (teamCato ADR 0009 point 10, ADR 0077).
public enum ConversionStep: Equatable, Sendable {
    /// Kennel holds notes there this device has not read, and only the vault opens them.
    case waitForKey
    /// Kennel cannot make plain workspaces, or the workspace is moving to another storage right now.
    case waitForKennel
    /// This device has the newest state: it converts.
    case convert
    /// Another device converted it already; this is the plain successor to follow.
    case follow(RemoteWorkspace)
    /// Gone from Kennel without a successor: the notes stay on this device, „Nur hier“.
    case keepHere
}

/// The decisions of the conversion, without network or files, so they can be tested (ADR 0077).
public enum ConversionPlanner {
    /// - Parameters:
    ///   - name: the local workspace's name.
    ///   - link: its link to the encrypted Kennel workspace.
    ///   - remotes: Kennel's workspaces of the account.
    ///   - taken: Kennel workspaces other local workspaces sync with.
    ///   - readable: this device has the newest state of the old workspace (its vault key is open and the sync went
    ///     through, or nothing came in since its last read).
    ///   - canPlain: Kennel makes plain workspaces (`modules.inkhash.plainWorkspaces`).
    ///   - overlap: how many notes each candidate shares with this workspace, by Kennel id; read only once the old
    ///     workspace is gone.
    ///   - hasSyncedNotes: this workspace has notes that reached Kennel (revision above 0).
    public static func step(
        name: String, link: WorkspaceLink, remotes: [RemoteWorkspace], taken: Set<String>, readable: Bool,
        canPlain: Bool, overlap: [String: Int], hasSyncedNotes: Bool
    ) -> ConversionStep {
        if let old = remotes.first(where: { $0.id == link.remote }) {
            guard canPlain, old.move?.isRunning != true else { return .waitForKennel }
            return readable ? .convert : .waitForKey
        }
        let found = candidates(named: name, among: remotes, taken: taken)
        if let successor = successor(among: found, overlap: overlap, hasSyncedNotes: hasSyncedNotes) {
            return .follow(successor)
        }
        return .keepHere
    }

    /// Plain Kennel workspaces with this name that no other local workspace syncs with.
    public static func candidates(named name: String, among remotes: [RemoteWorkspace], taken: Set<String>) -> [RemoteWorkspace] {
        let wanted = normalized(name)
        return remotes.filter { !$0.isSealed && !taken.contains($0.id) && normalized($0.name) == wanted }
    }

    /// The candidate sharing the most notes with this workspace. Sharing none is no proof, unless the old workspace
    /// never had a synced note and exactly one namesake exists. Nil leaves the workspace „Nur hier“, which loses nothing.
    public static func successor(among candidates: [RemoteWorkspace], overlap: [String: Int], hasSyncedNotes: Bool) -> RemoteWorkspace? {
        if let best = candidates.max(by: { (overlap[$0.id] ?? 0) < (overlap[$1.id] ?? 0) }), (overlap[best.id] ?? 0) > 0 {
            return best
        }
        if !hasSyncedNotes, candidates.count == 1 { return candidates[0] }
        return nil
    }

    /// A plain namesake on the same storage, e.g. one another device began converting into. The converting device
    /// joins it instead of making a second successor.
    public static func twin(of old: RemoteWorkspace, named name: String, among remotes: [RemoteWorkspace], taken: Set<String>) -> RemoteWorkspace? {
        candidates(named: name, among: remotes, taken: taken).first { $0.storageId == old.storageId }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// What converting needs from Kennel's workspaces. `APIClient` is the one for the network.
public protocol KennelWorkspaceWire: Sendable {
    func workspaceList() async throws -> RemoteWorkspaceList
    func createWorkspace(name: String, as choice: NewRemoteWorkspace) async throws -> RemoteWorkspace
    func deleteWorkspace(id: String) async throws
    /// The notes of one workspace, as they lie there.
    func notes(of remote: String) -> any NoteTransport
}

extension APIClient: KennelWorkspaceWire {
    public func notes(of remote: String) -> any NoteTransport {
        var scoped = self
        scoped.workspace = remote
        return scoped
    }
}

/// The steps of the conversion that talk to Kennel (ADR 0077). The app decides with `ConversionPlanner` and keeps
/// what it did in `Workspace.retiring` before it uploads anything, so an interrupted conversion goes on.
@MainActor
public enum Conversion {
    /// Whether Kennel has anything in `transport` past `cursor`. Only the change log is read, which needs no key.
    public static func hasChanges(after cursor: Int, in transport: any NoteTransport) async throws -> Bool {
        try await !transport.changes(after: cursor).changes.isEmpty
    }

    /// How many of `localIDs` each candidate holds, from its change log.
    public static func overlap(of candidates: [RemoteWorkspace], with localIDs: Set<UUID>, wire: any KennelWorkspaceWire) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for candidate in candidates {
            counts[candidate.id] = try await noteIDs(in: wire.notes(of: candidate.id)).intersection(localIDs).count
        }
        return counts
    }

    /// The plain successor of `old`: a twin another device began, or a new plain workspace on the same storage with
    /// the same name.
    public static func successor(
        of old: RemoteWorkspace, named name: String, remotes: [RemoteWorkspace], taken: Set<String>, wire: any KennelWorkspaceWire
    ) async throws -> RemoteWorkspace {
        if let twin = ConversionPlanner.twin(of: old, named: name, among: remotes, taken: taken) { return twin }
        return try await wire.createWorkspace(name: name, as: NewRemoteWorkspace(sealed: false, storageID: old.storageId))
    }

    /// Every note id in a workspace's change log.
    static func noteIDs(in transport: any NoteTransport) async throws -> Set<UUID> {
        var ids = Set<UUID>()
        var cursor = 0
        var page: ChangePage
        repeat {
            page = try await transport.changes(after: cursor)
            if page.hasMore && page.cursor <= cursor { throw APIError.invalidResponse }
            for change in page.changes { ids.insert(change.noteId) }
            cursor = page.cursor
        } while page.hasMore
        return ids
    }
}

/// Moving a library to a Kennel workspace that already holds its notes, e.g. the plain successor of an encrypted one,
/// without starting over like `Library.bind` (ADR 0077).
@MainActor
public enum Relinker {
    /// Merges what Kennel has in `transport` into `store`, then binds it to `bindingKey`. Nothing is lost:
    /// - a note Kennel has and this device has not changed takes Kennel's version,
    /// - a note changed here keeps the change, on top of Kennel's revision, and goes up with the next sync,
    /// - a note Kennel lacks goes up as new; a note in the trash stays in the trash on this device,
    /// - the other side of an old conflict becomes a note of its own, as in `Library.bind`.
    /// Bound to `bindingKey` already, nothing happens.
    public static func adopt(_ store: LocalStore, from transport: any NoteTransport, bindingKey: String) async throws {
        guard store.boundAccount() != bindingKey else { return }
        for (note, meta) in try store.list() where meta.conflict {
            if let other = try store.conflictNote(id: note.id), other.deletedAt == nil {
                var copy = other
                copy.id = UUID()
                copy.revision = 0
                try store.save(note: copy, meta: LocalMeta(dirty: true, conflict: false))
            }
            try store.clearConflict(id: note.id)
            try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        }
        let changedHere = Set(try store.list().filter { $0.meta.dirty }.map(\.note.id))
        var seen = Set<UUID>()
        var cursor = 0
        var page: ChangePage
        repeat {
            page = try await transport.changes(after: cursor)
            if page.hasMore && page.cursor <= cursor { throw APIError.invalidResponse }
            for change in page.changes where seen.insert(change.noteId).inserted {
                let server = try await transport.fetchNote(id: change.noteId)
                try await Syncer.ensureBlobs(of: server, store: store, transport: transport)
                if changedHere.contains(server.id), var kept = try store.note(id: server.id) {
                    kept.revision = server.revision
                    try store.save(note: kept, meta: LocalMeta(dirty: true, conflict: false))
                } else {
                    try store.save(note: server, meta: .clean)
                }
            }
            cursor = page.cursor
        } while page.hasMore
        for (note, _) in try store.list() where !seen.contains(note.id) {
            var local = note
            local.revision = 0
            try store.save(note: local, meta: note.deletedAt == nil ? LocalMeta(dirty: true, conflict: false) : .clean)
        }
        try store.setCursor(cursor)
        try store.setBoundAccount(bindingKey)
    }

    /// Notes another device wrote to the old encrypted workspace after this device left it, read with the vault key,
    /// become edits here, so they go up to the successor with the next sync. A note changed here meanwhile keeps the
    /// change; the late version then becomes a note of its own. Returns the old workspace's new cursor.
    public static func takeLate(from old: any NoteTransport, after cursor: Int, into store: LocalStore) async throws -> Int {
        var seen = Set<UUID>()
        var current = cursor
        var page: ChangePage
        repeat {
            page = try await old.changes(after: current)
            if page.hasMore && page.cursor <= current { throw APIError.invalidResponse }
            for change in page.changes where seen.insert(change.noteId).inserted {
                let late = try await old.fetchNote(id: change.noteId)
                try await Syncer.ensureBlobs(of: late, store: store, transport: old)
                let local = try store.note(id: late.id)
                let meta = try local.map { try store.meta(for: $0.id) }
                if let local, meta?.dirty == true {
                    guard late.deletedAt == nil, !local.sameContent(as: late) else { continue }
                    var copy = late
                    copy.id = UUID()
                    copy.revision = 0
                    try store.save(note: copy, meta: LocalMeta(dirty: true, conflict: false))
                } else if let local {
                    guard !local.sameContent(as: late) else { continue }
                    var taken = late
                    taken.revision = local.revision
                    try store.save(note: taken, meta: LocalMeta(dirty: true, conflict: false))
                } else if late.deletedAt == nil {
                    var taken = late
                    taken.revision = 0
                    try store.save(note: taken, meta: LocalMeta(dirty: true, conflict: false))
                }
            }
            current = page.cursor
        } while page.hasMore
        return current
    }
}
