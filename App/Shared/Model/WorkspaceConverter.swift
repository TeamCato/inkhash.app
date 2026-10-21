import Foundation
import InkhashCore
import KennelKit

/// Converts encrypted Kennel workspaces into plain ones and follows conversions made on other devices
/// (teamCato ADR 0009 point 10, ADR 0077). Decisions come from `ConversionPlanner`; this class gathers the facts,
/// does the network steps and writes what it did to the registry before any note goes up.
@MainActor
final class WorkspaceConverter {
    /// What the round found waiting, by workspace name.
    struct Waiting: Equatable {
        var forKey: [String] = []
        var forKennel: [String] = []
    }

    private let registry: WorkspaceRegistry
    private let status: StatusLine
    /// Hears of notes a sealed sync of the current workspace wrote, like the normal sync.
    var synced: (Note, LocalMeta) -> Void = { _, _ in }

    init(registry: WorkspaceRegistry, status: StatusLine) {
        self.registry = registry
        self.status = status
    }

    /// One round over every workspace linked to an encrypted Kennel workspace. `remotes` is Kennel's list from this
    /// round; `key` the vault key, if open here.
    func run(kennel: ServerEntry, client: APIClient, remotes: [RemoteWorkspace], module: ModuleInfo, key: VaultKey?) async throws -> Waiting {
        var waiting = Waiting()
        for workspace in registry.workspaces {
            guard let link = workspace.link, link.sealed, link.server == kennel.id else { continue }
            do {
                try await step(workspace, link: link, kennel: kennel, client: client, remotes: remotes, module: module, key: key, waiting: &waiting)
            } catch let error where Self.endsTheRound(error) {
                throw error
            } catch {
                // One workspace that fails must not hold back the others; the next round tries again.
                status.message = "„\(workspace.name)“: \(StatusLine.describe(error))"
            }
        }
        return waiting
    }

    private func step(
        _ workspace: Workspace, link: WorkspaceLink, kennel: ServerEntry, client: APIClient, remotes: [RemoteWorkspace],
        module: ModuleInfo, key: VaultKey?, waiting: inout Waiting
    ) async throws {
        let store = registry.store(for: workspace.id)
        let taken = registry.remotesTaken(besides: workspace.id)
        let old = remotes.first { $0.id == link.remote }
        let readable = try await old == nil ? false : isReadable(workspace, link: link, store: store, kennel: kennel, client: client, key: key)
        let candidates = ConversionPlanner.candidates(named: workspace.name, among: remotes, taken: taken)
        let overlap = old == nil && !candidates.isEmpty
            ? try await Conversion.overlap(of: candidates, with: Set(try store.list().map(\.note.id)), wire: client)
            : [:]
        let step = ConversionPlanner.step(
            name: workspace.name, link: link, remotes: remotes, taken: taken, readable: readable,
            canPlain: module.plainWorkspaces == true, overlap: overlap,
            hasSyncedNotes: try store.list().contains { $0.note.revision > 0 })
        switch step {
        case .waitForKey:
            waiting.forKey.append(workspace.name)
        case .waitForKennel:
            waiting.forKennel.append(workspace.name)
        case .convert:
            guard let old else { return }
            let successor = try await Conversion.successor(of: old, named: workspace.name, remotes: remotes, taken: taken, wire: client)
            let cursor = isBound(store, to: link, kennel: kennel) ? try store.cursor() : 0
            registry.moveOn(
                workspace.id, to: WorkspaceLink(server: kennel.id, remote: successor.id, sealed: false),
                retiring: RetiringRemote(remote: old.id, cursor: cursor, deletes: true))
            status.message = "„\(workspace.name)“ wird in einen unverschlüsselten Workspace umgewandelt …"
        case .follow(let successor):
            registry.moveOn(
                workspace.id, to: WorkspaceLink(server: kennel.id, remote: successor.id, sealed: false),
                retiring: RetiringRemote(remote: link.remote, cursor: 0, deletes: false))
            status.message = "„\(workspace.name)“ gleicht jetzt unverschlüsselt ab."
        case .keepHere:
            registry.setLink(workspace.id, to: nil)
            status.message = "„\(workspace.name)“ gibt es in Kennel nicht mehr. Er bleibt auf diesem Gerät."
        }
    }

