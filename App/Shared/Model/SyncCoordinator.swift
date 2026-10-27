import Foundation
import InkhashCore
import KennelKit

/// When and what to sync: waits for a pause in editing, then asks Kennel what it holds, syncs the look and order of the
/// workspaces and every linked library, encrypted ones with the vault's key (ADR 0082). Reports to `KennelOverview`,
/// whose state becomes the status line. See ADR 0017, 0020, 0043, 0077 and PITFALLS P-053.
@MainActor
final class SyncCoordinator {
    private let registry: WorkspaceRegistry
    private let sessions: ServerSessions
    private let vaults: VaultSessions
    private let library: NoteLibrary
    private let status: StatusLine
    private let overview: KennelOverview
    private let converter: WorkspaceConverter
    private var waiting: Task<Void, Never>?
    private var isSyncing = false
    private var again = false
    /// Called after each round, once the library is read again.
    var finished: () -> Void = {}

    init(
        registry: WorkspaceRegistry, sessions: ServerSessions, vaults: VaultSessions, library: NoteLibrary,
        status: StatusLine, overview: KennelOverview
    ) {
        self.registry = registry
        self.sessions = sessions
        self.vaults = vaults
        self.library = library
        self.status = status
        self.overview = overview
        converter = WorkspaceConverter(registry: registry, status: status)
        refreshExpired()
    }

    /// True if the workspace syncs right now: linked to the Kennel with a session.
    func syncs(_ workspace: Workspace) -> Bool {
        guard let link = workspace.link else { return false }
        return sessions.isSignedIn(link.server)
    }

    /// True while a Kennel is signed in, so there is something to sync.
    var isEnabled: Bool { sessions.signedInKennel != nil }

    /// What the line at the bottom says while nothing happens. Kennel's own state is the status line above it.
    var statusAtRest: String {
        registry.current.link == nil ? StatusLine.localOnly : ""
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

    /// Syncs with the Kennel. A call during a running sync makes it go round once more instead of being dropped.
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
        defer {
            refreshExpired()
            library.reload()
            finished()
        }
        guard let kennel = registry.kennel, let client = sessions.client(for: kennel.id) else { return }
        overview.state.phase = .syncing
        do {
            let health = try await client.kennel.health()
            guard let module = health.inkhash else {
                overview.module = nil
                overview.state.phase = .moduleOff
                return
            }
            overview.module = module
            let list = try await client.workspaceList()
            overview.remotes = list.workspaces
            // Kennel decides what is encrypted (ADR 0085); a workspace whose Kennel copy went follows its successor.
            registry.adoptEncryption(of: list.workspaces, on: kennel.id)
            try await converter.follow(kennel: kennel, client: client, remotes: list.workspaces)
            if module.workspaceStorage == true {
                overview.storages = (try? await client.noteStorages()) ?? overview.storages
            }
            overview.standardStorageID = (try? await client.standardStorageID()) ?? overview.standardStorageID
            let key = await vaultKey(for: kennel.id)
            // Encrypted workspaces sync with the vault open here and wait without it (ADR 0082); nothing converts.
            overview.state.waitingForKey = key == nil
                ? registry.workspaces.filter { $0.link?.sealed == true && $0.link?.server == kennel.id }.map(\.name) : []
            overview.state.waitingForKennel = []
            await syncLooks(kennel: kennel, client: client, key: key)
            let problem = try await syncNotes(kennel: kennel, client: client, key: key)
            if let fresh = try? await client.workspaceList() { overview.remotes = fresh.workspaces }
            overview.state.phase = problem.map { .failed($0) } ?? .synced(Date())
        } catch let error where WorkspaceConverter.endsTheRound(error) {
            if case APIError.unauthorized = error {
                sessions.expire(kennel.id, ifStill: client.token)
                overview.state.phase = .idle
            } else {
                overview.state.phase = .unreachable
            }
        } catch {
            overview.state.phase = .failed(StatusLine.describe(error))
        }
    }

    /// „Unverschlüsselt weiterführen …“: begins the conversion of an encrypted workspace, then syncs so its notes go
    /// to the plain successor (ADR 0085). Nil when it began, else why not.
    func convertToPlain(_ id: UUID) async -> String? {
        guard let kennel = registry.kennel, let client = sessions.client(for: kennel.id) else { return "Nicht mit Kennel verbunden." }
        do {
            guard let module = try await client.kennel.health().inkhash else { return "inkhash ist in Kennel ausgeschaltet." }
            if vaults.key(for: kennel.id) == nil { await vaults.check(kennel.id) }
            if let problem = try await converter.convert(
                id, kennel: kennel, client: client, module: module, key: vaults.key(for: kennel.id))
            {
                return problem
            }
        } catch APIError.unauthorized {
            sessions.expire(kennel.id, ifStill: client.token)
            return "Die Anmeldung ist abgelaufen."
        } catch {
            return StatusLine.describe(error)
        }
        await sync()
        return nil
    }

