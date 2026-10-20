import InkhashCore
import KennelKitUI
import SwiftUI

/// „Weiteres Gerät verbinden“ from KennelKitUI, with this server's session. See ADR 0072, 0074.
struct DeviceCodeView: View {
    @Environment(AppModel.self) private var model
    var serverID: UUID

    var body: some View {
        if let server = model.registry.server(serverID), let url = URL(string: server.url) {
            KennelDeviceCodeView(
                server: url,
                issue: { try await model.sessions.issueDeviceCode(on: serverID) },
                revoke: { try await model.sessions.revokeDeviceCode($0, on: serverID) }
            )
            .kennelBrand(.inkhash)
        } else {
            Text("Dieser Server ist nicht mehr verbunden.").foregroundStyle(Ink.muted)
        }
    }
}
