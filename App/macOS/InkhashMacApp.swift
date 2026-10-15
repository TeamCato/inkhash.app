import InkhashCore
import SwiftUI

@main
struct InkhashMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            InkhashCommands(model: model)
            // "Show/Hide Sidebar" on Ctrl+Cmd+S, see ADR 0030.
            SidebarCommands()
        }
        // Inkhash > Einstellungen (Cmd+,): what belongs to this Mac, not to a workspace. See ADR 0061.
        Settings {
            Form {
                TextSettingsSection()
            }
            .formStyle(.grouped)
            .frame(width: 460)
            .preferredColorScheme(.light)
        }
    }
}
