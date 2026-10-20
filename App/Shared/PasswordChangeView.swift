import KennelKitUI
import SwiftUI

/// The signed-in account changes its own password, with KennelKitUI's form. See ADR 0050, 0074.
struct PasswordChangeView: View {
    @Environment(AppModel.self) private var model
    var serverID: UUID

    var body: some View {
        KennelPasswordChangeView(
            note: "Andere Geräte mit diesem Account müssen sich danach neu anmelden. Die Notizen bleiben dort."
        ) { current, new in
            await model.sessions.changePassword(on: serverID, current: current, new: new)
        }
        .kennelBrand(.inkhash)
    }
}
