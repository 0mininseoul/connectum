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
    var included: Set<String> = []           // TableInfo.id
    var userTableId: String?                 // which included table is the user table
    var userIdCol = "id"; var emailCol = "email"
    var columns: [ColumnInfo] = []           // user table's columns
    var displayCols: Set<String> = []        // columns to show in the operational-DB table
    var amplitudeId: String?; var axiomId: String?
    var status: String?; var isBusy = false
    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    func load() async {
        do {
            supabaseAccounts = try await repo.fetchSupabaseAccounts()
            amplitudeAccounts = try await repo.fetchAmplitudeAccounts()
            axiomAccounts = try await repo.fetchAxiomAccounts()
            if selectedAccountId == nil { selectedAccountId = supabaseAccounts.first?.id }
        } catch { status = "계정 로드 실패: \(error)" }
    }
    func loadProjects() async {
        guard let a = selectedAccountId else { return }
        isBusy = true; defer { isBusy = false }
        do { projects = try await repo.listProjects(supabaseAccountId: a); status = "프로젝트 \(projects.count)개" }
        catch { status = "프로젝트 로드 실패: \(error)" }
    }
    // Default the service name to the project name (requirement: project name, not ref).
    func selectProject(_ ref: String?) {
        selectedProjectRef = ref
        if let ref, let p = projects.first(where: { $0.ref == ref }), (name.isEmpty || projects.contains { $0.name == name }) {
            name = p.name
        }
    }
    func loadTables() async {
        guard let a = selectedAccountId, let p = selectedProjectRef else { return }
        isBusy = true; defer { isBusy = false }
        do { tables = try await repo.listTables(supabaseAccountId: a, projectRef: p); status = "테이블 \(tables.count)개" }
        catch { status = "테이블 로드 실패: \(error)" }
    }
    // Marking the user table loads its columns so the user can pick which to display.
    func selectUserTable(_ id: String) async {
        userTableId = id; displayCols = []; columns = []
        guard let a = selectedAccountId, let p = selectedProjectRef, let t = tables.first(where: { $0.id == id }) else { return }
        isBusy = true; defer { isBusy = false }
        do {
            columns = try await repo.listColumns(supabaseAccountId: a, projectRef: p, schema: t.schema, table: t.table)
            status = "컬럼 \(columns.count)개"
        } catch { status = "컬럼 로드 실패: \(error)" }
    }
    func create() async {
        guard let a = selectedAccountId, let p = selectedProjectRef, !name.isEmpty else { status = "이름/계정/프로젝트 필요"; return }
        isBusy = true; defer { isBusy = false }
        let specs: [ServiceTableSpec] = tables.filter { included.contains($0.id) }.map { t in
            if t.id == userTableId {
                return ServiceTableSpec(schema: t.schema, table: t.table, role: "user_table",
                                        userIdCol: userIdCol, emailCol: emailCol, displayColumns: Array(displayCols))
            }
            return ServiceTableSpec(schema: t.schema, table: t.table, role: "related")
        }
        do {
            try await repo.createService(name: name, supabaseAccountId: a, projectRef: p, tables: specs, amplitudeAccountId: amplitudeId, axiomAccountId: axiomId)
            status = "서비스 '\(name)' 생성됨"; name = ""; included = []; userTableId = nil; columns = []; displayCols = []
        } catch { status = "생성 실패: \(error)" }
    }
}

struct ServiceWizardView: View {
    @State private var vm = ServiceWizardViewModel()

