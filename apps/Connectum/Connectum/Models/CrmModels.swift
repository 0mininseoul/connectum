import Foundation

struct Service: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let supabaseProjectRef: String?
    enum CodingKeys: String, CodingKey { case id, name, supabaseProjectRef = "supabase_project_ref" }
}

struct AmplitudeProfile: Codable, Hashable {
    let os: String?
    let platform: String?
    let deviceFamily: String?
    let deviceType: String?
    let country: String?
    let region: String?
    let city: String?
    let lastEventTime: String?
    enum CodingKeys: String, CodingKey {
        case os, platform, country, region, city
        case deviceFamily = "device_family", deviceType = "device_type", lastEventTime = "last_event_time"
    }
}

struct CrmUser: Codable, Identifiable, Hashable {
    let id: String
    let sourceUserId: String
    let email: String?
    let displayName: String?
    let contactStatus: String
    let amplitudeProfile: AmplitudeProfile?
    let aiSummary: String?
    let lastSyncedAt: String?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, email
        case sourceUserId = "source_user_id"
        case displayName = "display_name"
        case contactStatus = "contact_status"
        case amplitudeProfile = "amplitude_profile"
        case aiSummary = "ai_summary"
        case lastSyncedAt = "last_synced_at"
        case createdAt = "created_at"
    }
}

struct CrmUserEvent: Codable, Identifiable, Hashable {
    let id: Int64
    let eventType: String
    let eventTime: String
    let os: String?
    let browser: String?
    let platform: String?
    enum CodingKeys: String, CodingKey {
        case id, os, browser, platform
        case eventType = "event_type", eventTime = "event_time"
    }
}

struct ChannelRecord: Identifiable, Hashable {
    let id: String
    let channel: String
    let occurredAt: String?
    let body: String
}

// page_block row whose `content` jsonb holds a channel record.
struct PageBlockRow: Codable, Identifiable, Hashable {
    let id: String
    let content: Content
    struct Content: Codable, Hashable {
        let channel: String?
        let occurredAt: String?
        let body: String?
        enum CodingKeys: String, CodingKey { case channel, body, occurredAt = "occurred_at" }
    }
    var asChannelRecord: ChannelRecord {
        ChannelRecord(id: id, channel: content.channel ?? "memo", occurredAt: content.occurredAt, body: content.body ?? "")
    }
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: String
    let entryDate: String
    let imageUrl: String?
    let memo: String?
    enum CodingKeys: String, CodingKey { case id, memo, entryDate = "entry_date", imageUrl = "image_url" }
}

struct DashboardMetrics: Equatable {
    var total = 0
    var contacted = 0
    var profiled = 0
    var recentSignups = 0
    var contactRate: Double { total == 0 ? 0 : Double(contacted) / Double(total) }
}
