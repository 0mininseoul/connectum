import SwiftUI

@main
struct ConnectumApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)   // Raycast is dark-only; force it so native
                .tint(.white)                  // controls + default text never render light (black)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 820)

        // Connectum settings — opens with Cmd+,
        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
