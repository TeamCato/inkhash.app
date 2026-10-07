import Foundation
import InkhashCore
import Observation

/// The workspaces and servers of this device (`setup.json`), their libraries and pictures.
/// Knows nothing about sessions or the network. See ADR 0020 and 0043.
@MainActor
@Observable
final class WorkspaceRegistry {
    let base: URL
    private(set) var setup: DeviceSetup
    /// The server made from a sign-in of an older version, until its session token has moved.
    @ObservationIgnored private(set) var migrated: ServerEntry?
    @ObservationIgnored private var stores: [UUID: LocalStore] = [:]
    /// Workspace pictures by hash. A changed picture has a new hash, so nothing goes stale.
    @ObservationIgnored private var iconCache: [String: PlatformImage] = [:]
    private let status: StatusLine

    init(base: URL, legacy: LegacySignIn?, status: StatusLine) throws {
        self.base = base
        self.status = status
        let opened = try Workspaces.open(base: base, legacy: legacy)
        setup = opened.setup
        migrated = opened.migrated
        if !setup.workspaces.contains(where: { $0.id == setup.current }), let first = setup.workspaces.first {
            setup.current = first.id
        }
    }

    // MARK: Reading

    var current: Workspace {
        setup.workspaces.first { $0.id == setup.current } ?? setup.workspaces[0]
    }

    var workspaces: [Workspace] { setup.workspaces }
    var servers: [ServerEntry] { setup.servers }

    func workspace(_ id: UUID) -> Workspace? {
        setup.workspaces.first { $0.id == id }
    }

    func server(_ id: UUID?) -> ServerEntry? {
        setup.server(id)
    }

    func server(of workspace: Workspace) -> ServerEntry? {
        setup.server(workspace.link?.server)
    }

    func workspaces(on server: UUID) -> [Workspace] {
        setup.workspaces.filter { $0.link?.server == server }
    }

    func store(for id: UUID) -> LocalStore {
        if let cached = stores[id] { return cached }
        do {
            let opened = try Workspaces.store(of: id, base: base)
            stores[id] = opened
            return opened
        } catch {
            fatalError("Workspace ließ sich nicht öffnen: \(error)")
        }
    }

    var currentStore: LocalStore { store(for: setup.current) }

    /// No notes, not even in the trash, and no kept folders.
    func isEmpty(_ id: UUID) -> Bool {
        let library = store(for: id)
        return ((try? library.list().isEmpty) ?? false) && library.keptFolders().isEmpty
    }

    /// The workspace's own picture, or nil when it shows its symbol.
    func image(of workspace: Workspace) -> PlatformImage? {
        guard let name = workspace.icon else { return nil }
        if let cached = iconCache[name] { return cached }
        guard let image = PlatformImage(contentsOfFile: Workspaces.iconURL(name, base: base).path) else { return nil }
        iconCache[name] = image
        return image
    }

    // MARK: Workspaces

    /// False if there is no such workspace or it already is the current one.
    @discardableResult
    func select(_ id: UUID) -> Bool {
        guard id != setup.current, setup.workspaces.contains(where: { $0.id == id }) else { return false }
        setup.current = id
        persist()
        return true
    }

    func append(_ workspace: Workspace) {
        setup.workspaces.append(workspace)
        persist()
    }

    /// Name and symbol. True if anything changed; a linked workspace then sends its look. See ADR 0043.
    @discardableResult
    func setLook(_ id: UUID, name: String, symbol: String) -> Bool {
        edit(id) { workspace in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { workspace.name = trimmed.clippedUTF16(Limits.workspaceName) }
            workspace.symbol = symbol
        }
    }

    /// Sets or clears the own picture. `png` comes from `WorkspaceImage.normalize`. True if it changed.
    @discardableResult
    func setImage(_ id: UUID, png: Data?) -> Bool {
        let icon: String?
        if let png {
            do {
                icon = try Workspaces.saveIcon(png, base: base)
            } catch {
                status.message = "Das Bild ließ sich nicht sichern."
                return false
            }
        } else {
            icon = nil
        }
        let changed = edit(id) { $0.icon = icon }
        pruneIcons()
        return changed
    }

