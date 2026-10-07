import Foundation
import InkhashCore
import Observation
import PencilKit

/// The notes of the current workspace as the app edits them: kept in memory, written through
/// to its `LocalStore`. Navigation and syncing live elsewhere; `changed` is told after every
/// edit so a sync can follow. See ADR 0020 and 0022.
@MainActor
@Observable
final class NoteLibrary {
    private(set) var records: [NoteRecord] = []
    /// Folders kept without notes in them.
    private(set) var keptFolders: [String] = []
    /// How the sidebar is arranged. See ADR 0022.
    private(set) var sidebar = SidebarPrefs()
    /// Called after every edit that should reach the server.
    @ObservationIgnored var changed: () -> Void = {}
    private let registry: WorkspaceRegistry
    private let status: StatusLine

    init(registry: WorkspaceRegistry, status: StatusLine) {
        self.registry = registry
        self.status = status
        reload()
    }

    private var store: LocalStore { registry.currentStore }

    // MARK: Reading

    var listing: NoteListing { NoteListing(records: records, keptFolders: keptFolders) }

    func record(_ id: UUID) -> NoteRecord? {
        records.first { $0.id == id }
    }

    func drawingData(for blob: String) -> Data? {
        try? store.blob(blob)
    }

    /// What is drawn or placed on a page, in page coordinates. Nil for an empty page.
    func contentBounds(of page: InkPage) -> CGRect? {
        var bounds = CGRect.null
        if let data = drawingData(for: page.blob), let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty {
            bounds = drawing.bounds
        }
        for element in page.elements {
            bounds = bounds.union(ElementGeometry.bounds(of: element))
        }
        return bounds.isNull ? nil : bounds
    }

    func isExpanded(_ key: String) -> Bool {
        !sidebar.collapsed.contains(key)
    }

    /// Reads the current workspace again, e.g. after a sync or switching workspaces.
    func reload() {
        records = ((try? store.list()) ?? []).map { NoteRecord(note: $0.note, meta: $0.meta) }
        keptFolders = store.keptFolders()
        sidebar = store.sidebar()
    }

    /// Edits start from `records`, so they must see every revision a sync writes at once.
    /// Waiting for `reload` would let the next edit write the old revision back. See PITFALLS P-053.
    func synced(_ note: Note, meta: LocalMeta) {
        set(NoteRecord(note: note, meta: meta))
    }

    // MARK: Adding

    /// Stores a new note as it is and marks it for the next sync.
    func add(_ note: Note) {
        var note = note
        note.updatedAt = InkhashTime.now()
        upsert(note, dirty: true, conflict: false)
        changed()
    }

    /// Stores a drawing for a new ink note. Nil if the blob store fails; `failure` says so.
    func newInkNote(drawing data: Data, failure: String = "Die Zeichnung ließ sich nicht sichern.") -> Note? {
        guard let sha = try? store.putBlob(data) else {
            status.message = failure
            return nil
        }
        return Note.newInk(page: InkPage(blob: sha))
    }

    /// Keeps a photo as a JPEG blob. Returns its hash and pixel size, or nil if it is no image.
    func storeImage(_ data: Data) -> (blob: String, size: CGSize)? {
        guard let converted = ImageImport.jpeg(from: data) else {
            status.message = "Das Bild ließ sich nicht lesen."
            return nil
        }
        do {
            return (try store.putBlob(converted.data), converted.size)
        } catch {
            status.message = "Das Bild ließ sich nicht sichern."
            return nil
        }
    }

