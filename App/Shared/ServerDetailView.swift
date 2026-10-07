import InkhashCore
import SwiftUI

struct ServerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var serverID: UUID
    @State private var confirmRemoval = false
    @State private var remotes: [RemoteWorkspace] = []
    /// False for servers before 0.2.0: looks and order stay on each device (ADR 0043).
    @State private var keepsLooks = true
    @State private var loadingRemotes = true
    @State private var adding = false
    @State private var deletion: Deletion?

    /// A server workspace about to be deleted, with what the warning says about it.
    private struct Deletion: Identifiable {
        var remote: RemoteWorkspace
        var notes: Int?
        var here: [Workspace]
        var id: String { remote.id }
    }

    var body: some View {
        if let server = model.registry.servers.first(where: { $0.id == serverID }) {
            if model.sessions.isSignedIn(serverID) {
                signedIn(server)
            } else {
                ServerConnectView(presetURL: server.url, presetName: server.accountName)
            }
        } else {
            Text("Dieser Server ist nicht mehr verbunden.")
                .foregroundStyle(Ink.muted)
        }
    }

    private func signedIn(_ server: ServerEntry) -> some View {
        Form {
            Section {
                LabeledContent("Adresse", value: server.url)
                LabeledContent("Account", value: server.accountName)
            }
            onServer
            Section {
                Button("Abmelden") { model.sessions.logout(serverID) }
                Button("Server entfernen", role: .destructive) { confirmRemoval = true }
            } footer: {
                Text("Abmelden beendet nur den Abgleich, die Notizen bleiben hier. Weitere Accounts legt der Admin unter \(ServerAddress.admin(server.url)) an.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(ServerAddress.host(server.url))
        .confirmationDialog("Server entfernen?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                model.removeServer(serverID)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Workspaces, die damit abgleichen, bleiben auf diesem Gerät und hören auf abzugleichen.")
        }
        .confirmationDialog(
            deletion.map { "„\($0.remote.name)“ auf dem Server löschen?" } ?? "",
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
            titleVisibility: .visible,
            presenting: deletion
        ) { pending in
            Button("Auf dem Server löschen", role: .destructive) { delete(pending.remote) }
            Button("Abbrechen", role: .cancel) {}
        } message: { pending in
            Text(warning(for: pending))
        }
        .task(id: serverID) { await loadRemotes() }
    }

    private func warning(for pending: Deletion) -> String {
        let notes: String
        switch pending.notes {
        case .some(0): notes = "Er ist leer."
        case .some(1): notes = "Darin liegt 1 Notiz."
        case .some(let count): notes = "Darin liegen \(count) Notizen."
        case .none: notes = "Wie viele Notizen darin liegen, ließ sich nicht lesen."
        }
        let here = pending.here.isEmpty
            ? "Auf diesem Gerät ist er nicht."
            : "Auf diesem Gerät bleiben sie in „\(pending.here.map(\.name).joined(separator: "“, „"))“, ohne Abgleich."
        return "\(notes) Er verschwindet für alle Geräte; die dort bleiben nur noch lokal. \(here) Rückgängig machen kann das nur der Admin auf dem Server."
    }

    /// The account's workspaces: the ones here, the ones to take over (ADR 0044), and deleting
    /// one on the server (ADR 0045).
    @ViewBuilder
    private var onServer: some View {
        let missing = model.registry.setup.unlinked(remotes, on: serverID)
        Section {
            if loadingRemotes {
                ProgressView().controlSize(.small)
            } else if remotes.isEmpty {
                Text("Die Workspaces des Servers ließen sich nicht laden.")
                    .foregroundStyle(Ink.muted)
            } else {
                ForEach(remotes) { remote in
                    row(remote)
                }
                if missing.count > 1 {
                    Button("Alle hinzufügen") { add(missing) }
                        .disabled(adding)
                }
            }
        } header: {
            Text("Workspaces auf dem Server")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !missing.isEmpty {
                    Text("Ein hinzugefügter Workspace gleicht gleich ab, mit seinen Notizen, seinem Aussehen und seinem Platz in der Reihenfolge.")
                }
                Text("Löschen auf dem Server über das Kontextmenü eines Workspace. Den ersten Workspace des Accounts gibt es immer.")
                if !keepsLooks {
                    Text("Dieser Server ist älter als Version 0.2.0. Bild, Symbol und Reihenfolge bleiben deshalb auf jedem Gerät für sich.")
                }
            }
        }
    }

    private func row(_ remote: RemoteWorkspace) -> some View {
        let here = model.registry.workspaces(on: serverID).filter { $0.link?.remote == remote.id }
        return HStack {
            if let local = here.first {
                Label {
                    Text(local.name)
                } icon: {
                    WorkspaceIcon(workspace: local)
                }
                Spacer()
                Text("Auf diesem Gerät")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
            } else {
                Label(remote.name, systemImage: remote.symbol ?? "tray")
                Spacer()
                Button("Hinzufügen") { add([remote]) }
                    .disabled(adding)
            }
        }
        .contextMenu {
            if remote.id != APIClient.mainWorkspace {
                Button("Auf dem Server löschen…", systemImage: "trash", role: .destructive) { askToDelete(remote, here: here) }
            }
        }
        #if os(iOS)
        .swipeActions {
            if remote.id != APIClient.mainWorkspace {
                Button("Löschen", systemImage: "trash", role: .destructive) { askToDelete(remote, here: here) }
            }
        }
        #endif
    }

    private func loadRemotes() async {
        loadingRemotes = true
        let list = await model.sessions.remoteWorkspaceList(on: serverID)
        remotes = list?.workspaces ?? []
        keepsLooks = list?.keepsLooks ?? true
        loadingRemotes = false
    }

    private func askToDelete(_ remote: RemoteWorkspace, here: [Workspace]) {
        Task {
            let notes = await model.noteCount(of: remote, on: serverID)
            deletion = Deletion(remote: remote, notes: notes, here: here)
        }
    }

    private func delete(_ remote: RemoteWorkspace) {
        Task {
            if await model.deleteOnServer(remote, on: serverID) {
                remotes.removeAll { $0.id == remote.id }
            }
        }
    }

    private func add(_ chosen: [RemoteWorkspace]) {
        adding = true
        Task {
            await model.addFromServer(chosen, on: serverID)
            adding = false
        }
    }
}
