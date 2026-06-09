import AppKit
import SwiftUI
import Observation

enum ConnectionProvider: String, CaseIterable, Identifiable {
    case supabase = "Supabase"
    case amplitude = "Amplitude"
    case axiom = "Axiom"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .supabase: return "server.rack"
        case .amplitude: return "waveform.path.ecg"
        case .axiom: return "doc.text.magnifyingglass"
        }
    }
    var displayTitle: String {
        switch self {
        case .supabase: return "Supabase 프로젝트"
        case .amplitude: return "Amplitude 분석"
        case .axiom: return "Axiom 로그"
        }
    }
    var shortTitle: String {
        switch self {
        case .supabase: return "Supabase"
        case .amplitude: return "Amplitude"
        case .axiom: return "Axiom"
        }
    }
    var accountRole: String {
        switch self {
        case .supabase: return "운영 DB 원본"
        case .amplitude: return "제품 이벤트"
        case .axiom: return "로그/히스토리"
        }
    }
}

private struct ConnectedAccountDeletion: Identifiable {
    let provider: ConnectionProvider
    let account: ConnAccount

    var id: String { "\(provider.id):\(account.id)" }
}

@MainActor
@Observable
final class ConnectionsViewModel {
    var supabase: [ConnAccount] = []
    var amplitude: [ConnAccount] = []
    var axiom: [ConnAccount] = []
    var claude: AIAccount?
    var status: String?
    var didLoad = false
    var isBusy = false
    var supabaseProjectNamesByRef: [String: String] = [:]
    var supabaseAccountNamesById: [String: String] = [:]
    var axiomDatasetsByAccountId: [String: [String]] = [:]
    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    func load() async {
        do {
            supabase = try await repo.fetchSupabaseAccounts()
            amplitude = try await repo.fetchAmplitudeAccounts()
            axiom = try await repo.fetchAxiomAccounts()
        } catch { status = "불러오기 실패: \(error)" }
        claude = (try? await repo.fetchAIAccount()) ?? nil
        didLoad = true
    }

    // Claude's public client rejects loopback redirects, so we use the manual
    // out-of-band flow: open the authorize URL, the user pastes the displayed code.
    private var pendingClaudePKCE: ClaudePKCE?
    private var pendingClaudeState: String?

    // Returns true if the browser opened (caller then shows the paste sheet).
    func startClaudeConnect() -> Bool {
        let cfg = SupabaseClientProvider.claudeConfig()
        guard !cfg.clientId.isEmpty else {
            status = "Claude OAuth 클라이언트가 설정되지 않았습니다 (config.json의 claudeClientId)."
            return false
        }
        let pkce = ClaudePKCE.generate()
        let state = UUID().uuidString
        pendingClaudePKCE = pkce
        pendingClaudeState = state
        let url = ClaudeOAuthFlow.authorizeURL(
            authorizeURL: cfg.authorizeURL, clientId: cfg.clientId,
            redirectURI: ClaudeOAuthFlow.manualRedirectURI, scope: cfg.scope,
            state: state, codeChallenge: pkce.challenge)
        guard NSWorkspace.shared.open(url) else {
            status = "브라우저를 열 수 없습니다."
            return false
        }
        return true
    }

    func finishClaudeConnect(pasted: String) async {
        guard let pkce = pendingClaudePKCE else { return }
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        // The console callback often returns "code#state".
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts.first ?? trimmed
        if parts.count > 1, let expected = pendingClaudeState, parts[1] != expected {
            status = "state 값이 일치하지 않습니다. 다시 시도하세요."
            return
        }
        guard !code.isEmpty else { status = "코드가 비어 있습니다."; return }
        isBusy = true; defer { isBusy = false }
        do {
            try await repo.connectClaude(
                code: code, state: pendingClaudeState, codeVerifier: pkce.verifier,
                redirectURI: ClaudeOAuthFlow.manualRedirectURI)
            claude = (try? await repo.fetchAIAccount()) ?? nil
            pendingClaudePKCE = nil
            pendingClaudeState = nil
            status = "Claude 연결됨"
        } catch {
            status = "Claude 연결 실패: \(error.localizedDescription)"
        }
    }

    func disconnectClaude() async {
        guard let id = claude?.id else { return }
        isBusy = true; defer { isBusy = false }
        do {
            try await repo.disconnectClaude(id: id)
            claude = nil
            status = "Claude 연결 해제됨"
        } catch { status = "Claude 연결 해제 실패: \(error)" }
    }

