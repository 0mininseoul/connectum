import Foundation

struct LocalServiceTable: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var serviceId: String
    var sourceSchema: String
    var sourceTable: String
    var role: String
    var columnMap: [String: String]
    var cursorColumn: String
    var displayColumns: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case serviceId = "service_id"
        case sourceSchema = "source_schema"
        case sourceTable = "source_table"
        case role
        case columnMap = "column_map"
        case cursorColumn = "cursor_column"
        case displayColumns = "display_columns"
    }

    var asInfo: ServiceTableInfo {
        ServiceTableInfo(id: id, sourceSchema: sourceSchema, sourceTable: sourceTable, role: role)
    }
}

struct LocalCrmUserRow: Codable, Hashable, Sendable {
    var serviceId: String
    var user: CrmUser

    enum CodingKeys: String, CodingKey {
        case serviceId = "service_id"
        case user
    }
}

struct LocalCrmUserEventRow: Codable, Hashable, Sendable {
    var crmUserId: String
    var event: CrmUserEvent

    enum CodingKeys: String, CodingKey {
        case crmUserId = "crm_user_id"
        case event
    }
}

struct LocalMirroredRow: Codable, Hashable, Sendable {
    var serviceTableId: String
    var row: MirroredRow

    enum CodingKeys: String, CodingKey {
        case serviceTableId = "service_table_id"
        case row
    }
}

struct LocalChannelRecord: Codable, Hashable, Sendable {
    let id: String
    var crmUserId: String
    var channel: String
    var occurredAt: String?
    var body: String
    var position: Double

    enum CodingKeys: String, CodingKey {
        case id, channel, body, position
        case crmUserId = "crm_user_id"
        case occurredAt = "occurred_at"
    }

    var asRecord: ChannelRecord {
        ChannelRecord(id: id, channel: channel, occurredAt: occurredAt, body: body)
    }
}

struct LocalNoteBlock: Codable, Hashable, Sendable {
    let id: String
    var crmUserId: String
    var type: String
    var text: String
    var position: Double

    enum CodingKeys: String, CodingKey {
        case id, type, text, position
        case crmUserId = "crm_user_id"
    }

    var asNote: NoteBlock {
        NoteBlock(id: id, type: type, text: text)
    }
}

struct LocalHistoryRow: Codable, Hashable, Sendable {
    var crmUserId: String
    var entry: HistoryEntry

    enum CodingKeys: String, CodingKey {
        case crmUserId = "crm_user_id"
        case entry
    }
}

struct LocalKPI: Codable, Hashable, Sendable {
    var serviceId: String
    var definition: DashboardKPIDefinition

    enum CodingKeys: String, CodingKey {
        case serviceId = "service_id"
        case definition
    }
}

struct LocalServiceBriefRow: Codable, Sendable {
    var serviceId: String
    var brief: ServiceBrief

    enum CodingKeys: String, CodingKey {
        case serviceId = "service_id"
        case brief
    }
}

struct LocalChatMessage: Codable, Hashable, Sendable {
    var serviceId: String
    var role: String
    var content: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case serviceId = "service_id"
        case role
        case content
        case createdAt = "created_at"
    }
}

struct LocalClaudeOAuthConnection: Codable, Hashable, Sendable {
    var accountId: String
    var accessTokenKey: String
    var refreshTokenKey: String?
    var expiresAt: String
    var scope: String

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case accessTokenKey = "access_token_key"
        case refreshTokenKey = "refresh_token_key"
        case expiresAt = "expires_at"
        case scope
    }
}

struct LocalSupabaseOAuthConnection: Codable, Hashable, Sendable {
    var accountId: String
    var accessTokenKey: String
    var refreshTokenKey: String?
    var expiresAt: String
    var accountName: String?

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case accessTokenKey = "access_token_key"
        case refreshTokenKey = "refresh_token_key"
        case expiresAt = "expires_at"
        case accountName = "account_name"
    }
}

actor LocalConnectumStore {
    struct Snapshot: Codable, Sendable {
        var version: Int = 1
        var services: [Service] = []
        var supabaseAccounts: [ConnAccount] = []
        var amplitudeAccounts: [ConnAccount] = []
        var axiomAccounts: [ConnAccount] = []
        var serviceTables: [LocalServiceTable] = []
        var crmUsers: [LocalCrmUserRow] = []
        var events: [LocalCrmUserEventRow] = []
        var mirroredRows: [LocalMirroredRow] = []
        var channelRecords: [LocalChannelRecord] = []
        var notes: [LocalNoteBlock] = []
        var history: [LocalHistoryRow] = []
        var views: [SavedView] = []
        var kpis: [LocalKPI] = []
        var serviceBriefs: [LocalServiceBriefRow] = []
        var chatMessages: [LocalChatMessage] = []
        var aiAccount: AIAccount?
        var claudeOAuth: LocalClaudeOAuthConnection?
        var supabaseOAuth: [LocalSupabaseOAuthConnection]?
    }

    static let shared = LocalConnectumStore()

    let fileURL: URL

    init(fileURL: URL = LocalConnectumStore.defaultURL()) {
        self.fileURL = fileURL
    }

    static func defaultDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Connectum/Local", isDirectory: true)
    }

    static func defaultURL() -> URL {
        defaultDirectoryURL().appendingPathComponent("store.json", isDirectory: false)
    }

    func loadSnapshot() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Snapshot()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Snapshot.self, from: data)
    }

    func replaceSnapshot(_ snapshot: Snapshot) throws {
        try save(snapshot)
    }

    @discardableResult
    func mutate<T: Sendable>(_ body: @Sendable (inout Snapshot) throws -> T) throws -> T {
        var snapshot = try loadSnapshot()
        let result = try body(&snapshot)
        try save(snapshot)
        return result
    }

    private func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}
