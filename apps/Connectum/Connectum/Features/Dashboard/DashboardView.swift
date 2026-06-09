import SwiftUI
import Charts
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var metrics = DashboardMetrics()
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

    func load(serviceId: String) async {
        _ = loadCached(serviceId: serviceId)
        await refresh(serviceId: serviceId)
    }
}

struct DashboardView: View {
    let serviceId: String?
    let refreshID: Int
    @State private var vm = DashboardViewModel()

    init(serviceId: String?, refreshID: Int = 0) {
        self.serviceId = serviceId
        self.refreshID = refreshID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.sm) {
                    Text("대시보드").font(Typography.title).foregroundStyle(Palette.ink)
                    if vm.isRefreshing {
                        Label("동기화 중", systemImage: "arrow.triangle.2.circlepath")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }

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
        .task(id: "\(serviceId ?? ""):\(refreshID)") {
            if let serviceId {
                _ = vm.loadCached(serviceId: serviceId)
                await vm.refresh(serviceId: serviceId)
            }
        }
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
