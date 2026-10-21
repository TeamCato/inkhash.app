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
        // Inkhash > Einstellungen (Cmd+,): what belongs to this Mac, not to a workspace: text, and Kennel as its own
        // tab (ADR 0061, teamCato ADR 0009 point 3).
        Settings {
            TabView {
                Form {
                    TextSettingsSection()
                }
                .formStyle(.grouped)
                .tabItem { Label("Text", systemImage: "textformat") }
                KennelSettingsView()
                    .tabItem { Label("Kennel", systemImage: "house") }
            }
            .environment(model)
            .frame(width: 520, height: 480)
            .preferredColorScheme(.light)
        }
    }
}