    func accounts(for provider: ConnectionProvider) -> [ConnAccount] {
        switch provider {
        case .supabase: return supabase
        case .amplitude: return amplitude
        case .axiom: return axiom
        }
    }

    var providersNeedingConnection: [ConnectionProvider] {
        ConnectionProvider.allCases.filter { accounts(for: $0).isEmpty }
    }

    var connectionSignature: String {
        "\(supabase.count):\(amplitude.count):\(axiom.count)"
    }

    func addSupabase(pat: String, label: String) async {
        isBusy = true; defer { isBusy = false }
        do {
            try await repo.connectSupabasePAT(pat: pat, label: label.isEmpty ? "Supabase" : label)
            status = "Supabase 연결됨"
            await load()
        } catch { status = "Supabase 연결 실패: \(error)" }
    }

    @discardableResult
    func connectSupabaseOAuth() async -> Bool {
        isBusy = true; defer { isBusy = false }
        let receiver = SupabaseOAuthLoopbackReceiver()
        do {
            let port = try SupabaseOAuthLoopbackReceiver.availablePort()
            let loopbackURL = SupabaseOAuthFlow.redirectURI(port: port)
            let state = SupabaseOAuthState.generate(loopbackURL: loopbackURL)
            let authorizeURL = try await repo.supabaseOAuthAuthorizeURL(state: state)
            let callbackTask = Task {
                try await receiver.waitForCallback(expectedState: state, port: port)
            }
            guard NSWorkspace.shared.open(authorizeURL) else {
                receiver.cancel()
                callbackTask.cancel()
                status = "브라우저를 열 수 없습니다."
                return false
            }
            let callback = try await callbackTask.value
            try await repo.connectSupabaseOAuth(code: callback.code, state: callback.state)
            receiver.cancel()
            status = "Supabase 연결됨"
            await load()
            return true
        } catch {
            receiver.cancel()
            status = "Supabase 연결 실패: \(friendlySupabaseOAuthError(error))"
            return false
        }
    }

    func repairSupabaseConnection(for service: Service) async -> Bool {
        guard !service.isDraft, let projectRef = service.supabaseProjectRef else {
            status = "복구할 Supabase 프로젝트 정보가 없습니다."
            return false
        }

        if supabase.isEmpty {
            let connected = await connectSupabaseOAuth()
            guard connected else { return false }
        }

        isBusy = true
        defer { isBusy = false }
        do {
            for account in supabase {
                let projects = try await repo.listProjects(supabaseAccountId: account.id)
                if projects.contains(where: { $0.ref == projectRef }) {
                    try await repo.updateServiceSupabaseAccount(serviceId: service.id, accountId: account.id)
                    status = "Supabase 원본 복구됨"
                    await load()
                    await refreshDisplayContext(for: service)
                    return true
                }
            }
            status = "연결한 Supabase 계정에서 \(service.supabaseProjectName ?? projectRef) 프로젝트를 찾을 수 없습니다."
            return false
        } catch {
            status = "Supabase 원본 복구 실패: \(friendlySupabaseOAuthError(error))"
            return false
        }
    }

    private func friendlySupabaseOAuthError(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.contains("404") {
            return "OAuth 서버 함수가 아직 배포되지 않았습니다. 수동 연결을 사용하세요."
        }
        if message.contains("403") {
            return "OAuth 서버 권한 설정이 필요합니다. 수동 연결을 사용하세요."
        }
        if message.contains("SUPABASE_OAUTH_CLIENT_ID") || message.contains("SUPABASE_OAUTH_CLIENT_SECRET") {
            return "OAuth 클라이언트 설정이 필요합니다. 수동 연결을 사용하세요."
        }
        if error is CancellationError {
            return "연결이 취소되었습니다."
        }
        return message
    }

    func addAmplitude(projectName: String, key: String, secret: String, region: String) async {
        isBusy = true; defer { isBusy = false }
        do {
            try await repo.connectAmplitude(
                projectName: projectName,
                apiKey: key,
                secretKey: secret,
                region: region.isEmpty ? "us" : region
            )
            status = "Amplitude 연결됨"
            await load()
        } catch { status = "Amplitude 연결 실패: \(error)" }
    }

