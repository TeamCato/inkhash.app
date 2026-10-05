import InkhashCore
import SwiftUI

@main
struct InkhashIOSApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .commands {
            InkhashCommands(model: model)
        }
    }
}
