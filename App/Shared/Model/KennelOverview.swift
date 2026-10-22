import Foundation
import InkhashCore
import KennelKit
import Observation

/// What this device last learned from its Kennel: the sync state for the status line, the account's workspaces and
/// the storages inkhash may use. Filled by `SyncCoordinator`; the views read places and storages here instead of
/// asking Kennel themselves (teamCato ADR 0009, ADR 0077).
@MainActor
@Observable
final class KennelOverview {
    var state = KennelSyncState()
    /// The account's Kennel workspaces, in its order.
    var remotes: [RemoteWorkspace] = []
    /// Storages inkhash may put notes in, without the account's own.
    var storages: [KennelStorage] = []
    /// The account's binding for inkhash: where workspaces without `storageId` lie. `nil`: Kennel's default storage.
    var standardStorageID: String?
    /// What the module can do; nil until Kennel answered.
    var module: ModuleInfo?

    /// Back to nothing known, e.g. after disconnecting.
    func reset() {
        state = KennelSyncState()
        remotes = []
        storages = []
        standardStorageID = nil
        module = nil
    }

    func remote(of workspace: Workspace) -> RemoteWorkspace? {
        guard let link = workspace.link else { return nil }
        return remotes.first { $0.id == link.remote }
    }

    /// „Nur hier“, „Abgeglichen“ or „Zieht um“: a workspace always lies on the device too, so never „In Kennel“.
    func place(of workspace: Workspace) -> KennelPlace {
        guard workspace.link != nil else { return .here }
        return remote(of: workspace)?.move?.isRunning == true ? .moving : .synced
    }

    /// Name and visibility of the storage a Kennel workspace lies in.
    func storage(of remote: RemoteWorkspace?) -> (name: String, visibility: KennelVisibility)? {
        guard let remote else { return nil }
        guard let id = remote.storageId else {
            let standard = KennelStorages.standard(in: storages, id: standardStorageID)
            return (standard?.name ?? "Standard", standard?.visibility ?? .household)
        }
        guard let storage = storages.first(where: { $0.id == id }) else { return nil }
        return (storage.name, storage.visibility)
    }

    /// The storages for pickers and the Kennel page: „Standard“ first, with how many workspaces lie in each.
    var summaries: [KennelStorageSummary] {
        let all = KennelStorages.summaries(storages, standardID: standardStorageID, remotes: remotes)
        return module?.workspaceStorage == true ? all : Array(all.prefix(1))
    }

    /// Kennel workspaces no workspace here syncs with.
    func unlinked(in setup: DeviceSetup) -> [RemoteWorkspace] {
        guard let kennel = setup.servers.first else { return [] }
        return setup.unlinked(remotes, on: kennel.id)
    }
}
