import Foundation
import KennelKit

/// A local workspace as „Übernehmen“ needs to know it (ADR 0077).
public struct TakeOverLocal: Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// No notes and no kept folders.
    public var isEmpty: Bool
    /// What its library was last bound to (`Workspaces.bindingKey`), if it ever synced.
    public var boundKey: String?

    public init(id: UUID, name: String, isEmpty: Bool, boundKey: String? = nil) {
        self.id = id
        self.name = name
        self.isEmpty = isEmpty
        self.boundKey = boundKey
    }
}

/// What „Übernehmen“ does for one row, once the person confirmed.
public enum TakeOverAction: Equatable, Sendable {
    /// A new plain Kennel workspace for the local one, in this storage (nil: the account's).
    case place(UUID, storageID: String?)
    /// The local workspace syncs with this Kennel workspace; both sides' notes meet there.
    case link(UUID, remote: RemoteWorkspace)
    /// These Kennel workspaces come onto this device.
    case add([RemoteWorkspace])
}

/// Step 3 of „Mit Kennel verbinden“ for inkhash (teamCato ADR 0009 point 4, ADR 0077): what is on this device and not
/// in Kennel, and what Kennel has and this device not, each with a proposal. Nothing happens without „Übernehmen“.
public enum TakeOverPlanner {
    /// The account's own storage, which every account has; Kennel calls it `null`.
    public static let standardStorage = "standard"
    static let keep = "keep"
    static let add = "add"
    static let later = "later"
    static let placePrefix = "kennel:"
    static let linkPrefix = "link:"
    static let localPrefix = "local:"
    static let remotePrefix = "remote:"

    /// - Parameters:
    ///   - local: workspaces on this device that sync with nothing.
    ///   - remotes: the account's Kennel workspaces that no workspace here syncs with.
    ///   - storages: where a new Kennel workspace may go, „Standard“ first (`KennelStorages.summaries`).
    ///   - accountID: the signed-in account, to recognise a workspace that synced with it before.
    public static func plan(
        local: [TakeOverLocal], remotes: [RemoteWorkspace], storages: [KennelStorageSummary], accountID: String,
        account: String? = nil
    ) -> KennelTakeOverPlan {
        let onDevice = local.map { workspace in
            let matches = remotes.filter { remote in sameName(remote.name, workspace.name) || before(workspace, remote, accountID) }
            var choices = [KennelTakeOverChoice(id: keep, label: "Nur hier lassen")]
            choices += storages.map { KennelTakeOverChoice(id: placePrefix + $0.id, label: "In Kennel · \($0.name)") }
            choices += matches.map { KennelTakeOverChoice(id: linkPrefix + $0.id, label: "Mit „\($0.name)“ abgleichen") }
            return KennelTakeOverRow(
                id: localPrefix + workspace.id.uuidString.lowercased(), title: workspace.name,
                subtitle: workspace.isEmpty ? "Leer" : nil, choices: choices,
                proposed: proposal(for: workspace, matches: matches, storages: storages, accountID: accountID))
        }
        let inKennel = remotes.map { remote in
            KennelTakeOverRow(
                id: remotePrefix + remote.id, title: remote.name,
                subtitle: remote.isSealed ? "Verschlüsselt, wird umgewandelt" : nil,
                choices: [KennelTakeOverChoice(id: add, label: "Hinzufügen"), KennelTakeOverChoice(id: later, label: "Nicht jetzt")],
                proposed: add)
        }
        let notice = remotes.contains(where: \.isSealed)
            ? "inkhash verschlüsselt in Kennel nicht mehr. Verschlüsselte Workspaces werden zu unverschlüsselten auf demselben Speicher, sobald ein Gerät sie lesen kann. Dabei geht nichts verloren."
            : nil
        return KennelTakeOverPlan(
            onDevice: onDevice, inKennel: inKennel, account: account,
            hint: "Du kannst das später für jeden Workspace einzeln ändern.", notice: notice)
    }

