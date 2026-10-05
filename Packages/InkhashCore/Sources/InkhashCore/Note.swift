import Foundation

public enum NoteKind: String, Codable, Sendable, Equatable {
    case text
    case ink
}

public enum PageGeometry {
    public static let width: Double = 768
    public static let height: Double = 1024
}

public struct InkPage: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var blob: String
    public var width: Double
    public var height: Double
    public var transcript: String
    public var tags: [String]
    /// Photos, shapes, tape and link areas, under the ink. See ADR 0028.
    public var elements: [PageElement]

    public init(
        id: UUID = UUID(),
        blob: String,
        width: Double = PageGeometry.width,
        height: Double = PageGeometry.height,
        transcript: String = "",
        tags: [String] = [],
        elements: [PageElement] = []
    ) {
        self.elements = elements
        self.id = id
        self.blob = blob
        self.width = width
        self.height = height
        self.transcript = transcript
        self.tags = tags
    }
}

public struct Note: Equatable, Sendable, Identifiable {
    public static let untitled = "Ohne Titel"
    public static let schema = 1

    public var schemaVersion: Int
    public var id: UUID
    public var kind: NoteKind
    public var title: String
    public var revision: Int
    public var updatedAt: String
    public var deletedAt: String?
    public var markdown: String?
    public var transcript: String?
    public var tags: [String]
    public var pages: [InkPage]?
    /// Folder path, segments joined by "/". Empty means no folder. See ADR 0020.
    public var folder: String
    public var favorite: Bool
    /// Colour and pattern under the writing. Nil is `Paper.standard`. See ADR 0042.
    public var paper: Paper?

    public init(
        schemaVersion: Int = Note.schema,
        id: UUID = UUID(),
        kind: NoteKind,
        title: String = "",
        revision: Int = 0,
        updatedAt: String,
        deletedAt: String? = nil,
        markdown: String? = nil,
        transcript: String? = nil,
        tags: [String] = [],
        pages: [InkPage]? = nil,
        folder: String = "",
        favorite: Bool = false,
        paper: Paper? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.title = title
        self.revision = revision
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.markdown = markdown
        self.transcript = transcript
        self.tags = tags
        self.pages = pages
        self.folder = folder
        self.favorite = favorite
        self.paper = paper
    }

    /// Equal in everything a person wrote. Ignores revision and timestamps.
    public func sameContent(as other: Note) -> Bool {
        kind == other.kind
            && title == other.title
            && markdown == other.markdown
            && transcript == other.transcript
            && tags == other.tags
            && pages == other.pages
            && folder == other.folder
            && favorite == other.favorite
            && paper == other.paper
            && (deletedAt == nil) == (other.deletedAt == nil)
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return Self.clip(trimmed)
        }
        if kind == .ink, let line = Self.firstLine(transcript) {
            return Self.clip(line)
        }
        return Self.untitled
    }

    public var searchDocument: SearchDocument {
        let body = kind == .text ? (markdown ?? "") : (transcript ?? "")
        return SearchDocument(id: id, title: displayTitle, body: body, tags: tags)
    }

    public static func newText(now: String = InkhashTime.now()) -> Note {
        var note = Note(kind: .text, updatedAt: now, markdown: "")
        note.applyMarkdown("")
        return note
    }

    public static func newInk(page: InkPage, now: String = InkhashTime.now()) -> Note {
        Note(kind: .ink, updatedAt: now, transcript: "", tags: [], pages: [page])
    }

    /// True while the title follows the text. A title someone typed stays put. No flag on the wire:
    /// a title that equals what the text would give is automatic. See ADR 0019.
    public var hasAutomaticTitle: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        guard kind == .text else { return false }
        return title == MarkdownCodec.title(for: markdown ?? "")
    }

    /// The title the note would get from its content alone.
    public var automaticTitle: String {
        switch kind {
        case .text:
            return MarkdownCodec.title(for: markdown ?? "")
        case .ink:
            let line = (transcript ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? Self.untitled : trimmed
        }
    }

    /// Sets a title by hand. An empty title hands it back to the text. Returns false if nothing changed.
    @discardableResult
    public mutating func setTitle(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).clippedUTF16(Limits.title)
        let next: String
        if trimmed.isEmpty {
            next = kind == .text ? MarkdownCodec.title(for: markdown ?? "") : ""
        } else {
            next = trimmed
        }
        guard next != title else { return false }
        title = next
        return true
    }

    /// Writer-side update for text notes. Returns false when nothing changed.
    @discardableResult
    public mutating func applyMarkdown(_ markdown: String) -> Bool {
        let automatic = hasAutomaticTitle
        let nextTitle = automatic ? MarkdownCodec.title(for: markdown) : title
        let nextTags = Hashtags.inText(markdown, mode: .markdown)
        if self.markdown == markdown, title == nextTitle, tags == nextTags, transcript == nil, pages == nil {
            return false
        }
        self.kind = .text
        self.markdown = markdown
        self.title = nextTitle
        self.tags = nextTags
        self.transcript = nil
        self.pages = nil
        return true
    }

    /// Writer-side update after on-device recognition. Does not touch a custom ink title.
    /// An empty reading of a page that still has ink keeps the transcript it had: recognition
    /// failed, the words did not go away. See PITFALLS P-015.
    @discardableResult
    public mutating func applyInkReading(pageID: UUID, transcript: String, tags: [String], pageHasInk: Bool = false) -> Bool {
        guard var pages, let index = pages.firstIndex(where: { $0.id == pageID }) else { return false }
        if pageHasInk, transcript.isEmpty, tags.isEmpty { return false }
        let nextTags = Hashtags.unique(tags)
        if pages[index].transcript == transcript, pages[index].tags == nextTags { return false }
        pages[index].transcript = transcript
        pages[index].tags = nextTags
        self.pages = pages
        self.kind = .ink
        self.markdown = nil
        refreshInkSummary()
        return true
    }

    /// The paper as shown: the standard where the note has none.
    public var shownPaper: Paper { paper ?? .standard }

    /// Sets the paper. A text note keeps only the colour; the standard paper clears the field.
    /// Returns false if nothing changed. See ADR 0042.
    @discardableResult
    public mutating func setPaper(_ next: Paper) -> Bool {
        var next = next
        if kind == .text { next.pattern = .blank }
        let stored: Paper? = next == .standard ? nil : next
        guard stored != paper else { return false }
        paper = stored
        return true
    }

    /// Puts the pages in the given order. The ids must be exactly the pages there are.
    @discardableResult
    public mutating func reorderPages(_ order: [UUID]) -> Bool {
        guard let pages, order.count == pages.count, Set(order) == Set(pages.map(\.id)),
              order != pages.map(\.id) else { return false }
        let byID = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        self.pages = order.compactMap { byID[$0] }
        refreshInkSummary()
        return true
    }

    /// Moves one page by `offset` places, as far as the ends allow.
    @discardableResult
    public mutating func movePage(_ pageID: UUID, by offset: Int) -> Bool {
        guard var order = pages?.map(\.id), let from = order.firstIndex(of: pageID) else { return false }
        let to = min(max(from + offset, 0), order.count - 1)
        guard to != from else { return false }
        order.insert(order.remove(at: from), at: to)
        return reorderPages(order)
    }

    /// Removes a page. The last page of a note stays.
    @discardableResult
    public mutating func removePage(_ pageID: UUID) -> Bool {
        guard var pages, pages.count > 1, let index = pages.firstIndex(where: { $0.id == pageID }) else { return false }
        pages.remove(at: index)
        self.pages = pages
        refreshInkSummary()
        return true
    }

    /// Transcript and tags of an ink note follow its pages, in page order.
    private mutating func refreshInkSummary() {
        guard let pages else { return }
        transcript = pages.map(\.transcript).filter { !$0.isEmpty }.joined(separator: "\n\n")
        tags = Hashtags.unique(pages.flatMap(\.tags))
    }

    private static func firstLine(_ transcript: String?) -> String? {
        guard let transcript else { return nil }
        for line in transcript.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return String(trimmed) }
        }
        return nil
    }

    private static func clip(_ text: String) -> String {
        if text.count <= 80 { return text }
        return String(text.prefix(80))
    }
}

