import SwiftUI
import Charts
import Observation
import UniformTypeIdentifiers

private enum CustomKPIChartStatus {
    case generating
    case ready
}

@MainActor
@Observable
final class DashboardViewModel {
    var metrics = DashboardMetrics()
    var users: [CrmUser] = []
    var kpiState = DashboardKPIState.initial
    var selectedKPIId: String?
    var isLoading = false
    var isRefreshing = false
    var cacheUpdatedAt: Date?
    var errorMessage: String?
    private var customChartStatusById: [String: CustomKPIChartStatus] = [:]
    private let repo: CrmDataProviding
    private let cache: CrmCacheProviding
    private let kpiStore: DashboardKPIStore

    init(
        repo: CrmDataProviding = CrmRepository(),
        cache: CrmCacheProviding = CrmCacheStore(),
        kpiStore: DashboardKPIStore = DashboardKPIStore()
    ) {
        self.repo = repo
        self.cache = cache
        self.kpiStore = kpiStore
    }

    @discardableResult
    func loadCached(serviceId: String) -> Bool {
        do {
            guard let snapshot = try cache.loadDashboardMetrics(serviceId: serviceId),
                  snapshot.serviceId == serviceId
            else { return false }
            metrics = snapshot.metrics
            cacheUpdatedAt = snapshot.cachedAt
            errorMessage = nil
            return true
        } catch {
            errorMessage = "캐시 읽기 실패: \(error)"
            return false
        }
    }

    func loadKPIState(serviceId: String) {
        kpiState = kpiStore.load(serviceId: serviceId)
        ensureSelection()
    }

    func refresh(serviceId: String) async {
        let hasCachedMetrics = cacheUpdatedAt != nil
        isLoading = !hasCachedMetrics
        isRefreshing = hasCachedMetrics
        defer {
            isLoading = false
            isRefreshing = false
        }
        do {
            let freshMetrics = try await repo.fetchMetrics(serviceId: serviceId)
            metrics = freshMetrics
            users = (try? await repo.fetchUsers(serviceId: serviceId)) ?? users
            let snapshot = DashboardMetricsCacheSnapshot(
                serviceId: serviceId,
                cachedAt: Date(),
                metrics: freshMetrics
            )
            try? cache.saveDashboardMetrics(snapshot)
            cacheUpdatedAt = snapshot.cachedAt
            errorMessage = nil
        } catch {
            errorMessage = hasCachedMetrics ? "최신 동기화 실패: \(error)" : String(describing: error)
        }
    }

    func requestKPIConfirmation(serviceId: String, title: String, prompt: String) async throws -> DashboardKPIConfirmation {
        try await repo.confirmDashboardKPI(serviceId: serviceId, title: title, prompt: prompt)
    }

    func addCustomKPI(title: String, prompt: String, confirmation: DashboardKPIConfirmation, serviceId: String) {
        let definition = DashboardKPIDefinition.custom(title: title, prompt: prompt, confirmation: confirmation)
        kpiState.items.append(definition)
        selectedKPIId = definition.id
        customChartStatusById[definition.id] = .generating
        persist(serviceId: serviceId)
        scheduleChartGeneration(for: definition)
    }

    func deleteKPI(id: String, serviceId: String) {
        kpiState.items.removeAll { $0.id == id }
        customChartStatusById[id] = nil
        ensureSelection()
        persist(serviceId: serviceId)
    }

    func moveKPI(movingId: String, before targetId: String, serviceId: String) {
        guard movingId != targetId,
              let from = kpiState.items.firstIndex(where: { $0.id == movingId }),
              let target = kpiState.items.firstIndex(where: { $0.id == targetId })
        else { return }
        let item = kpiState.items.remove(at: from)
        let insertion = target > from ? target - 1 : target
        kpiState.items.insert(item, at: insertion)
        persist(serviceId: serviceId)
    }

    func selectKPI(id: String) {
        selectedKPIId = id
    }

    var selectedDefinition: DashboardKPIDefinition? {
        if let selectedKPIId,
           let selected = kpiState.items.first(where: { $0.id == selectedKPIId }) {
            return selected
        }
        return kpiState.items.first
    }

    func valueText(for definition: DashboardKPIDefinition) -> String {
        switch effectiveKind(for: definition) {
        case .totalUsers:
            return "\(metrics.total)"
        case .contactRate:
            return String(format: "%.0f%%", metrics.contactRate * 100)
        case .contacted:
            return "\(metrics.contacted)"
        case .custom:
            return customChartStatusById[definition.id] == .generating ? "생성 중" : "등록됨"
        }
    }

    func subtitle(for definition: DashboardKPIDefinition) -> String {
        definition.kind == .custom ? "커스텀" : "기본"
    }

    func chartPoints(for definition: DashboardKPIDefinition) -> [DashboardKPIChartPoint] {
        let kind = effectiveKind(for: definition)
        guard kind != .custom else { return [] }
        return DashboardChartBuilder.series(for: kind, metrics: metrics, users: users)
    }

    func chartMessage(for definition: DashboardKPIDefinition) -> String? {
        guard definition.kind == .custom else { return nil }
        if customChartStatusById[definition.id] == .generating {
            return "Gemini 확인 완료. 백그라운드에서 차트를 생성하는 중입니다."
        }
        if effectiveKind(for: definition) == .custom {
            return "계산 정의가 등록됐습니다. 이 프롬프트는 백엔드 계산 엔진 연결 후 날짜별 차트가 생성됩니다."
        }
        return nil
    }

