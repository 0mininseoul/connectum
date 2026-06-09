import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class ServiceWizardViewModel {
    var name = ""
    var supabaseAccounts: [ConnAccount] = []
    var amplitudeAccounts: [ConnAccount] = []
    var axiomAccounts: [ConnAccount] = []
    var selectedAccountId: String?
    var projects: [ProjectInfo] = []
    var selectedProjectRef: String?
    var tables: [TableInfo] = []
    var included: Set<String> = []
    var userTableId: String?
    var userIdCol = "id"
    var emailCol = "email"
    var columns: [ColumnInfo] = []
    var displayCols: Set<String> = []
    var amplitudeId: String?
    var axiomId: String?
    var axiomDataset: String?
    var status: String?
    var isBusy = false
    var needsSupabaseReauthorization = false
    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    func load() async {
        do {
            supabaseAccounts = try await repo.fetchSupabaseAccounts()
            amplitudeAccounts = try await repo.fetchAmplitudeAccounts()
            axiomAccounts = try await repo.fetchAxiomAccounts()
            if selectedAccountId == nil || !supabaseAccounts.contains(where: { $0.id == selectedAccountId }) {
                selectedAccountId = supabaseAccounts.last?.id
            }
        } catch { status = "계정 로드 실패: \(error)" }
    }

    func applyDraft(_ service: Service?) {
        guard let service, service.isDraft, name.isEmpty else { return }
        name = service.name
    }

    func loadProjects() async {
        guard let a = selectedAccountId else { return }
        isBusy = true; defer { isBusy = false }
        do {
            needsSupabaseReauthorization = false
            projects = try await repo.listProjects(supabaseAccountId: a)
            status = "프로젝트 \(projects.count)개"
        } catch { status = "프로젝트 로드 실패: \(error)" }
    }

    func selectProject(_ ref: String?) {
        selectedProjectRef = ref
        tables = []
        included = []
        userTableId = nil
        columns = []
        displayCols = []
        needsSupabaseReauthorization = false
        if let ref, let p = projects.first(where: { $0.ref == ref }), (name.isEmpty || name == "새 서비스" || projects.contains { $0.name == name }) {
            name = p.name
        }
    }

    func chooseProject(_ ref: String) async {
        selectProject(ref)
        await loadTables()
    }

    func selectSupabaseAccount(_ id: String) async {
        guard selectedAccountId != id else { return }
        selectedAccountId = id
        resetProjectAndTableSelection()
        projects = []
        status = nil
        await loadProjects()
    }

    func changeProject() {
        resetProjectAndTableSelection()
        status = nil
    }

    func changeUserTable() {
        userTableId = nil
        columns = []
        displayCols = []
        status = nil
    }

    func forgetSelectedSupabaseAccount() async {
        guard let id = selectedAccountId else { return }
        isBusy = true; defer { isBusy = false }
        do {
            try await repo.deleteSupabaseAccount(id: id)
            resetProjectAndTableSelection()
            projects = []
            status = "Supabase 계정 연결 해제됨"
            await load()
            if selectedAccountId != nil {
                await loadProjects()
            }
        } catch {
            status = "계정 제거 실패: \(error.localizedDescription)"
        }
    }

    func loadTables() async {
        guard let a = selectedAccountId, let p = selectedProjectRef else { return }
        isBusy = true; defer { isBusy = false }
        do {
            tables = try await repo.listTables(supabaseAccountId: a, projectRef: p)
            needsSupabaseReauthorization = false
            status = "테이블 \(tables.count)개"
        } catch CrmRepositoryError.supabaseReauthorizationRequired {
            needsSupabaseReauthorization = true
            status = nil
        } catch { status = "테이블 로드 실패: \(error)" }
    }

    func selectUserTable(_ id: String) async {
        included.insert(id)
        userTableId = id
        displayCols = []
        columns = []
        guard let a = selectedAccountId, let p = selectedProjectRef, let t = tables.first(where: { $0.id == id }) else { return }
        isBusy = true; defer { isBusy = false }
        do {
            columns = try await repo.listColumns(supabaseAccountId: a, projectRef: p, schema: t.schema, table: t.table)
            needsSupabaseReauthorization = false
            status = "컬럼 \(columns.count)개"
            if columns.contains(where: { $0.column == emailCol }) { displayCols.insert(emailCol) }
            if columns.contains(where: { $0.column == "name" }) { displayCols.insert("name") }
        } catch CrmRepositoryError.supabaseReauthorizationRequired {
            needsSupabaseReauthorization = true
            status = nil
        } catch { status = "컬럼 로드 실패: \(error)" }
    }

    func reconnectSupabaseOAuth() async {
        isBusy = true; defer { isBusy = false }
        let previousAccountIds = Set(supabaseAccounts.map(\.id))
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
                return
            }
            let callback = try await callbackTask.value
            try await repo.connectSupabaseOAuth(code: callback.code, state: callback.state)
            receiver.cancel()
            projects = []
            resetProjectAndTableSelection()
            needsSupabaseReauthorization = false
            await load()
            selectedAccountId = supabaseAccounts.first(where: { !previousAccountIds.contains($0.id) })?.id
                ?? supabaseAccounts.last?.id
                ?? selectedAccountId
            status = "Supabase 권한 승인됨"
            await loadProjects()
        } catch {
            receiver.cancel()
            status = "Supabase 승인 실패: \(error.localizedDescription)"
        }
    }

    func create() async -> String? {
        guard let a = selectedAccountId, let p = selectedProjectRef, !name.isEmpty else {
            status = "이름/계정/프로젝트 필요"
            return nil
        }
        guard userTableId != nil else {
            status = "유저 테이블 필요"
            return nil
        }
        isBusy = true; defer { isBusy = false }
        do {
            let latestAccounts = try await repo.fetchSupabaseAccounts()
            guard latestAccounts.contains(where: { $0.id == a }) else {
                supabaseAccounts = latestAccounts
                resetProjectAndTableSelection()
                selectedAccountId = latestAccounts.last?.id
                status = "Supabase 계정이 삭제되었습니다. 다시 연결하세요."
                return nil
            }
        } catch {
            status = "Supabase 계정 확인 실패: \(error.localizedDescription)"
            return nil
        }
        let specs: [ServiceTableSpec] = tables.filter { included.contains($0.id) }.map { t in
            if t.id == userTableId {
                return ServiceTableSpec(
                    schema: t.schema,
                    table: t.table,
                    role: "user_table",
                    userIdCol: userIdCol,
                    emailCol: emailCol,
                    displayColumns: Array(displayCols)
                )
            }
            return ServiceTableSpec(schema: t.schema, table: t.table, role: "related")
        }
        do {
            let createdName = name
            try await repo.createService(
                name: name,
                supabaseAccountId: a,
                projectRef: p,
                projectName: selectedProject?.name,
                tables: specs,
                amplitudeAccountId: amplitudeId,
                amplitudeProjectName: selectedAmplitudeAccount?.projectName,
                axiomAccountId: axiomId,
                axiomDataset: axiomDataset
            )
            status = "서비스 '\(createdName)' 생성됨"
            name = ""
            included = []
            userTableId = nil
            columns = []
            displayCols = []
            amplitudeId = nil
            axiomId = nil
            axiomDataset = nil
            return createdName
        } catch {
            status = "생성 실패: \(error)"
            return nil
        }
    }

    var selectedProject: ProjectInfo? {
        guard let selectedProjectRef else { return nil }
        return projects.first { $0.ref == selectedProjectRef }
    }

    var selectedSupabaseAccount: ConnAccount? {
        guard let selectedAccountId else { return nil }
        return supabaseAccounts.first { $0.id == selectedAccountId }
    }

    var selectedAmplitudeAccount: ConnAccount? {
        guard let amplitudeId else { return nil }
        return amplitudeAccounts.first { $0.id == amplitudeId }
    }

    var selectedAxiomAccount: ConnAccount? {
        guard let axiomId else { return nil }
        return axiomAccounts.first { $0.id == axiomId }
    }

    func alignAxiomDataset() {
        let datasets = selectedAxiomAccount?.datasets ?? []
        if axiomId == nil {
            axiomDataset = nil
        } else if let axiomDataset, datasets.contains(axiomDataset) {
            return
        } else {
            axiomDataset = datasets.first
        }
    }

    private func resetProjectAndTableSelection() {
        selectedProjectRef = nil
        tables = []
        included = []
        userTableId = nil
        columns = []
        displayCols = []
        needsSupabaseReauthorization = false
    }
}

