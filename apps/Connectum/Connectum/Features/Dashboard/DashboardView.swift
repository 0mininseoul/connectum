import SwiftUI
import Charts
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class DashboardViewModel {
    var metrics = DashboardMetrics()
    var users: [CrmUser] = []
    var kpis: [DashboardKPIDefinition] = []
    var selectedKPIId: String?
    var isLoading = false
    var isRefreshing = false
    var cacheUpdatedAt: Date?
    var errorMessage: String?
    private let repo: CrmDataProviding
    private let cache: CrmCacheProviding

    init(repo: CrmDataProviding = CrmRepository(), cache: CrmCacheProviding = CrmCacheStore()) {
        self.repo = repo
        self.cache = cache
    }

    @discardableResult
    func loadCached(serviceId: String) -> Bool {
        do {
            guard let snapshot = try cache.loadDashboardMetrics(serviceId: serviceId),
                  snapshot.serviceId == serviceId else { return false }
            metrics = snapshot.metrics
            cacheUpdatedAt = snapshot.cachedAt
            errorMessage = nil
            return true
        } catch {
            errorMessage = "캐시 읽기 실패: \(error)"
            return false
        }
    }

    func loadKPIs(serviceId: String) async {
        do {
            var rows = try await repo.fetchKPIs(serviceId: serviceId)
            if rows.isEmpty {
                try await repo.seedSystemKPIs(serviceId: serviceId)
                rows = try await repo.fetchKPIs(serviceId: serviceId)
            }
            kpis = rows
            ensureSelection()
        } catch {
            errorMessage = "KPI 불러오기 실패: \(error)"
        }
    }

    func refresh(serviceId: String) async {
        let hasCachedMetrics = cacheUpdatedAt != nil
        isLoading = !hasCachedMetrics
        isRefreshing = hasCachedMetrics
        defer { isLoading = false; isRefreshing = false }
        do {
            let freshMetrics = try await repo.fetchMetrics(serviceId: serviceId)
            metrics = freshMetrics
            users = (try? await repo.fetchUsers(serviceId: serviceId)) ?? users
            let snapshot = DashboardMetricsCacheSnapshot(serviceId: serviceId, cachedAt: Date(), metrics: freshMetrics)
            try? cache.saveDashboardMetrics(snapshot)
            cacheUpdatedAt = snapshot.cachedAt
            errorMessage = nil
        } catch {
            errorMessage = hasCachedMetrics ? "최신 동기화 실패: \(error)" : String(describing: error)
        }
        await recomputeCustomValues(serviceId: serviceId)
    }

    // Keep custom KPI values current against the latest data.
    func recomputeCustomValues(serviceId: String) async {
        for index in kpis.indices where kpis[index].kind == .custom {
            guard let spec = kpis[index].spec,
                  let value = try? await repo.recomputeKPI(serviceId: serviceId, spec: spec) else { continue }
            kpis[index].value = value
            try? await repo.updateKPIValue(id: kpis[index].id, value: value)
        }
    }

    func previewKPI(serviceId: String, title: String, prompt: String) async throws -> KPIPreview {
        try await repo.previewKPI(serviceId: serviceId, title: title, prompt: prompt)
    }

    func addCustomKPI(title: String, prompt: String, preview: KPIPreview, serviceId: String) async {
        let position = (kpis.map(\.position).max() ?? 0) + 1
        do {
            try await repo.insertKPI(serviceId: serviceId, title: title, prompt: prompt,
                                     spec: preview.spec, unit: preview.unit, value: preview.value, position: position)
            await loadKPIs(serviceId: serviceId)
            selectedKPIId = kpis.first(where: { $0.title == title && $0.kind == .custom })?.id ?? kpis.last?.id
        } catch {
            errorMessage = "KPI 추가 실패: \(error)"
        }
    }

    func deleteKPI(id: String, serviceId: String) async {
        do {
            try await repo.deleteKPIRow(id: id)
            kpis.removeAll { $0.id == id }
            ensureSelection()
        } catch {
            errorMessage = "KPI 삭제 실패: \(error)"
        }
    }

    func renameKPI(id: String, title: String, serviceId: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await repo.renameKPIRow(id: id, title: trimmed)
            if let i = kpis.firstIndex(where: { $0.id == id }) { kpis[i].title = trimmed }
        } catch {
            errorMessage = "이름 수정 실패: \(error)"
        }
    }

    func moveKPI(movingId: String, before targetId: String, serviceId: String) async {
        guard movingId != targetId,
              let from = kpis.firstIndex(where: { $0.id == movingId }),
              let target = kpis.firstIndex(where: { $0.id == targetId }) else { return }
        let item = kpis.remove(at: from)
        let insertion = target > from ? target - 1 : target
        kpis.insert(item, at: insertion)
        for index in kpis.indices { kpis[index].position = Double(index) }
        for kpi in kpis { try? await repo.updateKPIPosition(id: kpi.id, position: kpi.position) }
    }

    func selectKPI(id: String) { selectedKPIId = id }

    var selectedDefinition: DashboardKPIDefinition? {
        kpis.first { $0.id == selectedKPIId } ?? kpis.first
    }

    func valueText(for definition: DashboardKPIDefinition) -> String {
        switch definition.kind {
        case .totalUsers: return "\(metrics.total)"
        case .contactRate: return String(format: "%.0f%%", metrics.contactRate * 100)
        case .contacted: return "\(metrics.contacted)"
        case .custom:
            guard let v = definition.value else { return "—" }
            return definition.unit == "percent" ? String(format: "%.1f%%", v) : "\(Int(v.rounded()))"
        }
    }

    func subtitle(for definition: DashboardKPIDefinition) -> String {
        definition.kind == .custom ? "커스텀" : "기본"
    }

    func chartPoints(for definition: DashboardKPIDefinition) -> [DashboardKPIChartPoint] {
        if definition.kind == .custom {
            guard let spec = definition.spec else { return [] }
            return DashboardChartBuilder.customSeries(spec: spec, users: users)
        }
        return DashboardChartBuilder.series(for: definition.kind, metrics: metrics, users: users)
    }

    func chartMessage(for definition: DashboardKPIDefinition) -> String? {
        chartPoints(for: definition).isEmpty ? "표시할 날짜별 데이터가 아직 없습니다." : nil
    }

    private func ensureSelection() {
        if let selectedKPIId, kpis.contains(where: { $0.id == selectedKPIId }) { return }
        selectedKPIId = kpis.first?.id
    }
}

