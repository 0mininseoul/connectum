import SwiftUI
import Charts
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var services: [Service] = []
    var selectedServiceId: String?
    var metrics = DashboardMetrics()
    var isLoading = false
    var errorMessage: String?
    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            services = try await repo.fetchServices()
            if selectedServiceId == nil { selectedServiceId = services.first?.id }
            if let s = selectedServiceId { metrics = try await repo.fetchMetrics(serviceId: s) }
        } catch { errorMessage = String(describing: error) }
    }
    func select(_ id: String) async {
        selectedServiceId = id
        do { metrics = try await repo.fetchMetrics(serviceId: id) } catch { errorMessage = String(describing: error) }
    }
}

struct DashboardView: View {
    @State private var vm = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack {
                    Text("대시보드").font(Typography.cardTitle).foregroundStyle(Palette.ink)
                    Spacer()
                    Picker("", selection: Binding(get: { vm.selectedServiceId ?? "" }, set: { id in Task { await vm.select(id) } })) {
                        ForEach(vm.services) { s in Text(s.name).tag(s.id) }
                    }.labelsHidden().frame(width: 240)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Spacing.lg)], spacing: Spacing.lg) {
                    metric("전체 유저", "\(vm.metrics.total)")
                    metric("컨택률", String(format: "%.0f%%", vm.metrics.contactRate * 100))
                    metric("컨택 완료", "\(vm.metrics.contacted)")
                    metric("프로필 보유", "\(vm.metrics.profiled)")
                    metric("최근 7일 가입", "\(vm.metrics.recentSignups)")
                }
                card(title: "컨택 현황") {
                    Chart {
                        BarMark(x: .value("상태", "컨택"), y: .value("수", vm.metrics.contacted))
                            .foregroundStyle(Palette.accentGreen)
                        BarMark(x: .value("상태", "미컨택"), y: .value("수", max(0, vm.metrics.total - vm.metrics.contacted)))
                            .foregroundStyle(Palette.ash)
                    }
                    .frame(height: 200)
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .task { await vm.load() }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(Typography.caption).foregroundStyle(Palette.muted)
            Text(value).font(Typography.cardTitle).foregroundStyle(Palette.ink)
        }
        .padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }
    @ViewBuilder private func card<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(Typography.caption).foregroundStyle(Palette.muted)
            content()
        }
        .padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }
}
