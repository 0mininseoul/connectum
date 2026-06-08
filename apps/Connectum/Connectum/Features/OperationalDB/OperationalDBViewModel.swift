import Foundation
import Observation

@MainActor
@Observable
final class OperationalDBViewModel {
    var users: [CrmUser] = []
    var search: String = ""
    var isLoading = false
    var errorMessage: String?
    var config = ViewConfig()
    var savedViews: [SavedView] = []
    var displayColumns: [String] = []

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

    func load(serviceId: String) async {
        isLoading = true; defer { isLoading = false }
        do {
            users = try await repo.fetchUsers(serviceId: serviceId)
            savedViews = try await repo.fetchViews()
            displayColumns = try await repo.fetchDisplayColumns(serviceId: serviceId)
        } catch { errorMessage = String(describing: error) }
    }

    func saveView(name: String) async {
        do { try await repo.createView(name: name, config: config); savedViews = try await repo.fetchViews() }
        catch { errorMessage = String(describing: error) }
    }

    func applyView(_ v: SavedView) { config = v.config }
}
