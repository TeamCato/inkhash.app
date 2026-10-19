import InkhashCore
import SwiftUI

/// Address first, checked on its own; then only the fields this server needs. The address field
/// also takes a join link or app link, which fills in the code. See ADR 0018 and 0071.
struct ServerConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var presetURL: String
    var presetName = ""
    var presetCode = ""

    @State private var url = ""
    @State private var code = ""
    @State private var name = ""
    @State private var password = ""
    @State private var busy = false
    @State private var loaded = false
    /// The code turned out to be an invite: it needs name and password for a new account.
    @State private var invite = false
    @State private var scanning = false
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
                    TextField("Adresse oder Link", text: $url, prompt: Text(verbatim: "http://192.168.1.10:8790"))
                        .labelsHidden()
                        .textContentType(.URL)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                        .autocorrectionDisabled()
                        .onChange(of: url) { _, value in addressChanged(value) }
                        .onSubmit { model.sessions.addressChanged(url) }
                    connectionIndicator
                }
                if QRScanner.hasCamera {
                    Button("QR-Code scannen …", systemImage: "qrcode.viewfinder") { scanning = true }
                }
            } header: {
                Text("Adresse")
            } footer: {
                Text(connectionText)
            }
            if case .reachable(let mode) = model.sessions.connection {
                accountSection(mode)
            }
            if !StatusLine.isRoutine(model.status) {
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
            code = presetCode
            model.sessions.connection = .unknown
            if !url.isEmpty { model.sessions.addressChanged(url) }
        }
        .onChange(of: code) { _, _ in invite = false }
        .sheet(isPresented: $scanning) {
            QRScanSheet(accepts: JoinLink.isJoinLink) { scanned in addressChanged(scanned) }
        }
    }

    /// A pasted, scanned or opened link splits into address and code; a plain address is checked.
    private func addressChanged(_ value: String) {
        if let target = JoinLink.parse(value), let linked = target.code {
            code = linked
            let server = target.server.absoluteString
            if url != server {
                // Setting the field calls this again with the plain address, which checks it.
                url = server
                return
            }
        }
        model.sessions.addressChanged(value)
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch model.sessions.connection {
        case .checking:
            ProgressView().controlSize(.small)
        case .reachable:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.sage)
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
                TextField("Code", text: $code, prompt: Text(verbatim: "XXXX-XXXX-XXXX"))
                    .labelsHidden()
#if os(iOS)
                    .textInputAutocapitalization(.characters)
#endif
                    .autocorrectionDisabled()
                    .monospaced()
                if !code.isEmpty && !invite {
                    Button("Beitreten") { join() }
                        .disabled(busy || JoinCode.normalized(code) == nil)
                }
            } header: {
                Text("Code")
            } footer: {
                Text("Mit einem Code aus Kennels Verwaltung meldest du dieses Gerät ohne Passwort an oder nimmst eine Einladung an. Ohne Code meldest du dich mit Name und Passwort an.")
            }
            if code.isEmpty {
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
            } else if invite {
                Section {
                    nameField
                    SecureField("Passwort", text: $password)
                    Button("Account anlegen") { join() }
                        .disabled(busy || name.isEmpty || password.count < 8)
                } header: {
                    Text("Neuer Account")
                } footer: {
                    Text("Du bist eingeladen. Name und Passwort wählst du selbst, das Passwort hat mindestens 8 Zeichen.")
                }
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
            if let server { done(server) }
        }
    }

    /// Redeems the code: first alone, and for an invite again with name and password. See ADR 0071.
    private func join() {
        busy = true
        Task {
            let outcome = await model.join(url: url, code: code, name: invite ? name : nil, password: invite ? password : nil)
            busy = false
            switch outcome {
            case .joined(let server):
                code = ""
                done(server)
            case .needsAccount:
                name = ""
                invite = true
            case .failed:
                break
            }
        }
    }

    private func done(_ server: UUID) {
        password = ""
        // A known server shows its signed-in page in place; a new one shows it here.
        if presetURL.isEmpty || !presetCode.isEmpty { joined = server }
    }
}
