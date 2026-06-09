import SwiftUI

@main
struct ConnectumApp: App {
    @State private var shell = ShellModel()

    var body: some Scene {
        WindowGroup {
            GeometryReader { proxy in
                RootView(shell: shell)
                    .frame(
                        width: max(1, proxy.size.width / shell.uiScale),
                        height: max(1, proxy.size.height / shell.uiScale),
                        alignment: .topLeading
                    )
                    .scaleEffect(shell.uiScale, anchor: .topLeading)
            }
            .preferredColorScheme(shell.theme.colorScheme)
            .tint(shell.theme.tint)
        }
        .commands { ConnectumCommands(shell: shell) }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 820)

        // Connectum settings — opens with Cmd+,
        Settings {
            SettingsView()
                .preferredColorScheme(shell.theme.colorScheme)
                .tint(shell.theme.tint)
        }
    }
}