    func addAxiom(token: String) async {
        isBusy = true; defer { isBusy = false }
        do {
            let ds = try await repo.connectAxiom(token: token)
            status = "Axiom 연결됨 (데이터셋 \(ds.count)개)"
            await load()
        } catch { status = "Axiom 연결 실패: \(error)" }
    }

    func deleteService(_ service: Service) async -> Bool {
        guard !service.isDraft else { return false }
        isBusy = true; defer { isBusy = false }
        do {
            try await repo.deleteService(serviceId: service.id)
            status = "\(service.name) 삭제됨"
            return true
        } catch {
            status = "서비스 삭제 실패: \(error)"
            return false
        }
    }

    func deleteAccount(provider: ConnectionProvider, account: ConnAccount) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do {
            switch provider {
            case .supabase:
                try await repo.deleteSupabaseAccount(id: account.id)
            case .amplitude:
                try await repo.deleteAmplitudeAccount(id: account.id)
            case .axiom:
                try await repo.deleteAxiomAccount(id: account.id)
            }
            status = "\(provider.displayTitle) 계정 삭제됨"
            await load()
            return true
        } catch {
            status = "\(provider.displayTitle) 계정 삭제 실패: \(error)"
            return false
        }
    }

    func refreshDisplayContext(for service: Service?) async {
        guard let service, !service.isDraft else { return }
        await refreshSupabaseDisplayContext(for: service)
        await refreshAxiomDisplayContext(for: service)
    }

    private func refreshSupabaseDisplayContext(for service: Service) async {
        guard let accountId = service.supabaseAccountId else { return }
        if supabaseAccountNamesById[accountId] == nil,
           let account = supabase.first(where: { $0.id == accountId }),
           let name = cleanAccountName(account) {
            supabaseAccountNamesById[accountId] = name
        }
        if supabaseAccountNamesById[accountId] == nil {
            if let profileName = try? await repo.fetchSupabaseAccountProfile(id: accountId),
               let cleaned = clean(profileName) {
                supabaseAccountNamesById[accountId] = cleaned
            }
        }
        guard let ref = service.supabaseProjectRef, supabaseProjectNamesByRef[ref] == nil else { return }
        if let stored = clean(service.supabaseProjectName) {
            supabaseProjectNamesByRef[ref] = stored
            return
        }
        if let projects = try? await repo.listProjects(supabaseAccountId: accountId),
           let project = projects.first(where: { $0.ref == ref }) {
            supabaseProjectNamesByRef[ref] = project.name
        }
    }

    private func refreshAxiomDisplayContext(for service: Service) async {
        guard let accountId = service.axiomAccountId else { return }
        if axiomDatasetsByAccountId[accountId] == nil,
           let account = axiom.first(where: { $0.id == accountId }),
           let datasets = account.datasets,
           !datasets.isEmpty {
            axiomDatasetsByAccountId[accountId] = datasets
        }
        if axiomDatasetsByAccountId[accountId] == nil,
           let datasets = try? await repo.listAxiomDatasets(accountId: accountId),
           !datasets.isEmpty {
            axiomDatasetsByAccountId[accountId] = datasets
        }
    }

    func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func cleanAccountName(_ account: ConnAccount) -> String? {
        if let accountName = clean(account.accountName) { return accountName }
        let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.contains("@") else { return nil }
        return label
    }
}

struct ConnectionsView: View {
    let selectedService: Service?
    let onServiceCreated: (String) async -> Void
    let onServiceDeleted: (String) async -> Void
    let onServiceUpdated: () async -> Void

    @State private var vm = ConnectionsViewModel()
    @State private var provider: ConnectionProvider = .supabase
    @State private var sbPat = ""
    @State private var sbLabel = ""
    @State private var amProjectName = ""
    @State private var amKey = ""
    @State private var amSecret = ""
    @State private var amRegion = "us"
    @State private var axToken = ""
    @State private var servicePendingDeletion: Service?
    @State private var accountPendingDeletion: ConnectedAccountDeletion?
    @State private var deleteConfirmationName = ""

