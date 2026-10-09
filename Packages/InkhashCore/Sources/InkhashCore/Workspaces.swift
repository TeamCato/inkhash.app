import Foundation

/// A server this device knows: address and the account it signed in with.
/// The session token is not in here; it lies in the keychain under `id`.
public struct ServerEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var url: String
    public var accountName: String
    /// Empty while signed out. Kept bindings survive that, see ADR 0017.
    public var accountID: String

    public init(id: UUID = UUID(), url: String, accountName: String = "", accountID: String = "") {
        self.id = id
        self.url = url
        self.accountName = accountName
        self.accountID = accountID
    }
}

/// Where a workspace syncs to: one workspace of one account on one server.
public struct WorkspaceLink: Codable, Equatable, Sendable {
    public var server: UUID
    /// The workspace id on the server, `main` or a UUID.
    public var remote: String

    public init(server: UUID, remote: String) {
        self.server = server
        self.remote = remote
    }
}

/// A workspace is a library of its own: notes, folders, tags, search. See ADR 0020.
public struct Workspace: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// SF Symbol name.
    public var symbol: String
    /// sha256 of an own picture, lying in `icons/<sha>.png`. Shown instead of `symbol`. See ADR 0043.
    public var icon: String?
    public var link: WorkspaceLink?
    /// Name, symbol or picture changed here and the server has not taken it yet.
    public var lookPending: Bool

    public init(
        id: UUID = UUID(), name: String, symbol: String = "tray", icon: String? = nil,
        link: WorkspaceLink? = nil, lookPending: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.icon = icon
        self.link = link
        self.lookPending = lookPending
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, icon, link, lookPending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "tray"
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        link = try container.decodeIfPresent(WorkspaceLink.self, forKey: .link)
        lookPending = try container.decodeIfPresent(Bool.self, forKey: .lookPending) ?? false
    }
}

/// Servers and workspaces of this device, in `setup.json`.
public struct DeviceSetup: Codable, Equatable, Sendable {
    public var servers: [ServerEntry]
    public var workspaces: [Workspace]
    public var current: UUID
    /// Servers whose order of workspaces changed here and that have not taken it yet. See ADR 0043.
    public var orderPending: [UUID]

    public init(servers: [ServerEntry], workspaces: [Workspace], current: UUID, orderPending: [UUID] = []) {
        self.servers = servers
        self.workspaces = workspaces
        self.current = current
        self.orderPending = orderPending
    }

    private enum CodingKeys: String, CodingKey {
        case servers, workspaces, current, orderPending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servers = try container.decode([ServerEntry].self, forKey: .servers)
        workspaces = try container.decode([Workspace].self, forKey: .workspaces)
        current = try container.decode(UUID.self, forKey: .current)
        orderPending = try container.decodeIfPresent([UUID].self, forKey: .orderPending) ?? []
    }

    public func server(_ id: UUID?) -> ServerEntry? {
        guard let id else { return nil }
        return servers.first { $0.id == id }
    }

    /// Moves the workspaces at `offsets` in front of the one at `destination`, like `List.onMove`.
    /// The order is the order of the switcher. See ADR 0043.
    public mutating func moveWorkspaces(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let valid = offsets.filter { workspaces.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { workspaces[$0] }
        let before = valid.filter { $0 < destination }.count
        for index in valid.reversed() { workspaces.remove(at: index) }
        let target = min(max(destination - before, 0), workspaces.count)
        workspaces.insert(contentsOf: moving, at: target)
    }

    /// Moves one workspace a number of places up (negative) or down, stopping at the ends.
    public mutating func moveWorkspace(_ id: UUID, by step: Int) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + step, 0), workspaces.count - 1)
        guard target != index else { return }
        let workspace = workspaces.remove(at: index)
        workspaces.insert(workspace, at: target)
    }

    /// Server workspaces of `server` that no workspace here syncs with yet.
    public func unlinked(_ remotes: [RemoteWorkspace], on server: UUID) -> [RemoteWorkspace] {
        remotes.filter { remote in
            !workspaces.contains { $0.link?.server == server && $0.link?.remote == remote.id }
        }
    }

    /// Adds a workspace here for each server workspace, linked to it, with its name and symbol.
    /// On a fresh device the one empty local workspace takes the first, instead of staying behind
    /// as an empty extra. `isEmpty` says whether a workspace has no notes. Returns the ids used.
    /// See ADR 0044.
    @discardableResult
    public mutating func addLinked(
        _ remotes: [RemoteWorkspace], on server: UUID, isEmpty: (UUID) -> Bool
    ) -> [UUID] {
        var added: [UUID] = []
        for remote in unlinked(remotes, on: server) {
            let link = WorkspaceLink(server: server, remote: remote.id)
            if added.isEmpty, workspaces.count == 1, workspaces[0].link == nil, isEmpty(workspaces[0].id) {
                workspaces[0].name = remote.name
                workspaces[0].symbol = remote.symbol ?? workspaces[0].symbol
                workspaces[0].icon = nil
                workspaces[0].link = link
                workspaces[0].lookPending = false
                added.append(workspaces[0].id)
                continue
            }
            let workspace = Workspace(name: remote.name, symbol: remote.symbol ?? "tray", link: link)
            workspaces.append(workspace)
            added.append(workspace.id)
        }
        return added
    }

    /// Marks the order as changed for every server that has workspaces here.
    public mutating func markOrderChanged() {
        for workspace in workspaces {
            if let server = workspace.link?.server, !orderPending.contains(server) { orderPending.append(server) }
        }
    }

    /// Takes what a sync made of `snapshot`, keeping everything changed here in the meantime.
    /// A workspace, the order and the pending orders each count as one piece.
    public mutating func adopt(_ synced: DeviceSetup, since snapshot: DeviceSetup) {
        for updated in synced.workspaces {
            guard let index = workspaces.firstIndex(where: { $0.id == updated.id }),
                  workspaces[index] == snapshot.workspaces.first(where: { $0.id == updated.id }) else { continue }
            workspaces[index] = updated
        }
        if workspaces.map(\.id) == snapshot.workspaces.map(\.id) {
            let rank = Dictionary(uniqueKeysWithValues: synced.workspaces.enumerated().map { ($1.id, $0) })
            workspaces = workspaces.enumerated()
                .sorted { (rank[$0.element.id] ?? $0.offset) < (rank[$1.element.id] ?? $1.offset) }
                .map(\.element)
        }
        if orderPending == snapshot.orderPending {
            orderPending = synced.orderPending
        }
    }
}