struct DashboardView: View {
    let serviceId: String?
    let refreshID: Int
    @State private var vm = DashboardViewModel()
    @State private var isShowingKPISheet = false
    @State private var renamingKPI: DashboardKPIDefinition?
    @State private var renameText = ""

    init(serviceId: String?, refreshID: Int = 0) {
        self.serviceId = serviceId
        self.refreshID = refreshID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                kpiGrid
                selectedChartPanel
                if let error = vm.errorMessage {
                    Text(error).font(Typography.caption).foregroundStyle(Palette.accentRed)
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .sheet(isPresented: $isShowingKPISheet) {
            KPICreationSheet(vm: vm, serviceId: serviceId)
                .frame(width: 480)
        }
        .alert("KPI 이름 수정", isPresented: Binding(
            get: { renamingKPI != nil }, set: { if !$0 { renamingKPI = nil } }
        )) {
            TextField("이름", text: $renameText)
            Button("저장") {
                if let kpi = renamingKPI, let serviceId {
                    Task { await vm.renameKPI(id: kpi.id, title: renameText, serviceId: serviceId) }
                }
                renamingKPI = nil
            }
            Button("취소", role: .cancel) { renamingKPI = nil }
        }
        .task(id: "\(serviceId ?? ""):\(refreshID)") {
            guard let serviceId else { return }
            await vm.loadKPIs(serviceId: serviceId)
            _ = vm.loadCached(serviceId: serviceId)
            await vm.refresh(serviceId: serviceId)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Text("대시보드").font(Typography.title).foregroundStyle(Palette.ink)
                if vm.isRefreshing {
                    Label("동기화 중", systemImage: "arrow.triangle.2.circlepath")
                        .font(Typography.caption).foregroundStyle(Palette.muted)
                }
            }
            Spacer()
            Button { isShowingKPISheet = true } label: {
                Label("KPI 추가", systemImage: "plus")
                    .font(Typography.body).foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.lg).frame(height: 38)
                    .background(Palette.ctaFill).clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .buttonStyle(.plain).disabled(serviceId == nil)
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: Spacing.md)], spacing: Spacing.md) {
            ForEach(vm.kpis) { definition in
                KPICardView(
                    title: definition.title,
                    value: vm.valueText(for: definition),
                    subtitle: vm.subtitle(for: definition),
                    isSelected: vm.selectedDefinition?.id == definition.id,
                    onRename: { renameText = definition.title; renamingKPI = definition },
                    onDelete: { if let serviceId { Task { await vm.deleteKPI(id: definition.id, serviceId: serviceId) } } }
                )
                .onTapGesture { vm.selectKPI(id: definition.id) }
                .onDrag { NSItemProvider(object: definition.id as NSString) }
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in handleDrop(providers, target: definition) }
            }
        }
    }

    @ViewBuilder private var selectedChartPanel: some View {
        if let definition = vm.selectedDefinition {
            let points = vm.chartPoints(for: definition)
            card(title: "\(definition.title) 날짜별 차트") {
                if points.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 22, weight: .medium)).foregroundStyle(Palette.muted)
                        Text(vm.chartMessage(for: definition) ?? "표시할 날짜별 데이터가 아직 없습니다.")
                            .font(Typography.caption).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(height: 140, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Chart(points) { point in
                        LineMark(x: .value("날짜", point.date), y: .value("값", point.value))
                            .foregroundStyle(Palette.accentBlue)
                        AreaMark(x: .value("날짜", point.date), y: .value("값", point.value))
                            .foregroundStyle(Palette.accentBlue.opacity(0.16))
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .frame(height: 180)
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], target: DashboardKPIDefinition) -> Bool {
        guard let serviceId, let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let movingId: String?
            if let data = item as? Data { movingId = String(data: data, encoding: .utf8) }
            else if let string = item as? String { movingId = string }
            else { movingId = nil }
            guard let movingId else { return }
            Task { @MainActor in await vm.moveKPI(movingId: movingId, before: target.id, serviceId: serviceId) }
        }
        return true
    }

    @ViewBuilder private func card<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(Typography.caption).foregroundStyle(Palette.muted)
            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }
}