    init(
        selectedService: Service? = nil,
        onServiceCreated: @escaping (String) async -> Void = { _ in },
        onServiceDeleted: @escaping (String) async -> Void = { _ in },
        onServiceUpdated: @escaping () async -> Void = {}
    ) {
        self.selectedService = selectedService
        self.onServiceCreated = onServiceCreated
        self.onServiceDeleted = onServiceDeleted
        self.onServiceUpdated = onServiceUpdated
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                setupContent
                ClaudeConnectCard(vm: vm)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 1280, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("서비스 삭제", isPresented: Binding(
            get: { servicePendingDeletion != nil },
            set: { if !$0 { servicePendingDeletion = nil; deleteConfirmationName = "" } }
        )) {
            TextField("서비스 이름 입력", text: $deleteConfirmationName)
            if let service = servicePendingDeletion {
                Button("삭제", role: .destructive) {
                    Task {
                        if await vm.deleteService(service) {
                            await onServiceDeleted(service.id)
                        }
                        servicePendingDeletion = nil
                        deleteConfirmationName = ""
                    }
                }
                .disabled(deleteConfirmationName != service.name || vm.isBusy)
            }
            Button("취소", role: .cancel) {
                servicePendingDeletion = nil
                deleteConfirmationName = ""
            }
        } message: {
            if let service = servicePendingDeletion {
                Text("'\(service.name)' 서비스를 삭제합니다. 운영 DB 유저, 동기화 상태, 저장된 뷰 등 이 서비스에 연결된 데이터가 함께 삭제됩니다.")
            }
        }
        .alert("연결 계정 삭제", isPresented: Binding(
            get: { accountPendingDeletion != nil },
            set: { if !$0 { accountPendingDeletion = nil } }
        )) {
            if let deletion = accountPendingDeletion {
                Button("삭제", role: .destructive) {
                    let target = deletion
                    accountPendingDeletion = nil
                    Task {
                        _ = await vm.deleteAccount(provider: target.provider, account: target.account)
                        await onServiceUpdated()
                    }
                }
                .disabled(vm.isBusy)
            }
            Button("취소", role: .cancel) {
                accountPendingDeletion = nil
            }
        } message: {
            if let deletion = accountPendingDeletion {
                Text("'\(deletion.account.label)' \(deletion.provider.displayTitle) 계정을 삭제합니다. 이 계정을 쓰는 서비스는 해당 데이터 원본 연결이 끊기며, 다시 연결하기 전까지 동기화할 수 없습니다.")
            }
        }
        .task {
            await vm.load()
            await vm.refreshDisplayContext(for: selectedService)
            alignConnectionProvider()
        }
        .onChange(of: vm.connectionSignature) { _, _ in
            Task { await vm.refreshDisplayContext(for: selectedService) }
            alignConnectionProvider()
        }
        .onChange(of: selectedService?.id) { _, _ in
            Task { await vm.refreshDisplayContext(for: selectedService) }
            alignConnectionProvider()
        }
    }

    private func alignConnectionProvider() {
        if let selectedService, requiresSupabaseRepair(selectedService) {
            provider = .supabase
            return
        }
        if let selectedService, !selectedService.isDraft {
            let providers = availableOptionalProviders(for: selectedService)
            if let first = providers.first, !providers.contains(provider) {
                provider = first
            }
            return
        }
        guard let first = vm.providersNeedingConnection.first else { return }
        if !vm.providersNeedingConnection.contains(provider) {
            provider = first
        }
    }

