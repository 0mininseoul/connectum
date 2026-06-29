import Foundation

struct Service: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let supabaseProjectRef: String?
    let supabaseProjectName: String?
    let supabaseAccountId: String?
    let amplitudeAccountId: String?
    let amplitudeProjectName: String?
    let axiomAccountId: String?
    let axiomDataset: String?

    init(
        id: String,
        name: String,
        supabaseProjectRef: String?,
        supabaseProjectName: String? = nil,
        supabaseAccountId: String? = nil,
        amplitudeAccountId: String? = nil,
        amplitudeProjectName: String? = nil,
        axiomAccountId: String? = nil,
        axiomDataset: String? = nil
    ) {
        self.id = id
        self.name = name
        self.supabaseProjectRef = supabaseProjectRef
        self.supabaseProjectName = supabaseProjectName
        self.supabaseAccountId = supabaseAccountId
        self.amplitudeAccountId = amplitudeAccountId
        self.amplitudeProjectName = amplitudeProjectName
        self.axiomAccountId = axiomAccountId
        self.axiomDataset = axiomDataset
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case supabaseProjectRef = "supabase_project_ref"
        case supabaseProjectName = "supabase_project_name"
        case supabaseAccountId = "supabase_account_id"
        case amplitudeAccountId = "amplitude_account_id"
        case amplitudeProjectName = "amplitude_project_name"
        case axiomAccountId = "axiom_account_id"
        case axiomDataset = "axiom_dataset"
    }

    var isDraft: Bool { id.hasPrefix("draft:") }
}

struct AmplitudeProfile: Codable, Hashable, Sendable {
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
enum JSONScalar: Codable, Hashable, Sendable {
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

struct CrmUser: Codable, Identifiable, Hashable, Sendable {
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

struct CrmUserEvent: Codable, Identifiable, Hashable, Sendable {
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

struct ChannelRecord: Identifiable, Hashable, Sendable {
    let id: String
    let channel: String
    let occurredAt: String?
    let body: String
}

// page_block row whose `content` jsonb holds a channel record.
struct PageBlockRow: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let content: Content
    struct Content: Codable, Hashable, Sendable {
        let channel: String?
        let occurredAt: String?
        let body: String?
        enum CodingKeys: String, CodingKey { case channel, body, occurredAt = "occurred_at" }
    }
    var asChannelRecord: ChannelRecord {
        ChannelRecord(id: id, channel: content.channel ?? "memo", occurredAt: content.occurredAt, body: content.body ?? "")
    }
}

struct NoteBlock: Identifiable, Hashable, Sendable {
    let id: String
    var type: String
    var text: String
}
struct NoteBlockRow: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    let content: TextContent
    struct TextContent: Codable, Hashable, Sendable { let text: String? }
    var asNote: NoteBlock { NoteBlock(id: id, type: type, text: content.text ?? "") }
}

struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let entryDate: String
    let imageUrl: String?
    let memo: String?
    enum CodingKeys: String, CodingKey { case id, memo, entryDate = "entry_date", imageUrl = "image_url" }
}

struct DashboardMetrics: Codable, Equatable, Sendable {
    var total = 0
    var contacted = 0
    var profiled = 0
    var recentSignups = 0
    var contactRate: Double { total == 0 ? 0 : Double(contacted) / Double(total) }
}

struct ViewConfig: Codable, Hashable, Sendable {
    var contactFilter: String   // all | contacted | not_contacted
    var profiledOnly: Bool
    var sortKey: String         // created_at | email | contact_status
    var sortAsc: Bool
    var primaryColumn: String
    // JSON-encoded SwiftUI TableColumnCustomization (column order + visibility) for this view.
    var customization: String