private struct KPICardView: View {
    let title: String
    let value: String
    let subtitle: String
    let isSelected: Bool
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.caption).foregroundStyle(Palette.muted).lineLimit(1)
                Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ash).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Palette.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .stroke(isSelected ? Palette.accentBlue : Palette.hairline, lineWidth: isSelected ? 1.4 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        .contextMenu {
            Button { onRename() } label: { Label("이름 수정", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label("삭제", systemImage: "trash") }
        }
    }
}

// Minimal preview-and-confirm: describe the KPI, preview the real computed value,
// then add. One primary action (미리보기 → 추가); editing the inputs re-arms preview.
private struct KPICreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: DashboardViewModel
    let serviceId: String?
    @State private var title = ""
    @State private var prompt = ""
    @State private var preview: KPIPreview?
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("KPI 추가").font(Typography.cardTitle).foregroundStyle(Palette.ink)

            TextField("KPI 이름", text: $title)
                .textFieldStyle(.roundedBorder)
                .onChange(of: title) { _, _ in preview = nil }

            TextEditor(text: $prompt)
                .font(Typography.body)
                .frame(height: 84)
                .scrollContentBackground(.hidden)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("이 KPI를 어떻게 계산할지 설명하세요 (예: 전체 유저 대비 auth_provider가 kakao인 유저 비중)")
                            .font(Typography.caption).foregroundStyle(Palette.ash)
                            .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.sm)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: prompt) { _, _ in preview = nil }

            if let preview {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let interpretation = preview.interpretation, !interpretation.isEmpty {
                        Text(interpretation).font(Typography.caption).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(preview.valueText).font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.ink)
                        if preview.unit == "percent" {
                            Text("\(preview.numerator) / \(preview.denominator)명")
                                .font(Typography.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
            }

            if let errorMessage {
                Text(errorMessage).font(Typography.caption).foregroundStyle(Palette.accentRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
                Button("취소") { dismiss() }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                Spacer()
                Button {
                    Task { preview == nil ? await runPreview() : await add() }
                } label: {
                    Group {
                        if isBusy { ProgressView().controlSize(.small) }
                        else { Text(preview == nil ? "미리보기" : "추가") }
                    }
                    .frame(minWidth: 84, minHeight: 36)
                    .foregroundStyle(Palette.ctaText)
                    .background(Palette.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                }
                .buttonStyle(.plain)
                .disabled(!canRequest || isBusy)
            }
        }
        .padding(Spacing.xl)
        .background(Palette.canvas)
    }

    private var canRequest: Bool {
        serviceId != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runPreview() async {
        guard let serviceId else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            preview = try await vm.previewKPI(serviceId: serviceId, title: title, prompt: prompt)
        } catch {
            errorMessage = "미리보기 실패: \(error.localizedDescription)"
        }
    }

    private func add() async {
        guard let serviceId, let preview else { return }
        isBusy = true
        defer { isBusy = false }
        await vm.addCustomKPI(title: title, prompt: prompt, preview: preview, serviceId: serviceId)
        dismiss()
    }
}