    /// Points a workspace at a server workspace, or at none. True if the link changed.
    /// A workspace that already has a look on the server keeps it; a new one gets ours.
    @discardableResult
    func setLink(_ id: UUID, to link: WorkspaceLink?) -> Bool {
        guard let index = setup.workspaces.firstIndex(where: { $0.id == id }),
              setup.workspaces[index].link != link else { return false }
        setup.workspaces[index].link = link
        setup.workspaces[index].lookPending = false
        persist()
        return true
    }

    func moveWorkspaces(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        setup.moveWorkspaces(fromOffsets: offsets, toOffset: destination)
        setup.markOrderChanged()
        persist()
    }

    func moveWorkspace(_ id: UUID, by step: Int) {
        setup.moveWorkspace(id, by: step)
        setup.markOrderChanged()
        persist()
    }

    /// Removes a workspace and its files from this device; the last one stays. True if it went.
    @discardableResult
    func remove(_ id: UUID) -> Bool {
        guard setup.workspaces.count > 1, let index = setup.workspaces.firstIndex(where: { $0.id == id }) else { return false }
        setup.workspaces.remove(at: index)
        stores[id] = nil
        if setup.current == id { setup.current = setup.workspaces[0].id }
        persist()
        do {
            try Workspaces.removeFiles(of: id, base: base)
        } catch {
            status.message = "Die Dateien des Workspace ließen sich nicht entfernen."
        }
        pruneIcons()
        return true
    }

    /// Takes server workspaces onto this device. See ADR 0044.
    func addLinked(_ remotes: [RemoteWorkspace], on server: UUID) -> [UUID] {
        let added = setup.addLinked(remotes, on: server) { [self] id in isEmpty(id) }
        if !added.isEmpty { persist() }
        return added
    }

    /// Takes what a look sync made of `snapshot`. See `DeviceSetup.adopt`.
    func adopt(_ synced: DeviceSetup, since snapshot: DeviceSetup) {
        guard synced != snapshot else { return }
        setup.adopt(synced, since: snapshot)
        persist()
        pruneIcons()
    }

    // MARK: Servers

    /// A known address keeps its entry, so workspaces linked to it continue. Returns its id.
    func signedIn(url: String, accountName: String, accountID: String) -> UUID {
        let id: UUID
        if let index = setup.servers.firstIndex(where: { $0.url == url }) {
            id = setup.servers[index].id
            setup.servers[index].accountName = accountName
            setup.servers[index].accountID = accountID
        } else {
            let entry = ServerEntry(url: url, accountName: accountName, accountID: accountID)
            id = entry.id
            setup.servers.append(entry)
        }
        persist()
        return id
    }

    func signedOut(_ server: UUID) {
        guard let index = setup.servers.firstIndex(where: { $0.id == server }) else { return }
        setup.servers[index].accountID = ""
        persist()
    }

    /// Forgets a server. Workspaces linked to it stay and stop syncing.
    func removeServer(_ server: UUID) {
        setup.servers.removeAll { $0.id == server }
        for index in setup.workspaces.indices where setup.workspaces[index].link?.server == server {
            setup.workspaces[index].link = nil
        }
        persist()
    }

    func migrationDone() {
        migrated = nil
    }

    // MARK: Private

    /// A linked workspace whose look changed sends it with the next sync.
    private func edit(_ id: UUID, _ change: (inout Workspace) -> Void) -> Bool {
        guard let index = setup.workspaces.firstIndex(where: { $0.id == id }) else { return false }
        let before = setup.workspaces[index]
        change(&setup.workspaces[index])
        guard setup.workspaces[index] != before else { return false }
        if setup.workspaces[index].link != nil { setup.workspaces[index].lookPending = true }
        persist()
        return true
    }

    /// Pictures are named by content, so a file no workspace names anymore can go.
    private func pruneIcons() {
        do {
            try Workspaces.pruneIcons(keeping: setup, base: base)
        } catch {
            // A leftover file costs a few kilobytes and goes with the next change.
        }
        let used = Set(setup.workspaces.compactMap(\.icon))
        iconCache = iconCache.filter { used.contains($0.key) }
    }

    private func persist() {
        do {
            try Workspaces.save(setup, base: base)
        } catch {
            status.message = "Die Einstellungen ließen sich nicht sichern."
        }
    }
}
