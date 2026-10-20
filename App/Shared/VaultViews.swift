import InkhashCore
import KennelKitUI
import SwiftUI
import UniformTypeIdentifiers

/// Asks for what a server's vault needs: a new recovery key, a pairing code or the recovery key,
/// or patience for a server update. Opens by itself when syncing finds the vault missing. See ADR 0052, 0054.
struct VaultSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var serverID: UUID
    /// Made once per sheet, shown when setting up or resetting.
    @State private var newKey = RecoveryKey.generate()
    @State private var saved = false
    @State private var typedKey = ""
    @State private var password = ""
    @State private var resetting = false
    @State private var confirmReset = false
    @State private var scanning = false
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
                case .needsKey:
                    if resetting { reset } else { unlock }
                case .noInkhash:
                    Section {
                        Text("Auf \(host) läuft kein Kennel mit dem Modul inkhash, oder das Modul ist ausgeschaltet. Der Abgleich ruht, bis es dort läuft. Auf diesem Gerät geht alles weiter.")
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
            .onChange(of: typedKey) { failure = nil }
            .onChange(of: model.vaults.key(for: serverID)) { _, key in
                if key != nil { dismiss() }
            }
            .sheet(isPresented: $scanning) {
                KennelQRScanSheet(accepts: Pairing.isCode) { code in
                    run { await model.unlockVault(on: serverID, pairingCode: code) }
                }
                .kennelBrand(.inkhash)
            }
        }
        .macSheetSize(minWidth: 480, minHeight: 520)
        .interactiveDismissDisabled()
    }

    private var title: String {
        switch model.vaults.state(of: serverID) {
        case .needsSetup: "Notizen verschlüsseln"
        case .needsKey: resetting ? "Tresor zurücksetzen" : "Tresor öffnen"
        default: "Verschlüsselung"
        }
    }

    @ViewBuilder
    private var setup: some View {
        Section {
            Text("Ab jetzt gehen deine Notizen nur noch verschlüsselt zu \(host). Der Schlüssel liegt in einem Tresor. Weitere Geräte bekommen ihn per QR-Code von diesem Gerät; der Server und sein Admin können ihn nicht lesen.")
        }
        RecoveryKeyCard(key: newKey, saved: $saved)
        Section {
            Button("Tresor anlegen und verschlüsseln") {
                run { await model.createVault(on: serverID, recoveryKey: newKey) }
            }
            .disabled(!saved)
        }
    }

    @ViewBuilder
    private var unlock: some View {
        Section {
            Text("Die Notizen auf \(host) sind verschlüsselt. Öffne den Tresor mit einem Gerät, auf dem er schon offen ist, oder mit dem Wiederherstellungsschlüssel.")
        }
        Section {
            if KennelQRScanSheet.canScan {
                Button("QR-Code scannen…") { scanning = true }
            } else {
                Text("Dieses Gerät hat keine Kamera. Nimm den Wiederherstellungsschlüssel.")
                    .foregroundStyle(Ink.muted)
            }
        } header: {
            Text("Mit einem anderen Gerät")
        } footer: {
            Text("Dort in den Einstellungen des Servers „Gerät hinzufügen“ wählen. Der Code gilt fünf Minuten.")
        }
        Section {
            RecoveryKeyField(text: $typedKey, onSubmit: open)
            Button("Öffnen") { open() }
                .disabled(RecoveryKey(parsing: typedKey) == nil)
        } header: {
            Text("Mit dem Wiederherstellungsschlüssel")
        } footer: {
            if !typedKey.isEmpty, RecoveryKey(parsing: typedKey) == nil {
                Text("25 Zeichen in fünf Gruppen. Das Eingegebene ist noch kein gültiger Schlüssel.")
            }
        }
        Section {
            Button("Schlüssel verloren?") {
                resetting = true
                saved = false
                failure = nil
            }
        }
    }

    @ViewBuilder
    private var reset: some View {
        Section {
            Text("Ohne ein Gerät mit offenem Tresor und ohne Wiederherstellungsschlüssel lässt sich der Tresor nicht öffnen. Zurücksetzen löscht die Notizen dieses Accounts auf dem Server und legt einen neuen Tresor an. Dieses Gerät lädt danach seine Notizen neu hoch. Was nur auf dem Server lag, ist weg.")
        }
        Section {
            SecureField("Login-Passwort", text: $password)
                .textContentType(.password)
        }
        RecoveryKeyCard(key: newKey, saved: $saved)
        Section {
            Button("Tresor zurücksetzen", role: .destructive) { confirmReset = true }
                .disabled(password.isEmpty || !saved)
                .confirmationDialog("Notizen auf dem Server löschen?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Zurücksetzen", role: .destructive) {
                        run { await model.resetVault(on: serverID, password: password, recoveryKey: newKey) }
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

    private func open() {
        guard let key = RecoveryKey(parsing: typedKey) else { return }
        run { await model.unlockVault(on: serverID, recoveryKey: key) }
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

/// A fresh recovery key, shown once, with ways to keep it and a promise that it is kept. See ADR 0054.
struct RecoveryKeyCard: View {
    let key: RecoveryKey
    @Binding var saved: Bool
    @State private var copied = false

    var body: some View {
        Section {
            Text(key.display)
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .accessibilityLabel("Wiederherstellungsschlüssel \(key.display)")
            HStack(spacing: 20) {
                Button(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    Clipboard.copySecret(key.display)
                    copied = true
                }
                ShareLink(item: key.display, subject: Text("inkhash Wiederherstellungsschlüssel")) {
                    Label("Sichern…", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderless)
            Toggle("Ich habe den Schlüssel sicher abgelegt", isOn: $saved)
        } header: {
            Text("Wiederherstellungsschlüssel")
        } footer: {
            Text("Leg ihn in deiner Passwörter-App ab oder drucke ihn aus. Du brauchst ihn nur, wenn kein Gerät mit offenem Tresor mehr da ist. inkhash zeigt ihn nur jetzt.")
        }
    }
}

/// Where a recovery key is typed or pasted. Case and dashes do not matter.
struct RecoveryKeyField: View {
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        TextField("XXXXX-XXXXX-XXXXX-XXXXX-XXXXX", text: $text)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            #endif
            .onSubmit(onSubmit)
    }
}

enum Clipboard {
    /// A secret stays on this device: on iOS not on other devices' clipboards and gone after two minutes.
    static func copySecret(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
        )
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// The vault in a server's settings: whether it is open, adding a device, a new recovery key.
/// Sheets hang on their buttons, not on the section: a Form hands a section's modifiers to each
/// row, the header and the footer, so one sheet would be presented three times. See PITFALLS.
/// The caller checks the vault; a `.task` here would run three times for the same reason.
struct VaultSection: View {
    @Environment(AppModel.self) private var model
    var serverID: UUID
    @State private var showsVault = false
    @State private var showsPairing = false

    var body: some View {
        Section {
            switch model.vaults.state(of: serverID) {
            case .ready:
                Label("Notizen gehen verschlüsselt zum Server.", systemImage: "lock")
                Button("Gerät hinzufügen…") { showsPairing = true }
                    .sheet(isPresented: $showsPairing) {
                        PairingOfferSheet(serverID: serverID)
                    }
                NavigationLink("Neuer Wiederherstellungsschlüssel") { RecoveryKeyRenewView(serverID: serverID) }
            case .needsSetup, .needsKey:
                // One button for both: resetting turns needsKey into needsSetup while the sheet is open.
                Button(model.vaults.state(of: serverID) == .needsSetup ? "Tresor anlegen…" : "Tresor öffnen…") { showsVault = true }
                    .sheet(isPresented: $showsVault) {
                        VaultSheet(serverID: serverID)
                    }
            case .noInkhash:
                Label("Auf diesem Server läuft inkhash nicht. Das Modul in Kennel einschalten.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Ink.warning)
            case .failed(let reason):
                Text(reason).foregroundStyle(Ink.muted)
            case .unknown:
                ProgressView().controlSize(.small)
            }
        } header: {
            Text("Verschlüsselung")
        } footer: {
            Text("Den Schlüssel kennen nur deine Geräte, nicht der Server und nicht der Admin. Workspace-Namen und -Symbole bleiben lesbar.")
        }
    }
}

/// Shows a pairing code for a new device: five minutes, once. Closing takes it back. See ADR 0054.
struct PairingOfferSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var serverID: UUID
    @State private var pairing: Pairing?
    @State private var expiresAt = Date.distantPast
    @State private var failure: String?

    static let lifetime: TimeInterval = 5 * 60

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let pairing {
                    Text("Auf dem neuen Gerät am selben Account anmelden und unter „Tresor öffnen“ den QR-Code scannen.")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = expiresAt.timeIntervalSince(context.date)
                        VStack(spacing: 14) {
                            KennelQRCodeView(pairing.code, label: "QR-Code zum Koppeln")
                                .frame(maxWidth: 260)
                                .opacity(left > 0 ? 1 : 0.15)
                            if left > 0 {
                                Text("Gilt noch \(Int(left) / 60):\(String(format: "%02d", Int(left) % 60)) und nur einmal.")
                                    .font(.callout)
                                    .foregroundStyle(Ink.muted)
                                    .monospacedDigit()
                            } else {
                                Button("Neuen Code zeigen") { Task { await renew() } }
                                    .inkButton()
                            }
                        }
                    }
                } else if let failure {
                    Text(failure).foregroundStyle(.red)
                    Button("Nochmal versuchen") { Task { await offer() } }
                        .inkButton()
                } else {
                    ProgressView()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Gerät hinzufügen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .macSheetSize(minWidth: 420, minHeight: 500)
        .task { await offer() }
        .onDisappear {
            guard let pairing else { return }
            Task { await model.vaults.withdrawPairing(serverID, id: pairing.id) }
        }
    }

    private func offer() async {
        failure = nil
        switch await model.vaults.offerPairing(serverID) {
        case .success(let next):
            pairing = next
            expiresAt = Date().addingTimeInterval(Self.lifetime)
        case .failure(let problem):
            failure = problem.message
        }
    }

    /// The server keeps one pairing per account, so the new code replaces the old one there.
    private func renew() async {
        pairing = nil
        await offer()
    }
}

/// A new recovery key for the same account key. The old one stops working; open devices notice nothing.
struct RecoveryKeyRenewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var serverID: UUID
    @State private var key = RecoveryKey.generate()
    @State private var saved = false
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                Text("Ein neuer Wiederherstellungsschlüssel ersetzt den alten. Der alte öffnet den Tresor danach nicht mehr. Geräte, auf denen der Tresor offen ist, merken nichts.")
            }
            RecoveryKeyCard(key: key, saved: $saved)
            Section {
                Button("Neuen Schlüssel übernehmen") {
                    busy = true
                    Task {
                        failure = await model.vaults.renewRecoveryKey(serverID, to: key)
                        busy = false
                        if failure == nil { dismiss() }
                    }
                }
                .disabled(busy || !saved)
            } footer: {
                if let failure { Text(failure).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Wiederherstellungsschlüssel")
    }
}