    @ViewBuilder private var setupContent: some View {
        if selectedService?.isDraft == true {
            if vm.supabase.isEmpty {
                AccountConnectionPanel(
                    vm: vm,
                    provider: $provider,
                    availableProviders: [.supabase],
                    sbPat: $sbPat,
                    sbLabel: $sbLabel,
                    amKey: $amKey,
                    amSecret: $amSecret,
                    amProjectName: $amProjectName,
                    amRegion: $amRegion,
                    axToken: $axToken
                )
                .frame(width: 480, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ServiceWizardView(
                    draftService: selectedService,
                    onCreated: onServiceCreated
                )
                .frame(minWidth: 640, maxWidth: 860, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            if let selectedService, !selectedService.isDraft {
                realServiceContent(selectedService)
            } else {
                emptySelectionPanel
                    .frame(minWidth: 360, maxWidth: 520, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func realServiceContent(_ service: Service) -> some View {
        if !vm.didLoad {
            // Avoid flashing the repair panel before accounts have loaded.
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        } else if requiresSupabaseRepair(service) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SupabaseRepairPanel(service: service, isBusy: vm.isBusy) {
                    Task {
                        if await vm.repairSupabaseConnection(for: service) {
                            await onServiceUpdated()
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)

                ServiceDangerZone(service: service, isBusy: vm.isBusy) {
                    deleteConfirmationName = ""
                    servicePendingDeletion = service
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.lg) {
                ConnectedAccountsPanel(selectedService: service, vm: vm) { deletion in
                    accountPendingDeletion = deletion
                }
                .frame(minWidth: 440, maxWidth: 620, alignment: .topLeading)

                VStack(spacing: Spacing.md) {
                    let optionalProviders = availableOptionalProviders(for: service)
                    if !optionalProviders.isEmpty {
                        AccountConnectionPanel(
                            vm: vm,
                            provider: $provider,
                            availableProviders: optionalProviders,
                            title: "선택 연동 추가",
                            sbPat: $sbPat,
                            sbLabel: $sbLabel,
                            amKey: $amKey,
                            amSecret: $amSecret,
                            amProjectName: $amProjectName,
                            amRegion: $amRegion,
                            axToken: $axToken
                        )
                    }
                    ServiceDangerZone(service: service, isBusy: vm.isBusy) {
                        deleteConfirmationName = ""
                        servicePendingDeletion = service
                    }
                }
                .frame(width: 380, alignment: .top)
                Spacer(minLength: 0)
            }
        }
    }

    private func requiresSupabaseRepair(_ service: Service) -> Bool {
        guard !service.isDraft else { return false }
        guard let accountId = service.supabaseAccountId else { return true }
        return !vm.supabase.contains { $0.id == accountId }
    }

    private func availableOptionalProviders(for service: Service) -> [ConnectionProvider] {
        ConnectionProvider.allCases.filter { provider in
            switch provider {
            case .supabase:
                return false
            case .amplitude:
                return service.amplitudeAccountId == nil && vm.amplitude.isEmpty
            case .axiom:
                return service.axiomAccountId == nil && vm.axiom.isEmpty
            }
        }
    }

    private var emptySelectionPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: "sidebar.leading")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Palette.accentBlue)
            Text("서비스를 선택하세요")
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
            Text("좌측 사이드바에서 연결 상태를 볼 서비스를 고르세요.")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(selectedService?.isDraft == true ? "새 서비스" : "연동")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.ink)
                Text(selectedService?.isDraft == true ? "연동 계정과 운영 DB 기준을 정하세요" : "서비스별 데이터 연결 상태")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            if let status = vm.status {
                Text(status)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accentBlue)
                    .lineLimit(1)
            }
        }
    }
}

private enum SetupGuideMode {
    case connectSupabase
    case configureService
}

private struct SetupGuidePanel: View {
    let mode: SetupGuideMode

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: mode == .connectSupabase ? "1.circle.fill" : "2.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.accentBlue)
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
            }
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                guideRow(icon: "safari", title: "Supabase 승인", state: mode == .connectSupabase ? "필요" : "완료")
                guideRow(icon: "rectangle.stack", title: "프로젝트 선택", state: mode == .connectSupabase ? "다음" : "진행 중")
                guideRow(icon: "person.crop.circle", title: "유저 테이블 지정", state: "다음")
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }

    private var title: String {
        switch mode {
        case .connectSupabase: return "Supabase부터 연결하세요"
        case .configureService: return "서비스 기준을 정하세요"
        }
    }

    private var detail: String {
        switch mode {
        case .connectSupabase:
            return "브라우저에서 Supabase 권한을 승인하면 프로젝트와 테이블을 선택할 수 있습니다."
        case .configureService:
            return "프로젝트를 불러온 뒤 운영 DB의 유저 테이블과 화면에 보여줄 컬럼을 선택합니다."
        }
    }

    private func guideRow(icon: String, title: String, state: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 18)
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.body)
            Spacer()
            Text(state)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(state == "완료" ? Palette.accentGreen : Palette.muted)
        }
    }
}

private struct ServiceDangerZone: View {
    let service: Service
    let isBusy: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accentRed)
                Text("Danger Zone")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
            }
            Text(service.name)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            Button(action: onDelete) {
                Label("서비스 삭제", systemImage: "trash")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accentRed)
                    .frame(height: 30)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.accentRed.opacity(0.45)))
    }
}

