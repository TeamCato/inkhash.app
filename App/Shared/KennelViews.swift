import InkhashCore
import KennelKit
import KennelKitUI
import SwiftUI

/// „Mit Kennel verbinden“ for inkhash: KennelKitUI's sheet Finden › Anmelden › Übernehmen, with this app's rows to take
/// over. Opens wherever Kennel is needed and returns there (teamCato ADR 0009 point 4, ADR 0077).
struct InkhashConnectFlow: View {
    @Environment(AppModel.self) private var model
    var prefill: JoinLink?
    var name = ""
    var onFinished: (KennelConnectFlow.Finish) -> Void = { _ in }

    /// One instance for the sheet's life: a found name is resolved by the browser that found it.
    @State private var discovery = KennelDiscovery()

    var body: some View {
        KennelConnectFlow(
            appScheme: JoinLinks.scheme, check: KennelAddressCheck(module: APIClient.module), discovery: discovery,
            canScan: true, prefill: prefill, name: name,
            connect: { await model.connect($0) },
            takeOver: { await model.takeOverPlan() },
            apply: { await model.applyTakeOver($0) },
            onFinished: { finish in
                if finish == .connected { model.connectedWithoutTakingOver() }
                onFinished(finish)
            }
        )
        .kennelBrand(.inkhash)
    }
}

extension JoinLink: @retroactive Identifiable {
    public var id: Self { self }
}

extension View {
    /// Presents „Mit Kennel verbinden“ here, so it returns to where it was opened.
    func kennelConnectSheet(isPresented: Binding<Bool>, prefill: JoinLink? = nil, name: String = "") -> some View {
        sheet(isPresented: isPresented) {
            InkhashConnectFlow(prefill: prefill, name: name)
        }
    }
}

/// The address and name to sign in again with, when Kennel no longer knows the session.
extension AppModel {
    var signInAgainPrefill: JoinLink? {
        kennel.flatMap { URL(string: $0.url) }.map { JoinLink(address: $0, code: nil) }
    }

    /// Kennel's admin page, where the module inkhash is switched on.
    var adminPage: URL? {
        kennel.flatMap { URL(string: ServerAddress.admin($0.url)) }
    }

    /// What the status line's action does: sign in again, open the vault for locked encrypted workspaces, or open
    /// the admin page.
    func statusAction(
        signIn: @escaping @MainActor () -> Void, openVault: @escaping @MainActor () -> Void,
        open: @escaping @MainActor (URL) -> Void
    ) -> (@MainActor () -> Void)? {
        switch kennelStatus {
        case .signInAgain:
            return signIn
        case .attention:
            return openVault
        case .moduleOff:
            guard let page = adminPage else { return nil }
            return { open(page) }
        default:
            return nil
        }
    }
}

