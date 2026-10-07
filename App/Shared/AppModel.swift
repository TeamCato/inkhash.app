import Foundation
import InkhashCore
import Observation
import PencilKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum EditorAction: Equatable {
    case toggleBold
    case toggleItalic
    case toggleCode
    /// Puts a link on the selection, or takes it off with nil. See ADR 0024.
    case setLink(String?)
}

struct EditorImpulse: Equatable {
    var token: Int
    var action: EditorAction
}

extension LibrarySection {
    var title: String {
        switch self {
        case .notes: "Notizen"
        case .favorites: "Favoriten"
        case .trash: "Papierkorb"
        }
    }
}

/// What the app knows about the address typed into the server form.
enum ServerConnection: Equatable {
    case unknown
    case checking
    case reachable(RegistrationMode)
    case failed(String)
}

/// Where a new or existing workspace syncs to.
enum WorkspaceTarget: Hashable {
    case local
    /// `remote` nil creates a new workspace on that server.
    case server(UUID, remote: String?)
}

@MainActor
@Observable
final class AppModel {
    private let base: URL
    private(set) var setup: DeviceSetup
    private var stores: [UUID: LocalStore] = [:]
    /// Workspace pictures by file name. A changed picture has a new name, so nothing goes stale.
    @ObservationIgnored private var iconCache: [String: PlatformImage] = [:]
    /// Session tokens by server. A server without one is signed out.
    private var tokens: [UUID: String] = [:]
    private(set) var records: [NoteRecord] = []
    var selectedID: UUID?
    var section: LibrarySection = .notes {
        didSet { if oldValue != section { selectedID = nil } }
    }
    var query = ""
    /// Folders kept in the current workspace without notes in them.
    private(set) var keptFolders: [String] = []
    /// How the sidebar of the current workspace is arranged. See ADR 0022.
    private(set) var sidebar = SidebarPrefs()

