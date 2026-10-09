import InkhashCore
import SwiftUI

/// Asks for what a server's vault needs: a new passphrase, the passphrase, or patience for a
/// server update. Opens by itself when syncing finds the vault missing. See ADR 0052.
struct VaultSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var serverID: UUID
    @State private var passphrase = ""
    @State private var repeated = ""
    @State private var password = ""
    @State private var resetting = false
    @State private var confirmReset = false
    @State private var busy = false
    @State private var failure: String?

    private var host: String {
        model.registry.server(serverID).map { ServerAddress.host($0.url) } ?? "Server"
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.vaults.state(of: serverID) {
                case .needsSetup:
                    setup
                case .needsPassphrase:
                    if resetting { reset } else { unlock }
                case .serverTooOld:
                    Section {
                        Text("\(host) kann noch nicht verschlüsseln. Ab jetzt gehen Notizen nur verschlüsselt zum Server, deshalb ruht der Abgleich, bis der Server aktualisiert ist. Auf diesem Gerät geht alles weiter.")
                    }
                case .ready:
                    Section { Text("Der Tresor ist offen.") }
                case .unknown, .failed:
                    Section { ProgressView() }
                }
                if let failure {
                    Section { Text(failure).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.vaults.key(for: serverID) == nil ? "Später" : "Fertig") {
                        model.vaults.postpone(serverID)
                        dismiss()
                    }
                }
            }
            .disabled(busy)
            .onChange(of: passphrase) { failure = nil }
            .onChange(of: model.vaults.key(for: serverID)) { _, key in
                if key != nil { dismiss() }
            }
        }
        .macSheetSize(minWidth: 460, minHeight: 440)
        .interactiveDismissDisabled()
    }

    private var title: String {
        switch model.vaults.state(of: serverID) {
        case .needsSetup: "Notizen verschlüsseln"
        case .needsPassphrase: resetting ? "Tresor zurücksetzen" : "Tresor öffnen"
        default: "Verschlüsselung"
        }
    }

    @ViewBuilder
    private var setup: some View {
        Section {
            Text("Ab jetzt gehen deine Notizen nur noch verschlüsselt zu \(host). Der Schlüssel liegt in einem Tresor, den eine Passphrase schützt. Sie bleibt auf deinen Geräten; der Server und sein Admin kennen sie nicht.")
            Text("Ohne Passphrase lässt sich die Kopie auf dem Server nicht mehr lesen. Deine Geräte behalten ihre Notizen trotzdem.")
                .foregroundStyle(Ink.muted)
        }
        Section {
            SecureField("Passphrase", text: $passphrase)
                .textContentType(.newPassword)
            SecureField("Passphrase wiederholen", text: $repeated)
                .textContentType(.newPassword)
        } footer: {
            Text(hint(Passphrase.problem(passphrase, repeated: repeated)) ?? "Mindestens \(Passphrase.minimum) Zeichen. Ein paar Wörter, die nur du kennst, sind besser als ein kurzes Passwort.")
        }
        Section {
            Button("Tresor anlegen und verschlüsseln") {
                run { await model.createVault(on: serverID, passphrase: passphrase) }
            }
            .disabled(Passphrase.problem(passphrase, repeated: repeated) != nil)
        }
    }

    @ViewBuilder
    private var unlock: some View {
        Section {
            Text("Die Notizen auf \(host) sind verschlüsselt. Gib die Passphrase ein, die du beim Anlegen des Tresors gewählt hast.")
            SecureField("Passphrase", text: $passphrase)
                .textContentType(.password)
                .onSubmit { open() }
        }
        Section {
            Button("Öffnen") { open() }
                .disabled(passphrase.isEmpty)
            Button("Passphrase vergessen?") {
                resetting = true
                passphrase = ""
                failure = nil
            }
        }
    }

    @ViewBuilder
    private var reset: some View {
        Section {
            Text("Ohne Passphrase lässt sich der Tresor nicht öffnen. Zurücksetzen löscht die Notizen dieses Accounts auf dem Server und legt einen neuen Tresor an. Dieses Gerät lädt danach seine Notizen neu hoch. Was nur auf dem Server lag, ist weg. Andere Geräte fragen dann nach der neuen Passphrase.")
        }
        Section {
            SecureField("Login-Passwort", text: $password)
                .textContentType(.password)
            SecureField("Neue Passphrase", text: $passphrase)
                .textContentType(.newPassword)
            SecureField("Neue Passphrase wiederholen", text: $repeated)
                .textContentType(.newPassword)
        } footer: {
            Text(hint(Passphrase.problem(passphrase, repeated: repeated)) ?? "")
        }
        Section {
            Button("Tresor zurücksetzen", role: .destructive) { confirmReset = true }
                .disabled(password.isEmpty || Passphrase.problem(passphrase, repeated: repeated) != nil)
                .confirmationDialog("Notizen auf dem Server löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Zurücksetzen", role: .destructive) {
                        run { await model.resetVault(on: serverID, password: password, passphrase: passphrase) }
                    }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Die Notizen auf diesem Gerät bleiben und gehen danach verschlüsselt neu zum Server.")
                }
            Button("Zurück") {
                resetting = false
                failure = nil
            }
        }
    }

    /// The problem with what was typed, once there is something typed.
    private func hint(_ problem: String?) -> String? {
        passphrase.isEmpty && repeated.isEmpty ? nil : problem
    }

    private func open() {
        guard !passphrase.isEmpty else { return }
        run { await model.unlockVault(on: serverID, passphrase: passphrase) }
    }

    private func run(_ work: @escaping () async -> String?) {
        busy = true
        failure = nil
        Task {
            failure = await work()
            busy = false
        }
    }
}