private enum ServiceWizardStep {
    case connectSupabase
    case reauthorizeSupabase
    case loadingProjects
    case loadProjects
    case chooseProject
    case loadingTables
    case loadTables
    case chooseUserTable
    case loadingColumns
    case createService

    var icon: String {
        switch self {
        case .connectSupabase: return "link"
        case .reauthorizeSupabase: return "safari"
        case .loadingProjects, .loadProjects, .chooseProject: return "shippingbox"
        case .loadingTables, .loadTables, .chooseUserTable: return "tablecells"
        case .loadingColumns, .createService: return "checkmark.circle"
        }
    }

    var title: String {
        switch self {
        case .connectSupabase: return "Supabase 연결"
        case .reauthorizeSupabase: return "Supabase 권한 다시 승인"
        case .loadingProjects: return "프로젝트 확인 중"
        case .loadProjects: return "프로젝트 불러오기"
        case .chooseProject: return "프로젝트를 선택하세요"
        case .loadingTables: return "테이블 확인 중"
        case .loadTables: return "테이블 불러오기"
        case .chooseUserTable: return "유저 테이블을 선택하세요"
        case .loadingColumns: return "컬럼 확인 중"
        case .createService: return "서비스를 만들까요?"
        }
    }

    var subtitle: String {
        switch self {
        case .connectSupabase:
            return "운영 DB 원본이 되는 Supabase 계정을 먼저 연결합니다."
        case .reauthorizeSupabase:
            return "테이블 목록을 읽으려면 Supabase에서 데이터베이스 접근 권한을 승인해야 합니다."
        case .loadingProjects, .loadProjects:
            return "연결된 Supabase 계정에서 프로젝트 목록을 가져옵니다."
        case .chooseProject:
            return "Connectum에서 관리할 운영 DB 프로젝트 하나를 고르세요."
        case .loadingTables, .loadTables:
            return "선택한 프로젝트에서 테이블 목록을 가져옵니다."
        case .chooseUserTable:
            return "유저 한 명이 한 행으로 들어 있는 기준 테이블 하나를 고르세요."
        case .loadingColumns:
            return "선택한 테이블에서 표시할 수 있는 컬럼을 확인합니다."
        case .createService:
            return "필요한 기본값은 자동으로 잡혔습니다. 그대로 서비스를 만들 수 있습니다."
        }
    }
}

