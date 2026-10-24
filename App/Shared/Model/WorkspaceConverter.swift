import Foundation
import InkhashCore
import KennelKit

/// Finishes conversions of encrypted workspaces into plain ones that began under ADR 0077: once everything is in the
/// successor, the old workspace goes. inkhash starts no new conversions (ADR 0082); encrypted workspaces sync sealed.
@MainActor
final class WorkspaceConverter {
    private let registry: WorkspaceRegistry
    private let status: StatusLine

    init(registry: WorkspaceRegistry, status: StatusLine) {
        self.registry = registry
        self.status = status
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