    /// The vault key, only while a workspace here is encrypted. Checked against Kennel until it is open here.
    private func vaultKey(for server: UUID) async -> VaultKey? {
        guard registry.workspaces.contains(where: { $0.link?.sealed == true }) else { return nil }
        if vaults.key(for: server) == nil { await vaults.check(server) }
        return vaults.key(for: server)
    }

    /// Every linked workspace: plain ones as they are, encrypted ones sealed with the vault's key; without it they
    /// wait (ADR 0052, 0082). Returns what went wrong for the status line, if anything.
    private func syncNotes(kennel: ServerEntry, client: APIClient, key: VaultKey?) async throws -> String? {
        var problem: String?
        for workspace in registry.workspaces {
            guard let link = workspace.link, link.server == kennel.id else { continue }
            if link.sealed, key == nil { continue }
            var scoped = client
            scoped.workspace = link.remote
            let isCurrent = workspace.id == registry.current.id
            let store = registry.store(for: workspace.id)
            do {
                // A reset vault counts the epoch up: encrypted libraries start over, plain ones stay (ADR 0052).
                let epoch = link.sealed ? key?.epoch ?? 0 : 0
                let bindingKey = Workspaces.bindingKey(accountID: kennel.accountID, remote: link.remote, epoch: epoch)
                let transport: any NoteTransport =
                    if link.sealed, let key { SealedTransport(wire: scoped, sealer: Sealer(key)) } else { scoped }
                if workspace.retiring != nil {
                    // The successor holds these notes already, or the link took Kennel's word on encryption: merge, do
                    // not start over (ADR 0077, 0085).
                    try await Relinker.adopt(store, from: transport, bindingKey: bindingKey)
                } else {
                    // Idempotent. Another workspace on Kennel starts over (ADR 0017).
                    try Library.bind(store, to: bindingKey)
                }
                let report = try await Syncer.sync(
                    store: store, transport: transport, sealedWith: link.sealed ? key?.keyId : nil
                ) { [weak self] note, meta in
                    guard let self, workspace.id == self.registry.current.id else { return }
                    self.library.synced(note, meta: meta)
                }
                if let message = describe(report), isCurrent { status.message = message }
                if try await converter.finish(workspace, report: report, client: client, key: key) { again = true }
            } catch let error where WorkspaceConverter.endsTheRound(error) {
                throw error
            } catch {
                problem = problem ?? StatusLine.describe(error)
            }
        }
        return problem
    }

    /// Look and order of the workspaces, before the notes. Pictures of encrypted workspaces need the key; without it
    /// they stay as they are (ADR 0043, 0077).
    private func syncLooks(kennel: ServerEntry, client: APIClient, key: VaultKey?) async {
        guard registry.workspaces.contains(where: { $0.link?.server == kennel.id }) else { return }
        let snapshot = registry.setup
        let sealed = Set(overview.remotes.filter(\.isSealed).map(\.id))
        let transport = SealedLooks(
            inner: client, sealer: key.map(Sealer.init), sealed: { sealed.contains($0) },
            icons: snapshot.workspaces.compactMap(\.icon))
        do {
            let synced = try await LookSyncer.sync(snapshot, server: kennel.id, base: registry.base, transport: transport)
            registry.adopt(synced, since: snapshot)
            reportDeleted(before: snapshot, after: registry.setup)
        } catch APIError.unauthorized {
            sessions.expire(kennel.id, ifStill: client.token)
        } catch {
            // Pending looks and orders stay marked and go out with the next sync.
        }
    }

    private func refreshExpired() {
        overview.state.sessionExpired = registry.kennel.map { sessions.expired.contains($0.id) } ?? false
    }

    /// Workspaces whose Kennel copy was deleted, maybe on another device, stay here unlinked. See ADR 0045.
    private func reportDeleted(before: DeviceSetup, after: DeviceSetup) {
        let unlinked = after.workspaces.filter { workspace in
            workspace.link == nil && before.workspaces.contains { $0.id == workspace.id && $0.link != nil }
        }
        guard let first = unlinked.first else { return }
        status.message = unlinked.count == 1
            ? "„\(first.name)“ gibt es in Kennel nicht mehr. Er bleibt auf diesem Gerät."
            : "\(unlinked.count) Workspaces gibt es in Kennel nicht mehr. Sie bleiben auf diesem Gerät."
    }

    /// Notes Kennel refused or that are in conflict; nil when all went well.
    private func describe(_ report: SyncReport) -> String? {
        if let first = report.rejected.first {
            let title = library.record(first)?.note.displayTitle ?? Note.untitled
            return report.rejected.count == 1
                ? "Kennel lehnt „\(title)“ ab."
                : "Kennel lehnt \(report.rejected.count) Notizen ab, darunter „\(title)“."
        }
        return report.conflicts > 0 ? "Konflikt mit Kennel." : nil
    }
}
