import Foundation
import InkhashCore
import KennelKit
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
    /// Underline, strikethrough or highlighter. See ADR 0079.
    case toggleDecoration(InlineDecoration)
    /// Puts a link on the selection, or takes it off with nil. See ADR 0024.
    case setLink(String?)
}

/// What Cmd+F, Cmd+G and Cmd+Shift+G ask of the open text note. See ADR 0084.
enum FindStep: Equatable {
    case open
    case next
    case previous
}

struct FindImpulse: Equatable {
    var token: Int
    var step: FindStep
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

/// Where a new workspace lies (teamCato ADR 0009 point 5, ADR 0077).
enum WorkspaceTarget: Hashable {
    /// „Nur hier“.
    case local
    /// A new Kennel workspace in this storage (nil: the account's), end to end encrypted with `sealed` (ADR 0082).
    case kennel(storageID: String?, sealed: Bool = false)
}

/// What the views share: where the user is (section, search, selection) and the steps that need
/// several parts of the model at once. Each part does one job:
/// `WorkspaceRegistry` the workspaces and the Kennel of this device, `ServerSessions` signing in,
/// `NoteLibrary` the notes of the current workspace, `SyncCoordinator` syncing, `KennelOverview` what Kennel holds.
@MainActor
@Observable
final class AppModel {
    let registry: WorkspaceRegistry
    let sessions: ServerSessions
    let vaults: VaultSessions
    let library: NoteLibrary
    let overview: KennelOverview
    @ObservationIgnored private let syncer: SyncCoordinator
    private let statusLine: StatusLine

    var selectedID: UUID? {
        didSet { if selectedID != nil { showsTasks = false } }
    }
    var section: LibrarySection = .notes {
        didSet { if oldValue != section { selectedID = nil } }
    }
    /// The task list fills the detail instead of a note. See ADR 0060.
    var showsTasks = false
    var query = ""
    var editorEpoch = 0
    var searchFocusToken = 0
    var inlineImpulse: EditorImpulse?
    var findImpulse: FindImpulse?
    /// Bumped by Cmd+K: the open note shows its link field for the selection.
    var linkPromptToken = 0
    /// Set by the menu; the sidebar shows the file picker and clears it. See ADR 0024 and 0041.
    var importRequested = false
    /// A join link or app link the app was opened with; „Mit Kennel verbinden“ opens for it. See ADR 0071.
    var pendingJoin: JoinLink?
    private var impulseToken = 0

    /// Where the libraries live: Application Support, which the iCloud backup of iPad and iPhone
    /// and Time Machine on the Mac include. Never Caches or tmp. See ADR 0051.
    static var storageBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inkhash", isDirectory: true)
    }

    convenience init() {
        let defaults = UserDefaults.standard
        let legacy = LegacySignIn(
            url: defaults.string(forKey: "inkhash.baseURL") ?? "",
            accountName: defaults.string(forKey: "inkhash.accountName") ?? "",
            accountID: ServerAddress.accountID(defaults.string(forKey: "inkhash.accountID") ?? "") ?? ""
        )
        self.init(base: Self.storageBase, legacy: legacy)
    }

