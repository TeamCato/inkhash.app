import Foundation

/// The one library of a device. It belongs to no account and works without a server.
/// A server is optional; see ADR 0017.
@MainActor
public enum Library {
    static let folder = "library"
    static let staging = "library-migrating"

    /// Opens the library under `base`. Older layouts with a store per account and one for
    /// "signed out" are folded in once: the signed-in account's store becomes the library,
    /// signed-out notes join it as new local notes. Stores of other accounts stay where they are.
    public static func open(base: URL, signedInAccount: String?) throws -> LocalStore {
        let manager = FileManager.default
        let root = base.appendingPathComponent(folder, isDirectory: true)
        if manager.fileExists(atPath: root.path) {
            return try LocalStore(root: root)
        }
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        let stagingRoot = base.appendingPathComponent(staging, isDirectory: true)
        if !manager.fileExists(atPath: stagingRoot.path) {
            let accountRoot = signedInAccount.map {
                base.appendingPathComponent("accounts", isDirectory: true).appendingPathComponent($0, isDirectory: true)
            }
            if let accountRoot, let signedInAccount, manager.fileExists(atPath: accountRoot.path) {
                try manager.moveItem(at: accountRoot, to: stagingRoot)
                try LocalStore(root: stagingRoot).setBoundAccount(signedInAccount)
            } else {
                try manager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            }
        }
        let library = try LocalStore(root: stagingRoot)
        // `base` itself held notes before accounts existed.
        for source in [base.appendingPathComponent("signed-out", isDirectory: true), base] {
            guard hasNotes(source) else { continue }
            try importLocal(from: LocalStore(root: source), into: library)
            for name in ["notes", "meta", "conflicts", "blobs", "cursor.txt"] {
                let url = source.appendingPathComponent(name)
                if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            }
        }
        try manager.moveItem(at: stagingRoot, to: root)
        return try LocalStore(root: root)
    }

    /// Prepares the library to sync with `account`. Returns true if it had to let go of an earlier account.
    ///
    /// Same account: nothing changes, syncing continues where it stopped.
    /// Other account or first sign-in: every note becomes a new, unsent note for this account.
    @discardableResult
    public static func bind(_ store: LocalStore, to account: String) throws -> Bool {
        if store.boundAccount() == account { return false }
        for (note, meta) in try store.list() {
            if note.deletedAt != nil {
                try store.remove(id: note.id)
                continue
            }
            if meta.conflict, let other = try store.conflictNote(id: note.id), other.deletedAt == nil {
                var copy = other
                copy.id = UUID()
                copy.revision = 0
                try store.save(note: copy, meta: LocalMeta(dirty: true, conflict: false))
            }
            try store.clearConflict(id: note.id)
            var local = note
            local.revision = 0
            try store.save(note: local, meta: LocalMeta(dirty: true, conflict: false))
        }
        try store.setCursor(0)
        try store.setBoundAccount(account)
        return true
    }

    private static func importLocal(from source: LocalStore, into library: LocalStore) throws {
        for (note, meta) in try source.list() where note.deletedAt == nil {
            try copyBlobs(of: note, from: source, into: library)
            var local = note
            local.revision = 0
            if let existing = try library.note(id: note.id) {
                if existing.sameContent(as: note) { continue }
                local.id = UUID()
            }
            try library.save(note: local, meta: LocalMeta(dirty: true, conflict: false))
            if meta.conflict, var other = try source.conflictNote(id: note.id), other.deletedAt == nil {
                try copyBlobs(of: other, from: source, into: library)
                other.id = UUID()
                other.revision = 0
                try library.save(note: other, meta: LocalMeta(dirty: true, conflict: false))
            }
        }
    }

    private static func copyBlobs(of note: Note, from source: LocalStore, into library: LocalStore) throws {
        for page in note.pages ?? [] {
            for name in page.blobNames {
                if try library.blob(name) != nil { continue }
                if let data = try source.blob(name) {
                    try library.putBlob(data, expected: name)
                }
            }
        }
    }

    private static func hasNotes(_ root: URL) -> Bool {
        let directory = root.appendingPathComponent("notes", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        return urls.contains { $0.pathExtension == "json" }
    }
}
