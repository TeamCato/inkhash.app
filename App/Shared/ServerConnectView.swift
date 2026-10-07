import InkhashCore
import SwiftUI

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
    /// A new server after signing in: its page follows here, with the workspaces to take over.
    @State private var joined: UUID?

    var body: some View {
        if let joined {
            ServerDetailView(serverID: joined)
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack {
                    TextField("Adresse", text: $url, prompt: Text(verbatim: "http://192.168.1.10:8787"))
                        .labelsHidden()
                        .textContentType(.URL)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                        .autocorrectionDisabled()
                        .onChange(of: url) { _, value in model.sessions.addressChanged(value) }
                        .onSubmit { model.sessions.addressChanged(url) }
                    connectionIndicator
                }
            } header: {
                Text("Adresse")
            } footer: {
                Text(connectionText)
            }
            if case .reachable(let mode) = model.sessions.connection {
                accountSection(mode)
            }
            if !model.status.isEmpty, model.status != StatusLine.localOnly, model.status != "Abgeglichen." {
                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(presetURL.isEmpty ? "Server verbinden" : ServerAddress.host(presetURL))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            url = presetURL
            name = presetName
            model.sessions.connection = .unknown
            if !url.isEmpty { model.sessions.addressChanged(url) }
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch model.sessions.connection {
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
        switch model.sessions.connection {
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
                Text("Öffne \(ServerAddress.admin(url)) im Browser. Mit dem Setup-Token aus dem Log des Servers legst du dort den Admin an. Mit dem meldest du dich danach hier an.")
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
                Text("Accounts legt der Admin unter \(ServerAddress.admin(url)) an. Welche Workspaces damit abgleichen, wählst du danach pro Workspace.")
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
            let server = await model.signIn(url: url, name: name, password: password)
            busy = false
            if let server {
                password = ""
                // A known server shows its signed-in page in place; a new one shows it here.
                if presetURL.isEmpty { joined = server }
            }
        }
    }
}