private struct SupabaseRepairPanel: View {
    let service: Service
    let isBusy: Bool
    let onRepair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.accentYellow)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("운영 DB 원본을 다시 연결하세요")
                        .font(Typography.cardTitle)
                        .foregroundStyle(Palette.ink)
                    Text("이 서비스의 Supabase 계정이 삭제되어 동기화할 수 없습니다. 같은 프로젝트에 접근할 수 있는 Supabase 계정을 승인하면 기존 테이블 설정을 그대로 사용합니다.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.md)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                infoRow("서비스", service.name)
                infoRow("프로젝트", service.supabaseProjectName ?? service.supabaseProjectRef ?? "프로젝트 정보 없음")
            }

            Button(action: onRepair) {
                Label(isBusy ? "브라우저 대기 중" : "Supabase 다시 연결", systemImage: "safari")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 40)
                    .background(Palette.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.accentYellow.opacity(0.45)))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: Spacing.md) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(Typography.body)
                .foregroundStyle(Palette.body)
                .lineLimit(1)
        }
    }
}

private struct ConnectedAccountsPanel: View {
    let selectedService: Service?
    @Bindable var vm: ConnectionsViewModel
    let onDelete: (ConnectedAccountDeletion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("연결된 데이터 소스")
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
            accountGroup(.supabase, accounts: serviceAccounts(.supabase))
            accountGroup(.amplitude, accounts: serviceAccounts(.amplitude))
            accountGroup(.axiom, accounts: serviceAccounts(.axiom))
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }

    private func accountGroup(_ provider: ConnectionProvider, accounts: [ConnAccount]) -> some View {
        let missingRequiredSource = isMissingRequiredSource(provider)
        let missingReferencedAccount = hasMissingReferencedAccount(provider: provider, accounts: accounts)
        let isMissing = missingRequiredSource || missingReferencedAccount
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: provider.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isMissing ? Palette.accentYellow : Palette.accentBlue)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayTitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.body)
                    Text(provider.accountRole)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(groupStatusText(accounts: accounts, isMissing: isMissing))
                    .font(Typography.caption)
                    .foregroundStyle(isMissing ? Palette.accentYellow : (accounts.isEmpty ? Palette.ash : Palette.accentGreen))
            }
            if isMissing {
                HStack(spacing: Spacing.sm) {
                    Circle().fill(Palette.accentYellow).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(missingRequiredSource ? "운영 DB 원본 없음" : "연결 계정이 삭제됨")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(provider == .supabase ? "Supabase를 다시 연결해야 동기화할 수 있습니다." : "이 서비스에서 다시 선택해야 합니다.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Spacing.sm)
                }
                .padding(.leading, 26)
            }
            ForEach(accounts) { account in
                HStack(spacing: Spacing.sm) {
                    Circle().fill(Palette.accentGreen).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(resourceTitle(provider: provider, account: account))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(accountDisplayName(provider: provider, account: account))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Spacing.sm)
                    Button {
                        onDelete(ConnectedAccountDeletion(provider: provider, account: account))
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isBusy)
                    .help("\(provider.displayTitle) 계정 삭제")
                }
                .padding(.leading, 26)
            }
        }
        .padding(.vertical, Spacing.sm)
        .overlay(alignment: .bottom) {
            Divider().overlay(Palette.hairline.opacity(provider == .axiom ? 0 : 1))
        }
    }

    private func groupStatusText(accounts: [ConnAccount], isMissing: Bool) -> String {
        if isMissing { return "복구 필요" }
        return accounts.isEmpty ? "없음" : "\(accounts.count)"
    }

    private func isMissingRequiredSource(_ provider: ConnectionProvider) -> Bool {
        guard provider == .supabase, let selectedService, !selectedService.isDraft else { return false }
        return selectedService.supabaseAccountId == nil
    }

    private func hasMissingReferencedAccount(provider: ConnectionProvider, accounts: [ConnAccount]) -> Bool {
        guard let selectedService, !selectedService.isDraft else { return false }
        guard accounts.isEmpty else { return false }
        switch provider {
        case .supabase:
            return selectedService.supabaseAccountId != nil
        case .amplitude:
            return selectedService.amplitudeAccountId != nil
        case .axiom:
            return selectedService.axiomAccountId != nil
        }
    }

    private func serviceAccounts(_ provider: ConnectionProvider) -> [ConnAccount] {
        guard let selectedService, !selectedService.isDraft else {
            return vm.accounts(for: provider)
        }
        switch provider {
        case .supabase:
            guard let id = selectedService.supabaseAccountId else { return [] }
            return vm.supabase.filter { $0.id == id }
        case .amplitude:
            guard let id = selectedService.amplitudeAccountId else { return [] }
            return vm.amplitude.filter { $0.id == id }
        case .axiom:
            guard let id = selectedService.axiomAccountId else { return [] }
            return vm.axiom.filter { $0.id == id }
        }
    }

    private func resourceTitle(provider: ConnectionProvider, account: ConnAccount) -> String {
        guard let selectedService, !selectedService.isDraft else {
            return standaloneResourceTitle(provider: provider, account: account)
        }
        switch provider {
        case .supabase:
            if let ref = selectedService.supabaseProjectRef,
               let resolved = vm.supabaseProjectNamesByRef[ref],
               !resolved.isEmpty {
                return resolved
            }
            if let stored = vm.clean(selectedService.supabaseProjectName) { return stored }
            if let serviceName = vm.clean(selectedService.name) { return serviceName }
            return "프로젝트 이름 미확인"
        case .amplitude:
            if let serviceProject = vm.clean(selectedService.amplitudeProjectName) { return serviceProject }
            if let accountProject = vm.clean(account.projectName) { return accountProject }
            return "프로젝트 이름 미확인"
        case .axiom:
            if let dataset = vm.clean(selectedService.axiomDataset) { return dataset }
            if let datasets = vm.axiomDatasetsByAccountId[account.id], datasets.count == 1 {
                return datasets[0]
            }
            if let datasets = account.datasets, datasets.count == 1 {
                return datasets[0]
            }
            return "데이터셋 미지정"
        }
    }

    private func standaloneResourceTitle(provider: ConnectionProvider, account: ConnAccount) -> String {
        switch provider {
        case .supabase:
            return "프로젝트 선택 전"
        case .amplitude:
            return vm.clean(account.projectName) ?? "프로젝트 이름 미확인"
        case .axiom:
            if let datasets = account.datasets, datasets.count == 1 { return datasets[0] }
            return "데이터셋 미지정"
        }
    }

    private func accountDisplayName(provider: ConnectionProvider, account: ConnAccount) -> String {
        if provider == .amplitude {
            return "Export API"
        }
        if let resolved = vm.supabaseAccountNamesById[account.id], !resolved.isEmpty {
            return resolved
        }
        if let name = vm.cleanAccountName(account) {
            return name
        }
        return "계정 이름 미확인"
    }
}

