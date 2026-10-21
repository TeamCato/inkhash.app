import Foundation

/// Workspace looks for a mix of encrypted and plain workspaces. Pictures of an encrypted workspace go up encrypted
/// under their sealed name when the vault key is here, and sealed names coming back are turned into the plain hashes
/// the device keeps. Pictures of a plain workspace go up plain (ADR 0077). Names and symbols stay plain (ADR 0052).
/// A picture in the wrong form for its workspace is reported, so `LookSyncer` puts it up again; one this device
/// cannot read without the key is left alone.
public final class SealedLooks: WorkspaceTransport, @unchecked Sendable {
    private let inner: any WorkspaceTransport
    private let sealer: Sealer?
    private let isSealed: @Sendable (String) -> Bool
    private let lock = NSLock()
    /// Plain hash by sealed name, for the pictures this device has.
    private var known: [String: String]
    /// Plain hashes of the pictures this device has.
    private let local: Set<String>
    /// Pictures fetched while reading the list, by plain hash.
    private var fetched: [String: Data] = [:]
    /// Workspaces whose picture on the server has the wrong form.
    private var stale: Set<String> = []
    /// Workspaces whose picture this device cannot read.
    private var opaque: Set<String> = []

    /// Every workspace encrypted, as before ADR 0075. `icons`: plain hashes of the pictures on this device.
    public convenience init(inner: any WorkspaceTransport, sealer: Sealer, icons: [String]) {
        self.init(inner: inner, sealer: sealer, sealed: { _ in true }, icons: icons)
    }

    /// `sealer` nil: the vault is not open here. `sealed` says which Kennel workspaces are encrypted.
    public init(inner: any WorkspaceTransport, sealer: Sealer?, sealed: @escaping @Sendable (String) -> Bool, icons: [String]) {
        self.inner = inner
        self.sealer = sealer
        isSealed = sealed
        local = Set(icons)
        known = sealer.map { sealer in
            Dictionary(icons.map { (sealer.blobName($0), $0) }, uniquingKeysWith: { first, _ in first })
        } ?? [:]
    }

    public func workspaceList() async throws -> RemoteWorkspaceList {
        var list = try await inner.workspaceList()
        for index in list.workspaces.indices {
            list.workspaces[index] = try await plainLook(list.workspaces[index])
        }
        return list
    }

    public func updateWorkspace(id: String, look: WorkspaceLook) async throws -> RemoteWorkspace {
        var sent = look
        if let sealer = sealing(id), let icon = look.icon {
            sent.icon = sealer.blobName(icon)
            lock.withLock { known[sealer.blobName(icon)] = icon }
        }
        let updated = try await inner.updateWorkspace(id: id, look: sent)
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
        if let sealer = sealing(workspace) {
            try await inner.putIcon(workspace: workspace, sha256: sealer.blobName(sha256), data: try sealer.sealBlob(data, plain: sha256))
        } else {
            try await inner.putIcon(workspace: workspace, sha256: sha256, data: data)
        }
    }

    public func fetchIcon(workspace: String, sha256: String) async throws -> Data {
        if let data = lock.withLock({ fetched[sha256] }) { return data }
        if let sealer = sealing(workspace) {
            do {
                return try sealer.openBlob(try await inner.fetchIcon(workspace: workspace, sha256: sealer.blobName(sha256)), plain: sha256)
            } catch APIError.notFound {
                // Plain, from before the vault.
            }
        }
        let data = try await inner.fetchIcon(workspace: workspace, sha256: sha256)
        guard sha256Hex(data) == sha256 else { throw SealError.wrongBlob }
        return data
    }

    public func needsReupload(_ remote: RemoteWorkspace) -> Bool {
        lock.withLock { stale.contains(remote.id) }
    }

    public func hidesIcon(_ remote: RemoteWorkspace) -> Bool {
        lock.withLock { opaque.contains(remote.id) }
    }

    /// An encrypted workspace's look is written only with the key: Kennel takes no plain picture there.
    public func writesLook(of remote: String) -> Bool {
        !isSealed(remote) || sealer != nil
    }

    /// The key for this workspace's pictures, or nil when they go plain.
    private func sealing(_ workspace: String) -> Sealer? {
        isSealed(workspace) ? sealer : nil
    }

    /// The look with its picture named by the plain hash.
    private func plainLook(_ remote: RemoteWorkspace) async throws -> RemoteWorkspace {
        guard let name = remote.icon else { return remote }
        var look = remote
        if let plain = lock.withLock({ known[name] }) {
            look.icon = plain
            return look
        }
        // A plain picture this device has already; in an encrypted workspace it still goes up sealed.
        if local.contains(name), sealing(remote.id) == nil { return look }
        let data = try await inner.fetchIcon(workspace: remote.id, sha256: name)
        if sha256Hex(data) == name {
            lock.withLock {
                fetched[name] = data
                // Plain in an encrypted workspace, from before the vault: up again sealed.
                if sealing(remote.id) != nil { stale.insert(remote.id) }
            }
            return look
        }
        guard let sealer else {
            _ = lock.withLock { opaque.insert(remote.id) }
            return look
        }
        let opened = try sealer.openBlob(data, name: name)
        let plain = sha256Hex(opened)
        guard sealer.blobName(plain) == name else { throw SealError.wrongBlob }
        lock.withLock {
            known[name] = plain
            fetched[plain] = opened
            // Sealed in a plain workspace, from before ADR 0077: up again plain, so devices without a key see it.
            if !isSealed(remote.id) { stale.insert(remote.id) }
        }
        look.icon = plain
        return look
    }
}