    var connection: ServerConnection = .unknown
    private var probeTask: Task<Void, Never>?
    /// Servers whose session the server rejected. Shows a notice until signing in or dismissing it.
    private(set) var expiredServers: Set<UUID>
    var status = ""
    var editorEpoch = 0
    var searchFocusToken = 0
    var inlineImpulse: EditorImpulse?
    /// Bumped by Cmd+K: the open note shows its link field for the selection.
    var linkPromptToken = 0
    private var impulseToken = 0
    private var syncTask: Task<Void, Never>?
    private var isSyncing = false
    private var syncAgain = false

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inkhash", isDirectory: true)
        self.base = base
        let defaults = UserDefaults.standard
        let legacy = LegacySignIn(
            url: defaults.string(forKey: "inkhash.baseURL") ?? "",
            accountName: defaults.string(forKey: "inkhash.accountName") ?? "",
            accountID: ServerAddress.accountID(defaults.string(forKey: "inkhash.accountID") ?? "") ?? ""
        )
        do {
            let opened = try Workspaces.open(base: base, legacy: legacy)
            setup = opened.setup
            if let migrated = opened.migrated {
                if !migrated.accountID.isEmpty, let token = SecretStore.get(account: SecretStore.legacyAccount) {
                    try? SecretStore.set(token, account: SecretStore.key(for: migrated.id))
                }
                SecretStore.clear(account: SecretStore.legacyAccount)
                for key in ["inkhash.baseURL", "inkhash.accountName", "inkhash.accountID"] {
                    defaults.removeObject(forKey: key)
                }
            }
        } catch {
            fatalError("Lokaler Speicher ließ sich nicht anlegen: \(error)")
        }
        let expiredIDs = (defaults.stringArray(forKey: Self.expiredKey) ?? []).compactMap(UUID.init(uuidString:))
        expiredServers = Set(expiredIDs)
        for server in setup.servers where !server.accountID.isEmpty {
            if let token = SecretStore.get(account: SecretStore.key(for: server.id)), !token.isEmpty {
                tokens[server.id] = token
            }
        }
        if !setup.workspaces.contains(where: { $0.id == setup.current }), let first = setup.workspaces.first {
            setup.current = first.id
        }
        reload()
        status = statusAtRest
        ExcerptSource.current = ExcerptSource(
            note: { [weak self] id in self?.record(id)?.note },
            loadBlob: { [weak self] blob in self?.drawingData(for: blob) }
        )
    }

    static let localOnly = "Nur auf diesem Gerät."
    private static let expiredKey = "inkhash.expiredServers"

    // MARK: Workspace

    var workspace: Workspace {
        setup.workspaces.first { $0.id == setup.current } ?? setup.workspaces[0]
    }

    var workspaces: [Workspace] { setup.workspaces }
    var servers: [ServerEntry] { setup.servers }

    private var store: LocalStore { store(for: setup.current) }

    private func store(for id: UUID) -> LocalStore {
        if let cached = stores[id] { return cached }
        do {
            let opened = try Workspaces.store(of: id, base: base)
            stores[id] = opened
            return opened
        } catch {
            fatalError("Workspace ließ sich nicht öffnen: \(error)")
        }
    }

    func switchWorkspace(_ id: UUID) {
        guard id != setup.current, setup.workspaces.contains(where: { $0.id == id }) else { return }
        setup.current = id
        persistSetup()
        section = .notes
        query = ""
        selectedID = nil
        reload()
        status = statusAtRest
        scheduleSync()
    }

    func server(of workspace: Workspace) -> ServerEntry? {
        setup.server(workspace.link?.server)
    }

    /// True if the workspace syncs right now: linked to a server with a session.
    func syncs(_ workspace: Workspace) -> Bool {
        guard let link = workspace.link else { return false }
        return isSignedIn(link.server)
    }

    var isSyncEnabled: Bool { syncs(workspace) }

    private var statusAtRest: String {
        guard let link = workspace.link, let server = setup.server(link.server) else { return Self.localOnly }
        return isSignedIn(server.id) ? "" : "Abgleich mit \(ServerAddress.host(server.url)) ruht."
    }

    func createWorkspace(name: String, symbol: String, image: Data?, target: WorkspaceTarget) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Der Workspace braucht einen Namen."
            return
        }
        var workspace = Workspace(name: trimmed.clippedUTF16(Limits.workspaceName), symbol: symbol)
        do {
            workspace.link = try await link(for: target, name: workspace.name)
        } catch {
            status = describe(error)
            return
        }
        setup.workspaces.append(workspace)
        persistSetup()
        if let image { setWorkspaceImage(workspace.id, png: image) }
        switchWorkspace(workspace.id)
        await sync()
    }

    func updateWorkspace(_ id: UUID, name: String, symbol: String) {
        guard let index = setup.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let before = setup.workspaces[index]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { setup.workspaces[index].name = trimmed.clippedUTF16(Limits.workspaceName) }
        setup.workspaces[index].symbol = symbol
        lookChanged(index, from: before)
    }

    /// A linked workspace sends its new look with the next sync. See ADR 0043.
    private func lookChanged(_ index: Int, from before: Workspace) {
        guard setup.workspaces[index] != before else { return }
        if setup.workspaces[index].link != nil { setup.workspaces[index].lookPending = true }
        persistSetup()
        scheduleSync()
    }

    /// Sets or clears the workspace's own picture. `png` comes from `WorkspaceImage.normalize`.
    func setWorkspaceImage(_ id: UUID, png: Data?) {
        guard let index = setup.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let before = setup.workspaces[index]
        if let png {
            do {
                setup.workspaces[index].icon = try Workspaces.saveIcon(png, base: base)
            } catch {
                status = "Das Bild ließ sich nicht sichern."
                return
            }
        } else {
            setup.workspaces[index].icon = nil
        }
        lookChanged(index, from: before)
        pruneIcons()
    }

    /// The workspace's own picture, or nil when it shows its symbol.
    func workspaceImage(_ workspace: Workspace) -> PlatformImage? {
        guard let name = workspace.icon else { return nil }
        if let cached = iconCache[name] { return cached }
        guard let image = PlatformImage(contentsOfFile: Workspaces.iconURL(name, base: base).path) else { return nil }
        iconCache[name] = image
        return image
    }

    /// Pictures are named by content, so a file no workspace names anymore can go.
    private func pruneIcons() {
        do {
            try Workspaces.pruneIcons(keeping: setup, base: base)
        } catch {
            // A leftover file costs a few kilobytes and is retried on the next change.
        }
        let used = Set(setup.workspaces.compactMap(\.icon))
        iconCache = iconCache.filter { used.contains($0.key) }
    }

    func moveWorkspaces(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        setup.moveWorkspaces(fromOffsets: offsets, toOffset: destination)
        orderChanged()
    }

    func moveWorkspace(_ id: UUID, by step: Int) {
        setup.moveWorkspace(id, by: step)
        orderChanged()
    }

    private func orderChanged() {
        setup.markOrderChanged()
        persistSetup()
        scheduleSync()
    }

    /// Points a workspace at another server workspace, or at none. Changing the target uploads
    /// all its notes there, like signing in to another account (ADR 0017).
    func relink(_ id: UUID, to target: WorkspaceTarget) async {
        guard let index = setup.workspaces.firstIndex(where: { $0.id == id }) else { return }
        do {
            let link = try await link(for: target, name: setup.workspaces[index].name)
            guard link != setup.workspaces[index].link else { return }
            setup.workspaces[index].link = link
            // A workspace that already has a look on the server keeps it; a new one gets ours.
            setup.workspaces[index].lookPending = false
            persistSetup()
            status = link == nil ? "Der Workspace bleibt jetzt auf diesem Gerät." : ""
            if id == setup.current { status = statusAtRest }
            await sync()
        } catch {
            status = describe(error)
        }
    }

    /// Removes the workspace and its notes from this device. A server copy stays where it is.
    func removeWorkspace(_ id: UUID) {
        guard setup.workspaces.count > 1, let index = setup.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let removed = setup.workspaces.remove(at: index)
        stores[id] = nil
        if setup.current == id { setup.current = setup.workspaces[0].id }
        persistSetup()
        do {
            try Workspaces.removeFiles(of: id, base: base)
        } catch {
            status = "Die Dateien des Workspace ließen sich nicht entfernen."
        }
        if removed.icon != nil { pruneIcons() }
        reload()
    }

    /// Workspaces on a server, to choose one to sync with.
    func remoteWorkspaces(on server: UUID) async -> [RemoteWorkspace] {
        guard let client = client(for: server) else { return [] }
        do {
            return try await client.workspaces()
        } catch APIError.unauthorized {
            expireSession(of: server, ifStill: client.token)
            return []
        } catch {
            status = describe(error)
            return []
        }
    }

    private func link(for target: WorkspaceTarget, name: String) async throws -> WorkspaceLink? {
        switch target {
        case .local:
            return nil
        case .server(let serverID, let remote):
            guard let client = client(for: serverID) else { throw APIError.unauthorized }
            if let remote { return WorkspaceLink(server: serverID, remote: remote) }
            let created = try await client.createWorkspace(name: name)
            return WorkspaceLink(server: serverID, remote: created.id)
        }
    }

    private func persistSetup() {
        do {
            try Workspaces.save(setup, base: base)
        } catch {
            status = "Die Einstellungen ließen sich nicht sichern."
        }
    }

    // MARK: Lists

    /// What the sidebar and link menus read from the current workspace.
    var listing: NoteListing { NoteListing(records: records, keptFolders: keptFolders) }

    var listed: [ListedNote] { listing.listed(section, query: query) }

    var tagFilter: String? { NoteListing.tagFilter(query) }

    var suggestedTags: [TagCount] { listing.suggestedTags(query: query) }

    var folderTree: NoteTree { listing.folderTree(query: query) }

    func isExpanded(_ key: String) -> Bool {
        !sidebar.collapsed.contains(key)
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

    var tagCounts: [TagCount] { listing.tagCounts }

    private func saveSidebar() {
        do {
            try store.setSidebar(sidebar)
        } catch {
            status = "Die Ansicht ließ sich nicht sichern."
        }
    }

    var folders: [String] { listing.folders }

    var trashCount: Int { listing.trashCount }

    func record(_ id: UUID) -> NoteRecord? {
        records.first { $0.id == id }
    }

    func focusSearch() {
        searchFocusToken += 1
    }

    func sendInline(_ action: EditorAction) {
        impulseToken += 1
        inlineImpulse = EditorImpulse(token: impulseToken, action: action)
    }

    func promptLink() {
        linkPromptToken += 1
    }

    // MARK: Links

    func linkableNotes(matching query: String, excluding id: UUID? = nil, limit: Int = 8) -> [NoteRecord] {
        listing.linkable(matching: query, excluding: id, limit: limit)
    }

    /// Follows a link from text or a page: a note link or excerpt opens the note, anything else the system.
    /// See ADR 0027 and 0032.
    func openLink(_ target: String) {
        if let id = NoteLink.noteID(in: target) ?? ExcerptTarget(target: target)?.noteID {
            guard let record = record(id), record.note.deletedAt == nil else {
                status = "Die verlinkte Notiz gibt es in diesem Workspace nicht."
                return
            }
            if section != .notes { section = .notes }
            query = ""
            selectedID = record.id
            return
        }
        guard let url = Links.url(target) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    // MARK: Notes

    /// A new note lands next to the selected one, or in `folder` when asked for one there.
    /// In the favorites it starts as a favorite.
    private func placed(_ note: Note, in folder: String?) -> Note {
        var note = note
        if let folder {
            note.folder = folder
        } else if section == .notes, let selected = selectedID, let current = record(selected) {
            note.folder = current.note.folder
        }
        if section == .favorites { note.favorite = true }
        if section == .trash { section = .notes }
        return note
    }

    func createText(in folder: String? = nil) {
        var note = placed(Note.newText(), in: folder)
        note.updatedAt = InkhashTime.now()
        upsert(note, dirty: true, conflict: false)
        if let folder { reveal(folder) }
        selectedID = note.id
        scheduleSync()
    }

    /// A new note made from inside another one, for an excerpt: it stays closed, the open note keeps the
    /// screen. Same folder as the note it was made from, with a fixed title. See ADR 0032 and 0035.
    func createQuietly(_ note: Note, folder: String, title: String) -> Note {
        var note = note
        note.folder = Folders.isValid(folder) ? folder : ""
        note.title = String(title.prefix(80))
        note.updatedAt = InkhashTime.now()
        upsert(note, dirty: true, conflict: false)
        scheduleSync()
        return note
    }

    /// Where notes made from inside `parent` go: a folder named after it, next to it.
    /// `test / doc` gives `test / doc`. See ADR 0037.
    func childFolder(of parent: Note) -> String {
        guard let name = Folders.segment(parent.displayTitle) else { return parent.folder }
        let folder = Folders.join(parent.folder, name)
        return Folders.isValid(folder) ? folder : parent.folder
    }

    /// Throws away a note made in the excerpt picker. Never synced, so it leaves no trace.
    func discard(id: UUID) {
        guard let record = record(id) else { return }
        if record.note.revision == 0 {
            try? store.remove(id: id)
            records.removeAll { $0.id == id }
        } else {
            delete(id: id)
        }
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

    /// Stores a drawing for a new ink note. Nil if the blob store fails.
    func newInkNote(drawing data: Data) -> Note? {
        guard let sha = try? store.putBlob(data) else {
            status = "Die Zeichnung ließ sich nicht sichern."
            return nil
        }
        return Note.newInk(page: InkPage(blob: sha))
    }

    func notes(of kind: NoteKind) -> [Note] { listing.notes(of: kind) }

    func createInk(data: Data, in folder: String? = nil) {
        do {
            let sha = try store.putBlob(data)
            var note = placed(Note.newInk(page: InkPage(blob: sha)), in: folder)
            note.updatedAt = InkhashTime.now()
            upsert(note, dirty: true, conflict: false)
            if let folder { reveal(folder) }
            selectedID = note.id
            scheduleSync()
        } catch {
            status = "Die leere Seite ließ sich nicht anlegen."
        }
    }

    /// Set by the menu; the sidebar shows the file picker and clears it. See ADR 0024 and 0041.
    var importRequested = false

    /// A PDF export or a GoodNotes notebook becomes ink notes, one page per page. Which one it is
    /// comes from the bytes, not the file name. See ADR 0024 and 0041.
    func importFile(at url: URL, in folder: String? = nil) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.deletingPathExtension().lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            if data.starts(with: [0x50, 0x4B]) {
                let notebook = try InkImport.notebook(fromGoodNotes: data)
                addImported(notebook.pages, name: name, in: folder, skipped: notebook.skipped)
            } else {
                addImported(try InkImport.pages(fromPDF: data), name: name, in: folder, skipped: 0)
            }
        } catch PDFInkError.notAPDF, GoodNotesError.notGoodNotes {
            status = "Die Datei ist weder ein PDF noch ein GoodNotes-Notizbuch."
        } catch PDFInkError.noPages, GoodNotesError.noPages {
            status = "Die Datei hat keine Seiten."
        } catch {
            status = "Der Import ist fehlgeschlagen."
        }
    }

    /// The title is the file name and counts as set. Recognition runs when the note is opened.
    private func addImported(_ imported: [InkImport.ImportedPage], name: String, in folder: String?, skipped: Int) {
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
            status = "Der Import ließ sich nicht sichern."
            return
        }
        guard !pages.isEmpty else {
            status = "Die Datei hat keine Seiten."
            return
        }
        // A note holds at most 100 pages on the server; a longer file becomes several notes.
        let parts = stride(from: 0, to: pages.count, by: Limits.pages).map { Array(pages[$0..<min($0 + Limits.pages, pages.count)]) }
        var firstID: UUID?
        for (offset, part) in parts.enumerated() {
            var note = placed(Note.newInk(page: part[0]), in: folder)
            note.pages = part
            let suffix = parts.count > 1 ? " (\(offset + 1))" : ""
            note.title = name.clippedUTF16(Limits.title - suffix.utf16.count) + suffix
            note.updatedAt = InkhashTime.now()
            upsert(note, dirty: true, conflict: false)
            if firstID == nil { firstID = note.id }
        }
        if let folder { reveal(folder) }
        selectedID = firstID
        var message = pages.count == 1 ? "Eine Seite importiert" : "\(pages.count) Seiten importiert"
        if parts.count > 1 { message += ", aufgeteilt auf \(parts.count) Notizen" }
        if skipped > 0 { message += skipped == 1 ? ". Ein Element fehlt, meist ein Textfeld" : ". \(skipped) Elemente fehlen, meist Textfelder" }
        status = message + "."
        scheduleSync()
    }

    /// Opens every folder above `path` in the folder tree so the note inside is visible.
    private func reveal(_ path: String) {
        for ancestor in Folders.lineage(of: path) { setExpanded(ancestor, true) }
    }

    /// Sets the folder path of a note from what someone typed: "project xy / meeting z".
    func setFolder(id: UUID, typed: String) {
        guard let folder = Folders.path(typed) else {
            status = "Der Pfad ist zu lang."
            return
        }
        move(id: id, to: folder)
        reveal(folder)
    }

    /// Moves a note to the trash. It stays restorable there; see ADR 0020.
    func delete(id: UUID) {
        change(id) { note in
            note.deletedAt = InkhashTime.now()
            return true
        }
        if selectedID == id { selectedID = nil }
    }

    func restore(id: UUID) {
        change(id) { note in
            guard note.deletedAt != nil else { return false }
            note.deletedAt = nil
            return true
        }
    }

    /// True once nothing waits for the server: the deletion is synced, never had to be, or the
    /// workspace no longer syncs at all and never will on its own.
    private func purgeable(_ record: NoteRecord) -> Bool {
        record.note.deletedAt != nil && (!record.dirty || record.note.revision == 0 || workspace.link == nil)
    }

    /// Gone from this device for good. Only from the trash and only once the server knows it is deleted.
    func purge(id: UUID) {
        guard let record = record(id), purgeable(record) else {
            status = "Erst nach dem Abgleich endgültig löschbar."
            return
        }
        do {
            try store.remove(id: id)
            records.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
        } catch {
            status = "Die Notiz ließ sich nicht entfernen."
        }
    }

    func emptyTrash() {
        for record in records where purgeable(record) {
            try? store.remove(id: record.id)
        }
        reload()
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

    // MARK: Folders

    func createFolder(named raw: String, in parent: String) {
        guard let name = Folders.segment(raw) else { return }
        let path = Folders.join(parent, name)
        guard Folders.isValid(path) else {
            status = "Der Ordnerpfad ist zu lang."
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
        relocate(from: path, to: target)
        sidebar.collapsed = sidebar.collapsed.map { Folders.moved($0, from: path, to: target) }
        saveSidebar()
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
        scheduleSync()
    }

    private func relocate(from path: String, to target: String) {
        let now = InkhashTime.now()
        for index in records.indices where Folders.contains(path, records[index].note.folder) {
            records[index].note.folder = Folders.moved(records[index].note.folder, from: path, to: target)
            persistChange(at: index, now: now)
        }
        keptFolders = keptFolders.map { Folders.moved($0, from: path, to: target) }
        saveKeptFolders()
        scheduleSync()
    }

    private func saveKeptFolders() {
        keptFolders = Folders.tree(kept: keptFolders, used: [])
        do {
            try store.setKeptFolders(keptFolders)
        } catch {
            status = "Die Ordner ließen sich nicht sichern."
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
        scheduleSync()
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
            scheduleSync()
            return true
        } catch {
            status = "Die Zeichnung ließ sich nicht sichern."
            return false
        }
    }

    func applyReading(noteID: UUID, pageID: UUID, transcript: String, tags: [String], pageHasInk: Bool) {
        change(noteID) { note in note.applyInkReading(pageID: pageID, transcript: transcript, tags: tags, pageHasInk: pageHasInk) }
    }

    func addPage(noteID: UUID, data: Data) {
        guard let index = index(of: noteID) else { return }
        guard (records[index].note.pages ?? []).count < Limits.pages else {
            status = "Eine Notiz hat höchstens \(Limits.pages) Seiten."
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
            scheduleSync()
        } catch {
            status = "Die neue Seite ließ sich nicht anlegen."
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

    func drawingData(for blob: String) -> Data? {
        try? store.blob(blob)
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
            scheduleSync()
        } catch {
            status = "Die Seite ließ sich nicht sichern."
        }
    }

    /// Keeps a photo as a JPEG blob. Returns its hash and pixel size, or nil if it is no image.
    func storeImage(_ data: Data) -> (blob: String, size: CGSize)? {
        guard let converted = ImageImport.jpeg(from: data) else {
            status = "Das Bild ließ sich nicht lesen."
            return nil
        }
        do {
            return (try store.putBlob(converted.data), converted.size)
        } catch {
            status = "Das Bild ließ sich nicht sichern."
            return nil
        }
    }

    func keepMine(id: UUID) {
        guard let index = index(of: id), let server = try? store.conflictNote(id: id) else { return }
        let resolved = keepingMine(local: records[index].note, server: server)
        var record = records[index]
        record.note = resolved.0
        record.dirty = true
        record.conflict = false
        records[index] = record
        try? store.save(note: record.note, meta: resolved.1)
        try? store.clearConflict(id: id)
        editorEpoch += 1
        scheduleSync()
    }

    func takeServer(id: UUID) {
        guard let server = try? store.conflictNote(id: id), let index = index(of: id) else { return }
        let resolved = takingServer(server)
        var record = records[index]
        record.note = resolved.0
        record.dirty = false
        record.conflict = false
        records[index] = record
        try? store.save(note: record.note, meta: .clean)
        try? store.clearConflict(id: id)
        editorEpoch += 1
    }

    /// Applies a change to one note, stamps it and marks it for the next sync.
    private func change(_ id: UUID, _ edit: (inout Note) -> Bool) {
        guard let index = index(of: id) else { return }
        var note = records[index].note
        guard edit(&note) else { return }
        records[index].note = note
        persistChange(at: index, now: InkhashTime.now())
        scheduleSync()
    }

    private func persistChange(at index: Int, now: String) {
        records[index].note.updatedAt = now
        records[index].dirty = true
        let record = records[index]
        do {
            try store.save(note: record.note, meta: LocalMeta(dirty: true, conflict: record.conflict))
        } catch {
            status = "Die Änderung ließ sich nicht sichern."
        }
    }

    // MARK: Servers

    func isSignedIn(_ server: UUID) -> Bool {
        guard let entry = setup.server(server), !entry.accountID.isEmpty else { return false }
        return !(tokens[server] ?? "").isEmpty
    }

    /// Signs in to the server at `url`. A known address reuses its entry, so workspaces linked
    /// to it continue. Accounts are created on the server's admin page, not here (ADR 0021).
    /// Returns the server's id, or nil when it failed; `status` says why.
    func signIn(url raw: String, name: String, password: String) async -> UUID? {
        guard let url = ServerAddress.valid(raw) else {
            status = "Die Adresse braucht http oder https und einen Host."
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard password.count >= 8 else {
            status = "Das Passwort braucht mindestens 8 Zeichen."
            return nil
        }
        let client = APIClient(baseURL: url, token: "")
        do {
            let session = try await client.openSession(name: trimmed, password: password)
            let server = try accept(session, url: url.absoluteString)
            status = "Angemeldet."
            await sync()
            return server
        } catch {
            status = describe(error)
            return nil
        }
    }

    /// Takes server workspaces onto this device, linked and synced right away. See ADR 0044.
    func addFromServer(_ remotes: [RemoteWorkspace], on server: UUID) async {
        let added = setup.addLinked(remotes, on: server) { [self] id in
            let library = store(for: id)
            return ((try? library.list().isEmpty) ?? false) && library.keptFolders().isEmpty
        }
        guard !added.isEmpty else { return }
        persistSetup()
        status = added.count == 1 ? "Workspace hinzugefügt." : "\(added.count) Workspaces hinzugefügt."
        await sync()
    }

    /// Ends the session. Linked workspaces keep their notes and their binding; syncing pauses.
    func logout(_ server: UUID) {
        if let client = client(for: server) {
            Task { try? await client.logout() }
        }
        endSession(of: server)
        status = "Abgemeldet. Die Notizen bleiben auf diesem Gerät."
    }

    /// Forgets a server. Workspaces linked to it stay on this device and stop syncing.
    func removeServer(_ server: UUID) {
        logout(server)
        setup.servers.removeAll { $0.id == server }
        for index in setup.workspaces.indices where setup.workspaces[index].link?.server == server {
            setup.workspaces[index].link = nil
        }
        persistSetup()
        status = statusAtRest
    }

    func workspaces(on server: UUID) -> [Workspace] {
        setup.workspaces.filter { $0.link?.server == server }
    }

    var expiredNotice: ServerEntry? {
        guard let link = workspace.link, expiredServers.contains(link.server) else { return nil }
        return setup.server(link.server)
    }

    func dismissExpiredNotice(_ server: UUID) {
        expiredServers.remove(server)
        persistExpired()
    }

    /// The server no longer knows the session, e.g. after 90 days without use (ADR 0016).
    /// Same as logging out, minus telling the server. Bindings stay, so signing in to the
    /// same account again continues where syncing stopped.
    private func expireSession(of server: UUID, ifStill used: String) {
        // A request that started before a new login must not end the new session.
        guard !used.isEmpty, tokens[server] == used else { return }
        endSession(of: server)
        expiredServers.insert(server)
        persistExpired()
        status = "Anmeldung abgelaufen. Die Notizen bleiben auf diesem Gerät."
    }

    private func endSession(of server: UUID) {
        SecretStore.clear(account: SecretStore.key(for: server))
        tokens[server] = nil
        if let index = setup.servers.firstIndex(where: { $0.id == server }) {
            setup.servers[index].accountID = ""
            persistSetup()
        }
    }

    private func persistExpired() {
        UserDefaults.standard.set(expiredServers.map(\.uuidString), forKey: Self.expiredKey)
    }

    /// Checks the address as it is typed, after a short pause.
    func addressChanged(_ text: String) {
        probeTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ServerAddress.valid(trimmed) else {
            connection = trimmed.isEmpty ? .unknown : .failed("Die Adresse braucht http oder https und einen Host.")
            return
        }
        connection = .checking
        probeTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                let health = try await APIClient(baseURL: url, token: "").health()
                guard !Task.isCancelled else { return }
                connection = .reachable(health.registration)
            } catch {
                guard !Task.isCancelled else { return }
                connection = .failed(describe(error))
            }
        }
    }

    private func client(for server: UUID, workspace remote: String = APIClient.mainWorkspace) -> APIClient? {
        guard isSignedIn(server), let entry = setup.server(server), let url = URL(string: entry.url), let token = tokens[server] else {
            return nil
        }
        return APIClient(baseURL: url, token: token, workspace: remote)
    }

    @discardableResult
    private func accept(_ session: ServerSession, url: String) throws -> UUID {
        guard let id = ServerAddress.accountID(session.account.id) else { throw APIError.invalidResponse }
        let serverID: UUID
        if let index = setup.servers.firstIndex(where: { $0.url == url }) {
            serverID = setup.servers[index].id
            setup.servers[index].accountName = session.account.name
            setup.servers[index].accountID = id
        } else {
            let entry = ServerEntry(url: url, accountName: session.account.name, accountID: id)
            serverID = entry.id
            setup.servers.append(entry)
        }
        try SecretStore.set(session.token, account: SecretStore.key(for: serverID))
        tokens[serverID] = session.token
        dismissExpiredNotice(serverID)
        persistSetup()
        return serverID
    }

    // MARK: Sync

    /// Waits for a pause in editing, then syncs. A new edit only restarts the wait: cancelling
    /// a running sync would drop a request the server may already have stored. See PITFALLS P-053.
    func scheduleSync() {
        guard isSyncEnabled else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            Task { await self.sync() }
        }
    }

    /// Syncs every workspace that is linked to a signed-in server. The current one reports its status.
    /// A call during a running sync makes it go round once more instead of being dropped.
    func sync() async {
        guard !isSyncing else {
            syncAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncAgain = false
            await syncOnce()
        } while syncAgain
    }

    private func syncOnce() async {
        await syncLooks()
        for workspace in setup.workspaces {
            guard let link = workspace.link, let entry = setup.server(link.server),
                  let client = client(for: link.server, workspace: link.remote) else { continue }
            let isCurrent = workspace.id == setup.current
            let workspaceStore = store(for: workspace.id)
            do {
                // Binding is idempotent. A different account or workspace on the server starts over.
                try Library.bind(workspaceStore, to: Workspaces.bindingKey(accountID: entry.accountID, remote: link.remote))
                let report = try await Syncer.sync(store: workspaceStore, transport: client) { [weak self] note, meta in
                    self?.syncSaved(note, meta: meta, in: workspace.id)
                }
                if isCurrent {
                    status = syncStatus(report)
                }
            } catch APIError.unauthorized {
                expireSession(of: link.server, ifStill: client.token)
            } catch {
                if isCurrent { status = describe(error) }
            }
        }
        reload()
        if !isSyncEnabled { status = statusAtRest }
    }

    // MARK: Store

    private func reload() {
        let selected = selectedID
        records = ((try? store.list()) ?? []).map { item in
            NoteRecord(note: item.note, dirty: item.meta.dirty, conflict: item.meta.conflict)
        }
        keptFolders = store.keptFolders()
        sidebar = store.sidebar()
        if let selected, record(selected) == nil {
            selectedID = nil
        }
    }

    private func upsert(_ note: Note, dirty: Bool, conflict: Bool) {
        let record = NoteRecord(note: note, dirty: dirty, conflict: conflict)
        if let index = index(of: note.id) {
            records[index] = record
        } else {
            records.append(record)
        }
        try? store.save(note: note, meta: LocalMeta(dirty: dirty, conflict: conflict))
    }

    private func index(of id: UUID) -> Int? {
        records.firstIndex { $0.id == id }
    }

    /// Edits start from `records`, so they must see every revision the sync writes at once.
    /// Waiting for `reload` would let the next edit write the old revision back. See PITFALLS P-053.
    private func syncSaved(_ note: Note, meta: LocalMeta, in workspace: UUID) {
        guard workspace == setup.current else { return }
        let record = NoteRecord(note: note, dirty: meta.dirty, conflict: meta.conflict)
        if let index = index(of: note.id) {
            records[index] = record
        } else {
            records.append(record)
        }
    }

    /// Look and order of workspaces, per server, before the notes. See ADR 0043.
    private func syncLooks() async {
        let servers = Set(setup.workspaces.compactMap { $0.link?.server })
        for server in setup.servers.map(\.id) where servers.contains(server) {
            guard let client = client(for: server) else { continue }
            let snapshot = setup
            do {
                let synced = try await LookSyncer.sync(snapshot, server: server, base: base, transport: client)
                guard synced != snapshot else { continue }
                setup.adopt(synced, since: snapshot)
                persistSetup()
                pruneIcons()
            } catch APIError.unauthorized {
                expireSession(of: server, ifStill: client.token)
            } catch {
                // Pending looks and orders stay marked and go out with the next sync.
                if workspace.link?.server == server { status = describe(error) }
            }
        }
    }

    private func syncStatus(_ report: SyncReport) -> String {
        if let first = report.rejected.first {
            let title = record(first)?.note.displayTitle ?? Note.untitled
            return report.rejected.count == 1
                ? "Der Server lehnt „\(title)“ ab."
                : "Der Server lehnt \(report.rejected.count) Notizen ab, darunter „\(title)“."
        }
        return report.conflicts > 0 ? "Konflikt mit dem Server." : "Abgeglichen."
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case APIError.unauthorized:
            return "Anmeldung abgelehnt."
        case APIError.slowDown:
            return "Zu viele Versuche. Kurz warten."
        case APIError.notFound:
            return "Der Server kennt diesen Pfad nicht."
        case let APIError.badStatus(code, _):
            return "Der Server antwortete mit \(code)."
        case is URLError:
            return "Server nicht erreichbar."
        case let error as KeychainError:
            return "Die Anmeldung ließ sich nicht im Schlüsselbund sichern (\(error.status))."
        default:
            return "Abgleich fehlgeschlagen."
        }
    }
}
