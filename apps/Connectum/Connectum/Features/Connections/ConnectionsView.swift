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
    var brandColor: Color {
        switch self {
        case .supabase: return Color(hex: "3ECF8E")  // Supabase green
        case .amplitude: return Color(hex: "2E6DF6") // Amplitude blue
        case .axiom: return Color(hex: "8A63D2")     // Axiom indigo
        }
    }
    var logoAsset: String {
        switch self {
        case .supabase: return "SupabaseLogo"
        case .amplitude: return "AmplitudeLogo"
        case .axiom: return "AxiomLogo"
        }
    }
    // All three marks are single-path monochrome SVGs rendered as tintable
    // templates (full-color/gradient SVGs don't render in the asset catalog, and
    // a dark navy fill is invisible on the dark chips). Tinted to the brand color.
    var logoIsTemplate: Bool { true }
}

private enum DatabaseProvider: String, CaseIterable, Identifiable {
    case supabase
    case firebase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supabase: return "Supabase"
        case .firebase: return "Firebase"
        }
    }

    var subtitle: String {
        switch self {
        case .supabase: return "Postgres 운영 DB"
        case .firebase: return "Firestore / Realtime DB"
        }
    }

    var tint: Color {
        switch self {
        case .supabase: return Color(hex: "3ECF8E")
        case .firebase: return Color(hex: "F59E0B")
        }
    }

    var logoAsset: String {
        switch self {
        case .supabase: return "SupabaseLogo"
        case .firebase: return "FirebaseLogo"
        }
    }

    var logoIsTemplate: Bool { true }
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
    var isSupabaseOAuthWaiting = false
    var supabaseProjectNamesByRef: [String: String] = [:]
    var supabaseAccountNamesById: [String: String] = [:]
    var axiomDatasetsByAccountId: [String: [String]] = [:]
    private let repo: CrmDataProviding
    private let supportsSupabaseOAuth: Bool
    private var supabaseOAuthAttemptID: UUID?
    private var supabaseOAuthReceiver: SupabaseOAuthLoopbackReceiver?

    init(repo: CrmDataProviding = CrmRepository()) {
        self.repo = repo
        self.supportsSupabaseOAuth = true
    }

    var canUseSupabaseOAuth: Bool { supportsSupabaseOAuth }

    private func beginSupabaseOAuthAttempt() -> UUID {
        supabaseOAuthReceiver?.cancel()
        let attemptID = UUID()
        supabaseOAuthAttemptID = attemptID
        supabaseOAuthReceiver = nil
        isSupabaseOAuthWaiting = true
        isBusy = true
        return attemptID
    }

    private func bindSupabaseOAuthReceiver(_ receiver: SupabaseOAuthLoopbackReceiver, to attemptID: UUID) {
        guard supabaseOAuthAttemptID == attemptID else {
            receiver.cancel()
            return
        }
        supabaseOAuthReceiver = receiver
    }

    private func finishSupabaseOAuthAttempt(_ attemptID: UUID) {
        guard supabaseOAuthAttemptID == attemptID else { return }
        supabaseOAuthReceiver?.cancel()
        supabaseOAuthReceiver = nil
        supabaseOAuthAttemptID = nil
        isSupabaseOAuthWaiting = false
        isBusy = false
    }

    private func cancelSupabaseOAuthAttempt(status message: String? = nil) {
        guard isSupabaseOAuthWaiting else { return }
        supabaseOAuthAttemptID = nil
        supabaseOAuthReceiver?.cancel()
        supabaseOAuthReceiver = nil
        isSupabaseOAuthWaiting = false
        isBusy = false
        if let message { status = message }
    }

    private func isSupersededSupabaseOAuthAttempt(_ attemptID: UUID) -> Bool {
        supabaseOAuthAttemptID != attemptID
    }

    func load() async {
        do {
            supabase = try await repo.fetchSupabaseAccounts()
            amplitude = try await repo.fetchAmplitudeAccounts()
            axiom = try await repo.fetchAxiomAccounts()
        } catch { status = "불러오기 실패: \(error)" }
        claude = (try? await repo.fetchAIAccount()) ?? nil
        didLoad = true
    }

    private var pendingClaudePKCE: ClaudePKCE?
    private var pendingClaudeState: String?

    func startClaudeConnect() -> Bool {
        let config = SupabaseClientProvider.claudeConfig()
        guard !config.clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Claude OAuth client_id가 설정되지 않았습니다."
            return false
        }
        let pkce = ClaudePKCE.generate()
        let state = SupabaseOAuthState.generate()
        pendingClaudePKCE = pkce
        pendingClaudeState = state
        let url = ClaudeOAuthFlow.authorizeURL(
            authorizeURL: config.authorizeURL,
            clientId: config.clientId,
            redirectURI: ClaudeOAuthFlow.manualRedirectURI,
            scope: config.scope,
            state: state,
            codeChallenge: pkce.challenge
        )
        NSWorkspace.shared.open(url)
        status = "브라우저에서 Claude 인증을 완료한 뒤 코드를 붙여넣으세요."
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
        guard canUseSupabaseOAuth else {
            status = "현재 버전에서는 Supabase 토큰으로 연결하세요. 자동 OAuth는 배포 서버 설정이 완료된 버전에서 제공됩니다."
            return false
        }
        guard !isBusy || isSupabaseOAuthWaiting else {
            status = "진행 중인 작업이 끝난 뒤 다시 시도하세요."
            return false
        }

        let attemptID = beginSupabaseOAuthAttempt()
        defer { finishSupabaseOAuthAttempt(attemptID) }

        let receiver = SupabaseOAuthLoopbackReceiver()
        bindSupabaseOAuthReceiver(receiver, to: attemptID)
        do {
            let port = try SupabaseOAuthLoopbackReceiver.availablePort()
            let loopbackURL = SupabaseOAuthFlow.redirectURI(port: port)
            let state = SupabaseOAuthState.generate(loopbackURL: loopbackURL)
            let authorizeURL = try await repo.supabaseOAuthAuthorizeURL(state: state)
            let callbackTask = Task {
                try await receiver.waitForCallback(expectedState: state, port: port)
            }
            guard NSWorkspace.shared.open(authorizeURL) else {
                callbackTask.cancel()
                receiver.cancel()
                status = "브라우저를 열 수 없습니다."
                return false
            }
            status = "Supabase 승인 대기 중"
            let callback = try await callbackTask.value
            try await repo.connectSupabaseOAuth(code: callback.code, state: callback.state)
            status = "Supabase 연결됨"
            await load()
            return true
        } catch is CancellationError {
            let superseded = isSupersededSupabaseOAuthAttempt(attemptID)
            if !superseded {
                status = "Supabase 승인이 취소되었습니다. 다시 시도하세요."
            }
            return superseded
        } catch {
            if !isSupersededSupabaseOAuthAttempt(attemptID) {
                status = "Supabase OAuth 실패: \(friendlySupabaseOAuthError(error))"
            }
            return false
        }
    }

    func openSupabasePATPage() {
        cancelSupabaseOAuthAttempt()
        guard let url = URL(string: "https://supabase.com/dashboard/account/tokens") else { return }
        NSWorkspace.shared.open(url)
        status = "Supabase 토큰 페이지를 열었습니다. 발급한 PAT는 이 기기의 Keychain에만 저장됩니다."
    }

    func openFirebaseConsole() {
        guard let url = URL(string: "https://console.firebase.google.com/") else { return }
        NSWorkspace.shared.open(url)
        status = "Firebase는 Google OAuth와 Firestore 매핑이 필요합니다. 현재 지원 검토 중입니다."
    }

    func openOpenAIAPIKeys() {
        guard let url = URL(string: "https://platform.openai.com/api-keys") else { return }
        NSWorkspace.shared.open(url)
        status = "OpenAI API key 페이지를 열었습니다."
    }

    func openGeminiOAuthGuide() {
        guard let url = URL(string: "https://ai.google.dev/gemini-api/docs/oauth") else { return }
        NSWorkspace.shared.open(url)
        status = "Gemini OAuth 가이드를 열었습니다."
    }

    func repairSupabaseConnection(for service: Service) async -> Bool {
        guard !service.isDraft, let projectRef = service.supabaseProjectRef else {
            status = "복구할 Supabase 프로젝트 정보가 없습니다."
            return false
        }

        if supabase.isEmpty {
            guard canUseSupabaseOAuth else {
                status = "Supabase 계정 연결이 필요합니다. 연동 탭에서 PAT로 Supabase를 다시 연결하세요."
                return false
            }
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
        if message.contains("브리지")
            || message.localizedCaseInsensitiveContains("oauth bridge")
            || message.localizedCaseInsensitiveContains("Connectum Supabase OAuth client is not configured")
            || message.localizedCaseInsensitiveContains("OAuth broker 설정") {
            return "Connectum OAuth 서버에 Supabase OAuth 앱 client_id/client_secret 설정이 필요합니다. 설정 전에는 PAT 발급 페이지로 보조 연결할 수 있습니다."
        }
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

    // Connect a provider AND attach it to an existing service (sync requires the
    // service to reference the account). Returns true on success.
    func connectAmplitudeForService(_ service: Service, projectName: String, key: String, secret: String, region: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do {
            let before = Set(amplitude.map(\.id))
            try await repo.connectAmplitude(projectName: projectName, apiKey: key, secretKey: secret, region: region.isEmpty ? "us" : region)
            amplitude = try await repo.fetchAmplitudeAccounts()
            guard let acc = amplitude.first(where: { !before.contains($0.id) }) ?? amplitude.last else {
                status = "Amplitude 계정을 찾지 못했습니다"; return false
            }
            try await repo.updateServiceAmplitudeAccount(serviceId: service.id, accountId: acc.id)
            status = "Amplitude 연결됨"
            await load()
            return true
        } catch { status = "Amplitude 연결 실패: \(error)"; return false }
    }

    func connectAxiomForService(_ service: Service, token: String) async -> Bool {
        isBusy = true; defer { isBusy = false }
        do {
            let before = Set(axiom.map(\.id))
            let datasets = try await repo.connectAxiom(token: token)
            axiom = try await repo.fetchAxiomAccounts()
            guard let acc = axiom.first(where: { !before.contains($0.id) }) ?? axiom.last else {
                status = "Axiom 계정을 찾지 못했습니다"; return false
            }
            try await repo.updateServiceAxiomAccount(serviceId: service.id, accountId: acc.id, dataset: datasets.first)
            status = "Axiom 연결됨 (데이터셋 \(datasets.count)개)"
            await load()
            return true
        } catch { status = "Axiom 연결 실패: \(error)"; return false }
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
    @State private var databaseProvider: DatabaseProvider = .supabase
    @State private var sbPat = ""
    @State private var sbLabel = ""
    @State private var servicePendingDeletion: Service?
    @State private var accountPendingDeletion: ConnectedAccountDeletion?
    @State private var deleteConfirmationName = ""
    @State private var showTableEditor = false

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
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    if showsHeaderStatus, let status = vm.status {
                        ConnectionStatusNotice(text: status)
                    }
                    setupContent(viewportHeight: proxy.size.height)
                    if showsAIProviderSection {
                        AIProviderConnectionPanel(vm: vm)
                    }
                    if let service = selectedService, !service.isDraft {
                        ServiceDangerZone(service: service, isBusy: vm.isBusy) {
                            deleteConfirmationName = ""
                            servicePendingDeletion = service
                        }
                    }
                }
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(Spacing.xl)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
        .sheet(isPresented: $showTableEditor) {
            if let service = selectedService, !service.isDraft {
                ImportedTablesEditor(service: service) {
                    Task { await onServiceUpdated() }
                }
            }
        }
        .task {
            await vm.load()
            await vm.refreshDisplayContext(for: selectedService)
        }
        .onChange(of: vm.connectionSignature) { _, _ in
            Task { await vm.refreshDisplayContext(for: selectedService) }
        }
        .onChange(of: selectedService?.id) { _, _ in
            Task { await vm.refreshDisplayContext(for: selectedService) }
        }
    }

    @ViewBuilder private func setupContent(viewportHeight: CGFloat) -> some View {
        if selectedService?.isDraft == true {
            if vm.supabase.isEmpty {
                DatabaseConnectionPanel(
                    vm: vm,
                    provider: $databaseProvider,
                    sbPat: $sbPat,
                    sbLabel: $sbLabel
                )
                .frame(minWidth: 680, maxWidth: .infinity, alignment: .topLeading)
            } else {
                ServiceWizardView(
                    draftService: selectedService,
                    viewportHeight: viewportHeight,
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
            SupabaseRepairPanel(service: service, isBusy: vm.isBusy) {
                Task {
                    if await vm.repairSupabaseConnection(for: service) {
                        await onServiceUpdated()
                    }
                }
            }
        } else {
            connectedAccountsPanel(service)
        }
    }

    private func connectedAccountsPanel(_ service: Service) -> some View {
        ConnectedAccountsPanel(
            selectedService: service,
            vm: vm,
            onDelete: { deletion in accountPendingDeletion = deletion },
            onEditTables: { showTableEditor = true },
            onServiceUpdated: onServiceUpdated
        )
    }

    private func requiresSupabaseRepair(_ service: Service) -> Bool {
        guard !service.isDraft else { return false }
        guard let accountId = service.supabaseAccountId else { return true }
        return !vm.supabase.contains { $0.id == accountId }
    }

    private var showsAIProviderSection: Bool {
        guard let selectedService, !selectedService.isDraft else { return false }
        return !requiresSupabaseRepair(selectedService)
    }

    private var showsHeaderStatus: Bool {
        selectedService?.isDraft != true
    }

    private var contentMaxWidth: CGFloat {
        selectedService?.isDraft == true ? 960 : 760
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(selectedService?.isDraft == true ? "새 서비스" : "연동")
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.ink)
            Text(selectedService?.isDraft == true ? "연동 계정과 운영 DB 기준을 정하세요" : "서비스별 데이터 연결 상태")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ConnectionStatusNotice: View {
    let text: String

    private var tint: Color {
        if isError {
            return Palette.accentRed
        }
        if text.localizedCaseInsensitiveContains("필요")
            || text.localizedCaseInsensitiveContains("대기") {
            return Palette.accentBlue
        }
        if text.localizedCaseInsensitiveContains("완료")
            || text.localizedCaseInsensitiveContains("연결됨") {
            return Palette.accentGreen
        }
        return Palette.accentBlue
    }

    private var isError: Bool {
        text.localizedCaseInsensitiveContains("실패")
            || text.localizedCaseInsensitiveContains("오류")
            || text.localizedCaseInsensitiveContains("취소")
    }

    private var isSuccess: Bool {
        text.localizedCaseInsensitiveContains("완료")
            || text.localizedCaseInsensitiveContains("연결됨")
    }

    private var icon: String {
        if isError { return "exclamationmark.circle.fill" }
        if isSuccess { return "checkmark.circle.fill" }
        return "info.circle.fill"
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Palette.body)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.row))
        .overlay(RoundedRectangle(cornerRadius: Radius.row).stroke(tint.opacity(0.22)))
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
                guideRow(icon: "person.crop.circle.badge.checkmark", title: "Supabase 계정", state: mode == .connectSupabase ? "필요" : "완료")
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
        case .connectSupabase: return "데이터베이스를 연결하세요"
        case .configureService: return "서비스 기준을 정하세요"
        }
    }

    private var detail: String {
        switch mode {
        case .connectSupabase:
            return "운영 데이터가 있는 Supabase 계정을 연결하면 프로젝트와 테이블을 선택할 수 있습니다."
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

// Deliberately understated — a quiet footer action, not a loud red card.
private struct ServiceDangerZone: View {
    let service: Service
    let isBusy: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text("이 서비스가 더 필요 없나요?")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
            Spacer()
            Button(action: onDelete) {
                Label("서비스 삭제", systemImage: "trash")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accentRed)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider().overlay(Palette.hairline) }
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
                    Text("이 서비스의 Supabase 계정이 삭제되어 동기화할 수 없습니다. 연동 탭에서 같은 프로젝트에 접근할 수 있는 계정을 연결하면 기존 테이블 설정을 그대로 사용합니다.")
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
                Label(isBusy ? "확인 중" : "연결된 계정으로 복구", systemImage: "person.crop.circle.badge.checkmark")
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
    var onEditTables: () -> Void = {}
    var onServiceUpdated: () async -> Void = {}

    // Inline "add" form state (Amplitude/Axiom expand within their own row).
    @State private var expanded: ConnectionProvider?
    @State private var amProjectName = ""
    @State private var amKey = ""
    @State private var amSecret = ""
    @State private var amRegion = "us"
    @State private var axToken = ""

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
        let tint = isMissing ? Palette.accentYellow : provider.brandColor
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                IconChip(tint: tint, size: 30) {
                    ProviderLogo(assetName: provider.logoAsset, isTemplate: provider.logoIsTemplate, size: 17, tint: tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayTitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.body)
                    Text(provider.accountRole)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                trailingControl(provider, accounts: accounts, isMissing: isMissing)
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
                .padding(.leading, 42)
            }
            if expanded == provider {
                inlineAddForm(provider)
                    .padding(.leading, 42)
                    .padding(.top, Spacing.xxs)
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
                .padding(.leading, 42)
            }
        }
        .padding(.vertical, Spacing.sm)
        .overlay(alignment: .bottom) {
            Divider().overlay(Palette.hairline.opacity(provider == .axiom ? 0 : 1))
        }
    }

    // Right-aligned control per provider row: status pill, a Supabase "테이블"
    // button, an "추가" toggle for connectable providers, or a muted "없음".
    @ViewBuilder private func trailingControl(_ provider: ConnectionProvider, accounts: [ConnAccount], isMissing: Bool) -> some View {
        if isMissing {
            StatusPill(text: "복구 필요", color: Palette.accentYellow)
        } else if provider == .supabase, !accounts.isEmpty {
            HStack(spacing: Spacing.xs) {
                StatusPill(text: "연결됨", color: Palette.accentGreen)
                pillButton(icon: "tablecells.badge.ellipsis", title: "테이블") { onEditTables() }
            }
        } else if !accounts.isEmpty {
            StatusPill(text: "연결됨", color: Palette.accentGreen)
        } else if addable(provider) {
            pillButton(icon: expanded == provider ? "chevron.up" : "plus",
                       title: expanded == provider ? "닫기" : "추가") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expanded = (expanded == provider) ? nil : provider
                }
            }
        } else {
            Text("없음")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.ash)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 3)
                .background(Palette.ash.opacity(0.10), in: Capsule())
        }
    }

    private func pillButton(icon: String, title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs + 2) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Palette.accentBlue)
            .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
            .background(Palette.accentBlue.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(vm.isBusy)
    }

    private func addable(_ provider: ConnectionProvider) -> Bool {
        guard let s = selectedService, !s.isDraft else { return false }
        switch provider {
        case .supabase: return false
        case .amplitude: return s.amplitudeAccountId == nil && vm.amplitude.isEmpty
        case .axiom: return s.axiomAccountId == nil && vm.axiom.isEmpty
        }
    }

    // Compact connect form revealed under an Amplitude/Axiom row. On success the
    // account is created AND attached to the service, then the service re-syncs.
    @ViewBuilder private func inlineAddForm(_ provider: ConnectionProvider) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            switch provider {
            case .amplitude:
                Text("Export API 자격증명으로 연결합니다. 프로젝트 이름은 표시용입니다.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                field("프로젝트 이름", text: $amProjectName)
                field("API Key", text: $amKey)
                field("Secret Key", text: $amSecret, secure: true)
                Picker("", selection: $amRegion) { Text("US").tag("us"); Text("EU").tag("eu") }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 120)
                connectButton(enabled: !amProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !amKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !amSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    guard let s = selectedService else { return }
                    if await vm.connectAmplitudeForService(s, projectName: amProjectName, key: amKey, secret: amSecret, region: amRegion) {
                        amProjectName = ""; amKey = ""; amSecret = ""; expanded = nil
                        await onServiceUpdated()
                    }
                }
            case .axiom:
                Text("Axiom API Token 또는 PAT로 데이터셋을 연결합니다.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                field("API Token 또는 PAT", text: $axToken, secure: true)
                connectButton(enabled: !axToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    guard let s = selectedService else { return }
                    if await vm.connectAxiomForService(s, token: axToken) {
                        axToken = ""; expanded = nil
                        await onServiceUpdated()
                    }
                }
            case .supabase:
                EmptyView()
            }
        }
        .padding(.trailing, Spacing.sm)
    }

    @ViewBuilder private func field(_ title: String, text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(title, text: text) } else { TextField(title, text: text) }
        }
        .textFieldStyle(.plain)
        .font(Typography.caption)
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Spacing.sm)
        .frame(height: 30)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
    }

    private func connectButton(enabled: Bool, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(vm.isBusy ? "연결 중…" : "연결")
                .font(Typography.caption).foregroundStyle(Palette.ctaText)
                .padding(.horizontal, Spacing.md).frame(height: 30)
                .background(Palette.ctaFill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        }
        .buttonStyle(.plain)
        .disabled(vm.isBusy || !enabled)
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

// Workspace-global AI provider connection — powers the AI chat panel (⌘I).
private struct AIProviderConnectionPanel: View {
    @Bindable var vm: ConnectionsViewModel
    @State private var showPaste = false
    @State private var pasteCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("AI 연결")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Text("서비스 데이터가 준비되면 사용할 AI 계정을 선택합니다.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            aiProviderRow(
                icon: { ClaudeMark(size: 18) },
                tint: Palette.claude,
                title: "Claude",
                subtitle: "OAuth 지원 · 현재 사용 가능",
                detail: vm.claude == nil ? "Claude 계정으로 연결하면 AI 채팅에서 현재 서비스 데이터를 질문할 수 있습니다." : "Claude 계정으로 AI 채팅을 사용할 수 있습니다.",
                status: vm.claude == nil ? nil : "연결됨"
            ) {
                if vm.claude != nil {
                    Button { Task { await vm.disconnectClaude() } } label: {
                        Label("해제", systemImage: "xmark.circle")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.accentRed)
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isBusy)
                } else {
                    Button {
                        showPaste = vm.startClaudeConnect()
                    } label: {
                        Label("연결", systemImage: "person.crop.circle.badge.checkmark")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ctaText)
                            .padding(.horizontal, Spacing.md)
                            .frame(height: 32)
                            .background(Palette.ctaFill)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isBusy)
                }
            }

            aiProviderRow(
                icon: {
                    ProviderLogo(assetName: "ChatGPTLogo", isTemplate: true, size: 18, tint: Color(hex: "10A37F"))
                },
                tint: Color(hex: "10A37F"),
                title: "OpenAI",
                subtitle: "검토 결과 · API key 방식 우선",
                detail: "일반 서드파티 앱에서 사용자의 ChatGPT 구독을 그대로 쓰는 OAuth API는 공개 제품 흐름이 아닙니다.",
                status: "설계 필요"
            ) {
                Button {
                    vm.openOpenAIAPIKeys()
                } label: {
                    Label("API key", systemImage: "key")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.body)
                        .padding(.horizontal, Spacing.sm)
                        .frame(height: 30)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                }
                .buttonStyle(.plain)
            }

            aiProviderRow(
                icon: {
                    ProviderLogo(assetName: "GeminiLogo", isTemplate: true, size: 18, tint: Color(hex: "8E75B2"))
                },
                tint: Color(hex: "8E75B2"),
                title: "Gemini",
                subtitle: "검토 결과 · Google OAuth 가능",
                detail: "Gemini API는 OAuth를 지원하지만 Google Cloud 프로젝트, OAuth 클라이언트, 권한 범위 설정이 필요합니다.",
                status: "준비 중"
            ) {
                Button {
                    vm.openGeminiOAuthGuide()
                } label: {
                    Label("가이드", systemImage: "safari")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.body)
                        .padding(.horizontal, Spacing.sm)
                        .frame(height: 30)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
        .sheet(isPresented: $showPaste) {
            pasteSheet
        }
    }

    private func aiProviderRow<Icon: View, Action: View>(
        @ViewBuilder icon: @escaping () -> Icon,
        tint: Color,
        title: String,
        subtitle: String,
        detail: String,
        status: String?,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            IconChip(tint: tint, size: 34) { icon() }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.sm) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                    if let status {
                        StatusPill(text: status, color: status == "연결됨" ? Palette.accentGreen : Palette.ash)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.md)
            action()
        }
        .padding(Spacing.md)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.row))
        .overlay(RoundedRectangle(cornerRadius: Radius.row).stroke(Palette.hairline))
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