extension Note: Codable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, kind, title, revision, updatedAt, deletedAt
        case markdown, transcript, tags, pages, folder, favorite, paper
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schema else { throw InkhashError.unsupportedSchema }
        let idString = try container.decode(String.self, forKey: .id)
        guard let id = UUID(uuidString: idString) else { throw InkhashError.invalidID }
        self.schemaVersion = version
        self.id = id
        self.kind = try container.decode(NoteKind.self, forKey: .kind)
        self.title = try container.decode(String.self, forKey: .title)
        self.revision = try container.decode(Int.self, forKey: .revision)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.markdown = try container.decodeIfPresent(String.self, forKey: .markdown)
        self.transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.pages = try container.decodeIfPresent([InkPage].self, forKey: .pages)
        // Notes from before folders carry neither field.
        self.folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        self.favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        // Notes from before ADR 0042 have the standard paper.
        self.paper = try container.decodeIfPresent(Paper.self, forKey: .paper)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(revision, forKey: .revision)
        try container.encode(updatedAt, forKey: .updatedAt)
        if let deletedAt {
            try container.encode(deletedAt, forKey: .deletedAt)
        } else {
            try container.encodeNil(forKey: .deletedAt)
        }
        if let markdown {
            try container.encode(markdown, forKey: .markdown)
        } else {
            try container.encodeNil(forKey: .markdown)
        }
        if let transcript {
            try container.encode(transcript, forKey: .transcript)
        } else {
            try container.encodeNil(forKey: .transcript)
        }
        try container.encode(tags, forKey: .tags)
        if let pages {
            try container.encode(pages, forKey: .pages)
        } else {
            try container.encodeNil(forKey: .pages)
        }
        try container.encode(folder, forKey: .folder)
        try container.encode(favorite, forKey: .favorite)
        // Left out, not null, so notes on the standard paper look as they did before.
        try container.encodeIfPresent(paper, forKey: .paper)
    }
}

extension InkPage: Codable {
    enum CodingKeys: String, CodingKey {
        case id, blob, width, height, transcript, tags, elements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        guard let id = UUID(uuidString: idString) else { throw InkhashError.invalidID }
        self.id = id
        self.blob = try container.decode(String.self, forKey: .blob)
        self.width = try container.decode(Double.self, forKey: .width)
        self.height = try container.decode(Double.self, forKey: .height)
        self.transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        // Pages from before elements carry none. See ADR 0028.
        // A link area whose target could not be repaired has nothing left to be. See ADR 0031.
        self.elements = (try container.decodeIfPresent([PageElement].self, forKey: .elements) ?? [])
            .filter { $0.kind != .link || $0.link != nil }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(blob, forKey: .blob)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(tags, forKey: .tags)
        try container.encode(elements, forKey: .elements)
    }
}

public enum InkhashError: Error, Equatable {
    case unsupportedSchema
    case invalidID
    case missingBlob(String)
    case hashMismatch
    case invalidNote(String)
}

public enum InkhashTime {
    public static func now(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
    }
}

public enum InkhashJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
