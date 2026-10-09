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
    @State private var version: String?
    @State private var loadingRemotes = true
    @State private var adding = false
    @State private var deletion: Deletion?
    /// What the last action on the server's workspaces came to. The status line lies behind this sheet.
    @State private var notice: String?

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
                LabeledContent("Server-Version", value: loadingRemotes ? "…" : version ?? "unbekannt, älter als 0.5.0")
            }
            if !loadingRemotes, !keepsLooks {
                Section {
                    Label("Dieser Server ist älter als Version 0.2.0. Bild, Symbol und Reihenfolge bleiben auf jedem Gerät für sich, und Workspaces lassen sich nicht löschen. Bitte den Server aktualisieren.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            onServer
            Section {
                NavigationLink("Passwort ändern") { PasswordChangeView(serverID: serverID) }
                Button("Abmelden") { model.sessions.logout(serverID) }
                Button("Server entfernen", role: .destructive) { confirmRemoval = true }
                    .confirmationDialog("Server entfernen?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                        Button("Entfernen", role: .destructive) {
                            model.removeServer(serverID)
                            dismiss()
                        }
                        Button("Abbrechen", role: .cancel) {}
                    } message: {
                        Text("Workspaces, die damit abgleichen, bleiben auf diesem Gerät und hören auf abzugleichen.")
                    }
            } footer: {
                Text("Abmelden beendet nur den Abgleich, die Notizen bleiben hier. Weitere Accounts legt der Admin unter \(ServerAddress.admin(server.url)) an.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(ServerAddress.host(server.url))
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
            if let notice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
            }
        } header: {
            Text("Workspaces auf dem Server")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !missing.isEmpty {
                    Text("Ein hinzugefügter Workspace gleicht gleich ab, mit seinen Notizen, seinem Aussehen und seinem Platz in der Reihenfolge.")
                }
                Text("Löschen auf dem Server über „…“ neben einem Workspace. Einer muss bleiben.")
            }
        }
    }

    private func row(_ remote: RemoteWorkspace) -> some View {
        let here = model.registry.workspaces(on: serverID).filter { $0.link?.remote == remote.id }
        let isLast = remotes.count <= 1
        return HStack(spacing: 10) {
            if let local = here.first {
                Label {
                    Text(local.name)
                } icon: {
                    WorkspaceIcon(workspace: local)
                }
            } else {
                Label {
                    Text(remote.name)
                } icon: {
                    Image(systemName: remote.symbol ?? "tray")
                }
            }
            Spacer()
            if here.isEmpty {
                Button("Hinzufügen") { add([remote]) }
                    .disabled(adding)
            } else {
                Text("Auf diesem Gerät")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
            }
            // Visible on purpose: a context menu is easy to miss, and on the Mac a row with a
            // button does not reliably show one.
            Menu {
                Button("Auf dem Server löschen…", systemImage: "trash", role: .destructive) {
                    askToDelete(remote, here: here)
                }
                .disabled(isLast || !keepsLooks)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Ink.muted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Mehr zu „\(remote.name)“")
            .confirmationDialog(
                "„\(remote.name)“ auf dem Server löschen?",
                isPresented: Binding(get: { deletion?.id == remote.id }, set: { if !$0 { deletion = nil } }),
                titleVisibility: .visible,
                presenting: deletion
            ) { pending in
                Button("Auf dem Server löschen", role: .destructive) { delete(pending.remote) }
                Button("Abbrechen", role: .cancel) {}
            } message: { pending in
                Text(warning(for: pending))
            }
        }
        #if os(iOS)
        .swipeActions {
            if !isLast && keepsLooks {
                Button("Löschen", systemImage: "trash", role: .destructive) { askToDelete(remote, here: here) }
            }
        }
        #endif
    }

    private func loadRemotes() async {
        loadingRemotes = true
        version = await model.sessions.version(of: serverID)
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
            if let problem = await model.deleteOnServer(remote, on: serverID) {
                notice = problem
            } else {
                notice = "„\(remote.name)“ ist auf dem Server gelöscht."
                await loadRemotes()
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
