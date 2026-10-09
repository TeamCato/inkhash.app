import Foundation

/// A workspace as one ZIP file: every note to read in other apps, and a copy the app can bring
/// back. See ADR 0051.
///
/// ```
/// inkhash-export.json          what this is, for which workspace, when
/// Notizen/<Pfad>/<Titel>.md    text notes as Markdown
/// Notizen/<Pfad>/<Titel>.pdf   handwritten notes as PDF, if the app could render them
/// inkhash/notes/<id>.json      every note as the app stores it
/// inkhash/blobs/<sha256>       drawings and photos
/// ```
public enum WorkspaceExport {
    public static let manifestName = "inkhash-export.json"
    public static let format = "inkhash-export"
    public static let version = 1
    static let readable = "Notizen"
    static let notesFolder = "inkhash/notes/"
    static let blobsFolder = "inkhash/blobs/"

    public struct Manifest: Codable, Equatable, Sendable {
        public var format: String
        public var version: Int
        public var workspace: String
        public var exportedAt: String
        public var notes: Int
    }

    public struct Summary: Equatable, Sendable {
        public var notes: Int
        /// Handwritten notes whose PDF could not be made. Their copy for the app is still there.
        public var withoutPDF: Int
    }

    /// Writes the notes outside the trash to `url`. `blob` reads a blob by name; a missing blob is
    /// an error, since the copy would not come back whole. `pdf` renders a handwritten note.
    @MainActor
    public static func write(
        to url: URL,
        workspace: String,
        notes: [Note],
        now: String = InkhashTime.now(),
        blob: (String) throws -> Data?,
        pdf: (Note) -> Data?
    ) throws -> Summary {
        let living = notes.filter { $0.deletedAt == nil }.sorted { ($0.folder, $0.displayTitle, $0.id.uuidString) < ($1.folder, $1.displayTitle, $1.id.uuidString) }
        let zip = try ZipWriter(url: url)
        let manifest = Manifest(format: format, version: version, workspace: workspace, exportedAt: now, notes: living.count)
        try zip.add(manifestName, data: try InkhashJSON.encode(manifest))
        var namer = ExportNames.Namer()
        var written = Set<String>()
        var withoutPDF = 0
        for note in living {
            let directory = [readable, ExportNames.folderPath(note.folder)].filter { !$0.isEmpty }.joined(separator: "/")
            let name = ExportNames.fileName(note.displayTitle)
            switch note.kind {
            case .text:
                try zip.add(namer.path(in: directory, name: name, ext: "md"), data: Data((note.markdown ?? "").utf8))
            case .ink:
                if let data = pdf(note) {
                    try zip.add(namer.path(in: directory, name: name, ext: "pdf"), data: data)
                } else {
                    withoutPDF += 1
                }
            }
            try zip.add(notesFolder + note.id.uuidString.lowercased() + ".json", data: try InkhashJSON.encode(note))
            for page in note.pages ?? [] {
                for sha in page.blobNames where written.insert(sha).inserted {
                    guard let data = try blob(sha) else { throw InkhashError.missingBlob(sha) }
                    try zip.add(blobsFolder + sha, data: data)
                }
            }
        }
        try zip.finish()
        return Summary(notes: living.count, withoutPDF: withoutPDF)
    }

    /// True if `data` is a ZIP this app exported.
    public static func isExport(_ data: Data) -> Bool {
        guard let archive = try? ZipArchive(data) else { return false }
        return archive.contains(manifestName)
    }

    /// The notes and blobs of an export, checked: every blob matches its name, every note's
    /// blobs are there.
    public static func read(_ data: Data) throws -> Backup {
        let archive = try ZipArchive(data)
        guard let manifestData = try archive.read(manifestName),
              let manifest = try? InkhashJSON.decode(Manifest.self, from: manifestData),
              manifest.format == format else { throw ExportError.notAnExport }
        guard manifest.version <= version else { throw ExportError.newerVersion }
        var notes: [Note] = []
        var blobs: [String: Data] = [:]
        for name in archive.entries.keys.sorted() {
            if name.hasPrefix(notesFolder), name.hasSuffix(".json") {
                guard let data = try archive.read(name) else { continue }
                notes.append(try InkhashJSON.decode(Note.self, from: data))
            } else if name.hasPrefix(blobsFolder) {
                let sha = String(name.dropFirst(blobsFolder.count))
                guard let data = try archive.read(name), sha256Hex(data) == sha else { throw ExportError.damaged }
                blobs[sha] = data
            }
        }
        for note in notes {
            for page in note.pages ?? [] where page.blobNames.contains(where: { blobs[$0] == nil }) {
                throw ExportError.damaged
            }
        }
        return Backup(manifest: manifest, notes: notes, blobs: blobs)
    }

    public struct Backup: Sendable {
        public var manifest: Manifest
        public var notes: [Note]
        public var blobs: [String: Data]
    }

    /// Brings the notes of an export into `store` as new notes of this device: never sent,
    /// in the next sync. A note that is already here with the same content is left alone; one
    /// whose id is taken by something else gets a new id. Returns the ids now holding the notes.
    @MainActor
    @discardableResult
    public static func restore(_ backup: Backup, into store: LocalStore, now: String = InkhashTime.now()) throws -> [UUID] {
        for (sha, data) in backup.blobs where try store.blob(sha) == nil {
            try store.putBlob(data, expected: sha)
        }
        var ids: [UUID] = []
        for note in backup.notes where note.deletedAt == nil {
            var local = note
            local.revision = 0
            if let existing = try store.note(id: note.id) {
                if existing.deletedAt == nil, existing.sameContent(as: note) {
                    ids.append(existing.id)
                    continue
                }
                local.id = UUID()
            }
            local.touch(now)
            try store.save(note: local, meta: LocalMeta(dirty: true, conflict: false))
            ids.append(local.id)
        }
        return ids
    }
}

public enum ExportError: Error, Equatable {
    case notAnExport
    /// Made by a newer app; this one would lose what it does not know.
    case newerVersion
    case damaged
}
