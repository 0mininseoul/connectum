import Foundation
import Observation
import SwiftUI

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
    }

    var tab: Tab = .operational
    var services: [Service] = []
    var selectedServiceId: String?
    var columnVisibility: NavigationSplitViewVisibility = .all

    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    var selectedServiceName: String {
        services.first { $0.id == selectedServiceId }?.name ?? "서비스 없음"
    }

    func load() async {
        do {
            services = try await repo.fetchServices()
            if selectedServiceId == nil { selectedServiceId = services.first?.id }
        } catch { /* shell tolerates load failure */ }
    }

    func toggleSidebar() {
        columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
    }
}
