import Foundation

/// Workspace looks through a vault key: pictures go up encrypted under their sealed name, and
/// sealed names coming back are turned into the plain hashes the device keeps. Names and symbols
/// stay plain (ADR 0052). A plain picture from before the vault is reported, so `LookSyncer`
/// puts it up again sealed.
public final class SealedLooks: WorkspaceTransport, @unchecked Sendable {
    private let inner: any WorkspaceTransport
    private let sealer: Sealer
    private let lock = NSLock()
    /// Plain hash by sealed name, for the pictures this device has.
    private var known: [String: String]
    /// Pictures fetched while reading the list, by plain hash.
    private var fetched: [String: Data] = [:]
    /// Workspaces whose picture on the server is plain.
    private var stale: Set<String> = []

    /// `icons`: plain hashes of the pictures on this device.
    public init(inner: any WorkspaceTransport, sealer: Sealer, icons: [String]) {
        self.inner = inner
        self.sealer = sealer
        known = Dictionary(icons.map { (sealer.blobName($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func workspaceList() async throws -> RemoteWorkspaceList {
        var list = try await inner.workspaceList()
        for index in list.workspaces.indices {
            list.workspaces[index] = try await plainLook(list.workspaces[index])
        }
        return list
    }

    public func updateWorkspace(id: String, look: WorkspaceLook) async throws -> RemoteWorkspace {
        var sealedLook = look
        sealedLook.icon = look.icon.map(sealer.blobName)
        if let icon = look.icon { lock.withLock { known[sealer.blobName(icon)] = icon } }
        let updated = try await inner.updateWorkspace(id: id, look: sealedLook)
        _ = lock.withLock { stale.remove(id) }
        return try await plainLook(updated)
    }

    public func orderWorkspaces(ids: [String]) async throws -> RemoteWorkspaceList {
        var list = try await inner.orderWorkspaces(ids: ids)
        for index in list.workspaces.indices {
            list.workspaces[index] = try await plainLook(list.workspaces[index])
        }
        return list
    }

    public func putIcon(workspace: String, sha256: String, data: Data) async throws {
        try await inner.putIcon(workspace: workspace, sha256: sealer.blobName(sha256), data: try sealer.sealBlob(data, plain: sha256))
    }

    public func fetchIcon(workspace: String, sha256: String) async throws -> Data {
        if let data = lock.withLock({ fetched[sha256] }) { return data }
        do {
            return try sealer.openBlob(try await inner.fetchIcon(workspace: workspace, sha256: sealer.blobName(sha256)), plain: sha256)
        } catch APIError.notFound {
            let data = try await inner.fetchIcon(workspace: workspace, sha256: sha256)
            guard sha256Hex(data) == sha256 else { throw SealError.wrongBlob }
            return data
        }
    }

    public func needsReupload(_ remote: RemoteWorkspace) -> Bool {
        lock.withLock { stale.contains(remote.id) }
    }

    /// The look with its picture named by the plain hash.
    private func plainLook(_ remote: RemoteWorkspace) async throws -> RemoteWorkspace {
        guard let name = remote.icon else { return remote }
        var look = remote
        if let plain = lock.withLock({ known[name] }) {
            look.icon = plain
            return look
        }
        let data = try await inner.fetchIcon(workspace: remote.id, sha256: name)
        if sha256Hex(data) == name {
            // Plain, from before the vault.
            lock.withLock {
                stale.insert(remote.id)
                fetched[name] = data
            }
            return look
        }
        let opened = try sealer.openBlob(data, name: name)
        let plain = sha256Hex(opened)
        guard sealer.blobName(plain) == name else { throw SealError.wrongBlob }
        lock.withLock {
            known[name] = plain
            fetched[plain] = opened
        }
        look.icon = plain
        return look
    }
}
