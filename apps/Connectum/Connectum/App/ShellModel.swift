import Foundation
import Observation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }

    var tint: Color {
        switch self {
        case .dark: return .white
        case .light: return Color(hex: "111315")
        }
    }

    var toggleTitle: String {
        switch self {
        case .dark: return "라이트 모드로 전환"
        case .light: return "다크 모드로 전환"
        }
    }

    var settingsLabel: String {
        switch self {
        case .dark: return "다크 모드"
        case .light: return "라이트 모드"
        }
    }
}

enum AppPreferenceKeys {
    static let userDetailOpenMode = "userDetailOpenMode"
    static let uiScale = "uiScale"
}

enum UserDetailOpenMode: String, CaseIterable, Identifiable {
    case side
    case popup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .side: return "우측 사이드 보기"
        case .popup: return "팝업"
        }
    }
}

// App-level navigation state shared across all tabs: which tab is active, the
// persistent service selection (sidebar), and sidebar visibility.
@MainActor
@Observable
final class ShellModel {
    enum Tab: Int, CaseIterable, Identifiable {
        case operational, dashboard, connections
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .operational: return "운영 DB"
            case .dashboard:   return "대시보드"
            case .connections: return "연동"
            }
        }
        var systemImage: String {
            switch self {
            case .operational: return "tablecells"
            case .dashboard:   return "chart.bar.xaxis"
            case .connections: return "link"
            }
        }
    }

    var tab: Tab = .operational
    var services: [Service] = []
    var selectedServiceId: String?
    var didLoadServices = false
    var columnVisibility: NavigationSplitViewVisibility = .all
    var syncingServiceIds = Set<String>()
    var syncRevision = 0
    var syncErrorMessage: String?
    var uiScale: Double {
        didSet { UserDefaults.standard.set(uiScale, forKey: AppPreferenceKeys.uiScale) }
    }
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeDefaultsKey) }
    }

    private let repo: CrmDataProviding
    private let cache: CrmCacheProviding
    private static let themeDefaultsKey = "appearanceMode"

    init(repo: CrmDataProviding = CrmRepository(), cache: CrmCacheProviding = CrmCacheStore()) {
        self.repo = repo
        self.cache = cache
        let stored = UserDefaults.standard.string(forKey: Self.themeDefaultsKey)
        self.theme = AppTheme(rawValue: stored ?? "") ?? .dark
        let storedScale = UserDefaults.standard.double(forKey: AppPreferenceKeys.uiScale)
        self.uiScale = storedScale == 0 ? 1.0 : min(max(storedScale, 0.8), 1.4)
    }

    var selectedService: Service? {
        services.first { $0.id == selectedServiceId }
    }

    var realServices: [Service] {
        services.filter { !$0.isDraft }
    }

    var hasDraftService: Bool {
        services.contains { $0.isDraft }
    }

    var selectedDataServiceId: String? {
        guard selectedService?.isDraft != true else { return nil }
        return selectedServiceId
    }

    var selectedServiceName: String {
        services.first { $0.id == selectedServiceId }?.name ?? "서비스 없음"
    }

    func load() async {
        let draft = services.first { $0.isDraft }
        let previousSelection = selectedServiceId
        do {
            let fetched = try await repo.fetchServices()
            didLoadServices = true
            services = draft.map { [$0] + fetched } ?? fetched
            if let previousSelection, services.contains(where: { $0.id == previousSelection }) {
                selectedServiceId = previousSelection
            } else {
                selectedServiceId = services.first?.id
            }
        } catch {
            didLoadServices = true
        }
    }

    func startNewService() {
        services.removeAll { $0.isDraft }
        let draft = Service(id: "draft:\(UUID().uuidString)", name: "새 서비스", supabaseProjectRef: nil)
        services.insert(draft, at: 0)
        selectedServiceId = draft.id
        tab = .connections
        columnVisibility = .all
    }

    func finishServiceCreation(named name: String) async {
        selectedServiceId = nil
        services.removeAll { $0.isDraft }
        await load()
        let createdService = services.first { $0.name == name } ?? services.first
        selectedServiceId = createdService?.id
        tab = .operational
        if let createdService {
            await syncService(createdService)
        }
    }

    func finishServiceDeletion(deletedId: String) async {
        services.removeAll { $0.id == deletedId }
        syncingServiceIds.remove(deletedId)
        try? cache.removeService(serviceId: deletedId)
        if selectedServiceId == deletedId {
            selectedServiceId = services.first?.id
        }
        await load()
        if selectedServiceId == deletedId {
            selectedServiceId = services.first?.id
        }
        tab = .connections
    }

    func syncService(_ service: Service) async {
        guard !service.isDraft, !syncingServiceIds.contains(service.id) else { return }
        guard service.supabaseAccountId != nil else {
            syncErrorMessage = "\(service.name): Supabase 원본 계정이 없습니다. 연동 탭에서 다시 연결하세요."
            return
        }
        syncingServiceIds.insert(service.id)
        syncErrorMessage = nil
        defer { syncingServiceIds.remove(service.id) }
        do {
            try await repo.syncService(serviceId: service.id)
            syncRevision += 1
        } catch {
            syncErrorMessage = "동기화 실패: \(error)"
        }
    }

    var aiPanelVisible = false
    func toggleAIPanel() { aiPanelVisible.toggle() }

    func toggleSidebar() {
        columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
    }

    func toggleTheme() {
        theme = (theme == .dark) ? .light : .dark
    }

    func zoomIn() {
        uiScale = min(1.4, (uiScale * 10 + 1).rounded() / 10)
    }

    func zoomOut() {
        uiScale = max(0.8, (uiScale * 10 - 1).rounded() / 10)
    }

    func resetZoom() {
        uiScale = 1.0
    }
}
