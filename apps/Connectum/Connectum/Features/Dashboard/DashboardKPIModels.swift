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

// Structured computation spec (mirrors the backend kpi_spec.ts).
struct KPIFilter: Codable, Equatable, Hashable {
    var field: String
    var op: String        // eq | neq | contains | not_null
    var value: String?
}

struct KPISpec: Codable, Equatable, Hashable {
    var kind: String      // count | ratio
    var filter: KPIFilter?
    var unit: String      // count | percent
}

// One-shot preview returned by kpi-preview (interpretation + spec + real value).
struct KPIPreview: Decodable, Equatable {
    let interpretation: String?
    let spec: KPISpec
    let value: Double
    let numerator: Int
    let denominator: Int
    let unit: String
    let valueText: String

    enum CodingKeys: String, CodingKey {
        case interpretation, spec, value, numerator, denominator, unit
        case valueText = "value_text"
    }
}

struct DashboardKPIDefinition: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var kind: DashboardKPIKind
    var prompt: String?
    var spec: KPISpec?
    var unit: String?
    var value: Double?
    var position: Double

    static func system(_ kind: DashboardKPIKind, position: Double) -> DashboardKPIDefinition {
        DashboardKPIDefinition(id: kind.rawValue, title: kind.defaultTitle, kind: kind,
                               prompt: nil, spec: nil, unit: nil, value: nil, position: position)
    }

    static var seededSystem: [DashboardKPIDefinition] {
        [.system(.totalUsers, position: 0), .system(.contactRate, position: 1), .system(.contacted, position: 2)]
    }
}

struct DashboardKPIChartPoint: Codable, Identifiable, Equatable, Hashable {
    var date: Date
    var value: Double
    var id: String { "\(date.timeIntervalSince1970):\(value)" }
}

enum DashboardChartBuilder {
    static func series(
        for kind: DashboardKPIKind,
        metrics: DashboardMetrics,
        users: [CrmUser],
        calendar: Calendar? = nil
    ) -> [DashboardKPIChartPoint] {
        cumulativeSeries(users: users, calendar: calendar) { dayUsers, total, contacted in
            switch kind {
            case .totalUsers: return Double(total)
            case .contactRate: return total == 0 ? 0 : Double(contacted) / Double(total) * 100
            case .contacted: return Double(contacted)
            case .custom: return 0
            }
        } fallback: { currentValue(for: kind, metrics: metrics) }
    }

    // Daily cumulative series for a custom spec, evaluated over the loaded users.
    static func customSeries(
        spec: KPISpec,
        users: [CrmUser],
        calendar: Calendar? = nil
    ) -> [DashboardKPIChartPoint] {
        cumulativeSeries(users: users, calendar: calendar) { _, total, matched in
            if spec.kind == "ratio" {
                return total == 0 ? 0 : Double(matched) / Double(total) * 100
            }
            return Double(matched)
        } matchCount: { dayUsers in
            dayUsers.filter { matches($0, spec.filter) }.count
        } fallback: { 0 }
    }

    static func matches(_ user: CrmUser, _ filter: KPIFilter?) -> Bool {
        guard let filter else { return true }
        let raw = fieldValue(user, filter.field)
        let target = filter.value ?? ""
        switch filter.op {
        case "eq": return (raw ?? "") == target
        case "neq": return (raw ?? "") != target
        case "contains": return (raw ?? "").localizedCaseInsensitiveContains(target)
        case "not_null": return raw != nil && !(raw ?? "").isEmpty
        default: return false
        }
    }

    private static func fieldValue(_ user: CrmUser, _ field: String) -> String? {
        switch field {
        case "contact_status": return user.contactStatus
        case "email": return user.email
        case "display_name": return user.displayName
        case "source_user_id": return user.sourceUserId
        default:
            if field.hasPrefix("profile.") {
                let key = String(field.dropFirst("profile.".count))
                let v = user.supabaseProfile?[key]?.display
                return (v?.isEmpty == false) ? v : nil
            }
            return nil
        }
    }

    static func currentValue(for kind: DashboardKPIKind, metrics: DashboardMetrics) -> Double {
        switch kind {
        case .totalUsers: return Double(metrics.total)
        case .contactRate: return metrics.contactRate * 100
        case .contacted: return Double(metrics.contacted)
        case .custom: return 0
        }
    }

    // Shared cumulative-by-day walker. `value` receives (day users, cumulative total,
    // cumulative contacted-or-matched); `matchCount` overrides the "contacted" tally.
    private static func cumulativeSeries(
        users: [CrmUser],
        calendar: Calendar?,
        value: ([CrmUser], Int, Int) -> Double,
        matchCount: (([CrmUser]) -> Int)? = nil,
        fallback: () -> Double
    ) -> [DashboardKPIChartPoint] {
        let calendar = calendar ?? utcCalendar
        let dated = users.compactMap { user -> (day: Date, user: CrmUser)? in
            guard let createdAt = user.createdAt, let date = parseISO8601(createdAt) else { return nil }
            return (calendar.startOfDay(for: date), user)
        }
        guard !dated.isEmpty else {
            return [DashboardKPIChartPoint(date: Date(), value: fallback())]
        }
        let grouped = Dictionary(grouping: dated, by: \.day)
        let days = grouped.keys.sorted()
        var total = 0
        var tally = 0
        return days.map { day in
            let dayUsers = grouped[day]?.map(\.user) ?? []
            total += dayUsers.count
            tally += matchCount?(dayUsers) ?? dayUsers.filter { $0.contactStatus == "contacted" }.count
            return DashboardKPIChartPoint(date: day, value: value(dayUsers, total, tally))
        }
    }

    static func matchingBuiltInKind(for prompt: String) -> DashboardKPIKind? {
        let normalized = prompt.lowercased()
        if normalized.contains("컨택률") || normalized.contains("contact rate") { return .contactRate }
        if normalized.contains("컨택 완료") || normalized.contains("contacted") { return .contacted }
        if normalized.contains("전체 유저") || normalized.contains("total user") { return .totalUsers }
        return nil
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
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
