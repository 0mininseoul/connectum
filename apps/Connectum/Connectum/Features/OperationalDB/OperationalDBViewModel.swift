import Foundation
import Observation

@MainActor
@Observable
final class OperationalDBViewModel {
    var users: [CrmUser] = [] {
        didSet { rebuildProfileColumns() }
    }
    var search: String = ""
    var isLoading = false
    var errorMessage: String?
    var isRefreshing = false
    var cacheUpdatedAt: Date?
    var config = ViewConfig()
    var savedViews: [SavedView] = []
    var activeViewId: String?            // nil = the editable "기본" view
    var serviceId: String?
    var relatedTables: [ServiceTableInfo] = []   // extra imported tables (role = related)
    private(set) var profileColumns: [String] = []
    private var baseDisplayColumns: [String] = []   // service default (from the wizard)

    // Special, non-source column ids.
    nonisolated static let primaryCol = "__primary"
    nonisolated static let emailCol = "__email"
    nonisolated static let sourceUserIdCol = "__source_user_id"
    nonisolated static let contactCol = "__contact"
    nonisolated static let aiCol = "__ai"

    private let repo: CrmDataProviding
    private let cache: CrmCacheProviding
    init(repo: CrmDataProviding = CrmRepository(), cache: CrmCacheProviding = CrmCacheStore()) {
        self.repo = repo
        self.cache = cache
    }

    // Source columns actually present in the synced data (union of profile keys).
    var primaryColumn: String {
        primaryColumnCandidates.contains(config.primaryColumn) ? config.primaryColumn : Self.emailCol
    }
    var sortColumn: String {
        normalizedSortColumn(config.sortKey)
    }

    var primaryColumnCandidates: [String] {
        [Self.emailCol, Self.sourceUserIdCol] + profileColumns
    }

    func normalizedSortColumn(_ key: String) -> String {
        switch key {
        case "email": return Self.emailCol
        case "source_user_id": return Self.sourceUserIdCol
        case "contact_status": return Self.contactCol
        default: return key
        }
    }

    // Reorderable/toggleable columns (everything except the fixed main column).
    var availableColumns: [String] {
        let identityColumns = [Self.emailCol, Self.sourceUserIdCol].filter { $0 != primaryColumn }
        let dynamicColumns = profileColumns.filter { $0 != primaryColumn }
        return identityColumns + [Self.contactCol, Self.aiCol] + dynamicColumns
    }

    func columnLabel(_ id: String) -> String {
        switch id {
        case Self.primaryCol: return columnLabel(primaryColumn)
        case Self.emailCol: return "이메일"
        case Self.sourceUserIdCol: return "유저 ID"
        case Self.contactCol: return "컨택"
        case Self.aiCol: return "AI 총평"
        default: return id
        }
    }
    // Which columns start visible (excludes 이메일, always shown).
    var defaultVisible: [String] {
        let d = baseDisplayColumns.filter { $0 != primaryColumn }
        if d.contains(where: { $0.hasPrefix("__") }) { return d }
        return [Self.contactCol] + d + [Self.aiCol]
    }

    func primaryText(_ user: CrmUser) -> String {
        let value: String
        switch primaryColumn {
        case Self.emailCol:
            value = user.email ?? ""
        case Self.sourceUserIdCol:
            value = user.sourceUserId
        default:
            value = user.profileValue(primaryColumn)
        }
        if value.isEmpty || value == "—" {
            return user.email ?? user.sourceUserId
        }
        return value
    }

    var filteredUsers: [CrmUser] {
        var list = matchingUsers
        let comparator = CrmUserSortComparator(
            columnID: sortColumn,
            primaryColumnID: primaryColumn,
            order: config.sortAsc ? .forward : .reverse
        )
        list.sort { a, b in
            let result = comparator.compare(a, b)
            if result == .orderedSame {
                return a.sourceUserId < b.sourceUserId
            }
            return result == .orderedAscending
        }
        return list
    }

    var filteredUserCount: Int {
        matchingUsers.count
    }

    private var matchingUsers: [CrmUser] {
        var list = users
        switch config.contactFilter {
        case "contacted": list = list.filter { $0.contactStatus == "contacted" }
        case "not_contacted": list = list.filter { $0.contactStatus == "not_contacted" }
        default: break
        }
        if config.profiledOnly { list = list.filter { $0.amplitudeProfile?.os != nil } }
        if !search.isEmpty {
            let q = search.lowercased()
            list = list.filter { matchesSearch($0, query: q) }
        }
        return list
    }

    private func matchesSearch(_ user: CrmUser, query: String) -> Bool {
        searchableValues(user).contains { $0.lowercased().contains(query) }
    }

    private func searchableValues(_ user: CrmUser) -> [String] {
        var values = [
            primaryText(user),
            user.email ?? "",
            user.sourceUserId,
            user.displayName ?? "",
            user.contactStatus,
            user.aiSummary ?? "",
            user.lastSyncedAt ?? "",
            user.createdAt ?? ""
        ]

        if let profile = user.amplitudeProfile {
            values.append(contentsOf: [
                profile.os,
                profile.platform,
                profile.deviceFamily,
                profile.deviceType,
                profile.country,
                profile.region,
                profile.city,
                profile.lastEventTime
            ].compactMap { $0 })
        }

        if let profile = user.supabaseProfile {
            values.append(contentsOf: profile.values.map(\.display))
        }

        return values.filter { !$0.isEmpty && $0 != "—" }
    }