    init(contactFilter: String = "all", profiledOnly: Bool = false,
         sortKey: String = "created_at", sortAsc: Bool = false,
         primaryColumn: String = "__email", customization: String = "") {
        self.contactFilter = contactFilter; self.profiledOnly = profiledOnly
        self.sortKey = sortKey; self.sortAsc = sortAsc
        self.primaryColumn = primaryColumn; self.customization = customization
    }
    // Tolerant decode: older stored configs (and the wizard) omit newer keys.
    enum CodingKeys: String, CodingKey { case contactFilter, profiledOnly, sortKey, sortAsc, primaryColumn, customization }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contactFilter = try c.decodeIfPresent(String.self, forKey: .contactFilter) ?? "all"
        profiledOnly = try c.decodeIfPresent(Bool.self, forKey: .profiledOnly) ?? false
        sortKey = try c.decodeIfPresent(String.self, forKey: .sortKey) ?? "created_at"
        sortAsc = try c.decodeIfPresent(Bool.self, forKey: .sortAsc) ?? false
        primaryColumn = try c.decodeIfPresent(String.self, forKey: .primaryColumn) ?? "__email"
        customization = try c.decodeIfPresent(String.self, forKey: .customization) ?? ""
    }
}

struct SavedView: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let config: ViewConfig
}

struct ConnAccount: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let accountName: String?
    let projectName: String?
    let datasets: [String]?

    init(
        id: String,
        label: String,
        accountName: String? = nil,
        projectName: String? = nil,
        datasets: [String]? = nil
    ) {
        self.id = id
        self.label = label
        self.accountName = accountName
        self.projectName = projectName
        self.datasets = datasets
    }

    enum CodingKeys: String, CodingKey {
        case id, label
        case accountName = "account_name"
        case projectName = "project_name"
        case datasets
    }
}

struct ProjectInfo: Codable, Identifiable, Hashable, Sendable {
    let ref: String; let name: String; let region: String
    var id: String { ref }
}
struct TableInfo: Codable, Identifiable, Hashable, Sendable {
    let schema: String; let table: String
    var id: String { "\(schema).\(table)" }
}
struct ColumnInfo: Codable, Identifiable, Hashable, Sendable {
    let column: String; let type: String
    var id: String { column }
}

struct ServiceTableSpec: Hashable, Sendable {
    let schema: String; let table: String; let role: String   // "user_table" | "related"
    var userIdCol: String = "id"; var emailCol: String = "email"
    var displayColumns: [String] = []   // columns to show in the operational-DB table
}

// A row of `service_table` — which source tables this service imports.
struct ServiceTableInfo: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sourceSchema: String
    let sourceTable: String
    let role: String   // "user_table" | "related"

    enum CodingKeys: String, CodingKey {
        case id
        case sourceSchema = "source_schema"
        case sourceTable = "source_table"
        case role
    }

    var isUserTable: Bool { role == "user_table" }
    var displayName: String { sourceSchema == "public" ? sourceTable : "\(sourceSchema).\(sourceTable)" }
}

// A synced row from a `related` source table (stored as JSONB in `mirrored_row`).
struct MirroredRow: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sourcePk: String
    let data: [String: JSONScalar]

    enum CodingKeys: String, CodingKey {
        case id
        case sourcePk = "source_pk"
        case data
    }

    init(id: String, sourcePk: String, data: [String: JSONScalar]) {
        self.id = id
        self.sourcePk = sourcePk
        self.data = data
    }

    // Decode `data` defensively: a NULL/absent jsonb payload must not fail the
    // whole fetch (one bad row would blank the entire table).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sourcePk = try c.decode(String.self, forKey: .sourcePk)
        data = (try? c.decode([String: JSONScalar].self, forKey: .data)) ?? [:]
    }
}

// Latest distributable build advertised to the app for the update check.
struct AppRelease: Codable, Hashable, Sendable {
    let version: String
    let dmgUrl: String
    let notes: String?
    enum CodingKeys: String, CodingKey {
        case version, notes
        case dmgUrl = "dmg_url"
    }
}

// Workspace-global Claude (AI) account. Metadata only; tokens live in Vault.
struct AIAccount: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let accountName: String?
    enum CodingKeys: String, CodingKey {
        case id, label
        case accountName = "account_name"
    }
}

// One turn in the AI chat panel (session-memory only).
struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Role: Sendable { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var isStreaming: Bool = false
}