/// The vault in a server's settings: whether it is open, and changing the passphrase.
struct VaultSection: View {
    @Environment(AppModel.self) private var model
    var serverID: UUID
    @State private var showsVault = false

    var body: some View {
        Section {
            switch model.vaults.state(of: serverID) {
            case .ready:
                Label("Notizen gehen verschlüsselt zum Server.", systemImage: "lock")
                NavigationLink("Passphrase ändern") { PassphraseChangeView(serverID: serverID) }
            case .needsSetup:
                Button("Tresor anlegen…") { showsVault = true }
            case .needsPassphrase:
                Button("Tresor öffnen…") { showsVault = true }
            case .serverTooOld:
                Label("Der Server kann noch nicht verschlüsseln. Bitte aktualisieren.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .failed(let reason):
                Text(reason).foregroundStyle(Ink.muted)
            case .unknown:
                ProgressView().controlSize(.small)
            }
        } header: {
            Text("Verschlüsselung")
        } footer: {
            Text("Die Passphrase kennen nur deine Geräte, nicht der Server und nicht der Admin. Workspace-Namen und -Symbole bleiben lesbar.")
        }
        .sheet(isPresented: $showsVault) {
            VaultSheet(serverID: serverID)
        }
        .task(id: serverID) {
            if model.vaults.key(for: serverID) == nil { await model.vaults.check(serverID) }
        }
    }
}

/// A new passphrase for the same key. Other devices keep working without asking.
struct PassphraseChangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var serverID: UUID
    @State private var passphrase = ""
    @State private var repeated = ""
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        let problem = Passphrase.problem(passphrase, repeated: repeated)
        Form {
            Section {
                SecureField("Neue Passphrase", text: $passphrase)
                    .textContentType(.newPassword)
                SecureField("Neue Passphrase wiederholen", text: $repeated)
                    .textContentType(.newPassword)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let failure {
                        Text(failure).foregroundStyle(.red)
                    } else if !passphrase.isEmpty || !repeated.isEmpty, let problem {
                        Text(problem)
                    }
                    Text("Geräte, auf denen der Tresor offen ist, bleiben es. Neue Geräte brauchen die neue Passphrase.")
                }
            }
            Section {
                Button("Passphrase ändern") {
                    busy = true
                    Task {
                        failure = await model.vaults.changePassphrase(serverID, to: passphrase)
                        busy = false
                        if failure == nil { dismiss() }
                    }
                }
                .disabled(busy || problem != nil)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Passphrase ändern")
    }
}