    /// The answers turned into actions. A Kennel workspace chosen for a local one is not added a second time, and
    /// is linked to one local workspace at most.
    public static func actions(
        chosen: [String: String], local: [TakeOverLocal], remotes: [RemoteWorkspace]
    ) -> [TakeOverAction] {
        var actions: [TakeOverAction] = []
        var linked = Set<String>()
        for workspace in local {
            guard let answer = chosen[localPrefix + workspace.id.uuidString.lowercased()] else { continue }
            if answer.hasPrefix(placePrefix) {
                let storage = String(answer.dropFirst(placePrefix.count))
                actions.append(.place(workspace.id, storageID: storage == standardStorage ? nil : storage))
            } else if answer.hasPrefix(linkPrefix) {
                let id = String(answer.dropFirst(linkPrefix.count))
                guard let remote = remotes.first(where: { $0.id == id }), linked.insert(id).inserted else { continue }
                actions.append(.link(workspace.id, remote: remote))
            }
        }
        let added = remotes.filter { chosen[remotePrefix + $0.id] == add && !linked.contains($0.id) }
        if !added.isEmpty { actions.append(.add(added)) }
        return actions
    }

    /// The same Kennel workspace it synced with before beats a namesake; „Privat“ goes to the standard storage;
    /// anything else stays here until the person says otherwise.
    static func proposal(for workspace: TakeOverLocal, matches: [RemoteWorkspace], storages: [KennelStorageSummary], accountID: String) -> String {
        if let previous = matches.first(where: { before(workspace, $0, accountID) }) { return linkPrefix + previous.id }
        if let namesake = matches.first { return linkPrefix + namesake.id }
        if sameName(workspace.name, "Privat"), let first = storages.first { return placePrefix + first.id }
        return keep
    }

    /// The local library was bound to this Kennel workspace of this account, maybe before a vault reset.
    static func before(_ workspace: TakeOverLocal, _ remote: RemoteWorkspace, _ accountID: String) -> Bool {
        guard let bound = workspace.boundKey, !accountID.isEmpty else { return false }
        let plain = bound.split(separator: "#", maxSplits: 1).first.map(String.init) ?? bound
        return plain == Workspaces.bindingKey(accountID: accountID, remote: remote.id)
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Kennel's storages as inkhash shows them: „Standard“ first, then those inkhash may use (ADR 0077).
public enum KennelStorages {
    /// `storages`: from `APIClient.noteStorages`. `remotes`: the account's Kennel workspaces, to count per storage.
    /// Without `counts` no count is shown.
    public static func summaries(_ storages: [KennelStorage], remotes: [RemoteWorkspace]? = nil) -> [KennelStorageSummary] {
        let standard = KennelStorageSummary(
            id: TakeOverPlanner.standardStorage, name: "Standard", visibility: .onlyMe,
            count: remotes.map { count(remotes: $0, in: nil) })
        return [standard] + storages.map { storage in
            KennelStorageSummary(storage, count: remotes.map { count(remotes: $0, in: storage.id) })
        }
    }

    /// The summary's id as Kennel's `storageId`: nil for „Standard“.
    public static func storageID(_ summaryID: String?) -> String? {
        guard let summaryID, summaryID != TakeOverPlanner.standardStorage else { return nil }
        return summaryID
    }

    /// The summary id of a Kennel workspace's storage.
    public static func summaryID(of remote: RemoteWorkspace) -> String {
        remote.storageId ?? TakeOverPlanner.standardStorage
    }

    /// „1 Workspace“, „3 Workspaces“.
    public static func workspaces(_ count: Int) -> String {
        count == 1 ? "1 Workspace" : "\(count) Workspaces"
    }

    private static func count(remotes: [RemoteWorkspace], in storage: String?) -> String {
        workspaces(remotes.filter { $0.storageId == storage }.count)
    }
}
