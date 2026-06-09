import SwiftUI

struct ConnectumCommands: Commands {
    let shell: ShellModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("새 서비스") { shell.startNewService() }
                .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Button("찾기") {
                NotificationCenter.default.post(name: .connectumFindRequested, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("이동") {
            Button("운영 DB") { shell.tab = .operational }
                .keyboardShortcut("1", modifiers: .command)
            Button("대시보드") { shell.tab = .dashboard }
                .keyboardShortcut("2", modifiers: .command)
            Button("연동") { shell.tab = .connections }
                .keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("AI 채팅") { shell.toggleAIPanel() }
                .keyboardShortcut("i", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button("사이드바 보기/숨기기") { shell.toggleSidebar() }
                .keyboardShortcut("₩", modifiers: .command)
            Divider()
            Button("확대") { shell.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("축소") { shell.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("실제 크기") { shell.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button(shell.theme.toggleTitle) { shell.toggleTheme() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
