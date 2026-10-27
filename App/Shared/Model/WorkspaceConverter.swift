import Foundation
import InkhashCore
import KennelKit

/// Turns an encrypted Kennel workspace into a plain one when the person asks („Unverschlüsselt weiterführen …“,
/// ADR 0085), finishes it once everything is in the successor, and lets other devices follow. Nothing converts on its
/// own (ADR 0082); decisions come from `ConversionPlanner`.
@MainActor
final class WorkspaceConverter {
    private let registry: WorkspaceRegistry
    private let status: StatusLine

    init(registry: WorkspaceRegistry, status: StatusLine) {
        self.registry = registry
        self.status = status
    }

    /// Starts the conversion of an encrypted workspace whose notes this device has all read with the key: a plain
    /// successor on the same storage with the same name takes them, the old one goes once they are up. Nil when it
    /// began, else why not.
    func convert(_ id: UUID, kennel: ServerEntry, client: APIClient, module: ModuleInfo, key: VaultKey?) async throws -> String? {
        guard let workspace = registry.workspace(id), let link = workspace.link, link.sealed, link.server == kennel.id,
              workspace.retiring == nil else { return nil }
        guard module.plainWorkspaces == true else {
            return "Dieser Kennel legt keine unverschlüsselten Workspaces an. Bitte Kennel aktualisieren."
        }
        guard let key else { return "Schalte zuerst die Verschlüsselung auf diesem Gerät frei." }
        let remotes = try await client.workspaceList().workspaces
        guard let old = remotes.first(where: { $0.id == link.remote }) else { return "Diesen Workspace gibt es in Kennel nicht mehr." }
        if old.move?.isRunning == true { return "Der Workspace zieht gerade um. Versuch es danach noch einmal." }
        // The newest state first: every note this device has not read yet comes down, everything changed here goes up.
        let store = registry.store(for: id)
        var scoped = client
        scoped.workspace = link.remote
        try Library.bind(store, to: Workspaces.bindingKey(accountID: kennel.accountID, remote: link.remote, epoch: key.epoch))
        let report = try await Syncer.sync(
            store: store, transport: SealedTransport(wire: scoped, sealer: Sealer(key)), sealedWith: key.keyId)
        guard report.rejected.isEmpty, report.conflicts == 0 else {
            return "Erst die Konflikte und abgelehnten Notizen in „\(workspace.name)“ lösen."
        }
        let taken = registry.remotesTaken(besides: id)
        let successor = try await Conversion.successor(of: old, named: workspace.name, remotes: remotes, taken: taken, wire: client)
        registry.moveOn(
            id, to: WorkspaceLink(server: kennel.id, remote: successor.id, sealed: false),
            retiring: RetiringRemote(remote: old.id, cursor: try store.cursor(), deletes: true))
        status.message = "„\(workspace.name)“ wird unverschlüsselt weitergeführt …"
        return nil
    }

    /// A linked workspace whose Kennel copy is gone, e.g. because another device converted it and removed the old one,
    /// follows the plain successor that holds its notes instead of losing its link (ADR 0085). Without one it is left
    /// to the look sync, which keeps it here only.
    func follow(kennel: ServerEntry, client: APIClient, remotes: [RemoteWorkspace]) async throws {
        let present = Set(remotes.map(\.id))
        for workspace in registry.workspaces {
            guard let link = workspace.link, link.server == kennel.id, !present.contains(link.remote) else { continue }
            do {
                let store = registry.store(for: workspace.id)
                let taken = registry.remotesTaken(besides: workspace.id)
                let candidates = ConversionPlanner.candidates(named: workspace.name, among: remotes, taken: taken)
                guard !candidates.isEmpty else { continue }
                let notes = try store.list()
                let overlap = try await Conversion.overlap(of: candidates, with: Set(notes.map(\.note.id)), wire: client)
                guard let successor = ConversionPlanner.successor(
                    among: candidates, overlap: overlap, hasSyncedNotes: notes.contains { $0.note.revision > 0 })
                else { continue }
                registry.moveOn(
                    workspace.id, to: WorkspaceLink(server: kennel.id, remote: successor.id, sealed: successor.isSealed),
                    retiring: RetiringRemote(remote: link.remote, cursor: 0, deletes: false))
                status.message = "„\(workspace.name)“ gleicht jetzt mit seinem Nachfolger in Kennel ab."
            } catch let error where Self.endsTheRound(error) {
                throw error
            } catch {
                // The look sync then keeps it here only; nothing is lost.
                continue
            }
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
}
