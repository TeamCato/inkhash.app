import Foundation
import InkhashCore
import Observation
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

/// Where a new or existing workspace syncs to.
enum WorkspaceTarget: Hashable {
    case local
    /// `remote` nil creates a new workspace on that server.
    case server(UUID, remote: String?)
}

/// What the views share: where the user is (section, search, selection) and the steps that need
/// several parts of the model at once. Each part does one job:
/// `WorkspaceRegistry` the workspaces and servers of this device, `ServerSessions` signing in,
/// `NoteLibrary` the notes of the current workspace, `SyncCoordinator` syncing.
@MainActor
@Observable
final class AppModel {
    let registry: WorkspaceRegistry
    let sessions: ServerSessions
    let library: NoteLibrary
    @ObservationIgnored private let syncer: SyncCoordinator
    private let statusLine: StatusLine

    var selectedID: UUID?
    var section: LibrarySection = .notes {
        didSet { if oldValue != section { selectedID = nil } }
    }
    var query = ""
    var editorEpoch = 0
    var searchFocusToken = 0
    var inlineImpulse: EditorImpulse?
    /// Bumped by Cmd+K: the open note shows its link field for the selection.
    var linkPromptToken = 0
    /// Set by the menu; the sidebar shows the file picker and clears it. See ADR 0024 and 0041.
    var importRequested = false
    private var impulseToken = 0

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inkhash", isDirectory: true)
        let defaults = UserDefaults.standard
        let legacy = LegacySignIn(
            url: defaults.string(forKey: "inkhash.baseURL") ?? "",
            accountName: defaults.string(forKey: "inkhash.accountName") ?? "",
            accountID: ServerAddress.accountID(defaults.string(forKey: "inkhash.accountID") ?? "") ?? ""
        )
        let status = StatusLine()
        let registry: WorkspaceRegistry
        do {
            registry = try WorkspaceRegistry(base: base, legacy: legacy, status: status)
        } catch {
            fatalError("Lokaler Speicher ließ sich nicht anlegen: \(error)")
        }
        if registry.migrated != nil {
            for key in ["inkhash.baseURL", "inkhash.accountName", "inkhash.accountID"] {
                defaults.removeObject(forKey: key)
            }
        }
        let sessions = ServerSessions(registry: registry, status: status)
        let library = NoteLibrary(registry: registry, status: status)
        let syncer = SyncCoordinator(registry: registry, sessions: sessions, library: library, status: status)
        self.statusLine = status
        self.registry = registry
        self.sessions = sessions
        self.library = library
        self.syncer = syncer
        library.changed = { [weak syncer] in syncer?.schedule() }
        syncer.finished = { [weak self] in self?.dropMissingSelection() }
        status.message = syncer.statusAtRest
        ExcerptSource.current = ExcerptSource(
            note: { [weak library] id in library?.record(id)?.note },
            loadBlob: { [weak library] blob in library?.drawingData(for: blob) }
        )
    }

    var status: String {
        get { statusLine.message }
        set { statusLine.message = newValue }
    }

    // MARK: Sidebar

    var listed: [ListedNote] { library.listing.listed(section, query: query) }

    var tagFilter: String? { NoteListing.tagFilter(query) }

    var suggestedTags: [TagCount] { library.listing.suggestedTags(query: query) }

    var folderTree: NoteTree { library.listing.folderTree(query: query) }

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

    /// Follows a link from text or a page: a note link or excerpt opens the note, anything else the system.
    /// See ADR 0027 and 0032.
    func openLink(_ target: String) {
        if let id = NoteLink.noteID(in: target) ?? ExcerptTarget(target: target)?.noteID {
            guard let record = library.record(id), record.note.deletedAt == nil else {
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

    func createText(in folder: String? = nil) {
        add(placed(Note.newText(), in: folder), revealing: folder)
    }

    func createInk(data: Data, in folder: String? = nil) {
        guard let note = library.newInkNote(drawing: data, failure: "Die leere Seite ließ sich nicht anlegen.") else { return }
        add(placed(note, in: folder), revealing: folder)
    }

    /// A new note made from inside another one, for an excerpt: it stays closed, the open note keeps the
    /// screen. Same folder as the note it was made from, with a fixed title. See ADR 0032 and 0035.
    func createQuietly(_ note: Note, folder: String, title: String) -> Note {
        var note = note
        note.folder = Folders.isValid(folder) ? folder : ""
        note.title = String(title.prefix(80))
        library.add(note)
        return library.record(note.id)?.note ?? note
    }

    func importFile(at url: URL, in folder: String? = nil) {
        guard let first = library.importFile(at: url, place: { placed($0, in: folder) }) else { return }
        if let folder { library.reveal(folder) }
        selectedID = first
    }

    /// Moves a note to the trash. It stays restorable there; see ADR 0020.
    func delete(id: UUID) {
        library.moveToTrash(id)
        if selectedID == id { selectedID = nil }
    }

    /// Throws away a note made in the excerpt picker. Never synced, so it leaves no trace.
    func discard(id: UUID) {
        library.discard(id)
        if selectedID == id { selectedID = nil }
    }

    /// Gone from this device for good. Only from the trash and only once the server knows it is deleted.
    func purge(id: UUID) {
        if library.purge(id, syncs: registry.current.link != nil), selectedID == id { selectedID = nil }
    }

    func emptyTrash() {
        library.emptyTrash(syncs: registry.current.link != nil)
        dropMissingSelection()
    }

    func keepMine(id: UUID) {
        if library.keepMine(id: id) { editorEpoch += 1 }
    }

    func takeServer(id: UUID) {
        if library.takeServer(id: id) { editorEpoch += 1 }
    }

    /// A new note lands next to the selected one, or in `folder` when asked for one there.
    /// In the favorites it starts as a favorite.
    private func placed(_ note: Note, in folder: String?) -> Note {
        var note = note
        if let folder {
            note.folder = folder
        } else if section == .notes, let selected = selectedID, let current = library.record(selected) {
            note.folder = current.note.folder
        }
        if section == .favorites { note.favorite = true }
        if section == .trash { section = .notes }
        return note
    }

    private func add(_ note: Note, revealing folder: String?) {
        library.add(note)
        if let folder { library.reveal(folder) }
        selectedID = note.id
    }

    private func dropMissingSelection() {
        if let selected = selectedID, library.record(selected) == nil { selectedID = nil }
    }

    // MARK: Workspaces

    func switchWorkspace(_ id: UUID) {
        guard registry.select(id) else { return }
        section = .notes
        query = ""
        selectedID = nil
        library.reload()
        status = syncer.statusAtRest
        syncer.schedule()
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
            status = StatusLine.describe(error)
            return
        }
        registry.append(workspace)
        if let image { registry.setImage(workspace.id, png: image) }
        switchWorkspace(workspace.id)
        await sync()
    }

    func updateWorkspace(_ id: UUID, name: String, symbol: String) {
        if registry.setLook(id, name: name, symbol: symbol) { syncer.schedule() }
    }

    func setWorkspaceImage(_ id: UUID, png: Data?) {
        if registry.setImage(id, png: png) { syncer.schedule() }
    }

    func moveWorkspaces(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        registry.moveWorkspaces(fromOffsets: offsets, toOffset: destination)
        syncer.schedule()
    }

    func moveWorkspace(_ id: UUID, by step: Int) {
        registry.moveWorkspace(id, by: step)
        syncer.schedule()
    }

    /// Points a workspace at another server workspace, or at none. Changing the target uploads
    /// all its notes there, like signing in to another account (ADR 0017).
    func relink(_ id: UUID, to target: WorkspaceTarget) async {
        guard let workspace = registry.workspace(id) else { return }
        do {
            let link = try await link(for: target, name: workspace.name)
            guard registry.setLink(id, to: link) else { return }
            status = link == nil ? "Der Workspace bleibt jetzt auf diesem Gerät." : ""
            if id == registry.current.id { status = syncer.statusAtRest }
            await sync()
        } catch {
            status = StatusLine.describe(error)
        }
    }

    /// Removes the workspace and its notes from this device. A server copy stays where it is.
    func removeWorkspace(_ id: UUID) {
        guard registry.remove(id) else { return }
        library.reload()
        dropMissingSelection()
    }

    /// Takes server workspaces onto this device, linked and synced right away. See ADR 0044.
    func addFromServer(_ remotes: [RemoteWorkspace], on server: UUID) async {
        let added = registry.addLinked(remotes, on: server)
        guard !added.isEmpty else { return }
        status = added.count == 1 ? "Workspace hinzugefügt." : "\(added.count) Workspaces hinzugefügt."
        await sync()
    }

    /// How many notes a server workspace holds, for the warning before deleting it. Nil if unknown.
    func noteCount(of remote: RemoteWorkspace, on server: UUID) async -> Int? {
        guard let client = sessions.client(for: server) else { return nil }
        return try? await client.noteCount(workspace: remote.id)
    }

    /// Deletes a workspace on the server, for every device; one always stays. Workspaces here that
    /// synced with it keep their notes and stay on this device only. Nil if it is gone, else why
    /// not. See ADR 0045.
    func deleteOnServer(_ remote: RemoteWorkspace, on server: UUID) async -> String? {
        guard let client = sessions.client(for: server) else { return "Nicht angemeldet." }
        do {
            try await client.deleteWorkspace(id: remote.id)
        } catch APIError.notFound {
            // Already gone, e.g. deleted on another device.
        } catch APIError.badStatus(405, _) {
            return "Dieser Server kann noch keine Workspaces löschen. Er braucht Version 0.3.0 oder neuer."
        } catch let APIError.badStatus(400, body) where body.contains("last workspace") {
            return "Ein Workspace muss auf dem Server bleiben."
        } catch APIError.unauthorized {
            sessions.expire(server, ifStill: client.token)
            return "Die Anmeldung ist abgelaufen."
        } catch {
            return StatusLine.describe(error)
        }
        for workspace in registry.workspaces(on: server) where workspace.link?.remote == remote.id {
            registry.setLink(workspace.id, to: nil)
        }
        status = "„\(remote.name)“ ist auf dem Server gelöscht."
        if registry.current.link == nil { status = syncer.statusAtRest }
        return nil
    }

    private func link(for target: WorkspaceTarget, name: String) async throws -> WorkspaceLink? {
        switch target {
        case .local:
            return nil
        case .server(let serverID, let remote):
            guard let client = sessions.client(for: serverID) else { throw APIError.unauthorized }
            if let remote { return WorkspaceLink(server: serverID, remote: remote) }
            let created = try await client.createWorkspace(name: name)
            return WorkspaceLink(server: serverID, remote: created.id)
        }
    }

    // MARK: Servers and sync

    /// True if the workspace syncs right now: linked to a server with a session.
    func syncs(_ workspace: Workspace) -> Bool { syncer.syncs(workspace) }

    var isSyncEnabled: Bool { syncer.isEnabled }

    func sync() async {
        await syncer.sync()
    }

    /// Signs in, then syncs. Returns the server's id, or nil when it failed; the status says why.
    func signIn(url: String, name: String, password: String) async -> UUID? {
        guard let server = await sessions.signIn(url: url, name: name, password: password) else { return nil }
        await sync()
        return server
    }

    /// Forgets a server. Workspaces linked to it stay on this device and stop syncing.
    func removeServer(_ server: UUID) {
        sessions.logout(server)
        registry.removeServer(server)
        status = syncer.statusAtRest
    }

    /// The server of the current workspace, while its session has expired.
    var expiredNotice: ServerEntry? {
        guard let link = registry.current.link, sessions.expired.contains(link.server) else { return nil }
        return registry.server(link.server)
    }
}
