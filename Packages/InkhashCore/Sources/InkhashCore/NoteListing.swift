import Foundation

/// A note as the app shows it: the note and whether it waits for the server or conflicts with it.
public struct NoteRecord: Identifiable, Equatable, Sendable {
    public var note: Note
    public var dirty: Bool
    public var conflict: Bool
    public var id: UUID { note.id }

    public init(note: Note, dirty: Bool, conflict: Bool) {
        self.note = note
        self.dirty = dirty
        self.conflict = conflict
    }

    public init(note: Note, meta: LocalMeta) {
        self.init(note: note, dirty: meta.dirty, conflict: meta.conflict)
    }
}

public struct ListedNote: Identifiable, Equatable, Sendable {
    public var record: NoteRecord
    public var snippet: String?
    public var id: UUID { record.id }
}

/// What the sidebar lists. The tree of the workspace, or one of the two flat lists. See ADR 0022.
public enum LibrarySection: Hashable, Sendable {
    case notes
    case favorites
    case trash
}

/// A folder with its subfolders and the notes lying directly in it.
public struct NoteTree: Identifiable, Sendable {
    public var path: String
    public var folders: [NoteTree]
    public var notes: [NoteRecord]
    public var id: String { path }

    public var isEmpty: Bool { folders.isEmpty && notes.isEmpty }

    /// Builds the tree over `notes`. `kept` adds folders that hold no note yet.
    public static func build(notes: [NoteRecord], kept: [String]) -> NoteTree {
        let paths = Folders.tree(kept: kept, used: notes.map(\.note.folder))
        var byFolder: [String: [NoteRecord]] = [:]
        for record in notes {
            byFolder[record.note.folder, default: []].append(record)
        }
        func node(_ path: String) -> NoteTree {
            NoteTree(
                path: path,
                folders: paths.filter { $0 != path && Folders.parent(of: $0) == path }.map(node),
                notes: (byFolder[path] ?? []).sorted { $0.note.updatedAt > $1.note.updatedAt }
            )
        }
        return node("")
    }
}

public struct TagCount: Identifiable, Equatable, Sendable {
    public var tag: String
    public var count: Int
    public var id: String { tag }

    public init(tag: String, count: Int) {
        self.tag = tag
        self.count = count
    }
}

/// Everything the sidebar and the link menus read from the notes of one workspace.
/// Pure: it only looks at what it is given. See ADR 0022 and 0027.
public struct NoteListing {
    public var records: [NoteRecord]
    /// Folders kept without notes in them.
    public var keptFolders: [String]

    public init(records: [NoteRecord], keptFolders: [String]) {
        self.records = records
        self.keptFolders = keptFolders
    }

    public func record(_ id: UUID) -> NoteRecord? {
        records.first { $0.id == id }
    }

    /// Notes of a section, newest first; with a query only the hits, in their order, with snippets.
    public func listed(_ section: LibrarySection, query: String) -> [ListedNote] {
        let pool: [NoteRecord]
        switch section {
        case .notes: pool = livingRecords
        case .favorites: pool = livingRecords.filter(\.note.favorite)
        case .trash: pool = records.filter { $0.note.deletedAt != nil }
        }
        let sorted = pool.sorted { $0.note.updatedAt > $1.note.updatedAt }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return sorted.map { ListedNote(record: $0, snippet: nil) }
        }
        let hits = NoteSearch.search(trimmed, in: sorted.map(\.note.searchDocument))
        let byID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
        return hits.compactMap { hit in
            byID[hit.id].map { ListedNote(record: $0, snippet: hit.snippet) }
        }
    }

    /// A query starting with "#" filters the tree by tag instead of searching the text.
    public static func tagFilter(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        return trimmed.dropFirst().lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Tags offered while someone types a "#" filter: those starting with it, most used first.
    public func suggestedTags(query: String) -> [TagCount] {
        guard let filter = Self.tagFilter(query) else { return [] }
        return tagCounts.filter { filter.isEmpty || $0.tag.hasPrefix(filter) }
    }

    /// The folder tree. With a tag filter only the notes carrying a tag that starts with it, and
    /// only the folders they lie in; without one every folder, empty ones included.
    public func folderTree(query: String) -> NoteTree {
        guard let filter = Self.tagFilter(query) else {
            return NoteTree.build(notes: livingRecords, kept: keptFolders)
        }
        let matching = livingRecords.filter { record in
            record.note.tags.contains { filter.isEmpty || $0.hasPrefix(filter) }
        }
        return NoteTree.build(notes: matching, kept: [])
    }

    public var tags: [String] {
        Hashtags.unique(living.flatMap(\.tags))
    }

    public var tagCounts: [TagCount] {
        var counts: [String: Int] = [:]
        for note in living {
            for tag in Set(note.tags) { counts[tag, default: 0] += 1 }
        }
        return tags.map { TagCount(tag: $0, count: counts[$0] ?? 0) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    public var folders: [String] {
        Folders.tree(kept: keptFolders, used: living.map(\.folder))
    }

    public var trashCount: Int {
        records.filter { $0.note.deletedAt != nil }.count
    }

    /// The living notes of one kind, newest first.
    public func notes(of kind: NoteKind) -> [Note] {
        living.filter { $0.kind == kind }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Notes a link can point to: not in the trash, title containing the query, newest first. See ADR 0027.
    public func linkable(matching query: String, excluding id: UUID? = nil, limit: Int = 8) -> [NoteRecord] {
        let folded = Self.fold(query)
        return livingRecords
            .filter { $0.id != id }
            .filter { folded.isEmpty || Self.fold($0.note.displayTitle).contains(folded) }
            .sorted { $0.note.updatedAt > $1.note.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    private var livingRecords: [NoteRecord] {
        records.filter { $0.note.deletedAt == nil }
    }

    private var living: [Note] {
        livingRecords.map(\.note)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
}
