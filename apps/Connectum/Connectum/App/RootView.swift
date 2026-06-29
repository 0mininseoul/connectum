import SwiftUI

struct RootView: View {
    let shell: ShellModel
    private let windowMinSize = CGSize(width: 1080, height: 680)

    var body: some View {
        MainShell(shell: shell)
            .frame(minWidth: 1080, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
        .vibrantBackground()
        .overlay(alignment: .topLeading) {
            WindowMinSizeEnforcer(minSize: windowMinSize)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
    }
}

// Persistent left sidebar (services) + top tab bar, shared across all tabs.
struct MainShell: View {
    @Bindable var shell: ShellModel

    var body: some View {
        NavigationSplitView(columnVisibility: $shell.columnVisibility) {
            ShellSidebar(shell: shell)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            VStack(spacing: 0) {
                ShellTabBar(shell: shell)
                Divider().overlay(Palette.hairline)
                content
                    // AI chat slides in as a trailing overlay drawer. An overlay is
                    // sized to its parent and never enlarges it, so opening the panel
                    // can't push the window off-screen. It covers the right edge of
                    // the content.
                    .overlay(alignment: .trailing) {
                        if shell.aiPanelVisible {
                            HStack(spacing: 0) {
                                Divider().overlay(Palette.hairline)
                                AIChatView(vm: shell.aiChat, serviceId: shell.selectedDataServiceId, isVisible: shell.aiPanelVisible)
                                    .frame(width: 380)
                            }
                            .frame(maxHeight: .infinity)
                            .background(Palette.canvas)
                            .transition(.move(edge: .trailing))
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
        }
        .task { await shell.load() }
    }

    @ViewBuilder private var content: some View {
        if !shell.didLoadServices {
            LoadingStateView()
        } else if shell.realServices.isEmpty && !shell.hasDraftService {
            FirstRunOnboardingView(shell: shell)
        } else {
            switch shell.tab {
            case .operational:
                if shell.selectedService?.isDraft == true {
                    ServiceSetupPlaceholder(shell: shell)
                } else {
                    OperationalDBView(serviceId: shell.selectedDataServiceId, refreshID: shell.syncRevision)
                }
            case .dashboard:
                if shell.selectedService?.isDraft == true {
                    ServiceSetupPlaceholder(shell: shell)
                } else {
                    DashboardView(serviceId: shell.selectedDataServiceId, refreshID: shell.syncRevision)
                }
            case .connections:
                ConnectionsView(
                    selectedService: shell.selectedService,
                    onServiceCreated: { name in await shell.finishServiceCreation(named: name) },
                    onServiceDeleted: { id in await shell.finishServiceDeletion(deletedId: id) },
                    onServiceUpdated: {
                        await shell.load()
                        if let service = shell.selectedService, service.supabaseAccountId != nil {
                            await shell.syncService(service)
                        }
                    }
                )
            }
        }
    }
}

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .controlSize(.small)
            Text("서비스를 불러오는 중")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }
}

struct FirstRunOnboardingView: View {
    @Bindable var shell: ShellModel

    var body: some View {
        ScrollView {
            onboardingContent
                .padding(Spacing.xxl)
                .frame(maxWidth: 860, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Palette.canvas)
    }

    private var onboardingContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                Image("ConnectumLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("첫 서비스 만들기")
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                    Text("운영 DB 원본을 연결하고 유저 테이블을 고르면 Connectum 작업 공간이 시작됩니다.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                onboardingStep(
                    index: "1",
                    icon: "server.rack",
                    title: "데이터베이스 연결",
                    detail: "운영 중인 원본 프로젝트에 접근할 계정을 연결하고 프로젝트 목록을 불러옵니다."
                )
                Divider().overlay(Palette.hairline)
                onboardingStep(
                    index: "2",
                    icon: "tablecells",
                    title: "유저 테이블 선택",
                    detail: "운영 DB에서 기준이 되는 테이블과 표시할 컬럼을 정합니다."
                )
                Divider().overlay(Palette.hairline)
                onboardingStep(
                    index: "3",
                    icon: "arrow.triangle.2.circlepath",
                    title: "첫 동기화",
                    detail: "서비스가 생성되면 데이터를 가져오고 대시보드를 채웁니다."
                )
            }
            .background(Palette.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))

            Button {
                shell.startNewService()
            } label: {
                Label("새 서비스 시작", systemImage: "plus")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.xl)
                    .frame(height: 42)
                    .background(Palette.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .buttonStyle(.plain)
        }
    }

    private func onboardingStep(index: String, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(index)
                .font(Typography.caption)
                .foregroundStyle(Palette.ctaText)
                .frame(width: 20, height: 20)
                .background(Palette.ctaFill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.accentBlue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.sm)
        }
        .padding(Spacing.md)
    }
}

struct ServiceSetupPlaceholder: View {
    @Bindable var shell: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Image(systemName: "plus.square.dashed")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Palette.accentBlue)
            Text("새 서비스 설정")
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.ink)
            Text("연동 탭에서 기존 Supabase 프로젝트와 운영 DB 컬럼을 정하면 서비스가 생성됩니다.")
                .font(Typography.body)
                .foregroundStyle(Palette.muted)
            Button {
                shell.tab = .connections
            } label: {
                Label("연동으로 이동", systemImage: "arrow.right")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 38)
                    .background(Palette.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Palette.canvas)
    }
}

