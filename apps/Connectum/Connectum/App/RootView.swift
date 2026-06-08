import SwiftUI

struct RootView: View {
    @State private var vm = AuthViewModel()

    var body: some View {
        Group {
            if vm.isAuthenticated {
                MainShell()
            } else {
                LoginView(vm: vm)
            }
        }
        .frame(minWidth: 1080, minHeight: 680)
    }
}

// Persistent left sidebar (services) + top tab bar, shared across all tabs.
struct MainShell: View {
    @State private var shell = ShellModel()

    var body: some View {
        NavigationSplitView(columnVisibility: $shell.columnVisibility) {
            ShellSidebar(shell: shell)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                ShellTabBar(shell: shell)
                Divider().overlay(Palette.hairline)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
        }
        .background(shortcuts)
        .task { await shell.load() }
    }

    @ViewBuilder private var content: some View {
        switch shell.tab {
        case .operational: OperationalDBView(serviceId: shell.selectedServiceId)
        case .dashboard:   DashboardView(serviceId: shell.selectedServiceId)
        case .connections: ConnectionsView()
        }
    }

    // Hidden buttons provide keyboard shortcuts while the window is focused.
    private var shortcuts: some View {
        ZStack {
            Button("") { shell.tab = .operational }.keyboardShortcut("1", modifiers: .command)
            Button("") { shell.tab = .dashboard }.keyboardShortcut("2", modifiers: .command)
            Button("") { shell.tab = .connections }.keyboardShortcut("3", modifiers: .command)
            Button("") { shell.toggleSidebar() }.keyboardShortcut("\\", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}

struct ShellSidebar: View {
    @Bindable var shell: ShellModel

    var body: some View {
        List(selection: Binding(get: { shell.selectedServiceId }, set: { if let v = $0 { shell.selectedServiceId = v } })) {
            Section("서비스") {
                ForEach(shell.services) { s in
                    Label(s.name, systemImage: "cylinder.split.1x2")
                        .font(Typography.body)
                        .tag(s.id)
                }
            }
            if shell.services.isEmpty {
                Text("연동 탭에서 서비스를 추가하세요")
                    .font(Typography.caption).foregroundStyle(Palette.muted)
            }
        }
        .navigationTitle("Connectum")
    }
}

struct ShellTabBar: View {
    @Bindable var shell: ShellModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(ShellModel.Tab.allCases) { t in
                Button { shell.tab = t } label: {
                    Text(t.title)
                        .font(.system(size: 13, weight: shell.tab == t ? .semibold : .regular))
                        .foregroundStyle(shell.tab == t ? Palette.ink : Palette.muted)
                        .padding(.horizontal, Spacing.md).frame(height: 26)
                        .background(shell.tab == t ? Palette.surfaceElevated : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.row))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Label(shell.selectedServiceName, systemImage: "cylinder.split.1x2")
                .font(Typography.caption).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
        .background(Palette.canvas)
    }
}