    @discardableResult
    func loadCached(serviceId: String) async -> Bool {
        if serviceId != self.serviceId { relatedTables = [] }  // don't carry a prior service's tables
        self.serviceId = serviceId
        do {
            let cache = self.cache
            guard let snapshot = try await Task.detached(priority: .userInitiated, operation: {
                try cache.loadOperationalDB(serviceId: serviceId)
            }).value,
                  snapshot.serviceId == serviceId
            else { return false }
            apply(snapshot)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "캐시 읽기 실패: \(error)"
            return false
        }
    }

    func refresh(serviceId: String) async {
        self.serviceId = serviceId
        let hasExistingRows = !users.isEmpty
        isLoading = !hasExistingRows
        isRefreshing = hasExistingRows
        defer {
            isLoading = false
            isRefreshing = false
        }
        do {
            let freshUsers = try await repo.fetchUsers(serviceId: serviceId)
            let freshViews = try await repo.fetchViews()
            let freshDisplayColumns = try await repo.fetchDisplayColumns(serviceId: serviceId)
            users = freshUsers
            savedViews = freshViews
            baseDisplayColumns = freshDisplayColumns
            relatedTables = (try? await repo.fetchServiceTables(serviceId: serviceId))?
                .filter { !$0.isUserTable } ?? []
            let snapshot = OperationalDBCacheSnapshot(
                serviceId: serviceId,
                cachedAt: Date(),
                users: freshUsers,
                savedViews: freshViews,
                displayColumns: freshDisplayColumns
            )
            let cache = self.cache
            try? await Task.detached(priority: .utility) {
                try cache.saveOperationalDB(snapshot)
            }.value
            cacheUpdatedAt = snapshot.cachedAt
            errorMessage = nil
        } catch {
            errorMessage = hasExistingRows ? "최신 동기화 실패: \(error)" : String(describing: error)
        }
    }

    func load(serviceId: String) async {
        _ = await loadCached(serviceId: serviceId)
        await refresh(serviceId: serviceId)
    }

    func excludeUser(_ user: CrmUser) async {
        do {
            try await repo.excludeUser(crmUserId: user.id, reason: "manual")
            users.removeAll { $0.id == user.id }
            saveCurrentCache()
        } catch {
            errorMessage = "유저 제외 실패: \(error)"
        }
    }

    // MARK: Views (별도 테이블 뷰 — filters + column layout)
    func saveView(name: String, customization: String) async {
        config.customization = customization
        do { try await repo.createView(name: name, config: config); savedViews = try await repo.fetchViews() }
        catch { errorMessage = String(describing: error) }
    }
    func applyView(_ v: SavedView) { activeViewId = v.id; config = v.config }
    func resetToDefault() { activeViewId = nil; config = ViewConfig() }
    func customizationJSON(for viewId: String?) -> String? {
        guard let viewId, let v = savedViews.first(where: { $0.id == viewId }), !v.config.customization.isEmpty
        else { return nil }
        return v.config.customization
    }

    private func apply(_ snapshot: OperationalDBCacheSnapshot) {
        users = snapshot.users.filter { $0.contactStatus != "excluded" }
        savedViews = snapshot.savedViews
        baseDisplayColumns = snapshot.displayColumns
        cacheUpdatedAt = snapshot.cachedAt
    }

    private func saveCurrentCache() {
        guard let serviceId else { return }
        try? cache.saveOperationalDB(OperationalDBCacheSnapshot(
            serviceId: serviceId,
            cachedAt: Date(),
            users: users,
            savedViews: savedViews,
            displayColumns: baseDisplayColumns
        ))
    }

    private func rebuildProfileColumns() {
        var set = Set<String>()
        for user in users {
            if let profile = user.supabaseProfile {
                set.formUnion(profile.keys)
            }
        }
        profileColumns = set.sorted()
    }
}

struct CrmUserSortComparator: SortComparator, Equatable {
    let columnID: String
    let primaryColumnID: String
    var order: SortOrder = .forward

    func compare(_ lhs: CrmUser, _ rhs: CrmUser) -> ComparisonResult {
        let result = value(lhs).localizedStandardCompare(value(rhs))
        switch order {
        case .forward:
            return result
        case .reverse:
            switch result {
            case .orderedAscending: return .orderedDescending
            case .orderedDescending: return .orderedAscending
            case .orderedSame: return .orderedSame
            }
        }
    }

    private func value(_ user: CrmUser) -> String {
        if columnID == OperationalDBViewModel.primaryCol {
            return value(user, primaryColumnID)
        }
        return value(user, columnID)
    }

    private func value(_ user: CrmUser, _ id: String) -> String {
        switch id {
        case OperationalDBViewModel.emailCol:
            return user.email ?? ""
        case OperationalDBViewModel.sourceUserIdCol:
            return user.sourceUserId
        case OperationalDBViewModel.contactCol:
            return user.contactStatus
        case OperationalDBViewModel.aiCol:
            return user.aiSummary ?? ""
        default:
            return user.profileValue(id)
        }
    }
}
