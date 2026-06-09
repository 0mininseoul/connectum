import Foundation

enum DashboardKPIKind: String, Codable, Hashable {
    case totalUsers = "total_users"
    case contactRate = "contact_rate"
    case contacted
    case custom

    var defaultTitle: String {
        switch self {
        case .totalUsers: return "전체 유저"
        case .contactRate: return "컨택률"
        case .contacted: return "컨택 완료"
        case .custom: return "커스텀 KPI"
        }
    }
}

struct DashboardKPIConfirmation: Codable, Equatable, Hashable {
    let title: String
    let summary: String
    let calculationPlan: String
    let chartPlan: String
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case calculationPlan = "calculation_plan"
        case chartPlan = "chart_plan"
        case warnings
    }
}

struct DashboardKPIDefinition: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var kind: DashboardKPIKind
    var prompt: String?
    var confirmation: DashboardKPIConfirmation?
    var createdAt: Date

    static func system(_ kind: DashboardKPIKind) -> DashboardKPIDefinition {
        DashboardKPIDefinition(
            id: kind.rawValue,
            title: kind.defaultTitle,
            kind: kind,
            prompt: nil,
            confirmation: nil,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func custom(
        title: String,
        prompt: String,
        confirmation: DashboardKPIConfirmation
    ) -> DashboardKPIDefinition {
        DashboardKPIDefinition(
            id: "custom:\(UUID().uuidString)",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .custom,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            confirmation: confirmation,
            createdAt: Date()
        )
    }
}

struct DashboardKPIState: Codable, Equatable, Hashable {
    var items: [DashboardKPIDefinition]

    static var initial: DashboardKPIState {
        DashboardKPIState(items: [
            .system(.totalUsers),
            .system(.contactRate),
            .system(.contacted),
        ])
    }
}

struct DashboardKPIStore {
    private let defaults: UserDefaults
    private let keyPrefix = "dashboardKPIState"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(serviceId: String) -> DashboardKPIState {
        guard let data = defaults.data(forKey: key(serviceId: serviceId)),
              let state = try? JSONDecoder().decode(DashboardKPIState.self, from: data)
        else {
            return .initial
        }
        return state
    }

    func save(_ state: DashboardKPIState, serviceId: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key(serviceId: serviceId))
    }

    private func key(serviceId: String) -> String {
        "\(keyPrefix).\(serviceId)"
    }
}

struct DashboardKPIChartPoint: Codable, Identifiable, Equatable, Hashable {
    var date: Date
    var value: Double

    var id: String {
        "\(date.timeIntervalSince1970):\(value)"
    }
}

enum DashboardChartBuilder {
    static func series(
        for kind: DashboardKPIKind,
        metrics: DashboardMetrics,
        users: [CrmUser],
        calendar: Calendar? = nil
    ) -> [DashboardKPIChartPoint] {
        let calendar = calendar ?? utcCalendar
        let datedUsers = users.compactMap { user -> (day: Date, user: CrmUser)? in
            guard let createdAt = user.createdAt,
                  let date = parseISO8601(createdAt)
            else { return nil }
            return (calendar.startOfDay(for: date), user)
        }
        guard !datedUsers.isEmpty else {
            return [DashboardKPIChartPoint(date: Date(), value: currentValue(for: kind, metrics: metrics))]
        }

        let grouped = Dictionary(grouping: datedUsers, by: \.day)
        let days = grouped.keys.sorted()
        var cumulativeTotal = 0
        var cumulativeContacted = 0

        return days.map { day in
            let usersForDay = grouped[day]?.map(\.user) ?? []
            cumulativeTotal += usersForDay.count
            cumulativeContacted += usersForDay.filter { $0.contactStatus == "contacted" }.count

            let value: Double
            switch kind {
            case .totalUsers:
                value = Double(cumulativeTotal)
            case .contactRate:
                value = cumulativeTotal == 0 ? 0 : Double(cumulativeContacted) / Double(cumulativeTotal) * 100
            case .contacted:
                value = Double(cumulativeContacted)
            case .custom:
                value = 0
            }
            return DashboardKPIChartPoint(date: day, value: value)
        }
    }

    static func currentValue(for kind: DashboardKPIKind, metrics: DashboardMetrics) -> Double {
        switch kind {
        case .totalUsers:
            return Double(metrics.total)
        case .contactRate:
            return metrics.contactRate * 100
        case .contacted:
            return Double(metrics.contacted)
        case .custom:
            return 0
        }
    }

    static func matchingBuiltInKind(for prompt: String) -> DashboardKPIKind? {
        let normalized = prompt.lowercased()
        if normalized.contains("컨택률") || normalized.contains("contact rate") {
            return .contactRate
        }
        if normalized.contains("컨택 완료") || normalized.contains("contacted") {
            return .contacted
        }
        if normalized.contains("전체 유저") || normalized.contains("total user") || normalized.contains("total users") {
            return .totalUsers
        }
        return nil
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
