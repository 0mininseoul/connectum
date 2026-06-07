import Foundation
import Observation

@MainActor
@Observable
final class UserDetailViewModel {
    var events: [CrmUserEvent] = []
    var contactStatus: String
    var isBusy = false
    var errorMessage: String?

    let user: CrmUser
    private let repo: CrmDataProviding
    init(user: CrmUser, repo: CrmDataProviding = CrmRepository()) {
        self.user = user; self.contactStatus = user.contactStatus; self.repo = repo
    }
    func loadEvents() async {
        do { events = try await repo.fetchEvents(crmUserId: user.id, limit: 50) }
        catch { errorMessage = String(describing: error) }
    }
    func toggleContacted() async {
        let next = contactStatus == "contacted" ? "not_contacted" : "contacted"
        isBusy = true; defer { isBusy = false }
        do { try await repo.setContactStatus(crmUserId: user.id, status: next); contactStatus = next }
        catch { errorMessage = String(describing: error) }
    }
}