// Workspace-global Claude (AI) connection — powers the AI chat panel (⌘I).
private struct ClaudeConnectCard: View {
    @Bindable var vm: ConnectionsViewModel
    @State private var showPaste = false
    @State private var pasteCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude (AI)")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                    Text("AI 채팅 (⌘I) · 워크스페이스 전역")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                if vm.claude != nil {
                    HStack(spacing: Spacing.xs) {
                        Circle().fill(Palette.accentGreen).frame(width: 7, height: 7)
                        Text("연결됨").font(Typography.caption).foregroundStyle(Palette.accentGreen)
                    }
                }
            }

            Text("내 Claude 구독으로 로그인하면 현재 선택한 서비스의 데이터를 이해한 채팅을 쓸 수 있어요.")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if vm.claude != nil {
                Button { Task { await vm.disconnectClaude() } } label: {
                    Label("연결 해제", systemImage: "xmark.circle")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.accentRed)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
                .disabled(vm.isBusy)
            } else {
                Button {
                    if vm.startClaudeConnect() { showPaste = true }
                } label: {
                    Label("Claude 계정 연결", systemImage: "safari")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ctaText)
                        .padding(.horizontal, Spacing.lg)
                        .frame(height: 38)
                        .background(Palette.ctaFill)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
                .buttonStyle(.plain)
                .disabled(vm.isBusy)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
        .sheet(isPresented: $showPaste) { pasteSheet }
    }

    private var pasteSheet: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Claude 인증 코드 붙여넣기")
                .font(Typography.cardTitle).foregroundStyle(Palette.ink)
            Text("브라우저에서 승인하면 화면에 코드가 표시됩니다. 그 코드를 복사해 여기에 붙여넣으세요. (형식: code 또는 code#state)")
                .font(Typography.caption).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("인증 코드", text: $pasteCode, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(2...4)
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                .background(Palette.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
            HStack {
                Spacer()
                Button("취소") { showPaste = false; pasteCode = "" }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted)
                Button {
                    Task {
                        await vm.finishClaudeConnect(pasted: pasteCode)
                        if vm.claude != nil { showPaste = false; pasteCode = "" }
                    }
                } label: {
                    Text(vm.isBusy ? "연결 중…" : "연결 완료")
                        .font(Typography.body).foregroundStyle(Palette.ctaText)
                        .padding(.horizontal, Spacing.lg).frame(height: 36)
                        .background(Palette.ctaFill)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
                .buttonStyle(.plain)
                .disabled(vm.isBusy || pasteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
        .background(Palette.canvas)
    }
}

private struct AccountConnectionPanel: View {
    @Bindable var vm: ConnectionsViewModel
    @Binding var provider: ConnectionProvider
    let availableProviders: [ConnectionProvider]
    var title = "계정 추가"
    @Binding var sbPat: String
    @Binding var sbLabel: String
    @Binding var amKey: String
    @Binding var amSecret: String
    @Binding var amProjectName: String
    @Binding var amRegion: String
    @Binding var axToken: String
    @State private var showManualSupabase = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if vm.isBusy {
                    ProgressView()
                        .scaleEffect(0.6)
                        .controlSize(.small)
                }
            }

            Picker("", selection: $provider) {
                ForEach(availableProviders) { provider in
                    Text(provider.shortTitle).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            providerFields

            if provider != .supabase {
                Button {
                    Task { await connect() }
                } label: {
                    Label(vm.isBusy ? "연결 중" : "\(provider.shortTitle) 연결", systemImage: "link")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ctaText)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 36)
                        .background(Palette.ctaFill)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
                .buttonStyle(.plain)
                .disabled(vm.isBusy || !canSubmit)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }

    @ViewBuilder private var providerFields: some View {
        switch provider {
        case .supabase:
            Text("브라우저에서 Supabase 권한을 승인합니다. 토큰은 Connectum 서버에만 저장됩니다.")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await vm.connectSupabaseOAuth() }
            } label: {
                Label(vm.isBusy ? "브라우저 대기 중" : "Supabase로 계속하기", systemImage: "safari")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 38)
                    .background(Palette.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .buttonStyle(.plain)
            .disabled(vm.isBusy)

            DisclosureGroup("수동 연결", isExpanded: $showManualSupabase) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    connectionField("Supabase Personal Access Token", text: $sbPat, secure: true)
                    connectionField("계정 이름 또는 이메일", text: $sbLabel)
                    Button {
                        Task { await connect() }
                    } label: {
                        Label(vm.isBusy ? "연결 중" : "PAT로 연결", systemImage: "key")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.body)
                            .frame(height: 34)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isBusy || sbPat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, Spacing.xs)
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.muted)
        case .amplitude:
            Text("Export API 자격증명으로 이벤트 연결을 검증합니다. Amplitude API가 프로젝트 이름을 제공하지 않으므로 프로젝트 이름만 직접 입력합니다.")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            connectionField("프로젝트 이름", text: $amProjectName)
            connectionField("API Key", text: $amKey)
            connectionField("Secret Key", text: $amSecret, secure: true)
            Picker("리전", selection: $amRegion) {
                Text("US").tag("us")
                Text("EU").tag("eu")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
        case .axiom:
            Text("Axiom API Token 또는 PAT로 데이터셋을 불러옵니다. 사용자/조직 정보 권한이 있으면 계정명도 자동으로 표시합니다.")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            connectionField("API Token 또는 PAT", text: $axToken, secure: true)
        }
    }

    @ViewBuilder private func connectionField(_ title: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField(title, text: text)
            } else {
                TextField(title, text: text)
            }
        }
        .textFieldStyle(.plain)
        .font(Typography.body)
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Spacing.sm)
        .frame(height: 36)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
    }

    private func connect() async {
        switch provider {
        case .supabase:
            await vm.addSupabase(pat: sbPat, label: sbLabel)
            sbPat = ""; sbLabel = ""
        case .amplitude:
            await vm.addAmplitude(projectName: amProjectName, key: amKey, secret: amSecret, region: amRegion)
            amProjectName = ""; amKey = ""; amSecret = ""
        case .axiom:
            await vm.addAxiom(token: axToken)
            axToken = ""
        }
    }

    private var canSubmit: Bool {
        switch provider {
        case .supabase:
            return !sbPat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .amplitude:
            return !amProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !amKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !amSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .axiom:
            return !axToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