    /// No session, or no Kennel at all: the round stops instead of trying every workspace.
    static func endsTheRound(_ error: Error) -> Bool {
        switch error {
        case APIError.unauthorized, KennelError.unreachable, is URLError: true
        default: false
        }
    }

    /// After a plain sync of a workspace that left an encrypted one: once everything is up, the converting device
    /// removes the old one, unless another device wrote there meanwhile; those notes come along first. Returns true
    /// if another round should follow.
    func finish(_ workspace: Workspace, report: SyncReport, client: APIClient, key: VaultKey?) async throws -> Bool {
        guard let retiring = workspace.retiring, report.rejected.isEmpty else { return false }
        let store = registry.store(for: workspace.id)
        // Nothing may be lost: every note must be up in the successor first.
        guard try !store.list().contains(where: { $0.meta.dirty && !$0.meta.conflict }) else { return false }
        guard retiring.deletes else {
            registry.setRetiring(workspace.id, nil)
            return false
        }
        let old = client.notes(of: retiring.remote)
        do {
            if try await !Conversion.hasChanges(after: retiring.cursor, in: old) {
                try await client.deleteWorkspace(id: retiring.remote)
                registry.setRetiring(workspace.id, nil)
                status.message = "„\(workspace.name)“ ist umgewandelt und liegt jetzt unverschlüsselt in Kennel."
                return false
            }
            // Another device wrote to the old one meanwhile. Without the key, a device that has it takes over.
            guard let key else { return false }
            var oldClient = client
            oldClient.workspace = retiring.remote
            let cursor = try await Relinker.takeLate(
                from: SealedTransport(wire: oldClient, sealer: Sealer(key)), after: retiring.cursor, into: store)
            registry.setRetiring(workspace.id, RetiringRemote(remote: retiring.remote, cursor: cursor, deletes: true))
            return true
        } catch APIError.notFound {
            // Removed already, e.g. by another device that converted it too.
            registry.setRetiring(workspace.id, nil)
            return false
        }
    }

    /// Whether this device holds the newest state of the encrypted workspace: with the key, after a sealed sync that
    /// went through; without, when Kennel has nothing it has not read.
    private func isReadable(
        _ workspace: Workspace, link: WorkspaceLink, store: LocalStore, kennel: ServerEntry, client: APIClient, key: VaultKey?
    ) async throws -> Bool {
        var scoped = client
        scoped.workspace = link.remote
        if let key {
            try Library.bind(store, to: Workspaces.bindingKey(accountID: kennel.accountID, remote: link.remote, epoch: key.epoch))
            let report = try await Syncer.sync(
                store: store, transport: SealedTransport(wire: scoped, sealer: Sealer(key)), sealedWith: key.keyId
            ) { [weak self, registry] note, meta in
                guard workspace.id == registry.current.id else { return }
                self?.synced(note, meta)
            }
            return report.rejected.isEmpty
        }
        let cursor = isBound(store, to: link, kennel: kennel) ? try store.cursor() : 0
        return try await !Conversion.hasChanges(after: cursor, in: scoped)
    }

    /// The library was bound to this encrypted workspace, whatever the vault's epoch.
    private func isBound(_ store: LocalStore, to link: WorkspaceLink, kennel: ServerEntry) -> Bool {
        guard let bound = store.boundAccount() else { return false }
        let plain = bound.split(separator: "#", maxSplits: 1).first.map(String.init) ?? bound
        return plain == Workspaces.bindingKey(accountID: kennel.accountID, remote: link.remote)
    }
}