    /// A PDF export or a GoodNotes notebook becomes ink notes, one page per page. Which one it is
    /// comes from the bytes, not the file name. `place` puts each new note where it belongs.
    /// Returns the first new note. See ADR 0024 and 0041.
    func importFile(at url: URL, place: (Note) -> Note) -> UUID? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.deletingPathExtension().lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            if data.starts(with: [0x50, 0x4B]) {
                let notebook = try InkImport.notebook(fromGoodNotes: data)
                return addImported(notebook.pages, name: name, skipped: notebook.skipped, place: place)
            }
            return addImported(try InkImport.pages(fromPDF: data), name: name, skipped: 0, place: place)
        } catch PDFInkError.notAPDF, GoodNotesError.notGoodNotes {
            status.message = "Die Datei ist weder ein PDF noch ein GoodNotes-Notizbuch."
        } catch PDFInkError.noPages, GoodNotesError.noPages {
            status.message = "Die Datei hat keine Seiten."
        } catch {
            status.message = "Der Import ist fehlgeschlagen."
        }
        return nil
    }

    /// The title is the file name and counts as set. Recognition runs when the note is opened.
    private func addImported(_ imported: [InkImport.ImportedPage], name: String, skipped: Int, place: (Note) -> Note) -> UUID? {
        var pages: [InkPage] = []
        do {
            for page in imported {
                let sha = try store.putBlob(page.data)
                var elements: [PageElement] = []
                for var image in page.images {
                    image.element.blob = try store.putBlob(image.jpeg)
                    elements.append(image.element)
                }
                pages.append(InkPage(blob: sha, width: page.width, height: page.height, elements: elements))
            }
        } catch {
            status.message = "Der Import ließ sich nicht sichern."
            return nil
        }
        guard !pages.isEmpty else {
            status.message = "Die Datei hat keine Seiten."
            return nil
        }
        // A note holds at most 100 pages on the server; a longer file becomes several notes.
        let parts = stride(from: 0, to: pages.count, by: Limits.pages).map { Array(pages[$0..<min($0 + Limits.pages, pages.count)]) }
        var firstID: UUID?
        for (offset, part) in parts.enumerated() {
            var note = place(Note.newInk(page: part[0]))
            note.pages = part
            let suffix = parts.count > 1 ? " (\(offset + 1))" : ""
            note.title = name.clippedUTF16(Limits.title - suffix.utf16.count) + suffix
            note.updatedAt = InkhashTime.now()
            upsert(note, dirty: true, conflict: false)
            if firstID == nil { firstID = note.id }
        }
        var message = pages.count == 1 ? "Eine Seite importiert" : "\(pages.count) Seiten importiert"
        if parts.count > 1 { message += ", aufgeteilt auf \(parts.count) Notizen" }
        if skipped > 0 { message += skipped == 1 ? ". Ein Element fehlt, meist ein Textfeld" : ". \(skipped) Elemente fehlen, meist Textfelder" }
        status.message = message + "."
        changed()
        return firstID
    }

    // MARK: Notes

    /// Where notes made from inside `parent` go: a folder named after it, next to it.
    /// `test / doc` gives `test / doc`. See ADR 0037.
    func childFolder(of parent: Note) -> String {
        guard let name = Folders.segment(parent.displayTitle) else { return parent.folder }
        let folder = Folders.join(parent.folder, name)
        return Folders.isValid(folder) ? folder : parent.folder
    }

    func moveToTrash(_ id: UUID) {
        change(id) { note in
            note.deletedAt = InkhashTime.now()
            return true
        }
    }

    func restore(id: UUID) {
        change(id) { note in
            guard note.deletedAt != nil else { return false }
            note.deletedAt = nil
            return true
        }
    }

    /// Gone from this device for good: only from the trash and only once nothing waits for the
    /// server. `syncs` says whether the workspace is linked at all. True if it went.
    @discardableResult
    func purge(_ id: UUID, syncs: Bool) -> Bool {
        guard let record = record(id), Self.purgeable(record, syncs: syncs) else {
            status.message = "Erst nach dem Abgleich endgültig löschbar."
            return false
        }
        do {
            try store.remove(id: id)
            records.removeAll { $0.id == id }
            return true
        } catch {
            status.message = "Die Notiz ließ sich nicht entfernen."
            return false
        }
    }

    func emptyTrash(syncs: Bool) {
        for record in records where Self.purgeable(record, syncs: syncs) {
            try? store.remove(id: record.id)
        }
        reload()
    }

    /// Throws away a note that never reached the server; one that did goes to the trash.
    func discard(_ id: UUID) {
        guard let record = record(id) else { return }
        if record.note.revision == 0 {
            try? store.remove(id: id)
            records.removeAll { $0.id == id }
        } else {
            moveToTrash(id)
        }
    }

    func toggleFavorite(id: UUID) {
        change(id) { note in
            note.favorite.toggle()
            return true
        }
    }

    func move(id: UUID, to folder: String) {
        guard Folders.isValid(folder) else { return }
        change(id) { note in
            guard note.folder != folder else { return false }
            note.folder = folder
            return true
        }
    }

    /// Sets the folder path of a note from what someone typed: "project xy / meeting z".
    func setFolder(id: UUID, typed: String) {
        guard let folder = Folders.path(typed) else {
            status.message = "Der Pfad ist zu lang."
            return
        }
        move(id: id, to: folder)
        reveal(folder)
    }

    /// True once nothing waits for the server: the deletion is synced, never had to be, or the
    /// workspace does not sync at all.
    private static func purgeable(_ record: NoteRecord, syncs: Bool) -> Bool {
        record.note.deletedAt != nil && (!record.dirty || record.note.revision == 0 || !syncs)
    }

    // MARK: Folders

    func createFolder(named raw: String, in parent: String) {
        guard let name = Folders.segment(raw) else { return }
        let path = Folders.join(parent, name)
        guard Folders.isValid(path) else {
            status.message = "Der Ordnerpfad ist zu lang."
            return
        }
        if !keptFolders.contains(path) {
            keptFolders.append(path)
            saveKeptFolders()
        }
        reveal(path)
    }

    /// Renames a folder. Every note in it or below it gets the new path and syncs again.
    func renameFolder(_ path: String, to raw: String) {
        guard let name = Folders.segment(raw) else { return }
        let target = Folders.join(Folders.parent(of: path), name)
        guard target != path, Folders.isValid(target) else { return }
        let now = InkhashTime.now()
        for index in records.indices where Folders.contains(path, records[index].note.folder) {
            records[index].note.folder = Folders.moved(records[index].note.folder, from: path, to: target)
            persistChange(at: index, now: now)
        }
        keptFolders = keptFolders.map { Folders.moved($0, from: path, to: target) }
        saveKeptFolders()
        sidebar.collapsed = sidebar.collapsed.map { Folders.moved($0, from: path, to: target) }
        saveSidebar()
        changed()
    }

    /// Removes a folder. Its notes and subfolders move up one level; nothing is deleted.
    func removeFolder(_ path: String) {
        let parent = Folders.parent(of: path)
        let now = InkhashTime.now()
        for index in records.indices where records[index].note.folder != "" && Folders.contains(path, records[index].note.folder) {
            let rest = String(records[index].note.folder.dropFirst(path.count)).drop { $0 == "/" }
            records[index].note.folder = rest.isEmpty ? parent : Folders.join(parent, String(rest))
            persistChange(at: index, now: now)
        }
        keptFolders = keptFolders.compactMap { kept in
            guard Folders.contains(path, kept) else { return kept }
            let rest = String(kept.dropFirst(path.count)).drop { $0 == "/" }
            return rest.isEmpty ? nil : Folders.join(parent, String(rest))
        }
        saveKeptFolders()
        changed()
    }

    func setExpanded(_ key: String, _ expanded: Bool) {
        if expanded {
            guard sidebar.collapsed.contains(key) else { return }
            sidebar.collapsed.removeAll { $0 == key }
        } else {
            guard !sidebar.collapsed.contains(key) else { return }
            sidebar.collapsed.append(key)
        }
        saveSidebar()
    }

    /// Opens every folder above `path` in the folder tree so the note inside is visible.
    func reveal(_ path: String) {
        for ancestor in Folders.lineage(of: path) { setExpanded(ancestor, true) }
    }

    private func saveKeptFolders() {
        keptFolders = Folders.tree(kept: keptFolders, used: [])
        do {
            try store.setKeptFolders(keptFolders)
        } catch {
            status.message = "Die Ordner ließen sich nicht sichern."
        }
    }

    private func saveSidebar() {
        do {
            try store.setSidebar(sidebar)
        } catch {
            status.message = "Die Ansicht ließ sich nicht sichern."
        }
    }

    // MARK: Editing

    func updateMarkdown(id: UUID, markdown: String) {
        guard let index = index(of: id) else { return }
        var record = records[index]
        guard record.note.applyMarkdown(markdown) else { return }
        record.note.updatedAt = InkhashTime.now()
        record.dirty = true
        record.conflict = false
        records[index] = record
        try? store.save(note: record.note, meta: LocalMeta(dirty: true, conflict: false))
        try? store.clearConflict(id: id)
        changed()
    }

    /// Sets a title by hand for any note. An empty title goes back to the automatic one (ADR 0019).
    func rename(id: UUID, title: String) {
        change(id) { note in note.setTitle(title) }
    }

    /// Stores a page's drawing. True if the drawing or the page height changed.
    @discardableResult
    func updateDrawing(noteID: UUID, pageID: UUID, data: Data, height: Double? = nil) -> Bool {
        guard let index = index(of: noteID), var pages = records[index].note.pages,
              let pageIndex = pages.firstIndex(where: { $0.id == pageID }) else { return false }
        do {
            let sha = try store.putBlob(data)
            let grown = height.map { max($0, pages[pageIndex].height) } ?? pages[pageIndex].height
            guard pages[pageIndex].blob != sha || grown != pages[pageIndex].height else { return false }
            pages[pageIndex].blob = sha
            pages[pageIndex].height = grown
            var record = records[index]
            record.note.pages = pages
            record.note.updatedAt = InkhashTime.now()
            record.dirty = true
            records[index] = record
            try store.save(note: record.note, meta: LocalMeta(dirty: true, conflict: record.conflict))
            changed()
            return true
        } catch {
            status.message = "Die Zeichnung ließ sich nicht sichern."
            return false
        }
    }

    func applyReading(noteID: UUID, pageID: UUID, transcript: String, tags: [String], pageHasInk: Bool) {
        change(noteID) { note in note.applyInkReading(pageID: pageID, transcript: transcript, tags: tags, pageHasInk: pageHasInk) }
    }

    func addPage(noteID: UUID, data: Data) {
        guard let index = index(of: noteID) else { return }
        guard (records[index].note.pages ?? []).count < Limits.pages else {
            status.message = "Eine Notiz hat höchstens \(Limits.pages) Seiten."
            return
        }
        do {
            let sha = try store.putBlob(data)
            var record = records[index]
            var pages = record.note.pages ?? []
            pages.append(InkPage(blob: sha))
            record.note.pages = pages
            record.note.updatedAt = InkhashTime.now()
            record.dirty = true
            records[index] = record
            try store.save(note: record.note, meta: LocalMeta(dirty: true, conflict: record.conflict))
            changed()
        } catch {
            status.message = "Die neue Seite ließ sich nicht anlegen."
        }
    }

    /// Colour and pattern of a note. See ADR 0042.
    func setPaper(noteID: UUID, paper: Paper) {
        change(noteID) { $0.setPaper(paper) }
    }

    func reorderPages(noteID: UUID, order: [UUID]) {
        change(noteID) { $0.reorderPages(order) }
    }

    func movePage(noteID: UUID, pageID: UUID, by offset: Int) {
        change(noteID) { $0.movePage(pageID, by: offset) }
    }

    /// Removes a page; the last page of a note stays. Its blob stays in the store like every blob.
    func deletePage(noteID: UUID, pageID: UUID) {
        change(noteID) { $0.removePage(pageID) }
    }

    /// Replaces the elements of a page. See ADR 0028.
    func updateElements(noteID: UUID, pageID: UUID, elements: [PageElement]) {
        guard let index = index(of: noteID), var pages = records[index].note.pages,
              let pageIndex = pages.firstIndex(where: { $0.id == pageID }),
              pages[pageIndex].elements != elements else { return }
        pages[pageIndex].elements = elements
        var record = records[index]
        record.note.pages = pages
        record.note.updatedAt = InkhashTime.now()
        record.dirty = true
        records[index] = record
        do {
            try store.save(note: record.note, meta: LocalMeta(dirty: true, conflict: record.conflict))
            changed()
        } catch {
            status.message = "Die Seite ließ sich nicht sichern."
        }
    }

    // MARK: Conflicts

    /// Keeps this device's version on top of the server's revision. True if there was a conflict.
    @discardableResult
    func keepMine(id: UUID) -> Bool {
        guard let index = index(of: id), let server = try? store.conflictNote(id: id) else { return false }
        let resolved = keepingMine(local: records[index].note, server: server)
        records[index] = NoteRecord(note: resolved.0, meta: resolved.1)
        try? store.save(note: resolved.0, meta: resolved.1)
        try? store.clearConflict(id: id)
        changed()
        return true
    }

    /// Takes the server's version. True if there was a conflict.
    @discardableResult
    func takeServer(id: UUID) -> Bool {
        guard let server = try? store.conflictNote(id: id), let index = index(of: id) else { return false }
        let resolved = takingServer(server)
        records[index] = NoteRecord(note: resolved.0, meta: resolved.1)
        try? store.save(note: resolved.0, meta: resolved.1)
        try? store.clearConflict(id: id)
        return true
    }

    // MARK: Private

    /// Applies a change to one note, stamps it and marks it for the next sync.
    private func change(_ id: UUID, _ edit: (inout Note) -> Bool) {
        guard let index = index(of: id) else { return }
        var note = records[index].note
        guard edit(&note) else { return }
        records[index].note = note
        persistChange(at: index, now: InkhashTime.now())
        changed()
    }

    private func persistChange(at index: Int, now: String) {
        records[index].note.updatedAt = now
        records[index].dirty = true
        let record = records[index]
        do {
            try store.save(note: record.note, meta: LocalMeta(dirty: true, conflict: record.conflict))
        } catch {
            status.message = "Die Änderung ließ sich nicht sichern."
        }
    }

    private func upsert(_ note: Note, dirty: Bool, conflict: Bool) {
        set(NoteRecord(note: note, dirty: dirty, conflict: conflict))
        try? store.save(note: note, meta: LocalMeta(dirty: dirty, conflict: conflict))
    }

    private func set(_ record: NoteRecord) {
        if let index = index(of: record.id) {
            records[index] = record
        } else {
            records.append(record)
        }
    }

    private func index(of id: UUID) -> Int? {
        records.firstIndex { $0.id == id }
    }
}
