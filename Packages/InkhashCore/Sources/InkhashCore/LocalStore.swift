import Foundation

public struct LocalMeta: Codable, Equatable, Sendable {
    public var dirty: Bool
    public var conflict: Bool

    public init(dirty: Bool, conflict: Bool) {
        self.dirty = dirty
        self.conflict = conflict
    }

    public static let clean = LocalMeta(dirty: false, conflict: false)
}

@MainActor
public final class LocalStore {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        let manager = FileManager.default
        for name in ["notes", "meta", "conflicts", "blobs"] {
            try manager.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    public func list() throws -> [(note: Note, meta: LocalMeta)] {
        let directory = root.appendingPathComponent("notes")
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var records: [(Note, LocalMeta)] = []
        for url in urls where url.pathExtension == "json" {
            let note = try InkhashJSON.decode(Note.self, from: Data(contentsOf: url))
            records.append((note, try meta(for: note.id)))
        }
        return records
    }

    public func note(id: UUID) throws -> Note? {
        let url = noteURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try InkhashJSON.decode(Note.self, from: Data(contentsOf: url))
    }

    public func meta(for id: UUID) throws -> LocalMeta {
        let url = metaURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return .clean }
        return try InkhashJSON.decode(LocalMeta.self, from: Data(contentsOf: url))
    }

    public func save(note: Note, meta: LocalMeta) throws {
        try write(try InkhashJSON.encode(note), to: noteURL(note.id))
        try write(try InkhashJSON.encode(meta), to: metaURL(note.id))
    }

    public func remove(id: UUID) throws {
        let manager = FileManager.default
        for url in [noteURL(id), metaURL(id), conflictURL(id)] where manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
    }

    public func blob(_ sha: String) throws -> Data? {
        guard isSHA(sha) else { throw InkhashError.invalidID }
        let url = root.appendingPathComponent("blobs").appendingPathComponent(sha)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    @discardableResult
    public func putBlob(_ data: Data) throws -> String {
        let sha = sha256Hex(data)
        let url = root.appendingPathComponent("blobs").appendingPathComponent(sha)
        if !FileManager.default.fileExists(atPath: url.path) {
            try write(data, to: url)
        }
        return sha
    }

    public func putBlob(_ data: Data, expected: String) throws {
        let sha = try putBlob(data)
        guard sha == expected else { throw InkhashError.hashMismatch }
    }

    public func cursor() throws -> Int {
        let url = root.appendingPathComponent("cursor.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8), let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        return value
    }

    public func setCursor(_ value: Int) throws {
        try write(Data(String(value).utf8), to: root.appendingPathComponent("cursor.txt"))
    }

    /// The account this library last synced with, or nil if it never did. See ADR 0017.
    public func boundAccount() -> String? {
        let url = root.appendingPathComponent("account.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func setBoundAccount(_ account: String) throws {
        try write(Data(account.utf8), to: root.appendingPathComponent("account.txt"))
    }

    /// Folders kept on this device even while no note lies in them. Notes carry their own folder.
    public func keptFolders() -> [String] {
        let url = root.appendingPathComponent("folders.json")
        guard let data = try? Data(contentsOf: url), let list = try? InkhashJSON.decode([String].self, from: data) else {
            return []
        }
        return list.filter(Folders.isValid)
    }

    public func setKeptFolders(_ folders: [String]) throws {
        try write(try InkhashJSON.encode(folders), to: root.appendingPathComponent("folders.json"))
    }

    /// How the sidebar of this workspace is arranged. Device only, never synced. See ADR 0022.
    public func sidebar() -> SidebarPrefs {
        let url = root.appendingPathComponent("sidebar.json")
        guard let data = try? Data(contentsOf: url), let prefs = try? InkhashJSON.decode(SidebarPrefs.self, from: data) else {
            return SidebarPrefs()
        }
        return prefs
    }

    public func setSidebar(_ prefs: SidebarPrefs) throws {
        try write(try InkhashJSON.encode(prefs), to: root.appendingPathComponent("sidebar.json"))
    }

    public func saveConflict(_ note: Note) throws {
        try write(try InkhashJSON.encode(note), to: conflictURL(note.id))
    }

    public func conflictNote(id: UUID) throws -> Note? {
        let url = conflictURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try InkhashJSON.decode(Note.self, from: Data(contentsOf: url))
    }

    public func clearConflict(id: UUID) throws {
        let url = conflictURL(id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func noteURL(_ id: UUID) -> URL {
        root.appendingPathComponent("notes").appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    private func metaURL(_ id: UUID) -> URL {
        root.appendingPathComponent("meta").appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    private func conflictURL(_ id: UUID) -> URL {
        root.appendingPathComponent("conflicts").appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    private func isSHA(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}
