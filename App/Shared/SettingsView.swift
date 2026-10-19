import InkhashCore
import SwiftUI

/// Workspaces and servers. Servers are connected once; each workspace picks one of them, or none.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextSettingsSection()
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
            .navigationDestination(item: joinBinding) { target in
                ServerConnectView(presetURL: target.server.absoluteString, presetCode: target.code ?? "")
            }
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

    /// A join link the app was opened with. See ADR 0071.
    private var joinBinding: Binding<JoinTarget?> {
        Binding(get: { model.pendingJoin }, set: { model.pendingJoin = $0 })
    }

    private func target(of workspace: Workspace) -> String {
        guard let server = model.registry.server(of: workspace) else { return "Nur dieses Gerät" }
        return model.sessions.isSignedIn(server.id) ? ServerAddress.host(server.url) : "\(ServerAddress.host(server.url)), ruht"
    }
}

/// Font and size of text notes on this device: first in the settings, and on the Mac also under
/// Inkhash > Einstellungen (Cmd+,). See ADR 0061.
struct TextSettingsSection: View {
    @AppStorage(TextAppearance.familyKey) private var family = TextFamily.standard.rawValue
    @AppStorage(TextAppearance.sizeKey) private var size = TextAppearance.defaultSize

    var body: some View {
        Section {
            Picker("Schrift", selection: $family) {
                ForEach(TextFamily.allCases) { family in
                    Text(family.title).tag(family.rawValue)
                }
            }
            HStack(spacing: 12) {
                Text("Größe")
                Slider(value: $size, in: TextAppearance.sizes, step: 1)
                Text("\(Int(size)) pt")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            Text("So sieht Text in deinen Notizen aus.")
                .font(preview)
                .foregroundStyle(Ink.ink)
            if family != TextFamily.standard.rawValue || size != TextAppearance.defaultSize {
                Button("Standard wiederherstellen") {
                    family = TextFamily.standard.rawValue
                    size = TextAppearance.defaultSize
                }
            }
        } header: {
            Text("Text")
        } footer: {
            Text("Gilt für alle Textnotizen auf diesem Gerät. Überschriften bleiben in der Serif, Code in Monospace. Auf iPad und iPhone kommt die Textgröße des Systems dazu.")
        }
        .onAppear {
            // A value from outside the range shows as what the editor uses.
            size = TextAppearance.current.size
        }
    }

    private var preview: Font {
        let design: Font.Design = switch TextFamily(rawValue: family) ?? .standard {
        case .standard: .default
        case .serif: .serif
        case .rounded: .rounded
        case .mono: .monospaced
        }
        return .system(size: size, design: design)
    }
}
