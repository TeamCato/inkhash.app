import InkhashCore
import SwiftUI

/// Workspaces and servers. Servers are connected once; each workspace picks one of them, or none.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(model.registry.workspaces) { workspace in
                        NavigationLink {
                            WorkspaceEditor(workspace: workspace)
                        } label: {
                            HStack {
                                Label {
                                    Text(workspace.name)
                                } icon: {
                                    WorkspaceIcon(workspace: workspace)
                                }
                                Spacer()
                                Text(target(of: workspace))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.muted)
                            }
                        }
                        .contextMenu {
                            Button("Nach oben", systemImage: "arrow.up") { model.moveWorkspace(workspace.id, by: -1) }
                                .disabled(workspace.id == model.registry.workspaces.first?.id)
                            Button("Nach unten", systemImage: "arrow.down") { model.moveWorkspace(workspace.id, by: 1) }
                                .disabled(workspace.id == model.registry.workspaces.last?.id)
                        }
                    }
                    .onMove { model.moveWorkspaces(fromOffsets: $0, toOffset: $1) }
                    NavigationLink {
                        WorkspaceEditor(workspace: nil)
                    } label: {
                        Label("Workspace anlegen", systemImage: "plus")
                    }
                } header: {
                    Text("Workspaces")
                } footer: {
                    Text("Jeder Workspace hat eigene Notizen, Ordner und Schlagwörter. Er bleibt auf diesem Gerät oder gleicht mit einem Workspace auf einem deiner Server ab. Die Reihenfolge änderst du durch Ziehen oder im Kontextmenü.")
                }
                Section {
                    ForEach(model.registry.servers) { server in
                        NavigationLink {
                            ServerDetailView(serverID: server.id)
                        } label: {
                            HStack {
                                Label(ServerAddress.host(server.url), systemImage: "server.rack")
                                Spacer()
                                Text(model.sessions.isSignedIn(server.id) ? server.accountName : "abgemeldet")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.muted)
                            }
                        }
                    }
                    NavigationLink {
                        ServerConnectView(presetURL: "")
                    } label: {
                        Label("Server verbinden", systemImage: "plus")
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("Optional. Ohne Server bleibt alles auf diesem Gerät. Ein Account kann mehrere Workspaces abgleichen.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Einstellungen")
            .preferredColorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .inkButton()
                }
            }
        }
        .macSheetSize(minWidth: 480, minHeight: 480)
    }

    private func target(of workspace: Workspace) -> String {
        guard let server = model.registry.server(of: workspace) else { return "Nur dieses Gerät" }
        return model.sessions.isSignedIn(server.id) ? ServerAddress.host(server.url) : "\(ServerAddress.host(server.url)), ruht"
    }
}