struct ServiceWizardView: View {
    let draftService: Service?
    let onCreated: (String) async -> Void

    @State private var vm = ServiceWizardViewModel()
    @State private var showDisplayColumnOptions = false
    @State private var showIdentityColumnOptions = false

    init(
        draftService: Service? = nil,
        onCreated: @escaping (String) async -> Void = { _ in }
    ) {
        self.draftService = draftService
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            stepHeader
            currentStep
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
        .task {
            await vm.load()
            vm.applyDraft(draftService)
            if !vm.supabaseAccounts.isEmpty && vm.projects.isEmpty && !vm.isBusy {
                await vm.loadProjects()
            }
        }
        .onChange(of: draftService?.id) { _, _ in
            vm.applyDraft(draftService)
        }
    }

    private var stepHeader: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: activeStep.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.accentBlue)
                .frame(width: 34, height: 34)
                .background(Palette.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(activeStep.title)
                    .font(Typography.cardTitle)
                    .foregroundStyle(Palette.ink)
                Text(activeStep.subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder private var currentStep: some View {
        switch activeStep {
        case .connectSupabase:
            emptyState(
                title: "Supabase 연결이 필요합니다",
                detail: "먼저 Supabase 계정을 연결하면 프로젝트를 선택할 수 있습니다.",
                systemImage: "link"
            )
        case .reauthorizeSupabase:
            singleActionState(
                title: "Supabase 권한을 다시 승인하세요",
                detail: "프로젝트는 보이지만 테이블 목록을 읽을 권한이 부족합니다. 브라우저에서 한 번만 다시 승인하면 이어서 진행됩니다.",
                buttonTitle: vm.isBusy ? "브라우저 대기 중" : "브라우저에서 승인",
                systemImage: "safari"
            ) {
                Task { await vm.reconnectSupabaseOAuth() }
            }
        case .loadingProjects:
            loadingState("프로젝트 목록을 불러오는 중")
        case .loadProjects:
            singleActionState(
                title: "프로젝트 목록을 불러오세요",
                detail: selectedAccountLabel.map { "\($0) 계정에서 프로젝트를 가져옵니다." } ?? "연결된 Supabase 계정에서 프로젝트를 가져옵니다.",
                buttonTitle: "프로젝트 불러오기",
                systemImage: "arrow.clockwise"
            ) {
                Task { await vm.loadProjects() }
            }
        case .chooseProject:
            projectList
        case .loadingTables:
            loadingState("테이블 목록을 불러오는 중")
        case .loadTables:
            singleActionState(
                title: "테이블 목록을 불러오세요",
                detail: "\(vm.selectedProject?.name ?? "선택한 프로젝트")에서 운영 DB 테이블을 가져옵니다.",
                buttonTitle: "테이블 불러오기",
                systemImage: "tablecells"
            ) {
                Task { await vm.loadTables() }
            }
        case .chooseUserTable:
            userTableList
        case .loadingColumns:
            loadingState("컬럼 정보를 불러오는 중")
        case .createService:
            createServiceStep()
        }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            accountContextBar
            ForEach(vm.projects) { project in
                choiceRow(
                    title: project.name,
                    detail: project.ref,
                    systemImage: "shippingbox"
                ) {
                    Task { await vm.chooseProject(project.ref) }
                }
            }
        }
    }

    private var userTableList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            projectContextBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(vm.tables) { table in
                        choiceRow(
                            title: table.table,
                            detail: table.schema,
                            systemImage: "tablecells"
                        ) {
                            Task { await vm.selectUserTable(table.id) }
                        }
                    }
                }
            }
            .frame(maxHeight: 440)
        }
    }

    private func createServiceStep() -> some View {
        @Bindable var vm = vm
        return VStack(alignment: .leading, spacing: Spacing.md) {
            serviceReviewCard
            optionalConnectionsSection

            disclosureSection("유저 식별 기준", isExpanded: $showIdentityColumnOptions) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("각 행을 어떤 유저로 볼지 정하는 기준입니다. 기본값이 맞지 않을 때만 바꾸세요.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: Spacing.md) {
                        columnSelector(
                            title: "고유 ID 컬럼",
                            detail: "동일 유저를 구분하는 값입니다.",
                            selection: $vm.userIdCol
                        )
                        columnSelector(
                            title: "이메일 컬럼",
                            detail: "유저 연락처와 보조 식별자로 사용합니다.",
                            selection: $vm.emailCol
                        )
                    }
                }
                .padding(.top, Spacing.sm)
            }

            disclosureSection("표시 컬럼 조정", isExpanded: $showDisplayColumnOptions) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("운영 DB 테이블에 처음 보여줄 컬럼입니다. 생성 후에도 컬럼 메뉴에서 다시 바꿀 수 있습니다.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !vm.columns.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: Spacing.xs) {
                            ForEach(vm.columns) { column in
                                Toggle(isOn: Binding(
                                    get: { vm.displayCols.contains(column.column) },
                                    set: { on in
                                        if on { vm.displayCols.insert(column.column) }
                                        else { vm.displayCols.remove(column.column) }
                                    }
                                )) {
                                    Text(column.column)
                                        .font(Typography.caption)
                                        .foregroundStyle(Palette.body)
                                        .lineLimit(1)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
                .padding(.top, Spacing.sm)
            }

            primaryButton(
                title: vm.isBusy ? "생성 중" : "서비스 만들기",
                systemImage: "checkmark"
            ) {
                Task {
                    if let createdName = await vm.create() {
                        await onCreated(createdName)
                    }
                }
            }
            .disabled(vm.isBusy || vm.name.isEmpty || vm.userTableId == nil)
        }
    }

    private var serviceReviewCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            selectedServiceContextBar
            VStack(alignment: .leading, spacing: Spacing.sm) {
                reviewRow(
                    icon: "rectangle.stack",
                    title: "서비스",
                    value: vm.name.isEmpty ? (vm.selectedProject?.name ?? "새 서비스") : vm.name
                )
                reviewRow(
                    icon: "shippingbox",
                    title: "프로젝트",
                    value: vm.selectedProject?.name ?? "프로젝트 미선택"
                )
                if let table = selectedUserTable {
                    reviewRow(
                        icon: "tablecells",
                        title: "유저 테이블",
                        value: "\(table.schema).\(table.table)"
                    )
                }
                reviewRow(
                    icon: "person.crop.circle",
                    title: "Supabase 계정",
                    value: selectedAccountLabel ?? "계정 미선택"
                )
            }
        }
        .padding(Spacing.md)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }

    private func reviewRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accentBlue)
                .frame(width: 20)
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: Spacing.sm)
        }
    }

    private var optionalConnectionsSection: some View {
        @Bindable var vm = vm
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("선택 연동")
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
            if vm.amplitudeAccounts.isEmpty && vm.axiomAccounts.isEmpty {
                Text("연결된 Amplitude/Axiom 계정이 없습니다. 서비스 생성 후 연동 탭에서 추가할 수 있습니다.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: Spacing.md) {
                    optionalAccountSelector(
                        title: "Amplitude",
                        accounts: vm.amplitudeAccounts,
                        selection: $vm.amplitudeId
                    )
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        optionalAccountSelector(
                            title: "Axiom",
                            accounts: vm.axiomAccounts,
                            selection: $vm.axiomId
                        )
                        if let axiom = vm.selectedAxiomAccount, let datasets = axiom.datasets, !datasets.isEmpty {
                            Picker("", selection: $vm.axiomDataset) {
                                ForEach(datasets, id: \.self) { dataset in
                                    Text(dataset).tag(Optional(dataset))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 240, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                }
            }
        }
        .padding(Spacing.md)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
        .onChange(of: vm.axiomId) { _, _ in vm.alignAxiomDataset() }
    }

    private var activeStep: ServiceWizardStep {
        if vm.supabaseAccounts.isEmpty { return .connectSupabase }
        if vm.needsSupabaseReauthorization { return .reauthorizeSupabase }
        if vm.projects.isEmpty { return vm.isBusy ? .loadingProjects : .loadProjects }
        if vm.selectedProjectRef == nil { return .chooseProject }
        if vm.tables.isEmpty { return vm.isBusy ? .loadingTables : .loadTables }
        if vm.userTableId == nil { return .chooseUserTable }
        if vm.columns.isEmpty && vm.isBusy { return .loadingColumns }
        return .createService
    }

    private var selectedAccountLabel: String? {
        guard let account = vm.selectedSupabaseAccount else { return nil }
        return displayName(for: account)
    }

    private var selectedUserTable: TableInfo? {
        guard let id = vm.userTableId else { return nil }
        return vm.tables.first(where: { $0.id == id })
    }

    private func loadingState(_ title: String) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(Typography.body)
                .foregroundStyle(Palette.body)
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
    }

    private func emptyState(title: String, detail: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.muted)
            Text(title)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
    }

    private func singleActionState(
        title: String,
        detail: String,
        buttonTitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            primaryButton(title: buttonTitle, systemImage: systemImage, action: action)
                .disabled(vm.isBusy)
        }
    }

    private var accountContextBar: some View {
        HStack(spacing: Spacing.md) {
            Label("Supabase 계정", systemImage: "person.crop.circle")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
            Text(selectedAccountLabel ?? "계정 미선택")
                .font(Typography.caption)
                .foregroundStyle(Palette.body)
                .lineLimit(1)
            Spacer(minLength: Spacing.md)
            accountMenu
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 42)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.row))
        .overlay(RoundedRectangle(cornerRadius: Radius.row).stroke(Palette.hairline))
    }

    private var projectContextBar: some View {
        HStack(spacing: Spacing.md) {
            Label("프로젝트", systemImage: "shippingbox")
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.selectedProject?.name ?? "프로젝트 미선택")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.body)
                    .lineLimit(1)
                Text(selectedAccountLabel ?? "Supabase")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.md)
            secondaryButton(title: "프로젝트 변경", systemImage: "chevron.left") {
                vm.changeProject()
            }
            accountMenu
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 48)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.row))
        .overlay(RoundedRectangle(cornerRadius: Radius.row).stroke(Palette.hairline))
    }

    private var selectedServiceContextBar: some View {
        HStack(spacing: Spacing.md) {
            Label("선택", systemImage: "checkmark.circle")
                .font(Typography.caption)
                .foregroundStyle(Palette.accentGreen)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.selectedProject?.name ?? "프로젝트")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.body)
                    .lineLimit(1)
                if let table = selectedUserTable {
                    Text("\(table.schema).\(table.table)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.md)
            secondaryButton(title: "테이블 변경", systemImage: "tablecells") {
                vm.changeUserTable()
            }
            secondaryButton(title: "프로젝트 변경", systemImage: "shippingbox") {
                vm.changeProject()
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 50)
        .background(Palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Radius.row))
        .overlay(RoundedRectangle(cornerRadius: Radius.row).stroke(Palette.hairline))
    }

    private var accountMenu: some View {
        Menu {
            if vm.supabaseAccounts.count > 1 {
                Section("연결된 계정") {
                    ForEach(vm.supabaseAccounts) { account in
                        Button {
                            Task { await vm.selectSupabaseAccount(account.id) }
                        } label: {
                            if account.id == vm.selectedAccountId {
                                Label(displayName(for: account), systemImage: "checkmark")
                            } else {
                                Text(displayName(for: account))
                            }
                        }
                    }
                }
            }
            Button {
                Task { await vm.reconnectSupabaseOAuth() }
            } label: {
                Label("다른 Supabase 계정 연결", systemImage: "person.badge.plus")
            }
            if vm.selectedAccountId != nil {
                Divider()
                Button(role: .destructive) {
                    Task { await vm.forgetSelectedSupabaseAccount() }
                } label: {
                    Label("현재 계정 연결 해제", systemImage: "trash")
                }
            }
        } label: {
            Label("계정 변경", systemImage: "person.crop.circle")
                .font(Typography.caption)
                .foregroundStyle(Palette.body)
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(vm.isBusy)
    }

    private func choiceRow(
        title: String,
        detail: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.accentBlue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, Spacing.lg)
            .frame(height: 58)
            .background(Palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.row))
            .overlay(RoundedRectangle(cornerRadius: Radius.row).stroke(Palette.hairline))
        }
        .buttonStyle(.plain)
        .disabled(vm.isBusy)
    }

    private func primaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Typography.body)
                .foregroundStyle(Palette.ctaText)
                .padding(.horizontal, Spacing.lg)
                .frame(height: 40)
                .background(Palette.ctaFill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Typography.caption)
                .foregroundStyle(Palette.body)
                .padding(.horizontal, Spacing.sm)
                .frame(height: 30)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
        }
        .buttonStyle(.plain)
        .disabled(vm.isBusy)
        .fixedSize()
    }

    private func displayName(for account: ConnAccount) -> String {
        let accountName = account.accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? (label.isEmpty ? "Supabase" : label) : accountName
    }

    @ViewBuilder private var selectedTableSummary: some View {
        if !selectedTables.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(selectedTables.prefix(4)) { table in
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: table.id == vm.userTableId ? "person.crop.circle.fill" : "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(table.id == vm.userTableId ? Palette.accentGreen : Palette.muted)
                            .frame(width: 14)
                        Text(table.table)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.body)
                            .lineLimit(1)
                    }
                }
                if selectedTables.count > 4 {
                    Text("외 \(selectedTables.count - 4)개")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private var selectedTables: [TableInfo] {
        vm.tables.filter { vm.included.contains($0.id) }
    }

    private func wizardStep<C: View>(index: String, title: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(index)
                .font(Typography.caption)
                .foregroundStyle(Palette.ctaText)
                .frame(width: 18, height: 18)
                .background(Palette.ctaFill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(title)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
                content()
            }
        }
    }

    private func disclosureSection<C: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.14)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .frame(width: 14)
                    Text(title)
                        .font(Typography.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private func optionalAccountSelector(
        title: String,
        accounts: [ConnAccount],
        selection: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.body)
            Picker("", selection: selection) {
                Text("연동 안 함").tag(nil as String?)
                ForEach(accounts) { account in
                    Text(displayName(for: account)).tag(Optional(account.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 240, alignment: .leading)
    }

    @ViewBuilder private func formField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Spacing.sm)
            .frame(height: 30)
            .background(Palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
    }

    private func columnSelector(title: String, detail: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.body)
            Picker("", selection: selection) {
                if selection.wrappedValue.isEmpty {
                    Text("선택 안 함").tag("")
                } else if !vm.columns.contains(where: { $0.column == selection.wrappedValue }) {
                    Text(selection.wrappedValue).tag(selection.wrappedValue)
                }
                ForEach(vm.columns) { column in
                    Text(column.column).tag(column.column)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 240, alignment: .leading)
    }
}

private struct TablePickerPanel: View {
    @Bindable var vm: ServiceWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("테이블 선택")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(vm.included.count)/\(vm.tables.count)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
            }

            ScrollView {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(vm.tables) { table in
                        tableRow(table)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .padding(Spacing.md)
        .frame(width: 380, height: 420, alignment: .topLeading)
        .background(Palette.surfaceCard)
    }

    private func tableRow(_ table: TableInfo) -> some View {
        let isIncluded = vm.included.contains(table.id)
        let isUser = vm.userTableId == table.id
        return HStack(spacing: Spacing.sm) {
            Toggle("", isOn: Binding(
                get: { vm.included.contains(table.id) },
                set: { on in
                    if on {
                        vm.included.insert(table.id)
                    } else {
                        vm.included.remove(table.id)
                        if vm.userTableId == table.id {
                            vm.userTableId = nil
                            vm.columns = []
                            vm.displayCols = []
                        }
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 1) {
                Text(table.table)
                    .font(Typography.body)
                    .foregroundStyle(isIncluded ? Palette.ink : Palette.body)
                    .lineLimit(1)
                Text(table.schema)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: Spacing.sm)
            if isIncluded {
                Button {
                    Task { await vm.selectUserTable(table.id) }
                } label: {
                    Label(isUser ? "유저" : "지정", systemImage: isUser ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(Typography.caption)
                        .foregroundStyle(isUser ? Palette.accentGreen : Palette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .frame(height: 42)
        .background(isUser ? Palette.surfaceElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.row))
        .contentShape(Rectangle())
    }
}
