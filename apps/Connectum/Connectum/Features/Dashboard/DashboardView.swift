import SwiftUI
import Charts
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var metrics = DashboardMetrics()
    var isLoading = false
    var errorMessage: String?
    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    func load(serviceId: String) async {
        isLoading = true; defer { isLoading = false }
        do { metrics = try await repo.fetchMetrics(serviceId: serviceId) }
        catch { errorMessage = String(describing: error) }
    }
}

struct DashboardView: View {
    let serviceId: String?
    @State private var vm = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("대시보드").font(Typography.title).foregroundStyle(Palette.ink)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Spacing.md)], spacing: Spacing.md) {
                    metric("전체 유저", "\(vm.metrics.total)")
                    metric("컨택률", String(format: "%.0f%%", vm.metrics.contactRate * 100))
                    metric("컨택 완료", "\(vm.metrics.contacted)")
                    metric("프로필 보유", "\(vm.metrics.profiled)")
                    metric("최근 7일 가입", "\(vm.metrics.recentSignups)")
                }

                card(title: "컨택 현황") {
                    Chart {
                        BarMark(x: .value("수", vm.metrics.contacted), y: .value("상태", "컨택"))
                            .foregroundStyle(Palette.accentGreen)
                        BarMark(x: .value("수", max(0, vm.metrics.total - vm.metrics.contacted)), y: .value("상태", "미컨택"))
                            .foregroundStyle(Palette.ash)
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .frame(height: 120)
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .task(id: serviceId) { if let serviceId { await vm.load(serviceId: serviceId) } }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(Typography.caption).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.ink)
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
