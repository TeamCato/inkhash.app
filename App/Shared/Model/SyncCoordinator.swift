import Foundation
import InkhashCore

/// When and what to sync: waits for a pause in editing, then syncs the look and order of the
/// workspaces and every linked library. See ADR 0017, 0020, 0043 and PITFALLS P-053.
@MainActor
final class SyncCoordinator {
    private let registry: WorkspaceRegistry
    private let sessions: ServerSessions
    private let library: NoteLibrary
    private let status: StatusLine
    private var waiting: Task<Void, Never>?
    private var isSyncing = false
    private var again = false
    /// Called after each round, once the library is read again.
    var finished: () -> Void = {}

    init(registry: WorkspaceRegistry, sessions: ServerSessions, library: NoteLibrary, status: StatusLine) {
        self.registry = registry
        self.sessions = sessions
        self.library = library
        self.status = status
    }

    /// True if the workspace syncs right now: linked to a server with a session.
    func syncs(_ workspace: Workspace) -> Bool {
        guard let link = workspace.link else { return false }
        return sessions.isSignedIn(link.server)
    }

    var isEnabled: Bool { syncs(registry.current) }

    /// What the status line says while nothing happens.
    var statusAtRest: String {
        guard let link = registry.current.link, let server = registry.server(link.server) else { return StatusLine.localOnly }
        return sessions.isSignedIn(server.id) ? "" : "Abgleich mit \(ServerAddress.host(server.url)) ruht."
    }

    /// Waits for a pause in editing, then syncs. A new edit only restarts the wait: cancelling
    /// a running sync would drop a request the server may already have stored.
    func schedule() {
        guard isEnabled else { return }
        waiting?.cancel()
        waiting = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            Task { await self.sync() }
        }
    }

    /// Syncs every workspace that is linked to a signed-in server. The current one reports its status.
    /// A call during a running sync makes it go round once more instead of being dropped.
    func sync() async {
        guard !isSyncing else {
            again = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            again = false
            await syncOnce()
        } while again
    }

    private func syncOnce() async {
        await syncLooks()
        for workspace in registry.workspaces {
            guard let link = workspace.link, let entry = registry.server(link.server),
                  let client = sessions.client(for: link.server, workspace: link.remote) else { continue }
            let isCurrent = workspace.id == registry.current.id
            let store = registry.store(for: workspace.id)
            do {
                // Binding is idempotent. A different account or workspace on the server starts over.
                try Library.bind(store, to: Workspaces.bindingKey(accountID: entry.accountID, remote: link.remote))
                let report = try await Syncer.sync(store: store, transport: client) { [weak self] note, meta in
                    guard let self, workspace.id == self.registry.current.id else { return }
                    self.library.synced(note, meta: meta)
                }
                if isCurrent { status.message = describe(report) }
            } catch APIError.unauthorized {
                sessions.expire(link.server, ifStill: client.token)
            } catch {
                if isCurrent { status.message = StatusLine.describe(error) }
            }
        }
        library.reload()
        finished()
        if !isEnabled { status.message = statusAtRest }
    }

    /// Look and order of workspaces, per server, before the notes. See ADR 0043.
    private func syncLooks() async {
        let linked = Set(registry.workspaces.compactMap { $0.link?.server })
        for server in registry.servers.map(\.id) where linked.contains(server) {
            guard let client = sessions.client(for: server) else { continue }
            let snapshot = registry.setup
            do {
                let synced = try await LookSyncer.sync(snapshot, server: server, base: registry.base, transport: client)
                registry.adopt(synced, since: snapshot)
            } catch APIError.unauthorized {
                sessions.expire(server, ifStill: client.token)
            } catch {
                // Pending looks and orders stay marked and go out with the next sync.
                if registry.current.link?.server == server { status.message = StatusLine.describe(error) }
            }
        }
    }

    private func describe(_ report: SyncReport) -> String {
        if let first = report.rejected.first {
            let title = library.record(first)?.note.displayTitle ?? Note.untitled
            return report.rejected.count == 1
                ? "Der Server lehnt „\(title)“ ab."
                : "Der Server lehnt \(report.rejected.count) Notizen ab, darunter „\(title)“."
        }
        return report.conflicts > 0 ? "Konflikt mit dem Server." : "Abgeglichen."
    }
}