/// Settings › Kennel: the one home of Kennel in inkhash (teamCato ADR 0009 point 3). Verbindung, „Speicher für
/// Inkhash“, Geräte, Konto; workspaces are in the sidebar, not here.
struct KennelSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var connecting = false
    @State private var signingInAgain = false
    @State private var newStorage = false
    @State private var editing: KennelStorage?
    @State private var password = false
    @State private var vaultSheet: VaultSheet?

    var body: some View {
        page
            .kennelBrand(.inkhash)
            .kennelConnectSheet(isPresented: $connecting)
            .kennelConnectSheet(
                isPresented: $signingInAgain, prefill: model.signInAgainPrefill, name: model.kennel?.accountName ?? "")
            .sheet(isPresented: $newStorage) { storageSheet(nil) }
            .sheet(item: $editing) { storageSheet($0) }
            .sheet(isPresented: $password) { kennelSheet { PasswordChangeView(serverID: model.kennel?.id ?? UUID()) } }
            .sheet(item: $vaultSheet) { VaultSheetView(sheet: $0) }
            .task {
                guard model.kennel != nil else { return }
                await model.sync()
                await model.checkVault()
            }
    }

    private var page: some View {
        let signedIn = model.kennel.map { model.sessions.isSignedIn($0.id) } ?? false
        let addsStorage = signedIn && model.overview.module?.workspaceStorage == true
        let newStorageAction = only(addsStorage) { newStorage = true }
        let editStorage = only(signedIn) { (summary: KennelStorageSummary) in
            editing = model.overview.storages.first { $0.id == summary.id }
        }
        let changePassword = only(signedIn) { password = true }
        let invite = model.kennel.flatMap { model.sessions.session(of: $0.id)?.invitePage }.map { page in
            { @MainActor in openURL(page) }
        }
        return KennelSettingsPage(
            connection: connection,
            connect: { connecting = true },
            syncNow: { Task { await model.sync() } },
            statusAction: statusAction,
            storages: signedIn ? model.overview.summaries : nil,
            newStorage: newStorageAction,
            editStorage: editStorage,
            changePassword: changePassword,
            invite: invite,
            disconnect: { model.disconnect() },
            disconnectConsequence: AppModel.disconnectConsequence,
            notConnectedText: "inkhash funktioniert ohne Kennel. Mit Kennel gleichst du Workspaces zwischen deinen Geräten ab und legst sie in den Speichern deines Haushalts ab.",
            vault: signedIn ? model.vaultSection { vaultSheet = $0 } : nil
        )
    }

    /// An action only where it applies; KennelKitUI leaves out what is nil.
    private func only(_ applies: Bool, _ action: @escaping @MainActor () -> Void) -> (@MainActor () -> Void)? {
        applies ? action : nil
    }

    private func only<Value>(_ applies: Bool, _ action: @escaping @MainActor (Value) -> Void) -> (@MainActor (Value) -> Void)? {
        applies ? action : nil
    }

    private var connection: KennelSettingsPage.Connection? {
        guard let kennel = model.kennel, let status = model.kennelStatus else { return nil }
        return KennelSettingsPage.Connection(host: ServerAddress.host(kennel.url), account: kennel.accountName, status: status)
    }

    /// „Anmelden …“, „Freischalten …“ or the admin page, whichever the status asks for.
    private var statusAction: (@MainActor () -> Void)? {
        model.statusAction(
            signIn: { signingInAgain = true }, openVault: { vaultSheet = model.vaultSheetToOpen }, open: { openURL($0) })
    }

    @ViewBuilder
    private func storageSheet(_ storage: KennelStorage?) -> some View {
        if let kennel = model.kennel, let client = model.sessions.client(for: kennel.id) {
            // KennelNewStorageView brings its own „Abbrechen“ and „Anlegen“; a second cancellation action would push
            // „Abbrechen“ out (Kennel ADR 0037).
            kennelFrame {
                if let storage {
                    KennelNewStorageView(client: client.kennel, editing: storage) { model.addStorage($0) }
                } else {
                    KennelNewStorageView(client: client.kennel, module: APIClient.module) { model.addStorage($0) }
                }
            }
        }
    }

    /// For sheets without buttons of their own: adds „Fertig“.
    private func kennelSheet<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        kennelFrame {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        CloseButton()
                    }
                }
        }
    }

    private func kennelFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content()
        }
        .kennelBrand(.inkhash)
        .macSheetSize(minWidth: 440, minHeight: 460)
    }
}

/// „Fertig“ for the sheets of the Kennel page.
private struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Fertig") { dismiss() }
    }
}

/// The sync status as a symbol beside the buttons at the foot of the sidebar while Kennel is connected (teamCato ADR
/// 0009 point 7, Kennel ADR 0060): a tap on the red cross runs its action, „Anmelden …“ opens the connect flow again,
/// „Freischalten …“ unlocks encrypted workspaces (ADR 0082, Kennel ADR 0065); otherwise a tap syncs.
struct KennelSyncSymbol: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var signingIn = false
    @State private var vaultSheet: VaultSheet?

    var body: some View {
        Group {
            if let status = model.kennelStatus {
                KennelStatusSymbol(status, syncNow: { Task { await model.sync() } }, action: action)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                    .frame(width: 28, height: 28)
            }
        }
        .kennelBrand(.inkhash)
        .kennelConnectSheet(isPresented: $signingIn, prefill: model.signInAgainPrefill, name: model.kennel?.accountName ?? "")
        .sheet(item: $vaultSheet) { VaultSheetView(sheet: $0) }
    }

    private var action: (@MainActor () -> Void)? {
        model.statusAction(
            signIn: { signingIn = true }, openVault: { vaultSheet = model.vaultSheetToOpen }, open: { openURL($0) })
    }
}
