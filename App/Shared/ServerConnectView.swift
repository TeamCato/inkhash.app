import InkhashCore
import KennelKit
import KennelKitUI
import SwiftUI

/// „Server verbinden“ with KennelKitUI's sections: found Kennels, address or link, code, name and password, and the
/// new account of an invite. After signing in, the server's page follows. See ADR 0018, 0071, 0072, 0074.
struct ServerConnectView: View {
    @Environment(AppModel.self) private var model
    var presetURL: String
    var presetName = ""
    var presetCode = ""

    /// One instance for the form's life: the address of a found name is resolved by the browser that found it.
    @State private var discovery = KennelDiscovery()
    /// A new server after signing in: its page follows here, with the workspaces to take over.
    @State private var joined: UUID?

    var body: some View {
        if let joined {
            ServerDetailView(serverID: joined)
        } else {
            Form {
                KennelConnectSection(
                    appScheme: JoinLinks.scheme, check: KennelAddressCheck(module: APIClient.module),
                    discovery: discovery, canScan: true, prefill: prefill, name: presetName,
                    footer: "Accounts legt der Admin in Kennels Verwaltung an. Welche Workspaces damit abgleichen, wählst du danach pro Workspace."
                ) { request in
                    await connect(request)
                }
            }
            .formStyle(.grouped)
            .kennelBrand(.inkhash)
            .navigationTitle(presetURL.isEmpty ? "Server verbinden" : ServerAddress.host(presetURL))
        }
    }

    private var prefill: JoinLink? {
        JoinLinks.parse(presetURL).map { JoinLink(address: $0.address, code: JoinCode(presetCode) ?? $0.code) }
    }

    private func connect(_ request: KennelConnectRequest) async -> KennelConnectOutcome {
        switch request {
        case .signIn(let address, let name, let password):
            guard let server = await model.signIn(url: address.absoluteString, name: name, password: password) else {
                return .failed(model.status)
            }
            done(server)
            return .connected
        case .join(let address, let code, let account):
            switch await model.join(
                url: address.absoluteString, code: code.description, name: account?.name, password: account?.password)
            {
            case .joined(let server):
                done(server)
                return .connected
            case .needsAccount:
                return .needsAccount
            case .failed:
                return .failed(model.status)
            }
        }
    }

    private func done(_ server: UUID) {
        // A known server shows its signed-in page in place; a new one shows it here.
        if presetURL.isEmpty || !presetCode.isEmpty { joined = server }
    }
}
