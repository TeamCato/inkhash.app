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
    public var link: WorkspaceLink?

    public init(id: UUID = UUID(), name: String, symbol: String = "tray", link: WorkspaceLink? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.link = link
    }
}

/// Servers and workspaces of this device, in `setup.json`.
public struct DeviceSetup: Codable, Equatable, Sendable {
    public var servers: [ServerEntry]
    public var workspaces: [Workspace]
    public var current: UUID

    public init(servers: [ServerEntry], workspaces: [Workspace], current: UUID) {
        self.servers = servers
        self.workspaces = workspaces
        self.current = current
    }

    public func server(_ id: UUID?) -> ServerEntry? {
        guard let id else { return nil }
        return servers.first { $0.id == id }
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

    /// What a workspace's library is bound to. `main` keeps the bare account id that
    /// libraries before workspaces wrote, so they continue without uploading everything again.
    public static func bindingKey(accountID: String, remote: String) -> String {
        remote == APIClient.mainWorkspace ? accountID : accountID + "/" + remote
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