/// What a device signed in to before there were several servers.
public struct LegacySignIn: Equatable, Sendable {
    public var url: String
    public var accountName: String
    public var accountID: String

    public init(url: String, accountName: String, accountID: String) {
        self.url = url
        self.accountName = accountName
        self.accountID = accountID
    }
}

@MainActor
public enum Workspaces {
    static let setupFile = "setup.json"
    static let folder = "workspaces"
    static let iconFolder = "icons"

    /// Loads the setup under `base`, or makes one from the single library of older versions.
    /// That library becomes the workspace "Privat", synced with `main` of the account it was signed in to.
    /// Returns the server made from `legacy`, so the caller can move its session token.
    public static func open(base: URL, legacy: LegacySignIn?) throws -> (setup: DeviceSetup, migrated: ServerEntry?) {
        let manager = FileManager.default
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent(setupFile)
        if manager.fileExists(atPath: url.path) {
            let setup = try InkhashJSON.decode(DeviceSetup.self, from: Data(contentsOf: url))
            try adoptLibrary(base: base, into: setup)
            return (setup, nil)
        }
        let signedIn = legacy.flatMap { $0.accountID.isEmpty || $0.url.isEmpty ? nil : $0 }
        let server = legacy.flatMap { $0.url.isEmpty ? nil : ServerEntry(url: $0.url, accountName: $0.accountName, accountID: signedIn?.accountID ?? "") }
        // The old library is opened first: it may itself still migrate from the store-per-account layout.
        let library = try Library.open(base: base, signedInAccount: signedIn?.accountID)
        let link: WorkspaceLink?
        if let server, let bound = library.boundAccount(), bound == signedIn?.accountID {
            link = WorkspaceLink(server: server.id, remote: APIClient.mainWorkspace)
        } else {
            link = nil
        }
        let privat = Workspace(name: "Privat", symbol: "house", link: link)
        let setup = DeviceSetup(servers: server.map { [$0] } ?? [], workspaces: [privat], current: privat.id)
        // Setup first, then the move: a crash in between is finished by `adoptLibrary` on the next start.
        try save(setup, base: base)
        try adoptLibrary(base: base, into: setup)
        return (setup, server)
    }

    public static func save(_ setup: DeviceSetup, base: URL) throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try InkhashJSON.encode(setup).write(to: base.appendingPathComponent(setupFile), options: .atomic)
    }

    public static func root(of workspace: UUID, base: URL) -> URL {
        base.appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(workspace.uuidString.lowercased(), isDirectory: true)
    }

    public static func store(of workspace: UUID, base: URL) throws -> LocalStore {
        try LocalStore(root: root(of: workspace, base: base))
    }

    /// Removes a workspace and its notes from this device. Its server copy stays.
    public static func removeFiles(of workspace: UUID, base: URL) throws {
        let url = root(of: workspace, base: base)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func iconURL(_ sha256: String, base: URL) -> URL {
        base.appendingPathComponent(iconFolder, isDirectory: true).appendingPathComponent(sha256 + ".png")
    }

    /// Writes a picture made by `WorkspaceImage.normalize` and returns its sha256,
    /// which is also its name on the server.
    @discardableResult
    public static func saveIcon(_ png: Data, base: URL) throws -> String {
        let sha = sha256Hex(png)
        let url = iconURL(sha, base: base)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try png.write(to: url, options: .atomic)
        }
        return sha
    }

    /// Removes pictures no workspace shows anymore.
    public static func pruneIcons(keeping setup: DeviceSetup, base: URL) throws {
        let folder = base.appendingPathComponent(iconFolder, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        let used = Set(setup.workspaces.compactMap(\.icon).map { $0 + ".png" })
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where !used.contains(name) {
            try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// What a workspace's library is bound to. `main` keeps the bare account id that
    /// libraries before workspaces wrote, so they continue without uploading everything again.
    /// `epoch` counts resets of the account's vault: after one, the server holds none of the old
    /// notes, so every library binds anew and sends all its notes again. See ADR 0052.
    public static func bindingKey(accountID: String, remote: String, epoch: Int = 0) -> String {
        let base = remote == APIClient.mainWorkspace ? accountID : accountID + "/" + remote
        return epoch > 0 ? base + "#\(epoch)" : base
    }

    private static func adoptLibrary(base: URL, into setup: DeviceSetup) throws {
        let manager = FileManager.default
        let libraryRoot = base.appendingPathComponent(Library.folder, isDirectory: true)
        guard manager.fileExists(atPath: libraryRoot.path), let first = setup.workspaces.first else { return }
        let target = root(of: first.id, base: base)
        guard !manager.fileExists(atPath: target.path) else { return }
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.moveItem(at: libraryRoot, to: target)
    }
}