    private func effectiveKind(for definition: DashboardKPIDefinition) -> DashboardKPIKind {
        guard definition.kind == .custom else { return definition.kind }
        guard customChartStatusById[definition.id] != .generating,
              let prompt = definition.prompt,
              let kind = DashboardChartBuilder.matchingBuiltInKind(for: prompt)
        else {
            return .custom
        }
        return kind
    }

    private func persist(serviceId: String) {
        kpiStore.save(kpiState, serviceId: serviceId)
    }

    private func ensureSelection() {
        if let selectedKPIId,
           kpiState.items.contains(where: { $0.id == selectedKPIId }) {
            return
        }
        selectedKPIId = kpiState.items.first?.id
    }

    private func scheduleChartGeneration(for definition: DashboardKPIDefinition) {
        Task { [weak self, id = definition.id] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                self?.customChartStatusById[id] = .ready
            }
        }
    }
}

struct DashboardView: View {
    let serviceId: String?
    let refreshID: Int
    @State private var vm = DashboardViewModel()
    @State private var isShowingKPISheet = false

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
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.accentRed)
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .sheet(isPresented: $isShowingKPISheet) {
            KPICreationSheet(vm: vm, serviceId: serviceId)
                .frame(width: 560)
        }
        .task(id: "\(serviceId ?? ""):\(refreshID)") {
            guard let serviceId else { return }
            vm.loadKPIState(serviceId: serviceId)
            _ = vm.loadCached(serviceId: serviceId)
            await vm.refresh(serviceId: serviceId)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Text("대시보드")
                    .font(Typography.title)
                    .foregroundStyle(Palette.ink)
                if vm.isRefreshing {
                    Label("동기화 중", systemImage: "arrow.triangle.2.circlepath")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer()
            Button {
                isShowingKPISheet = true
            } label: {
                Label("KPI 추가", systemImage: "plus")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ctaText)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 38)
                    .background(Palette.ctaFill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
            .buttonStyle(.plain)
            .disabled(serviceId == nil)
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: Spacing.md)], spacing: Spacing.md) {
            ForEach(vm.kpiState.items) { definition in
                KPICardView(
                    title: definition.title,
                    value: vm.valueText(for: definition),
                    subtitle: vm.subtitle(for: definition),
                    isSelected: vm.selectedDefinition?.id == definition.id,
                    isGenerating: definition.kind == .custom && vm.chartMessage(for: definition) != nil,
                    onDelete: {
                        if let serviceId {
                            vm.deleteKPI(id: definition.id, serviceId: serviceId)
                        }
                    }
                )
                .onTapGesture {
                    vm.selectKPI(id: definition.id)
                }
                .onDrag {
                    NSItemProvider(object: definition.id as NSString)
                }
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                    handleDrop(providers, target: definition)
                }
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
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Palette.muted)
                        Text(vm.chartMessage(for: definition) ?? "표시할 날짜별 데이터가 아직 없습니다.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(height: 140, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Chart(points) { point in
                        LineMark(
                            x: .value("날짜", point.date),
                            y: .value("값", point.value)
                        )
                        .foregroundStyle(Palette.accentBlue)
                        AreaMark(
                            x: .value("날짜", point.date),
                            y: .value("값", point.value)
                        )
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
        guard let serviceId,
              let provider = providers.first
        else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let movingId: String?
            if let data = item as? Data {
                movingId = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                movingId = string
            } else {
                movingId = nil
            }
            guard let movingId else { return }
            Task { @MainActor in
                vm.moveKPI(movingId: movingId, before: target.id, serviceId: serviceId)
            }
        }
        return true
    }

    @ViewBuilder private func card<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.muted)
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
    let isGenerating: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isGenerating ? Palette.accentBlue : Palette.ash)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.sm)
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("KPI 삭제")
            }
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
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
    }
}

private struct KPICreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: DashboardViewModel
    let serviceId: String?
    @State private var title = ""
    @State private var prompt = ""
    @State private var confirmation: DashboardKPIConfirmation?
    @State private var isRequesting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("KPI 추가")
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.ink)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField("KPI 이름", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $prompt)
                    .font(Typography.body)
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
            }

            if let confirmation {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Label("Gemini 확인", systemImage: "sparkle")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                    Text(confirmation.summary)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accentRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Spacing.sm) {
                Button("취소") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                Spacer()
                Button {
                    Task { await requestConfirmation() }
                } label: {
                    if isRequesting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 120, height: 36)
                    } else {
                        Label("Gemini 확인 요청", systemImage: "sparkle")
                            .frame(height: 36)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.body)
                .padding(.horizontal, Spacing.md)
                .background(Palette.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                .disabled(!canRequest || isRequesting)

                Button {
                    guard let serviceId, let confirmation else { return }
                    vm.addCustomKPI(title: title, prompt: prompt, confirmation: confirmation, serviceId: serviceId)
                    dismiss()
                } label: {
                    Text("컨펌하고 추가")
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.ctaText)
                .padding(.horizontal, Spacing.md)
                .background(Palette.ctaFill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                .disabled(confirmation == nil || serviceId == nil)
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

    private func requestConfirmation() async {
        guard let serviceId else { return }
        isRequesting = true
        errorMessage = nil
        confirmation = nil
        defer { isRequesting = false }
        do {
            confirmation = try await vm.requestKPIConfirmation(serviceId: serviceId, title: title, prompt: prompt)
        } catch {
            errorMessage = "Gemini 확인 실패: \(error.localizedDescription)"
        }
    }
}
