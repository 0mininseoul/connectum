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

// A scalar value out of a jsonb row (supabase_profile). Nested objects/arrays
// collapse to .other so the model stays simple + Hashable for the Table.
enum JSONScalar: Codable, Hashable {
    case string(String), number(Double), bool(Bool), null, other
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .other }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .null, .other:  try c.encodeNil()
        }
    }
    var display: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b):   return b ? "예" : "아니오"
        case .null, .other:  return ""
        }
    }
}

struct CrmUser: Codable, Identifiable, Hashable {
    let id: String
    let sourceUserId: String
    let email: String?
    let displayName: String?
    let contactStatus: String
    let amplitudeProfile: AmplitudeProfile?
    let supabaseProfile: [String: JSONScalar]?
    let aiSummary: String?
    let lastSyncedAt: String?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, email
        case sourceUserId = "source_user_id"
        case displayName = "display_name"
        case contactStatus = "contact_status"
        case amplitudeProfile = "amplitude_profile"
        case supabaseProfile = "supabase_profile"
        case aiSummary = "ai_summary"
        case lastSyncedAt = "last_synced_at"
        case createdAt = "created_at"
    }
    // Display value of a source column (from supabase_profile) for the dynamic table.
    func profileValue(_ column: String) -> String {
        let v = supabaseProfile?[column]?.display ?? ""
        return v.isEmpty ? "—" : v
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

struct NoteBlock: Identifiable, Hashable {
    let id: String
    var type: String
    var text: String
}
struct NoteBlockRow: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let content: TextContent
    struct TextContent: Codable, Hashable { let text: String? }
    var asNote: NoteBlock { NoteBlock(id: id, type: type, text: content.text ?? "") }
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

struct ViewConfig: Codable, Hashable {
    var contactFilter: String = "all"   // all | contacted | not_contacted
    var profiledOnly: Bool = false
    var sortKey: String = "created_at"  // created_at | email | contact_status
    var sortAsc: Bool = false
}

struct SavedView: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let config: ViewConfig
}

struct ConnAccount: Codable, Identifiable, Hashable {
    let id: String
    let label: String
}

struct ProjectInfo: Codable, Identifiable, Hashable {
    let ref: String; let name: String; let region: String
    var id: String { ref }
}
struct TableInfo: Codable, Identifiable, Hashable {
    let schema: String; let table: String
    var id: String { "\(schema).\(table)" }
}
struct ColumnInfo: Codable, Identifiable, Hashable {
    let column: String; let type: String
    var id: String { column }
}

struct ServiceTableSpec: Hashable {
    let schema: String; let table: String; let role: String   // "user_table" | "related"
    var userIdCol: String = "id"; var emailCol: String = "email"
    var displayColumns: [String] = []   // columns to show in the operational-DB table
}