private struct DatabaseConnectionPanel: View {
    @Bindable var vm: ConnectionsViewModel
    @Binding var provider: DatabaseProvider
    @Binding var sbPat: String
    @Binding var sbLabel: String
    @State private var showPATFallback = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("데이터베이스 연결")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.ink)
                Text("운영 데이터가 있는 DB를 먼저 연결하세요. AI 계정은 서비스 생성 후 연결합니다.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let status = vm.status {
                ConnectionStatusNotice(text: status)
            }

            HStack(spacing: Spacing.lg) {
                ForEach(DatabaseProvider.allCases) { option in
                    providerTile(option)
                }
            }

            switch provider {
            case .supabase:
                supabaseConnectStep
            case .firebase:
                firebaseConnectStep
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }

    private func providerTile(_ option: DatabaseProvider) -> some View {
        let selected = provider == option
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                provider = option
            }
        } label: {
            HStack(spacing: Spacing.md) {
                IconChip(tint: option.tint, size: 32, corner: Radius.badge) {
                    ProviderLogo(assetName: option.logoAsset, isTemplate: option.logoIsTemplate, size: 18, tint: option.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                    Text(option.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? option.tint : Palette.ash)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(selected ? option.tint.opacity(0.08) : Palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.row))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.row)
                    .stroke(selected ? option.tint.opacity(0.55) : Palette.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private var supabaseConnectStep: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if vm.canUseSupabaseOAuth {
                supabaseOAuthApprovalRow
            } else {
                connectionSummary(
                    logoAsset: "SupabaseLogo",
                    tint: DatabaseProvider.supabase.tint,
                    title: "Supabase 토큰으로 연결",
                    detail: "현재 버전에서는 PAT 연결을 사용합니다. 토큰은 이 기기의 Keychain에만 저장되고 프로젝트 목록을 가져오는 데 사용됩니다."
                )

                Button {
                    vm.openSupabasePATPage()
                    showPATFallback = true
                } label: {
                    Label("토큰 발급 페이지 열기", systemImage: "key")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.body)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 36)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                }
                .buttonStyle(.plain)
            }

            if showPATFallback || !vm.canUseSupabaseOAuth {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Supabase 토큰 페이지에서 Personal Access Token을 만든 뒤 붙여넣으세요.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                    connectionField("Supabase Personal Access Token", text: $sbPat, secure: true)
                    connectionField("계정 이름 또는 이메일", text: $sbLabel)
                    Button {
                        Task {
                            await vm.addSupabase(pat: sbPat, label: sbLabel)
                            sbPat = ""
                            sbLabel = ""
                        }
                    } label: {
                        Label(vm.isBusy ? "연결 중" : "PAT로 연결", systemImage: "key.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.ctaText)
                            .padding(.horizontal, Spacing.md)
                            .frame(height: 34)
                            .background(Palette.ctaFill)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isBusy || sbPat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(Spacing.md)
                .background(Palette.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Radius.row))
                .overlay(RoundedRectangle(cornerRadius: Radius.row).stroke(Palette.hairline))
            }
        }
    }

    private var supabaseOAuthApprovalRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                supabaseOAuthSummary
                    .frame(maxWidth: 420, alignment: .leading)
                Spacer(minLength: Spacing.lg)
                supabaseOAuthActions
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                supabaseOAuthSummary
                supabaseOAuthActions
            }
        }
    }

    private var supabaseOAuthSummary: some View {
        connectionSummary(
            logoAsset: "SupabaseLogo",
            tint: DatabaseProvider.supabase.tint,
            title: "브라우저에서 Supabase 승인",
            detail: vm.isSupabaseOAuthWaiting
                ? "브라우저 창을 닫았거나 다시 열어야 하면 다시 시도하세요."
                : "Supabase 계정 승인만으로 접근 가능한 프로젝트 목록을 가져옵니다."
        )
    }

    private var supabaseOAuthActions: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                Task {
                    let connected = await vm.connectSupabaseOAuth()
                    if !connected { showPATFallback = true }
                }
            } label: {
                Label(
                    vm.isSupabaseOAuthWaiting ? "다시 시도" : "Supabase로 계속",
                    systemImage: vm.isSupabaseOAuthWaiting ? "arrow.clockwise" : "person.crop.circle.badge.checkmark"
                )
                    .font(Typography.body)
                    .foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 40)
                    .background(Palette.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .buttonStyle(.plain)
            .disabled(vm.isBusy && !vm.isSupabaseOAuthWaiting)

            Button {
                vm.openSupabasePATPage()
                showPATFallback = true
            } label: {
                Label("PAT 발급 페이지", systemImage: "key")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.body)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 36)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var firebaseConnectStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            connectionSummary(
                logoAsset: "FirebaseLogo",
                tint: DatabaseProvider.firebase.tint,
                title: "Firebase 지원 준비 중",
                detail: "Google OAuth 인증은 가능하지만 Firestore/Realtime DB를 운영 DB로 쓰려면 프로젝트 권한, 컬렉션 선택, 문서 ID 매핑이 추가로 필요합니다."
            )
            HStack(spacing: Spacing.sm) {
                Button {
                    vm.openFirebaseConsole()
                } label: {
                    Label("Firebase 콘솔", systemImage: "safari")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.body)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 36)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                }
                .buttonStyle(.plain)
                StatusPill(text: "데이터 모델 확장 필요", color: Palette.ash)
            }
        }
    }

    private func connectionSummary(logoAsset: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            IconChip(tint: tint, size: 28, corner: Radius.badge) {
                ProviderLogo(assetName: logoAsset, isTemplate: true, size: 16, tint: tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
    }
}
