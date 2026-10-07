import Foundation

/// What syncing the look and order of workspaces needs from a server. See ADR 0043.
public protocol WorkspaceTransport: Sendable {
    func workspaceList() async throws -> RemoteWorkspaceList
    func updateWorkspace(id: String, look: WorkspaceLook) async throws -> RemoteWorkspace
    func orderWorkspaces(ids: [String]) async throws -> RemoteWorkspaceList
    func putIcon(workspace: String, sha256: String, data: Data) async throws
    func fetchIcon(workspace: String, sha256: String) async throws -> Data
}

extension APIClient: WorkspaceTransport {
    public func putIcon(workspace: String, sha256: String, data: Data) async throws {
        var scoped = self
        scoped.workspace = workspace
        try await scoped.putBlob(sha256: sha256, data: data)
    }

    public func fetchIcon(workspace: String, sha256: String) async throws -> Data {
        var scoped = self
        scoped.workspace = workspace
        return try await scoped.fetchBlob(sha256: sha256)
    }
}

/// Makes name, symbol, picture and order of the workspaces linked to one server the same
/// on every device. The last device to change a look wins; there are no conflicts. See ADR 0043.
@MainActor
public enum LookSyncer {
    /// Returns `setup` as it should be after syncing with `server`. Merge it back with
    /// `DeviceSetup.adopt`, since the setup may change while this waits for the server.
    public static func sync(_ setup: DeviceSetup, server: UUID, base: URL, transport: WorkspaceTransport) async throws -> DeviceSetup {
        var setup = setup
        let list = try await transport.workspaceList()
        guard list.keepsLooks else { return setup }
        let remotes = Dictionary(list.workspaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for index in setup.workspaces.indices {
            let workspace = setup.workspaces[index]
            guard let link = workspace.link, link.server == server, let remote = remotes[link.remote] else { continue }
            // A look nobody has set on the server yet comes from the first device that syncs.
            if workspace.lookPending || remote.updatedAt == nil {
                if let icon = workspace.icon {
                    let data = try Data(contentsOf: Workspaces.iconURL(icon, base: base))
                    try await transport.putIcon(workspace: remote.id, sha256: icon, data: data)
                }
                do {
                    _ = try await transport.updateWorkspace(
                        id: remote.id,
                        look: WorkspaceLook(name: workspace.name, symbol: workspace.symbol, icon: workspace.icon)
                    )
                } catch APIError.notFound {
                    continue
                }
                setup.workspaces[index].lookPending = false
            } else {
                setup.workspaces[index].name = remote.name
                if let symbol = remote.symbol { setup.workspaces[index].symbol = symbol }
                if let icon = remote.icon, icon != workspace.icon,
                   !FileManager.default.fileExists(atPath: Workspaces.iconURL(icon, base: base).path) {
                    let data = try await transport.fetchIcon(workspace: remote.id, sha256: icon)
                    guard sha256Hex(data) == icon else { throw APIError.invalidResponse }
                    try Workspaces.saveIcon(data, base: base)
                }
                setup.workspaces[index].icon = remote.icon
            }
        }

        let linked = setup.workspaces.indices.filter { index in
            guard let link = setup.workspaces[index].link else { return false }
            return link.server == server && remotes[link.remote] != nil
        }
        if setup.orderPending.contains(server) || list.ordered == false {
            if !linked.isEmpty {
                _ = try await transport.orderWorkspaces(ids: linked.compactMap { setup.workspaces[$0].link?.remote })
            }
            setup.orderPending.removeAll { $0 == server }
        } else {
            // The server's order fills the places its workspaces hold here; the others stay put.
            let rank = Dictionary(list.workspaces.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            let sorted = linked.map { setup.workspaces[$0] }.sorted { a, b in
                (a.link.flatMap { rank[$0.remote] } ?? 0) < (b.link.flatMap { rank[$0.remote] } ?? 0)
            }
            for (slot, workspace) in zip(linked, sorted) { setup.workspaces[slot] = workspace }
        }
        return setup
    }
}