    var body: some View {
        @Bindable var vm = vm
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("서비스 추가").font(Typography.body).foregroundStyle(Palette.ink)
            if let s = vm.status { Text(s).font(Typography.caption).foregroundStyle(Palette.accentBlue) }
            TextField("서비스 이름", text: $vm.name).textFieldStyle(.plain).foregroundStyle(Palette.ink).padding(Spacing.sm)
                .background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button))

            HStack {
                Picker("Supabase 계정", selection: $vm.selectedAccountId) {
                    Text("선택").tag(String?.none)
                    ForEach(vm.supabaseAccounts) { a in Text(a.label).tag(String?.some(a.id)) }
                }.frame(maxWidth: 240)
                Button("프로젝트 불러오기") { Task { await vm.loadProjects() } }.font(Typography.caption).disabled(vm.isBusy)
            }
            if !vm.projects.isEmpty {
                HStack {
                    Picker("프로젝트", selection: Binding(get: { vm.selectedProjectRef }, set: { vm.selectProject($0) })) {
                        Text("선택").tag(String?.none)
                        ForEach(vm.projects) { p in Text(p.name).tag(String?.some(p.ref)) }
                    }.frame(maxWidth: 240)
                    Button("테이블 불러오기") { Task { await vm.loadTables() } }.font(Typography.caption).disabled(vm.isBusy || vm.selectedProjectRef == nil)
                }
            }
            if !vm.tables.isEmpty {
                Text("가져올 테이블 (복수 선택, 하나를 유저 테이블로 지정)").font(Typography.caption).foregroundStyle(Palette.muted)
                ForEach(vm.tables) { t in
                    HStack(spacing: Spacing.sm) {
                        Toggle("", isOn: Binding(get: { vm.included.contains(t.id) }, set: { on in if on { vm.included.insert(t.id) } else { vm.included.remove(t.id); if vm.userTableId == t.id { vm.userTableId = nil } } })).labelsHidden()
                        Text("\(t.schema).\(t.table)").font(Typography.caption).foregroundStyle(Palette.body)
                        Spacer()
                        if vm.included.contains(t.id) {
                            Button(vm.userTableId == t.id ? "● 유저" : "○ 유저") { Task { await vm.selectUserTable(t.id) } }
                                .font(Typography.caption).buttonStyle(.plain).foregroundStyle(vm.userTableId == t.id ? Palette.accentGreen : Palette.muted)
                        }
                    }
                }
                if vm.userTableId != nil {
                    HStack(spacing: Spacing.sm) {
                        TextField("user_id 컬럼", text: $vm.userIdCol).textFieldStyle(.plain).foregroundStyle(Palette.ink).padding(Spacing.xs).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button)).frame(width: 140)
                        TextField("email 컬럼", text: $vm.emailCol).textFieldStyle(.plain).foregroundStyle(Palette.ink).padding(Spacing.xs).background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button)).frame(width: 140)
                    }
                    if !vm.columns.isEmpty {
                        Text("운영 DB 표시 컬럼 (체크)").font(Typography.caption).foregroundStyle(Palette.muted)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: Spacing.xs) {
                            ForEach(vm.columns) { c in
                                Toggle(isOn: Binding(get: { vm.displayCols.contains(c.column) }, set: { on in if on { vm.displayCols.insert(c.column) } else { vm.displayCols.remove(c.column) } })) {
                                    Text(c.column).font(Typography.caption).foregroundStyle(Palette.body)
                                }.toggleStyle(.checkbox)
                            }
                        }
                    }
                }
                HStack {
                    Picker("Amplitude", selection: $vm.amplitudeId) { Text("없음").tag(String?.none); ForEach(vm.amplitudeAccounts) { a in Text(a.label).tag(String?.some(a.id)) } }.frame(maxWidth: 200)
                    Picker("Axiom", selection: $vm.axiomId) { Text("없음").tag(String?.none); ForEach(vm.axiomAccounts) { a in Text(a.label).tag(String?.some(a.id)) } }.frame(maxWidth: 200)
                }
                Button { Task { await vm.create() } } label: {
                    Text(vm.isBusy ? "생성 중…" : "서비스 생성").font(Typography.caption).foregroundStyle(Palette.ctaText)
                        .padding(.horizontal, Spacing.md).frame(height: 28).background(Palette.ctaFill).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(vm.isBusy || vm.name.isEmpty || vm.included.isEmpty)
            }
        }
        .padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
        .task { await vm.load() }
    }
}
