import InkhashCore
import SwiftUI

struct ServerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var serverID: UUID
    @State private var confirmRemoval = false
    @State private var remotes: [RemoteWorkspace] = []
    @State private var loadingRemotes = true
    @State private var adding = false

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
            Section {
                let linked = model.registry.workspaces(on: serverID)
                if linked.isEmpty {
                    Text("Noch kein Workspace gleicht hiermit ab.")
                        .foregroundStyle(Ink.muted)
                }
                ForEach(linked) { workspace in
                    Label {
                        Text(workspace.name)
                    } icon: {
                        WorkspaceIcon(workspace: workspace)
                    }
                }
            } header: {
                Text("Workspaces")
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
        .task(id: serverID) { await loadRemotes() }
    }

    /// Workspaces of the account that this device does not have yet. See ADR 0044.
    @ViewBuilder
    private var onServer: some View {
        let missing = model.registry.setup.unlinked(remotes, on: serverID)
        Section {
            if loadingRemotes {
                ProgressView().controlSize(.small)
            } else if missing.isEmpty {
                Text("Alle Workspaces des Accounts sind auf diesem Gerät.")
                    .foregroundStyle(Ink.muted)
            } else {
                ForEach(missing) { remote in
                    HStack {
                        Label(remote.name, systemImage: remote.symbol ?? "tray")
                        Spacer()
                        Button("Hinzufügen") { add([remote]) }
                            .disabled(adding)
                    }
                }
                if missing.count > 1 {
                    Button("Alle hinzufügen") { add(missing) }
                        .disabled(adding)
                }
            }
        } header: {
            Text("Auf dem Server")
        } footer: {
            if !missing.isEmpty {
                Text("Ein hinzugefügter Workspace gleicht gleich ab, mit seinen Notizen, seinem Aussehen und seinem Platz in der Reihenfolge.")
            }
        }
    }

    private func loadRemotes() async {
        loadingRemotes = true
        remotes = await model.sessions.remoteWorkspaces(on: serverID)
        loadingRemotes = false
    }

    private func add(_ chosen: [RemoteWorkspace]) {
        adding = true
        Task {
            await model.addFromServer(chosen, on: serverID)
            adding = false
        }
    }
}
