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
                    ForEach(model.workspaces) { workspace in
                        NavigationLink {
                            WorkspaceEditor(workspace: workspace)
                        } label: {
                            HStack {
                                Label(workspace.name, systemImage: workspace.symbol)
                                Spacer()
                                Text(target(of: workspace))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.muted)
                            }
                        }
                    }
                    NavigationLink {
                        WorkspaceEditor(workspace: nil)
                    } label: {
                        Label("Workspace anlegen", systemImage: "plus")
                    }
                } header: {
                    Text("Workspaces")
                } footer: {
                    Text("Jeder Workspace hat eigene Notizen, Ordner und Schlagwörter. Er bleibt auf diesem Gerät oder gleicht mit einem Workspace auf einem deiner Server ab.")
                }
                Section {
                    ForEach(model.servers) { server in
                        NavigationLink {
                            ServerDetailView(serverID: server.id)
                        } label: {
                            HStack {
                                Label(AppModel.host(server.url), systemImage: "server.rack")
                                Spacer()
                                Text(model.isSignedIn(server.id) ? server.accountName : "abgemeldet")
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
        guard let server = model.server(of: workspace) else { return "Nur dieses Gerät" }
        return model.isSignedIn(server.id) ? AppModel.host(server.url) : "\(AppModel.host(server.url)), ruht"
    }
}

// MARK: Workspace

/// Creates a workspace (`workspace` nil) or edits one: name, symbol and where it syncs.
struct WorkspaceEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var workspace: Workspace?

    @State private var name = ""
    @State private var symbol = "tray"
    @State private var serverChoice: UUID?
    @State private var remoteChoice = WorkspaceEditor.newRemote
    @State private var remotes: [RemoteWorkspace] = []
    @State private var loadingRemotes = false
    @State private var busy = false
    @State private var confirmRemoval = false
    @State private var loaded = false

    private static let newRemote = "+new"
    static let symbols = ["house", "briefcase", "tray", "book", "lightbulb", "graduationcap", "heart", "leaf", "hammer", "paintpalette", "airplane", "cart"]

    var body: some View {
        Form {
            Section("Name") {
                TextField("z. B. Arbeit", text: $name)
                    .autocorrectionDisabled()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Self.symbols, id: \.self) { item in
                        Button {
                            symbol = item
                        } label: {
                            Image(systemName: item)
                                .font(.system(size: 15))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(symbol == item ? Ink.accent.opacity(0.16) : Color.clear)
                                )
                                .foregroundStyle(symbol == item ? Ink.accent : Ink.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item)
                        .accessibilityAddTraits(symbol == item ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Picker("Abgleich", selection: $serverChoice) {
                    Text("Nur dieses Gerät").tag(UUID?.none)
                    ForEach(model.servers.filter { model.isSignedIn($0.id) }) { server in
                        Text("\(AppModel.host(server.url)) · \(server.accountName)").tag(UUID?.some(server.id))
                    }
                }
                if serverChoice != nil {
                    if loadingRemotes {
                        ProgressView().controlSize(.small)
                    } else {
                        Picker("Workspace auf dem Server", selection: $remoteChoice) {
                            Text("Neu anlegen").tag(Self.newRemote)
                            ForEach(remotes) { remote in
                                Text(remote.name).tag(remote.id)
                                    .disabled(isTaken(remote))
                            }
                        }
                    }
                }
            } header: {
                Text("Abgleich")
            } footer: {
                Text(syncFooter)
            }
            if let workspace, model.workspaces.count > 1 {
                Section {
                    Button("Vom Gerät entfernen", role: .destructive) { confirmRemoval = true }
                } footer: {
                    Text(workspace.link == nil
                        ? "Die Notizen dieses Workspace liegen nur hier und wären danach weg."
                        : "Die Notizen verschwinden von diesem Gerät. Auf dem Server bleiben sie.")
                }
            }
            if !model.status.isEmpty, model.status != AppModel.localOnly, model.status != "Abgeglichen." {
                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(workspace == nil ? "Neuer Workspace" : workspace?.name ?? "")
        .toolbar {
            if workspace == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(workspace == nil ? "Anlegen" : "Sichern") { save() }
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Workspace vom Gerät entfernen?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                if let workspace { model.removeWorkspace(workspace.id) }
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .onAppear(perform: load)
        .onChange(of: serverChoice) { _, _ in Task { await loadRemotes() } }
    }

    private var syncFooter: String {
        if model.servers.isEmpty {
            return "Noch kein Server verbunden. Der Workspace bleibt auf diesem Gerät."
        }
        guard serverChoice != nil else { return "Notizen bleiben auf diesem Gerät." }
        if let workspace, let link = workspace.link, link.server == serverChoice, link.remote == remoteChoice {
            return "Gleicht mit diesem Workspace ab."
        }
        return workspace == nil
            ? "Die Notizen gleichen mit diesem Workspace auf dem Server ab."
            : "Beim Sichern wandern alle Notizen dieses Workspace dorthin. Was dort schon liegt, kommt dazu."
    }

    /// A server workspace another local workspace already syncs with. Two would mirror each other.
    private func isTaken(_ remote: RemoteWorkspace) -> Bool {
        model.workspaces.contains { other in
            other.id != workspace?.id && other.link?.server == serverChoice && other.link?.remote == remote.id
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = workspace?.name ?? ""
        symbol = workspace?.symbol ?? "tray"
        if let link = workspace?.link {
            serverChoice = link.server
            remoteChoice = link.remote
        }
    }

    private func loadRemotes() async {
        guard let server = serverChoice else {
            remotes = []
            return
        }
        loadingRemotes = true
        remotes = await model.remoteWorkspaces(on: server)
        loadingRemotes = false
        if remoteChoice != Self.newRemote, !remotes.contains(where: { $0.id == remoteChoice }) {
            remoteChoice = Self.newRemote
        }
    }

    private var target: WorkspaceTarget {
        guard let serverChoice else { return .local }
        return .server(serverChoice, remote: remoteChoice == Self.newRemote ? nil : remoteChoice)
    }

    private func save() {
        busy = true
        Task {
            if let workspace {
                model.updateWorkspace(workspace.id, name: name, symbol: symbol)
                let current = workspace.link.map { WorkspaceTarget.server($0.server, remote: $0.remote) } ?? .local
                if target != current { await model.relink(workspace.id, to: target) }
            } else {
                await model.createWorkspace(name: name, symbol: symbol, target: target)
            }
            busy = false
            dismiss()
        }
    }
}

// MARK: Server

struct ServerDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var serverID: UUID
    @State private var confirmRemoval = false

    var body: some View {
        if let server = model.servers.first(where: { $0.id == serverID }) {
            if model.isSignedIn(serverID) {
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
                let linked = model.workspaces(on: serverID)
                if linked.isEmpty {
                    Text("Noch kein Workspace gleicht hiermit ab.")
                        .foregroundStyle(Ink.muted)
                }
                ForEach(linked) { workspace in
                    Label(workspace.name, systemImage: workspace.symbol)
                }
            } header: {
                Text("Workspaces")
            }
            Section {
                Button("Abmelden") { model.logout(serverID) }
                Button("Server entfernen", role: .destructive) { confirmRemoval = true }
            } footer: {
                Text("Abmelden beendet nur den Abgleich, die Notizen bleiben hier. Weitere Accounts legt der Admin unter \(AppModel.adminAddress(server.url)) an.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(AppModel.host(server.url))
        .confirmationDialog("Server entfernen?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                model.removeServer(serverID)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Workspaces, die damit abgleichen, bleiben auf diesem Gerät und hören auf abzugleichen.")
        }
    }
}

/// Address first, checked on its own; then only the fields this server needs. See ADR 0018.
struct ServerConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var presetURL: String
    var presetName = ""

    @State private var url = ""
    @State private var name = ""
    @State private var password = ""
    @State private var busy = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("http://192.168.1.10:8787", text: $url)
                        .textContentType(.URL)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                        .autocorrectionDisabled()
                        .onChange(of: url) { _, value in model.addressChanged(value) }
                        .onSubmit { model.addressChanged(url) }
                    connectionIndicator
                }
            } header: {
                Text("Adresse")
            } footer: {
                Text(connectionText)
            }
            if case .reachable(let mode) = model.connection {
                accountSection(mode)
            }
            if !model.status.isEmpty, model.status != AppModel.localOnly, model.status != "Abgeglichen." {
                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(presetURL.isEmpty ? "Server verbinden" : AppModel.host(presetURL))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            url = presetURL
            name = presetName
            model.connection = .unknown
            if !url.isEmpty { model.addressChanged(url) }
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch model.connection {
        case .checking:
            ProgressView().controlSize(.small)
        case .reachable:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unknown:
            EmptyView()
        }
    }

    private var connectionText: String {
        switch model.connection {
        case .unknown:
            "Die Adresse deines Servers, im lokalen Netz mit http."
        case .checking:
            "Prüfe die Verbindung …"
        case .reachable(.setup):
            "Server erreichbar, aber noch nicht eingerichtet."
        case .reachable(.closed):
            "Server erreichbar."
        case .failed(let reason):
            reason
        }
    }

    @ViewBuilder
    private func accountSection(_ mode: RegistrationMode) -> some View {
        switch mode {
        case .setup:
            Section {
                Text("Öffne \(AppModel.adminAddress(url)) im Browser. Mit dem Setup-Token aus dem Log des Servers legst du dort den Admin an. Mit dem meldest du dich danach hier an.")
                    .textSelection(.enabled)
            } header: {
                Text("Einrichten")
            }
        case .closed:
            Section {
                nameField
                SecureField("Passwort", text: $password)
                Button("Anmelden") { submit() }
                    .disabled(busy || name.isEmpty || password.count < 8)
            } header: {
                Text("Anmelden")
            } footer: {
                Text("Accounts legt der Admin unter \(AppModel.adminAddress(url)) an. Welche Workspaces damit abgleichen, wählst du danach pro Workspace.")
            }
        }
    }

    private var nameField: some View {
        TextField("Name", text: $name)
#if os(iOS)
            .textInputAutocapitalization(.never)
#endif
            .autocorrectionDisabled()
    }

    private func submit() {
        busy = true
        Task {
            let ok = await model.signIn(url: url, name: name, password: password)
            busy = false
            if ok {
                password = ""
                // A known server shows its signed-in page in place; a new one goes back to the list.
                if presetURL.isEmpty { dismiss() }
            }
        }
    }
}
