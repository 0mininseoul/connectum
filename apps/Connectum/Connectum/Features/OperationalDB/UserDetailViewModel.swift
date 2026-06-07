import Foundation
import Observation

@MainActor
@Observable
final class UserDetailViewModel {
    var events: [CrmUserEvent] = []
    var contactStatus: String
    var isBusy = false
    var errorMessage: String?
    var records: [ChannelRecord] = []
    var aiSummary: String?
    var isRegenerating = false

    let user: CrmUser
    private let repo: CrmDataProviding
    init(user: CrmUser, repo: CrmDataProviding = CrmRepository()) {
        self.user = user; self.contactStatus = user.contactStatus; self.repo = repo
        self.aiSummary = user.aiSummary
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
    func loadRecords() async {
        do { records = try await repo.fetchChannelRecords(crmUserId: user.id) }
        catch { errorMessage = String(describing: error) }
    }
    func regenerate() async {
        isRegenerating = true; defer { isRegenerating = false }
        do { aiSummary = try await repo.regenerateSummary(crmUserId: user.id) }
        catch { errorMessage = String(describing: error) }
    }
    func addRecord(channel: String, occurredAt: String, body: String) async {
        do {
            try await repo.addChannelRecord(crmUserId: user.id, channel: channel, occurredAt: occurredAt, body: body)
            await loadRecords()
        } catch { errorMessage = String(describing: error) }
    }
}
