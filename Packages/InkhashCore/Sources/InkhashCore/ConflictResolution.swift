import Foundation

/// How a conflict between this device and the server ends. See ADR 0005 and 0049.
public enum ConflictChoice: Equatable, Sendable {
    /// This device's version goes up on top of the server's revision.
    case mine
    /// The server's version replaces this device's.
    case server
    /// This device's version goes up; the server's stays as a new note next to it.
    case both
}

/// Both versions of a note in conflict, and what can be done with them.
public struct NoteConflict: Equatable, Sendable {
    public var local: Note
    public var server: Note

    public init(local: Note, server: Note) {
        self.local = local
        self.server = server
    }

    /// Keeping both only makes sense while both are notes someone still wants: a deletion on
    /// either side is a choice between keeping and deleting, not between two texts.
    public var canKeepBoth: Bool {
        local.deletedAt == nil && server.deletedAt == nil
    }

    /// The choices offered for this conflict, in the order they are shown.
    public var choices: [ConflictChoice] {
        canKeepBoth ? [.mine, .server, .both] : [.mine, .server]
    }

    /// What to store after `choice`. `kept` replaces the note in conflict, `copy` is a new note.
    /// Nil for `.both` when `canKeepBoth` is false.
    public func resolve(_ choice: ConflictChoice, now: String) -> ConflictResolution? {
        switch choice {
        case .mine:
            return ConflictResolution(kept: keepingMine(local: local, server: server), copy: nil)
        case .server:
            return ConflictResolution(kept: takingServer(server), copy: nil)
        case .both:
            guard canKeepBoth else { return nil }
            return ConflictResolution(
                kept: keepingMine(local: local, server: server),
                copy: (Self.copy(of: server, now: now), LocalMeta(dirty: true, conflict: false))
            )
        }
    }

    /// The server's version as a note of its own: new id, never sent, its title marked so the two
    /// can be told apart in the tree. The title counts as set by hand from then on (ADR 0019).
    static func copy(of server: Note, now: String) -> Note {
        var copy = server
        copy.id = UUID()
        copy.revision = 0
        copy.deletedAt = nil
        let suffix = " (Server)"
        copy.title = server.displayTitle.clippedUTF16(Limits.title - suffix.utf16.count) + suffix
        copy.touch(now)
        return copy
    }
}

public struct ConflictResolution: Equatable, Sendable {
    public var kept: (note: Note, meta: LocalMeta)
    public var copy: (note: Note, meta: LocalMeta)?

    public static func == (lhs: ConflictResolution, rhs: ConflictResolution) -> Bool {
        lhs.kept.note == rhs.kept.note && lhs.kept.meta == rhs.kept.meta
            && lhs.copy?.note == rhs.copy?.note && lhs.copy?.meta == rhs.copy?.meta
    }
}

public func keepingMine(local: Note, server: Note) -> (Note, LocalMeta) {
    var note = local
    note.revision = server.revision
    return (note, LocalMeta(dirty: true, conflict: false))
}

public func takingServer(_ server: Note) -> (Note, LocalMeta) {
    (server, .clean)
}