    /// The model over the libraries at `base`. Tests hand in a folder of their own.
    init(base: URL, legacy: LegacySignIn?) {
        let defaults = UserDefaults.standard
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
        let vaults = VaultSessions(sessions: sessions, status: status)
        let library = NoteLibrary(registry: registry, status: status)
        let overview = KennelOverview()
        let syncer = SyncCoordinator(
            registry: registry, sessions: sessions, vaults: vaults, library: library, status: status, overview: overview)
        self.statusLine = status
        self.registry = registry
        self.sessions = sessions
        self.vaults = vaults
        self.library = library
        self.overview = overview
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

    /// A text note fills the detail: Cmd+F finds in it instead of the library. See ADR 0084.
    var findsInNote: Bool {
        guard !showsTasks, let selectedID else { return false }
        return library.record(selectedID)?.note.kind == .text
    }

    /// Cmd+F: in the open text note, otherwise in the library.
    func find() {
        if findsInNote {
            sendFind(.open)
        } else {
            focusSearch()
        }
    }

    func sendFind(_ step: FindStep) {
        impulseToken += 1
        findImpulse = FindImpulse(token: impulseToken, step: step)
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

    /// A new note made from inside another one while embedding: it stays closed, the open note keeps the
    /// screen. It lies in the same folder and hangs below the note it was made from, which opens to show
    /// it. No title: it follows what gets written. See ADR 0019, 0037 and 0090.
    func createChild(_ note: Note, of parent: Note) -> Note {
        var note = note
        note.folder = parent.folder
        note.title = ""
        // The picker of a note that is not in the library yet has nothing to hang below.
        if library.record(parent.id) != nil {
            note.parent = parent.id
            library.reveal(parent.folder)
            library.setExpanded(NoteTree.expansionKey(for: parent.id), true)
        }
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

    /// Deleted for good, from the trash, on every device that syncs this workspace. See ADR 0089.
    func purge(id: UUID) {
        if library.purge(id, syncs: registry.current.link != nil), selectedID == id { selectedID = nil }
    }

    func emptyTrash() {
        library.emptyTrash(syncs: registry.current.link != nil)
        dropMissingSelection()
    }

    // MARK: Export

    /// One note as a file to save: Markdown or PDF. Nil if it failed; the status says why. See ADR 0051.
    func exportFile(for id: UUID) -> ExportedFile? {
        guard let note = library.record(id)?.note else { return nil }
        do {
            return ExportedFile(url: try NoteExport.file(for: note) { [library] in library.drawingData(for: $0) })
        } catch {
            status = "Die Notiz ließ sich nicht exportieren."
            return nil
        }
    }

    /// A note for the share sheet; the file is made when a target is picked.
    func shared(_ id: UUID) -> SharedNote? {
        guard let note = library.record(id)?.note else { return nil }
        return SharedNote(note: note) { [weak library] in library?.drawingData(for: $0) }
    }

    /// A whole workspace as one ZIP: readable files and a copy to import again. See ADR 0051.
    func exportWorkspace(_ id: UUID) -> ExportedFile? {
        guard let workspace = registry.workspace(id) else { return nil }
        do {
            let (url, summary) = try WorkspaceExporter.export(workspace, store: registry.store(for: id))
            var message = summary.notes == 1 ? "Eine Notiz exportiert." : "\(summary.notes) Notizen exportiert."
            if summary.withoutPDF > 0 {
                message += " \(summary.withoutPDF) Handschrift ohne PDF, aber in der Sicherung."
            }
            status = message
            return ExportedFile(url: url)
        } catch {
            status = "Der Export ist fehlgeschlagen."
            return nil
        }
    }

    /// Ends a conflict. The open editor starts over from the kept version. See ADR 0049.
    func resolveConflict(id: UUID, choice: ConflictChoice) {
        if library.resolveConflict(id: id, choice: choice) != nil { editorEpoch += 1 }
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

    /// Shows the task list of the workspace, or closes it again.
    func toggleTasks() {
        if showsTasks, selectedID == nil {
            showsTasks = false
        } else {
            selectedID = nil
            showsTasks = true
        }
    }

    func switchWorkspace(_ id: UUID) {
        guard registry.select(id) else { return }
        section = .notes
        query = ""
        selectedID = nil
        library.reload()
        status = syncer.statusAtRest
        syncer.schedule()
    }

    func createWorkspace(name: String, symbol: String, image: Data?, target: WorkspaceTarget) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Der Workspace braucht einen Namen." }
        var workspace = Workspace(name: trimmed.clippedUTF16(Limits.workspaceName), symbol: symbol)
        do {
            workspace.link = try await link(for: target, name: workspace.name)
        } catch {
            return describe(error)
        }
        registry.append(workspace)
        if let image { registry.setImage(workspace.id, png: image) }
        if workspace.link != nil { registry.placeLook(workspace.id) }
        switchWorkspace(workspace.id)
        await sync()
        return nil
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

    /// „In Kennel ablegen …“: a new plain Kennel workspace in this storage (nil: the account's) takes all notes of a
    /// workspace that lies only here (teamCato ADR 0009 point 6, ADR 0077). Nil on success, else why not.
    func placeInKennel(_ id: UUID, storageID: String?, syncing: Bool = true) async -> String? {
        guard let workspace = registry.workspace(id), workspace.link == nil else { return nil }
        do {
            let link = try await link(for: .kennel(storageID: storageID), name: workspace.name)
            registry.setLink(id, to: link)
            registry.placeLook(id)
        } catch {
            return describe(error)
        }
        status = "„\(workspace.name)“ liegt jetzt auch in Kennel."
        if syncing { await sync() }
        return nil
    }

    /// „Nur noch auf diesem Gerät …“: the workspace stops syncing. Its notes stay here, the Kennel copy stays there.
    func keepOnlyHere(_ id: UUID) {
        guard let workspace = registry.workspace(id), registry.setLink(id, to: nil) else { return }
        status = "„\(workspace.name)“ liegt jetzt nur noch auf diesem Gerät."
    }

    /// „Mit Kennel-Workspace verbinden …“: a workspace that lies only here syncs with an existing Kennel workspace; the
    /// notes of both meet there, nothing is lost (ADR 0017, 0085). An encrypted one syncs once it is unlocked here.
    func link(_ id: UUID, to remote: RemoteWorkspace) async {
        guard let workspace = registry.workspace(id), attach(id, to: remote) else { return }
        status = "„\(workspace.name)“ gleicht jetzt mit „\(remote.name)“ in Kennel ab."
        await sync()
    }

    /// Links without syncing. Merged like a successor: notes Kennel has already, e.g. from before a lost link, do not
    /// come in twice. False if the workspace is linked already.
    @discardableResult
    private func attach(_ id: UUID, to remote: RemoteWorkspace) -> Bool {
        guard let kennel = registry.kennel, registry.workspace(id)?.link == nil else { return false }
        registry.moveOn(
            id, to: WorkspaceLink(server: kennel.id, remote: remote.id, sealed: remote.isSealed),
            retiring: RetiringRemote(remote: remote.id, cursor: 0, deletes: false))
        return true
    }

    /// „Unverschlüsselt weiterführen …“ (ADR 0085). Nil when it began, else why not.
    func convertToPlain(_ id: UUID) async -> String? {
        await syncer.convertToPlain(id)
    }

    /// Moves the Kennel workspace behind a linked workspace to another storage (`nil`: the account's). Kennel moves in
    /// the background; the answer is the workspace with its move. Nil when it failed; the text says why (ADR 0076).
    func moveInKennel(_ id: UUID, to storageID: String?) async -> Result<RemoteWorkspace, KennelProblem> {
        guard let link = registry.workspace(id)?.link, let client = sessions.client(for: link.server) else {
            return .failure(KennelProblem("Nicht mit Kennel verbunden."))
        }
        do {
            let moved = try await client.moveWorkspace(id: link.remote, to: storageID)
            replaceRemote(moved)
            return .success(moved)
        } catch APIError.unauthorized {
            sessions.expire(link.server, ifStill: client.token)
            return .failure(KennelProblem("Die Anmeldung ist abgelaufen."))
        } catch let APIError.badStatus(400, body) where body.contains("storage") {
            return .failure(KennelProblem("Diesen Speicher darf inkhash nicht nutzen."))
        } catch {
            return .failure(KennelProblem(StatusLine.describe(error)))
        }
    }

    /// Asks Kennel now and then until the move of the workspace is over, then syncs (ADR 0076).
    func watchMove(of id: UUID) async {
        guard let link = registry.workspace(id)?.link, let kennel = registry.kennel else { return }
        while overview.remotes.first(where: { $0.id == link.remote })?.move?.isRunning == true {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard let fresh = await sessions.remoteWorkspaceList(on: kennel.id) else { return }
            overview.remotes = fresh.workspaces
        }
        await sync()
    }

    /// Removes the workspace and its notes from this device. A Kennel copy stays where it is.
    func removeWorkspace(_ id: UUID) {
        guard registry.remove(id) else { return }
        library.reload()
        dropMissingSelection()
    }

    /// Takes Kennel workspaces onto this device, linked and synced right away. See ADR 0044.
    func addFromKennel(_ remotes: [RemoteWorkspace]) async {
        guard let kennel = registry.kennel else { return }
        let added = registry.addLinked(remotes, on: kennel.id)
        guard !added.isEmpty else { return }
        status = added.count == 1 ? "Workspace hinzugefügt." : "\(added.count) Workspaces hinzugefügt."
        await sync()
    }

    /// How many notes a Kennel workspace holds, for the warning before deleting it. Nil if unknown.
    func noteCount(of remote: RemoteWorkspace) async -> Int? {
        guard let kennel = registry.kennel, let client = sessions.client(for: kennel.id) else { return nil }
        return try? await client.noteCount(workspace: remote.id)
    }

    /// Deletes a workspace in Kennel, for every device; one always stays. Workspaces here that synced with it keep
    /// their notes and stay on this device only. Nil if it is gone, else why not. See ADR 0045.
    func deleteInKennel(_ remote: RemoteWorkspace) async -> String? {
        guard let kennel = registry.kennel, let client = sessions.client(for: kennel.id) else {
            return "Nicht mit Kennel verbunden."
        }
        do {
            try await client.deleteWorkspace(id: remote.id)
        } catch APIError.notFound {
            // Already gone, e.g. deleted on another device.
        } catch let APIError.badStatus(400, body) where body.contains("last workspace") {
            return "Ein Workspace muss in Kennel bleiben."
        } catch APIError.unauthorized {
            sessions.expire(kennel.id, ifStill: client.token)
            return "Die Anmeldung ist abgelaufen."
        } catch {
            return StatusLine.describe(error)
        }
        for workspace in registry.workspaces(on: kennel.id) where workspace.link?.remote == remote.id {
            registry.setLink(workspace.id, to: nil)
        }
        overview.remotes.removeAll { $0.id == remote.id }
        status = "„\(remote.name)“ ist in Kennel gelöscht."
        return nil
    }

    /// A new Kennel workspace: plain, or end to end encrypted with the vault open here (ADR 0082). Encryption is chosen
    /// once and never changes (Kennel ADR 0026).
    private func link(for target: WorkspaceTarget, name: String) async throws -> WorkspaceLink? {
        switch target {
        case .local:
            return nil
        case .kennel(let storageID, let sealed):
            guard let kennel = registry.kennel, let client = sessions.client(for: kennel.id) else {
                throw KennelProblem("Nicht mit Kennel verbunden.")
            }
            let module = try await client.kennel.health().inkhash
            if sealed {
                if vaults.key(for: kennel.id) == nil { await vaults.check(kennel.id) }
                guard vaults.key(for: kennel.id) != nil else {
                    throw KennelProblem("Schalte zuerst die Verschlüsselung auf diesem Gerät frei.")
                }
            } else {
                guard module?.plainWorkspaces == true else {
                    throw KennelProblem("Dieser Kennel legt keine unverschlüsselten Workspaces an. Bitte Kennel aktualisieren.")
                }
            }
            do {
                let created = try await client.createWorkspace(
                    name: name,
                    as: NewRemoteWorkspace(sealed: sealed, storageID: module?.workspaceStorage == true ? storageID : nil))
                overview.remotes.append(created)
                return WorkspaceLink(server: kennel.id, remote: created.id, sealed: created.isSealed)
            } catch let APIError.badStatus(400, body) where body.contains("storage") {
                throw KennelProblem("Diesen Speicher darf inkhash nicht nutzen.")
            }
        }
    }

    private func replaceRemote(_ remote: RemoteWorkspace) {
        if let index = overview.remotes.firstIndex(where: { $0.id == remote.id }) {
            overview.remotes[index] = remote
        } else {
            overview.remotes.append(remote)
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? KennelProblem)?.message ?? StatusLine.describe(error)
    }

    // MARK: Kennel

    /// The one Kennel of this app, while one is connected (teamCato ADR 0009 point 8).
    var kennel: ServerEntry? { registry.kennel }

    /// The status line at the foot of the sidebar, nil while no Kennel is connected (teamCato ADR 0009 point 7).
    var kennelStatus: KennelStatus? {
        registry.kennel == nil ? nil : overview.state.status
    }

    /// True if the workspace syncs right now: linked to the Kennel with a session.
    func syncs(_ workspace: Workspace) -> Bool { syncer.syncs(workspace) }

    var isSyncEnabled: Bool { syncer.isEnabled }

    func sync() async {
        await syncer.sync()
    }

    /// Signs in or redeems a join code for „Mit Kennel verbinden“ (ADR 0071). Syncing waits for „Übernehmen“.
    func connect(_ request: KennelConnectRequest) async -> KennelConnectOutcome {
        let before = registry.kennel?.id
        switch request {
        case .signIn(let address, let name, let password):
            guard await sessions.signIn(url: address.absoluteString, name: name, password: password) != nil else {
                return .failed(status)
            }
        case .join(let address, let code, let account):
            switch await sessions.join(
                url: address.absoluteString, code: code.description, name: account?.name, password: account?.password)
            {
            case .joined: break
            case .needsAccount: return .needsAccount
            case .failed: return .failed(status)
            }
        }
        if registry.kennel?.id != before { overview.reset() }
        return .connected
    }

    /// Asks Kennel for its workspaces and storages, e.g. when a sheet that lists them opens. False if it failed;
    /// the status says why.
    @discardableResult
    func refreshKennel() async -> Bool {
        guard let kennel = registry.kennel, let client = sessions.client(for: kennel.id) else { return false }
        do {
            let module = try await client.kennel.health().inkhash
            overview.module = module
            overview.remotes = try await client.workspaceList().workspaces
            if module?.workspaceStorage == true { overview.storages = (try? await client.noteStorages()) ?? overview.storages }
            overview.standardStorageID = (try? await client.standardStorageID()) ?? overview.standardStorageID
            return true
        } catch APIError.unauthorized {
            sessions.expire(kennel.id, ifStill: client.token)
            return false
        } catch {
            status = StatusLine.describe(error)
            return false
        }
    }

    /// „Übernehmen“: what lies only here and what Kennel has that is not here, each with a proposal (ADR 0077).
    func takeOverPlan() async -> KennelTakeOverPlan? {
        guard let kennel = registry.kennel, await refreshKennel() else { return nil }
        return TakeOverPlanner.plan(
            local: localOnly(), remotes: overview.unlinked(in: registry.setup), storages: overview.summaries,
            accountID: kennel.accountID, account: kennel.accountName)
    }

    /// Applies the answers of „Übernehmen“, then syncs. Nil on success, else what went wrong.
    func applyTakeOver(_ chosen: [String: String]) async -> String? {
        let actions = TakeOverPlanner.actions(chosen: chosen, local: localOnly(), remotes: overview.unlinked(in: registry.setup))
        for action in actions {
            switch action {
            case .place(let id, let storageID):
                if let problem = await placeInKennel(id, storageID: storageID, syncing: false) { return problem }
            case .link(let id, let remote):
                attach(id, to: remote)
            case .add(let remotes):
                if let kennel = registry.kennel { _ = registry.addLinked(remotes, on: kennel.id) }
            }
        }
        status = actions.isEmpty ? "" : "Übernommen. Kennel gleicht jetzt ab."
        await sync()
        return nil
    }

    /// „Mit Kennel verbinden“ ended with „Später“ or nothing to take over: nothing is linked, but Kennel is asked once.
    func connectedWithoutTakingOver() {
        Task { await sync() }
    }

    private func localOnly() -> [TakeOverLocal] {
        registry.workspaces.filter { $0.link == nil }.map { workspace in
            TakeOverLocal(
                id: workspace.id, name: workspace.name, isEmpty: registry.isEmpty(workspace.id),
                boundKey: registry.store(for: workspace.id).boundAccount())
        }
    }

    /// Takes `inkhash://kennel/join?…`; other URLs are not for this. Returns whether it was one.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == JoinLinks.scheme, let target = JoinLinks.parse(url.absoluteString) else { return false }
        pendingJoin = target
        return true
    }

    /// „Von Kennel trennen“: lossless (teamCato ADR 0002). Every workspace stays here as „Nur hier“, the Kennel copies
    /// stay in Kennel, and the session and vault key leave this device.
    func disconnect() {
        guard let kennel = registry.kennel else { return }
        sessions.logout(kennel.id)
        sessions.dismissExpiredNotice(kennel.id)
        vaults.forget(kennel.id)
        registry.removeServer(kennel.id)
        overview.reset()
        status = "Von Kennel getrennt. Alle Workspaces bleiben auf diesem Gerät."
    }

    /// What „Von Kennel trennen …“ says will happen.
    static let disconnectConsequence = "Alle Workspaces bleiben mit ihren Notizen auf diesem Gerät und gelten danach als „Nur hier“. In Kennel bleibt alles liegen. Verbindest du wieder, schlägt „Übernehmen“ die alten Zuordnungen vor."

    /// A storage made in „Neuer Speicher …“ is offered right away.
    func addStorage(_ storage: KennelStorage) {
        if !overview.storages.contains(where: { $0.id == storage.id }) { overview.storages.append(storage) }
    }

    // MARK: Vault (ADR 0082, Kennel ADR 0043, 0058)

    /// Where the vault stands here; nil without a Kennel.
    var vaultState: VaultState? {
        registry.kennel.map { vaults.state(of: $0.id) }
    }

    var vaultFromInkhash: Bool {
        registry.kennel.map { vaults.isFromInkhash($0.id) } ?? false
    }

    /// Asks Kennel where the vault stands, for the Kennel page and „Wo soll er liegen?“.
    func checkVault() async {
        guard let kennel = registry.kennel, sessions.isSignedIn(kennel.id) else { return }
        await vaults.check(kennel.id)
    }

    /// Each returns nil on success, else what went wrong, for KennelKitUI's vault windows; success syncs, so locked
    /// encrypted workspaces open.
    func createVault(_ key: KennelRecoveryKey) async -> String? {
        await vaultAction { await self.vaults.create($0, recoveryKey: key) }
    }

    func openVault(_ key: KennelRecoveryKey) async -> String? {
        await vaultAction { await self.vaults.unlock($0, recoveryKey: key) }
    }

    func openVault(pairingCode: String) async -> String? {
        await vaultAction { await self.vaults.unlock($0, pairingCode: pairingCode) }
    }

    /// „Sperren …“: this device forgets the key until it is unlocked again (ADR 0087). Only the keychain can fail here.
    func lockVault() async {
        if let failure = await vaultAction({ await self.vaults.lock($0) }) {
            statusLine.message = failure
        }
    }

    func offerPairing() async -> Result<KennelPairing, KennelProblem> {
        guard let kennel = registry.kennel else { return .failure(KennelProblem("Nicht mit Kennel verbunden.")) }
        return await vaults.offerPairing(kennel.id)
    }

    func withdraw(_ pairing: KennelPairing) async {
        guard let kennel = registry.kennel else { return }
        await vaults.withdraw(kennel.id, pairing)
    }

    private func vaultAction(_ work: (UUID) async -> String?) async -> String? {
        guard let kennel = registry.kennel else { return "Nicht mit Kennel verbunden." }
        let problem = await work(kennel.id)
        if problem == nil { await sync() }
        return problem
    }
}

/// Something about Kennel that went wrong, in words for the person.
struct KennelProblem: Error, Equatable {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}
