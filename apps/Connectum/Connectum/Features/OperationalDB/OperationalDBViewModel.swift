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

    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    var filteredUsers: [CrmUser] {
        guard !search.isEmpty else { return users }
        let q = search.lowercased()
        return users.filter { ($0.email ?? "").lowercased().contains(q) || $0.sourceUserId.lowercased().contains(q) }
    }

    func loadServices() async {
        isLoading = true; defer { isLoading = false }
        do {
            services = try await repo.fetchServices()
            if selectedServiceId == nil { selectedServiceId = services.first?.id }
            if let sid = selectedServiceId { await loadUsers(serviceId: sid) }
        } catch { errorMessage = String(describing: error) }
    }
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