struct ShellSidebar: View {
    @Bindable var shell: ShellModel

    var body: some View {
        sidebarStack
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarFooter
            }
        .font(Typography.body)
        .background {
            ZStack {
                VisualEffectView(material: .sidebar)
                Palette.sidebarOverlay
            }
            .ignoresSafeArea()
        }
        .navigationTitle("Connectum")
    }

    private var sidebarStack: some View {
        VStack(spacing: 0) {
            sidebarContent
                .frame(maxHeight: .infinity)
            if let error = shell.syncErrorMessage {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accentRed)
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.xs)
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.hairline)
            sidebarActionBar
        }
    }

    @ViewBuilder private var sidebarContent: some View {
        if shell.services.isEmpty {
            EmptySidebarStart()
                .frame(maxHeight: .infinity, alignment: .topLeading)
        } else {
            List(selection: Binding(get: { shell.selectedServiceId }, set: { if let v = $0 { shell.selectedServiceId = v } })) {
                Section("서비스") {
                    ForEach(shell.services) { s in
                        ServiceSidebarRow(
                            service: s,
                            isSyncing: shell.syncingServiceIds.contains(s.id),
                            sync: { Task { await shell.syncService(s) } }
                        )
                        .tag(s.id)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var sidebarActionBar: some View {
        HStack(spacing: Spacing.sm) {
            if !shell.realServices.isEmpty || shell.hasDraftService {
                Button { shell.startNewService() } label: {
                    Label("새 서비스", systemImage: "plus")
                        .font(Typography.body)
                        .foregroundStyle(Palette.accentBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(height: 32, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: Spacing.sm)
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.md)
        .frame(minHeight: 56, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ZStack {
                VisualEffectView(material: .sidebar)
                Palette.sidebarOverlay
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

private struct EmptySidebarStart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("서비스")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                Text("첫 서비스를 연결하세요")
                    .font(Typography.body)
                    .foregroundStyle(Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ServiceSidebarRow: View {
    let service: Service
    let isSyncing: Bool
    let sync: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Label(service.name, systemImage: "cylinder.split.1x2")
                .font(Typography.body)
                .lineLimit(1)
            Spacer(minLength: Spacing.sm)
            if !service.isDraft {
                Button(action: sync) {
                    if isSyncing {
                        SyncIcon()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isSyncing)
                .help("input source 수동 동기화")
            }
        }
    }
}

private struct SyncIcon: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.accentBlue)
                .rotationEffect(.degrees(phase * 360))
        }
    }
}

struct ShellTabBar: View {
    @Bindable var shell: ShellModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.xs) {
                ForEach(ShellModel.Tab.allCases) { t in
                    Button { shell.tab = t } label: {
                        MainTabButton(
                            title: t.title,
                            systemImage: t.systemImage,
                            isSelected: shell.tab == t
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.xs)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))

            Spacer()
            Label(shell.selectedServiceName, systemImage: "cylinder.split.1x2")
                .font(Typography.caption).foregroundStyle(Palette.muted)
            Button { shell.toggleAIPanel() } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(shell.aiPanelVisible ? Palette.accentBlue : Palette.muted)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("AI 채팅 (⌘I)")
        }
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.md)
        .background(Palette.canvas)
    }
}

private struct MainTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
        }
        .foregroundStyle(isSelected ? Palette.ink : Palette.body)
        .padding(.horizontal, Spacing.lg)
        .frame(minWidth: 118)
        .frame(height: 40)
        .background(isSelected ? Palette.surfaceElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.row))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.row)
                    .stroke(Palette.hairline)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.row))
    }
}
