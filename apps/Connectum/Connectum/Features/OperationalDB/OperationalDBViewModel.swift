import Foundation
import Observation

@MainActor
@Observable
final class OperationalDBViewModel {
    var services: [Service] = []
    var selectedServiceId: String?
    var users: [CrmUser] = []
    var search: String = ""
    var isLoading = false
    var errorMessage: String?
    var config = ViewConfig()
    var savedViews: [SavedView] = []

    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    var filteredUsers: [CrmUser] {
        var list = users
        switch config.contactFilter {
        case "contacted": list = list.filter { $0.contactStatus == "contacted" }
        case "not_contacted": list = list.filter { $0.contactStatus == "not_contacted" }
        default: break
        }
        if config.profiledOnly { list = list.filter { $0.amplitudeProfile?.os != nil } }
        if !search.isEmpty {
            let q = search.lowercased()
            list = list.filter { ($0.email ?? "").lowercased().contains(q) || $0.sourceUserId.lowercased().contains(q) }
        }
        list.sort { a, b in
            let asc: Bool
            switch config.sortKey {
            case "email": asc = (a.email ?? "") < (b.email ?? "")
            case "contact_status": asc = a.contactStatus < b.contactStatus
            default: asc = (a.createdAt ?? "") < (b.createdAt ?? "")
            }
            return config.sortAsc ? asc : !asc
        }
        return list
    }

    func loadServices() async {
        isLoading = true; defer { isLoading = false }
        do {
            services = try await repo.fetchServices()
            if selectedServiceId == nil { selectedServiceId = services.first?.id }
            if let sid = selectedServiceId { await loadUsers(serviceId: sid) }
            await loadViews()
        } catch { errorMessage = String(describing: error) }
    }
    func loadViews() async {
        do { savedViews = try await repo.fetchViews() } catch { errorMessage = String(describing: error) }
    }
    func saveView(name: String) async {
        do { try await repo.createView(name: name, config: config); await loadViews() }
        catch { errorMessage = String(describing: error) }
    }
    func applyView(_ v: SavedView) { config = v.config }
    func loadUsers(serviceId: String) async {
        isLoading = true; defer { isLoading = false }
        do { users = try await repo.fetchUsers(serviceId: serviceId) }
        catch { errorMessage = String(describing: error) }
    }
    func selectService(_ id: String) async {
        selectedServiceId = id
        await loadUsers(serviceId: id)
    }
}
