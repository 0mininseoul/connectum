import Foundation

protocol SupabaseManagementAPIProviding: Sendable {
    func listProjects(token: String) async throws -> [ProjectInfo]
    func listTables(token: String, projectRef: String) async throws -> [TableInfo]
    func listColumns(token: String, projectRef: String, schema: String, table: String) async throws -> [ColumnInfo]
    func readRows(token: String, projectRef: String, schema: String, table: String, cursorColumn: String?, limit: Int) async throws -> [[String: JSONScalar]]
}

enum SupabaseManagementAPIError: LocalizedError {
    case invalidURL
    case httpStatus(Int, String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Supabase Management API URL이 올바르지 않습니다."
        case .httpStatus(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Supabase Management API HTTP \(status)" : "Supabase Management API HTTP \(status): \(trimmed)"
        case .unexpectedResponse:
            return "Supabase Management API 응답을 해석할 수 없습니다."
        }
    }
}

struct URLSessionSupabaseManagementAPI: SupabaseManagementAPIProviding {
    private let baseURL = URL(string: "https://api.supabase.com/v1")!

    func listProjects(token: String) async throws -> [ProjectInfo] {
        struct RawProject: Decodable {
            let id: String?
            let ref: String?
            let name: String?
            let region: String?
        }
        struct Wrapped: Decodable { let projects: [RawProject] }

        let data = try await request(token: token, path: "projects")
        let raw: [RawProject]
        if let list = try? JSONDecoder().decode([RawProject].self, from: data) {
            raw = list
        } else if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: data) {
            raw = wrapped.projects
        } else {
            throw SupabaseManagementAPIError.unexpectedResponse
        }
        return raw.compactMap { item in
            guard let ref = item.id ?? item.ref, let name = item.name else { return nil }
            return ProjectInfo(ref: ref, name: name, region: item.region ?? "")
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func listTables(token: String, projectRef: String) async throws -> [TableInfo] {
        let sql = """
        select table_schema, table_name
        from information_schema.tables
        where table_type = 'BASE TABLE'
          and table_schema not in ('pg_catalog','information_schema','auth','storage','vault','cron',
                                   'graphql','graphql_public','realtime','supabase_functions',
                                   'supabase_migrations','extensions','pgsodium','pgsodium_masks','net')
        order by table_schema, table_name
        """
        let rows = try await query(token: token, projectRef: projectRef, sql: sql)
        return rows.compactMap { row in
            guard let schema = row["table_schema"]?.display, let table = row["table_name"]?.display,
                  !schema.isEmpty, !table.isEmpty else { return nil }
            return TableInfo(schema: schema, table: table)
        }
    }

    func listColumns(token: String, projectRef: String, schema: String, table: String) async throws -> [ColumnInfo] {
        let sql = """
        select column_name, data_type
        from information_schema.columns
        where table_schema = \(Self.sqlLiteral(schema))
          and table_name = \(Self.sqlLiteral(table))
        order by ordinal_position
        """
        let rows = try await query(token: token, projectRef: projectRef, sql: sql)
        return rows.compactMap { row in
            guard let column = row["column_name"]?.display, let type = row["data_type"]?.display,
                  !column.isEmpty else { return nil }
            return ColumnInfo(column: column, type: type)
        }
    }

    func readRows(token: String, projectRef: String, schema: String, table: String, cursorColumn: String?, limit: Int) async throws -> [[String: JSONScalar]] {
        let cappedLimit = max(1, min(limit, 500))
        let orderClause: String
        if let cursorColumn, !cursorColumn.isEmpty {
            orderClause = " order by \(Self.sqlIdentifier(cursorColumn)) asc"
        } else {
            orderClause = ""
        }
        let sql = "select * from \(Self.sqlIdentifier(schema)).\(Self.sqlIdentifier(table))\(orderClause) limit \(cappedLimit)"
        return try await query(token: token, projectRef: projectRef, sql: sql)
    }

    private func query(token: String, projectRef: String, sql: String) async throws -> [[String: JSONScalar]] {
        struct Body: Encodable { let query: String }
        struct Wrapped: Decodable { let rows: [[String: JSONScalar]]? }

        let data = try await request(
            token: token,
            path: "projects/\(projectRef)/database/query/read-only",
            method: "POST",
            body: Body(query: sql)
        )
        if let rows = try? JSONDecoder().decode([[String: JSONScalar]].self, from: data) {
            return rows
        }
        if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: data), let rows = wrapped.rows {
            return rows
        }
        throw SupabaseManagementAPIError.unexpectedResponse
    }

    private func request(
        token: String,
        path: String,
        method: String = "GET"
    ) async throws -> Data {
        try await request(token: token, path: path, method: method, bodyData: nil)
    }

    private func request<Body: Encodable>(
        token: String,
        path: String,
        method: String = "GET",
        body: Body
    ) async throws -> Data {
        try await request(token: token, path: path, method: method, bodyData: try JSONEncoder().encode(body))
    }

    private func request(
        token: String,
        path: String,
        method: String,
        bodyData: Data?
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL.absoluteString)/\(path)") else {
            throw SupabaseManagementAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseManagementAPIError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseManagementAPIError.httpStatus(
                http.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    private static func sqlIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

struct SupabaseOAuthTokens: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: String
    let accountName: String?
}

protocol SupabaseOAuthAPIProviding: Sendable {
    func authorizeURL(state: String) async throws -> URL
    func exchangeCode(code: String, state: String) async throws -> SupabaseOAuthTokens
    func refresh(refreshToken: String) async throws -> SupabaseOAuthTokens
}

struct URLSessionSupabaseOAuthAPI: SupabaseOAuthAPIProviding {
    private struct AuthorizeRequest: Encodable {
        let state: String
    }

    private struct AuthorizeResponse: Decodable {
        let authorizeURL: String

        enum CodingKeys: String, CodingKey {
            case authorizeURL = "authorize_url"
        }
    }

    private struct ExchangeRequest: Encodable {
        let code: String
        let state: String
        let label: String
        let storage: String
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: String
        let accountName: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case accountName = "account_name"
        }
    }

    private struct RefreshRequest: Encodable {
        let refresh_token: String
        let storage: String
    }

    func authorizeURL(state: String) async throws -> URL {
        let response: AuthorizeResponse = try await invoke("oauth-supabase-start", body: AuthorizeRequest(state: state))
        guard let url = URL(string: response.authorizeURL) else {
            throw CrmRepositoryError.functionMessage("Supabase OAuth 승인 URL이 올바르지 않습니다.")
        }
        return url
    }

    func exchangeCode(code: String, state: String) async throws -> SupabaseOAuthTokens {
        let response: TokenResponse = try await invoke(
            "oauth-supabase",
            body: ExchangeRequest(code: code, state: state, label: "Supabase", storage: "local_keychain")
        )
        return SupabaseOAuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresAt,
            accountName: response.accountName
        )
    }

    func refresh(refreshToken: String) async throws -> SupabaseOAuthTokens {
        let response: TokenResponse = try await invoke(
            "oauth-supabase",
            body: RefreshRequest(refresh_token: refreshToken, storage: "local_keychain")
        )
        return SupabaseOAuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresAt,
            accountName: response.accountName
        )
    }

    private func invoke<Response: Decodable, Body: Encodable>(_ functionName: String, body: Body) async throws -> Response {
        let config = SupabaseClientProvider.supabaseOAuthBrokerConfig()
        let url = config.functionsBaseURL.appendingPathComponent(functionName)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.anonKey.isEmpty {
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CrmRepositoryError.functionMessage("Supabase OAuth broker 응답을 읽을 수 없습니다.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw CrmRepositoryError.functionMessage(Self.errorMessage(statusCode: http.statusCode, data: data))
            }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as CrmRepositoryError {
            throw error
        } catch {
            throw CrmRepositoryError.functionMessage("Supabase OAuth broker 연결 실패: \(error.localizedDescription)")
        }
    }

    private static func errorMessage(statusCode: Int, data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.localizedCaseInsensitiveContains("client is not configured")
            || text.localizedCaseInsensitiveContains("client_id")
            || text.localizedCaseInsensitiveContains("client_secret") {
            return "Supabase OAuth broker 설정이 필요합니다. Connectum OAuth 서버에 client_id/client_secret을 설정해야 합니다."
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Supabase OAuth broker HTTP \(statusCode)" : "Supabase OAuth broker HTTP \(statusCode): \(trimmed)"
    }
}

struct ClaudeOAuthTokens: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: String
}

protocol ClaudeOAuthAPIProviding: Sendable {
    func exchangeCode(code: String, state: String?, codeVerifier: String, redirectURI: String, clientId: String) async throws -> ClaudeOAuthTokens
    func refresh(refreshToken: String, clientId: String) async throws -> ClaudeOAuthTokens
}

struct URLSessionClaudeOAuthAPI: ClaudeOAuthAPIProviding {
    private struct TokenRequest: Encodable {
        let grant_type: String
        let code: String?
        let redirect_uri: String?
        let client_id: String
        let code_verifier: String?
        let refresh_token: String?
        let state: String?
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    func exchangeCode(code: String, state: String?, codeVerifier: String, redirectURI: String, clientId: String) async throws -> ClaudeOAuthTokens {
        try await request(TokenRequest(
            grant_type: "authorization_code",
            code: code,
            redirect_uri: redirectURI,
            client_id: clientId,
            code_verifier: codeVerifier,
            refresh_token: nil,
            state: state
        ))
    }

    func refresh(refreshToken: String, clientId: String) async throws -> ClaudeOAuthTokens {
        try await request(TokenRequest(
            grant_type: "refresh_token",
            code: nil,
            redirect_uri: nil,
            client_id: clientId,
            code_verifier: nil,
            refresh_token: refreshToken,
            state: nil
        ))
    }

    private func request(_ body: TokenRequest) async throws -> ClaudeOAuthTokens {
        let config = SupabaseClientProvider.claudeConfig()
        guard let url = URL(string: config.tokenURL) else {
            throw CrmRepositoryError.functionMessage("Claude OAuth token URL이 올바르지 않습니다.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CrmRepositoryError.functionMessage("Claude OAuth 응답을 읽을 수 없습니다.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw CrmRepositoryError.functionMessage("Claude OAuth HTTP \(http.statusCode): \(message)")
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return ClaudeOAuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: Self.expiresAt(secondsFromNow: decoded.expiresIn ?? 3600)
        )
    }

    private static func expiresAt(secondsFromNow seconds: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(seconds)))
    }
}

struct LocalCrmRepository: CrmDataProviding {
    private let store: LocalConnectumStore
    private let secrets: SecretStoring
    private let supabaseAPI: SupabaseManagementAPIProviding
    private let supabaseOAuthAPI: SupabaseOAuthAPIProviding
    private let claudeOAuthAPI: ClaudeOAuthAPIProviding

    init(
        store: LocalConnectumStore = .shared,
        secrets: SecretStoring = KeychainSecretStore(),
        supabaseAPI: SupabaseManagementAPIProviding = URLSessionSupabaseManagementAPI(),
        supabaseOAuthAPI: SupabaseOAuthAPIProviding = URLSessionSupabaseOAuthAPI(),
        claudeOAuthAPI: ClaudeOAuthAPIProviding = URLSessionClaudeOAuthAPI()
    ) {
        self.store = store
        self.secrets = secrets
        self.supabaseAPI = supabaseAPI
        self.supabaseOAuthAPI = supabaseOAuthAPI
        self.claudeOAuthAPI = claudeOAuthAPI
    }

    func fetchServices() async throws -> [Service] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.services.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func syncService(serviceId: String) async throws {
        let snapshot = try await store.loadSnapshot()
        guard let service = snapshot.services.first(where: { $0.id == serviceId }),
              let supabaseAccountId = service.supabaseAccountId,
              let projectRef = service.supabaseProjectRef else {
            throw CrmRepositoryError.functionMessage("동기화할 Supabase 원본 설정이 없습니다.")
        }
        let token = try await supabaseToken(accountId: supabaseAccountId)
        let tables = snapshot.serviceTables.filter { $0.serviceId == serviceId }
        let now = Self.isoNow()

        for table in tables {
            let rows = try await supabaseAPI.readRows(
                token: token,
                projectRef: projectRef,
                schema: table.sourceSchema,
                table: table.sourceTable,
                cursorColumn: table.cursorColumn,
                limit: 500
            )
            if table.role == "user_table" {
                let resolvedTable = try await userTableForSync(serviceId: serviceId, table: table, rows: rows)
                try await upsertUsers(serviceId: serviceId, table: resolvedTable, rows: rows, syncedAt: now)
            } else {
                try await upsertMirroredRows(serviceTableId: table.id, table: table, rows: rows)
            }
        }
    }

    func deleteService(serviceId: String) async throws {
        try await store.mutate { snapshot in
            snapshot.services.removeAll { $0.id == serviceId }
            let tableIds = Set(snapshot.serviceTables.filter { $0.serviceId == serviceId }.map(\.id))
            let userIds = Set(snapshot.crmUsers.filter { $0.serviceId == serviceId }.map(\.user.id))
            snapshot.serviceTables.removeAll { $0.serviceId == serviceId }
            snapshot.crmUsers.removeAll { $0.serviceId == serviceId }
            snapshot.events.removeAll { userIds.contains($0.crmUserId) }
            snapshot.mirroredRows.removeAll { tableIds.contains($0.serviceTableId) }
            snapshot.channelRecords.removeAll { userIds.contains($0.crmUserId) }
            snapshot.notes.removeAll { userIds.contains($0.crmUserId) }
            snapshot.history.removeAll { userIds.contains($0.crmUserId) }
            snapshot.kpis.removeAll { $0.serviceId == serviceId }
            snapshot.serviceBriefs.removeAll { $0.serviceId == serviceId }
            snapshot.chatMessages.removeAll { $0.serviceId == serviceId }
        }
    }

    func fetchUsers(serviceId: String) async throws -> [CrmUser] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.crmUsers
            .filter { $0.serviceId == serviceId && $0.user.contactStatus != "excluded" }
            .map(\.user)
            .sorted { lhs, rhs in
                (lhs.createdAt ?? "") > (rhs.createdAt ?? "")
            }
    }

    func excludeUser(crmUserId: String, reason: String? = nil) async throws {
        try await setContactStatus(crmUserId: crmUserId, status: "excluded")
    }

    func fetchEvents(crmUserId: String, limit: Int = 50) async throws -> [CrmUserEvent] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.events
            .filter { $0.crmUserId == crmUserId }
            .map(\.event)
            .sorted { $0.eventTime > $1.eventTime }
            .prefix(limit)
            .map { $0 }
    }

    func setContactStatus(crmUserId: String, status: String) async throws {
        try await store.mutate { snapshot in
            guard let index = snapshot.crmUsers.firstIndex(where: { $0.user.id == crmUserId }) else { return }
            let old = snapshot.crmUsers[index].user
            snapshot.crmUsers[index].user = CrmUser(
                id: old.id,
                sourceUserId: old.sourceUserId,
                email: old.email,
                displayName: old.displayName,
                contactStatus: status,
                amplitudeProfile: old.amplitudeProfile,
                supabaseProfile: old.supabaseProfile,
                aiSummary: old.aiSummary,
                lastSyncedAt: old.lastSyncedAt,
                createdAt: old.createdAt
            )
        }
    }

    func regenerateSummary(crmUserId: String) async throws -> String {
        let snapshot = try await store.loadSnapshot()
        let user = snapshot.crmUsers.first { $0.user.id == crmUserId }?.user
        if let summary = user?.aiSummary, !summary.isEmpty { return summary }
        throw CrmRepositoryError.functionMessage(Self.aiUnsupportedMessage)
    }

    func fetchChannelRecords(crmUserId: String) async throws -> [ChannelRecord] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.channelRecords
            .filter { $0.crmUserId == crmUserId }
            .sorted { $0.position > $1.position }
            .map(\.asRecord)
    }

    func addChannelRecord(crmUserId: String, channel: String, occurredAt: String, body: String) async throws {
        try await store.mutate { snapshot in
            snapshot.channelRecords.append(LocalChannelRecord(
                id: UUID().uuidString,
                crmUserId: crmUserId,
                channel: channel,
                occurredAt: occurredAt.isEmpty ? nil : occurredAt,
                body: body,
                position: Date().timeIntervalSince1970
            ))
        }
    }

    func fetchNoteBlocks(crmUserId: String) async throws -> [NoteBlock] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.notes
            .filter { $0.crmUserId == crmUserId }
            .sorted { $0.position < $1.position }
            .map(\.asNote)
    }

    func addNoteBlock(crmUserId: String, text: String) async throws {
        try await store.mutate { snapshot in
            snapshot.notes.append(LocalNoteBlock(
                id: UUID().uuidString,
                crmUserId: crmUserId,
                type: "text",
                text: text,
                position: Date().timeIntervalSince1970
            ))
        }
    }

    func updateNoteBlock(id: String, text: String) async throws {
        try await store.mutate { snapshot in
            guard let index = snapshot.notes.firstIndex(where: { $0.id == id }) else { return }
            snapshot.notes[index].text = text
        }
    }

    func deleteNoteBlock(id: String) async throws {
        try await store.mutate { snapshot in
            snapshot.notes.removeAll { $0.id == id }
        }
    }

    func fetchHistory(crmUserId: String) async throws -> [HistoryEntry] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.history
            .filter { $0.crmUserId == crmUserId }
            .map(\.entry)
            .sorted { $0.entryDate > $1.entryDate }
    }

    func addHistory(crmUserId: String, entryDate: String, memo: String, imageData: Data?, fileExt: String) async throws {
        try await store.mutate { snapshot in
            snapshot.history.append(LocalHistoryRow(
                crmUserId: crmUserId,
                entry: HistoryEntry(
                    id: UUID().uuidString,
                    entryDate: entryDate,
                    imageUrl: nil,
                    memo: memo
                )
            ))
        }
    }

    func fetchMetrics(serviceId: String) async throws -> DashboardMetrics {
        let users = try await fetchUsers(serviceId: serviceId)
        let total = users.count
        let contacted = users.filter { $0.contactStatus == "contacted" }.count
        let profiled = users.filter { ($0.supabaseProfile?.isEmpty == false) || $0.amplitudeProfile != nil }.count
        let recent = users.filter { user in
            guard let createdAt = user.createdAt, let date = Self.parseISO8601(createdAt) else { return false }
            return date >= Date().addingTimeInterval(-7 * 24 * 3600)
        }.count
        return DashboardMetrics(total: total, contacted: contacted, profiled: profiled, recentSignups: recent)
    }

    func previewKPI(serviceId: String, title: String, prompt: String) async throws -> KPIPreview {
        let users = try await fetchUsers(serviceId: serviceId)
        let metrics = try await fetchMetrics(serviceId: serviceId)
        let kind = DashboardChartBuilder.matchingBuiltInKind(for: "\(title) \(prompt)")
        let spec: KPISpec
        let numerator: Int
        let denominator: Int
        let value: Double
        let unit: String

        switch kind {
        case .contactRate:
            numerator = metrics.contacted
            denominator = max(metrics.total, 1)
            value = denominator == 0 ? 0 : Double(numerator) / Double(denominator) * 100
            unit = "percent"
            spec = KPISpec(kind: "ratio", filter: KPIFilter(field: "contact_status", op: "eq", value: "contacted"), unit: unit)
        case .contacted:
            numerator = metrics.contacted
            denominator = metrics.total
            value = Double(numerator)
            unit = "count"
            spec = KPISpec(kind: "count", filter: KPIFilter(field: "contact_status", op: "eq", value: "contacted"), unit: unit)
        case .totalUsers, .custom, .none:
            numerator = users.count
            denominator = users.count
            value = Double(users.count)
            unit = "count"
            spec = KPISpec(kind: "count", filter: nil, unit: unit)
        }

        return KPIPreview(
            interpretation: "로컬 데이터에서 계산 가능한 기본 KPI로 해석했습니다.",
            spec: spec,
            value: value,
            numerator: numerator,
            denominator: denominator,
            unit: unit,
            valueText: unit == "percent" ? String(format: "%.1f%%", value) : "\(Int(value.rounded()))"
        )
    }

    func recomputeKPI(serviceId: String, spec: KPISpec) async throws -> Double {
        let users = try await fetchUsers(serviceId: serviceId)
        let matched = users.filter { DashboardChartBuilder.matches($0, spec.filter) }.count
        if spec.kind == "ratio" {
            return users.isEmpty ? 0 : Double(matched) / Double(users.count) * 100
        }
        return Double(matched)
    }

    func fetchKPIs(serviceId: String) async throws -> [DashboardKPIDefinition] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.kpis
            .filter { $0.serviceId == serviceId }
            .map(\.definition)
            .sorted { $0.position < $1.position }
    }

    func seedSystemKPIs(serviceId: String) async throws {
        try await store.mutate { snapshot in
            let existingKinds = Set(snapshot.kpis.filter { $0.serviceId == serviceId }.map(\.definition.kind))
            for seed in DashboardKPIDefinition.seededSystem where !existingKinds.contains(seed.kind) {
                let definition = DashboardKPIDefinition(
                    id: "\(serviceId):\(seed.kind.rawValue)",
                    title: seed.title,
                    kind: seed.kind,
                    prompt: seed.prompt,
                    spec: seed.spec,
                    unit: seed.unit,
                    value: seed.value,
                    position: seed.position
                )
                snapshot.kpis.append(LocalKPI(serviceId: serviceId, definition: definition))
            }
        }
    }

    func insertKPI(serviceId: String, title: String, prompt: String, spec: KPISpec, unit: String, value: Double, position: Double) async throws {
        try await store.mutate { snapshot in
            snapshot.kpis.append(LocalKPI(
                serviceId: serviceId,
                definition: DashboardKPIDefinition(
                    id: UUID().uuidString,
                    title: title,
                    kind: .custom,
                    prompt: prompt,
                    spec: spec,
                    unit: unit,
                    value: value,
                    position: position
                )
            ))
        }
    }

    func deleteKPIRow(id: String) async throws {
        try await store.mutate { snapshot in
            snapshot.kpis.removeAll { $0.definition.id == id }
        }
    }

    func renameKPIRow(id: String, title: String) async throws {
        try await store.mutate { snapshot in
            guard let index = snapshot.kpis.firstIndex(where: { $0.definition.id == id }) else { return }
            snapshot.kpis[index].definition.title = title
        }
    }

    func updateKPIValue(id: String, value: Double) async throws {
        try await store.mutate { snapshot in
            guard let index = snapshot.kpis.firstIndex(where: { $0.definition.id == id }) else { return }
            snapshot.kpis[index].definition.value = value
        }
    }

    func updateKPIPosition(id: String, position: Double) async throws {
        try await store.mutate { snapshot in
            guard let index = snapshot.kpis.firstIndex(where: { $0.definition.id == id }) else { return }
            snapshot.kpis[index].definition.position = position
        }
    }

    func fetchViews() async throws -> [SavedView] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.views
    }

    func createView(name: String, config: ViewConfig) async throws {
        try await store.mutate { snapshot in
            snapshot.views.append(SavedView(id: UUID().uuidString, name: name, config: config))
        }
    }

    func fetchSupabaseAccounts() async throws -> [ConnAccount] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.supabaseAccounts
    }

    func fetchAmplitudeAccounts() async throws -> [ConnAccount] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.amplitudeAccounts
    }

    func fetchAxiomAccounts() async throws -> [ConnAccount] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.axiomAccounts
    }

    func supabaseOAuthAuthorizeURL(state: String) async throws -> URL {
        try await supabaseOAuthAPI.authorizeURL(state: state)
    }

    func connectSupabaseOAuth(code: String, state: String) async throws {
        let tokens = try await supabaseOAuthAPI.exchangeCode(code: code, state: state)
        _ = try await supabaseAPI.listProjects(token: tokens.accessToken)
        let account = ConnAccount(
            id: UUID().uuidString,
            label: tokens.accountName ?? "Supabase",
            accountName: tokens.accountName
        )
        let accessKey = Self.supabaseOAuthAccessTokenKey(account.id)
        let refreshKey = tokens.refreshToken.map { _ in Self.supabaseOAuthRefreshTokenKey(account.id) }
        try secrets.save(tokens.accessToken, for: accessKey)
        if let refreshToken = tokens.refreshToken, let refreshKey {
            try secrets.save(refreshToken, for: refreshKey)
        }
        try await store.mutate { snapshot in
            snapshot.supabaseAccounts.append(account)
            var connections = snapshot.supabaseOAuth ?? []
            connections.removeAll { $0.accountId == account.id }
            connections.append(LocalSupabaseOAuthConnection(
                accountId: account.id,
                accessTokenKey: accessKey,
                refreshTokenKey: refreshKey,
                expiresAt: tokens.expiresAt,
                accountName: account.accountName
            ))
            snapshot.supabaseOAuth = connections
        }
    }

    func connectSupabasePAT(pat: String, label: String) async throws {
        let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CrmRepositoryError.functionMessage("Supabase Personal Access Token을 입력하세요.")
        }
        _ = try await supabaseAPI.listProjects(token: trimmed)
        let account = ConnAccount(
            id: UUID().uuidString,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Supabase" : label,
            accountName: nil
        )
        try secrets.save(trimmed, for: Self.supabaseSecretKey(account.id))
        try await store.mutate { snapshot in
            snapshot.supabaseAccounts.append(account)
        }
    }

    func connectAmplitude(projectName: String, apiKey: String, secretKey: String, region: String) async throws {
        let account = ConnAccount(id: UUID().uuidString, label: projectName.isEmpty ? "Amplitude" : projectName, projectName: projectName)
        try secrets.save(apiKey, for: Self.amplitudeAPIKey(account.id))
        try secrets.save(secretKey, for: Self.amplitudeSecretKey(account.id))
        try await store.mutate { snapshot in
            snapshot.amplitudeAccounts.append(account)
        }
    }

    func connectAxiom(token: String) async throws -> [String] {
        let account = ConnAccount(id: UUID().uuidString, label: "Axiom", datasets: [])
        try secrets.save(token, for: Self.axiomSecretKey(account.id))
        try await store.mutate { snapshot in
            snapshot.axiomAccounts.append(account)
        }
        return []
    }

    func deleteSupabaseAccount(id: String) async throws {
        try secrets.delete(Self.supabaseSecretKey(id))
        let snapshot = try await store.loadSnapshot()
        if let connection = snapshot.supabaseOAuth?.first(where: { $0.accountId == id }) {
            try secrets.delete(connection.accessTokenKey)
            if let refreshTokenKey = connection.refreshTokenKey {
                try secrets.delete(refreshTokenKey)
            }
        }
        try await store.mutate { snapshot in
            snapshot.supabaseAccounts.removeAll { $0.id == id }
            snapshot.supabaseOAuth = snapshot.supabaseOAuth?.filter { $0.accountId != id }
            snapshot.services = snapshot.services.map { service in
                guard service.supabaseAccountId == id else { return service }
                return Service(
                    id: service.id,
                    name: service.name,
                    supabaseProjectRef: service.supabaseProjectRef,
                    supabaseProjectName: service.supabaseProjectName,
                    supabaseAccountId: nil,
                    amplitudeAccountId: service.amplitudeAccountId,
                    amplitudeProjectName: service.amplitudeProjectName,
                    axiomAccountId: service.axiomAccountId,
                    axiomDataset: service.axiomDataset
                )
            }
        }
    }

    func deleteAmplitudeAccount(id: String) async throws {
        try secrets.delete(Self.amplitudeAPIKey(id))
        try secrets.delete(Self.amplitudeSecretKey(id))
        try await store.mutate { snapshot in
            snapshot.amplitudeAccounts.removeAll { $0.id == id }
            snapshot.services = snapshot.services.map { service in
                guard service.amplitudeAccountId == id else { return service }
                return Service(
                    id: service.id,
                    name: service.name,
                    supabaseProjectRef: service.supabaseProjectRef,
                    supabaseProjectName: service.supabaseProjectName,
                    supabaseAccountId: service.supabaseAccountId,
                    amplitudeAccountId: nil,
                    amplitudeProjectName: nil,
                    axiomAccountId: service.axiomAccountId,
                    axiomDataset: service.axiomDataset
                )
            }
        }
    }

    func deleteAxiomAccount(id: String) async throws {
        try secrets.delete(Self.axiomSecretKey(id))
        try await store.mutate { snapshot in
            snapshot.axiomAccounts.removeAll { $0.id == id }
            snapshot.services = snapshot.services.map { service in
                guard service.axiomAccountId == id else { return service }
                return Service(
                    id: service.id,
                    name: service.name,
                    supabaseProjectRef: service.supabaseProjectRef,
                    supabaseProjectName: service.supabaseProjectName,
                    supabaseAccountId: service.supabaseAccountId,
                    amplitudeAccountId: service.amplitudeAccountId,
                    amplitudeProjectName: service.amplitudeProjectName,
                    axiomAccountId: nil,
                    axiomDataset: nil
                )
            }
        }
    }

    func updateServiceSupabaseAccount(serviceId: String, accountId: String) async throws {
        try await updateService(serviceId: serviceId) { service in
            Service(
                id: service.id,
                name: service.name,
                supabaseProjectRef: service.supabaseProjectRef,
                supabaseProjectName: service.supabaseProjectName,
                supabaseAccountId: accountId,
                amplitudeAccountId: service.amplitudeAccountId,
                amplitudeProjectName: service.amplitudeProjectName,
                axiomAccountId: service.axiomAccountId,
                axiomDataset: service.axiomDataset
            )
        }
    }

    func updateServiceAmplitudeAccount(serviceId: String, accountId: String) async throws {
        let snapshot = try await store.loadSnapshot()
        let account = snapshot.amplitudeAccounts.first { $0.id == accountId }
        try await updateService(serviceId: serviceId) { service in
            Service(
                id: service.id,
                name: service.name,
                supabaseProjectRef: service.supabaseProjectRef,
                supabaseProjectName: service.supabaseProjectName,
                supabaseAccountId: service.supabaseAccountId,
                amplitudeAccountId: accountId,
                amplitudeProjectName: account?.projectName,
                axiomAccountId: service.axiomAccountId,
                axiomDataset: service.axiomDataset
            )
        }
    }

    func updateServiceAxiomAccount(serviceId: String, accountId: String, dataset: String?) async throws {
        try await updateService(serviceId: serviceId) { service in
            Service(
                id: service.id,
                name: service.name,
                supabaseProjectRef: service.supabaseProjectRef,
                supabaseProjectName: service.supabaseProjectName,
                supabaseAccountId: service.supabaseAccountId,
                amplitudeAccountId: service.amplitudeAccountId,
                amplitudeProjectName: service.amplitudeProjectName,
                axiomAccountId: accountId,
                axiomDataset: dataset
            )
        }
    }

    func fetchSupabaseAccountProfile(id: String) async throws -> String? {
        let snapshot = try await store.loadSnapshot()
        return snapshot.supabaseAccounts.first { $0.id == id }?.accountName
    }

    func listAxiomDatasets(accountId: String) async throws -> [String] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.axiomAccounts.first { $0.id == accountId }?.datasets ?? []
    }

    func listProjects(supabaseAccountId: String) async throws -> [ProjectInfo] {
        try await supabaseAPI.listProjects(token: try await supabaseToken(accountId: supabaseAccountId))
    }

    func listTables(supabaseAccountId: String, projectRef: String) async throws -> [TableInfo] {
        try await supabaseAPI.listTables(token: try await supabaseToken(accountId: supabaseAccountId), projectRef: projectRef)
    }

    @discardableResult
    func createService(name: String, supabaseAccountId: String, projectRef: String, projectName: String?, tables: [ServiceTableSpec], amplitudeAccountId: String?, amplitudeProjectName: String?, axiomAccountId: String?, axiomDataset: String?) async throws -> String {
        let serviceId = UUID().uuidString
        let service = Service(
            id: serviceId,
            name: name,
            supabaseProjectRef: projectRef,
            supabaseProjectName: projectName,
            supabaseAccountId: supabaseAccountId,
            amplitudeAccountId: amplitudeAccountId,
            amplitudeProjectName: amplitudeProjectName,
            axiomAccountId: axiomAccountId,
            axiomDataset: axiomDataset
        )
        let serviceTables = tables.map { spec in
            LocalServiceTable(
                id: UUID().uuidString,
                serviceId: serviceId,
                sourceSchema: spec.schema,
                sourceTable: spec.table,
                role: spec.role,
                columnMap: spec.role == "user_table"
                    ? ["user_id": spec.userIdCol, "email": spec.emailCol]
                    : ["pk": "id"],
                cursorColumn: "created_at",
                displayColumns: spec.role == "user_table" ? spec.displayColumns : []
            )
        }
        try await store.mutate { snapshot in
            snapshot.services.append(service)
            snapshot.serviceTables.append(contentsOf: serviceTables)
        }
        return serviceId
    }

    func listColumns(supabaseAccountId: String, projectRef: String, schema: String, table: String) async throws -> [ColumnInfo] {
        try await supabaseAPI.listColumns(token: try await supabaseToken(accountId: supabaseAccountId), projectRef: projectRef, schema: schema, table: table)
    }

    func fetchDisplayColumns(serviceId: String) async throws -> [String] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.serviceTables.first { $0.serviceId == serviceId && $0.role == "user_table" }?.displayColumns ?? []
    }

    func updateDisplayColumns(serviceId: String, columns: [String]) async throws {
        try await store.mutate { snapshot in
            guard let index = snapshot.serviceTables.firstIndex(where: { $0.serviceId == serviceId && $0.role == "user_table" }) else { return }
            snapshot.serviceTables[index].displayColumns = columns
        }
    }

    func fetchServiceTables(serviceId: String) async throws -> [ServiceTableInfo] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.serviceTables
            .filter { $0.serviceId == serviceId }
            .sorted { lhs, rhs in
                if lhs.role != rhs.role { return lhs.role == "user_table" }
                return lhs.sourceTable < rhs.sourceTable
            }
            .map(\.asInfo)
    }

    func addRelatedTable(serviceId: String, schema: String, table: String) async throws {
        try await store.mutate { snapshot in
            snapshot.serviceTables.append(LocalServiceTable(
                id: UUID().uuidString,
                serviceId: serviceId,
                sourceSchema: schema,
                sourceTable: table,
                role: "related",
                columnMap: ["pk": "id"],
                cursorColumn: "created_at",
                displayColumns: []
            ))
        }
    }

    func removeServiceTable(id: String) async throws {
        try await store.mutate { snapshot in
            snapshot.serviceTables.removeAll { $0.id == id }
            snapshot.mirroredRows.removeAll { $0.serviceTableId == id }
        }
    }

    func fetchMirroredRows(serviceTableId: String, limit: Int = 500) async throws -> [MirroredRow] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.mirroredRows
            .filter { $0.serviceTableId == serviceTableId }
            .map(\.row)
            .prefix(limit)
            .map { $0 }
    }

    func fetchAIAccount() async throws -> AIAccount? {
        let snapshot = try await store.loadSnapshot()
        if let account = snapshot.aiAccount {
            return account
        }
        if let connection = snapshot.claudeOAuth {
            return AIAccount(id: connection.accountId, label: "Claude", accountName: nil)
        }
        return nil
    }

    func connectClaude(code: String, state: String?, codeVerifier: String, redirectURI: String) async throws {
        let config = SupabaseClientProvider.claudeConfig()
        guard !config.clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CrmRepositoryError.functionMessage("Claude OAuth client_id가 설정되지 않았습니다.")
        }
        let tokens = try await claudeOAuthAPI.exchangeCode(
            code: code,
            state: state,
            codeVerifier: codeVerifier,
            redirectURI: redirectURI,
            clientId: config.clientId
        )
        let snapshot = try await store.loadSnapshot()
        if let old = snapshot.claudeOAuth {
            try? secrets.delete(old.accessTokenKey)
            if let refreshTokenKey = old.refreshTokenKey {
                try? secrets.delete(refreshTokenKey)
            }
        }

        let accountId = UUID().uuidString
        let accessTokenKey = Self.claudeAccessTokenKey(accountId)
        let refreshTokenKey = tokens.refreshToken.map { _ in Self.claudeRefreshTokenKey(accountId) }
        try secrets.save(tokens.accessToken, for: accessTokenKey)
        if let refreshToken = tokens.refreshToken, let refreshTokenKey {
            try secrets.save(refreshToken, for: refreshTokenKey)
        }

        let account = AIAccount(id: accountId, label: "Claude", accountName: nil)
        let connection = LocalClaudeOAuthConnection(
            accountId: accountId,
            accessTokenKey: accessTokenKey,
            refreshTokenKey: refreshTokenKey,
            expiresAt: tokens.expiresAt,
            scope: config.scope
        )
        try await store.mutate { snapshot in
            snapshot.aiAccount = account
            snapshot.claudeOAuth = connection
        }
    }

    func disconnectClaude(id: String) async throws {
        let snapshot = try await store.loadSnapshot()
        if let connection = snapshot.claudeOAuth, connection.accountId == id {
            try? secrets.delete(connection.accessTokenKey)
            if let refreshTokenKey = connection.refreshTokenKey {
                try? secrets.delete(refreshTokenKey)
            }
        }
        try await store.mutate { snapshot in
            snapshot.aiAccount = nil
            snapshot.claudeOAuth = nil
        }
    }

    func fetchChatMessages(serviceId: String) async throws -> [ChatMessage] {
        let snapshot = try await store.loadSnapshot()
        return snapshot.chatMessages
            .filter { $0.serviceId == serviceId }
            .sorted { $0.createdAt < $1.createdAt }
            .map { ChatMessage(role: $0.role == "user" ? .user : .assistant, text: $0.content) }
    }

    func saveChatMessage(serviceId: String, role: String, content: String) async throws {
        try await store.mutate { snapshot in
            snapshot.chatMessages.append(LocalChatMessage(
                serviceId: serviceId,
                role: role,
                content: content,
                createdAt: Self.isoNow()
            ))
        }
    }

    func fetchServiceBrief(serviceId: String) async throws -> ServiceBrief? {
        let snapshot = try await store.loadSnapshot()
        return snapshot.serviceBriefs.first { $0.serviceId == serviceId }?.brief
    }

    func synthesizeBrief(serviceId: String, document: String?, transcript: [[String: String]]?, currentSections: BriefSections?, userPrompt: String?) async throws -> ServiceBrief {
        if let currentSections {
            let brief = ServiceBrief(sections: currentSections, status: currentSections.hasAnyContent ? "ready" : "empty", gaps: nil)
            try await upsertBrief(serviceId: serviceId, brief: brief)
            return brief
        }
        throw CrmRepositoryError.functionMessage(Self.aiUnsupportedMessage)
    }

    func interviewStep(serviceId: String, transcript: [[String: String]], targetSections: [String]?) async throws -> InterviewStep {
        throw CrmRepositoryError.functionMessage(Self.aiUnsupportedMessage)
    }

    func fetchLatestRelease() async throws -> AppRelease? {
        nil
    }

    private func upsertUsers(serviceId: String, table: LocalServiceTable, rows: [[String: JSONScalar]], syncedAt: String) async throws {
        let idColumn = table.columnMap["user_id"] ?? "id"
        let emailColumn = table.columnMap["email"] ?? "email"
        try await store.mutate { snapshot in
            for row in rows {
                let sourceUserId = row[idColumn]?.display.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !sourceUserId.isEmpty else { continue }
                let existingIndex = snapshot.crmUsers.firstIndex {
                    $0.serviceId == serviceId && $0.user.sourceUserId == sourceUserId
                }
                let existing = existingIndex.map { snapshot.crmUsers[$0].user }
                let crmUser = CrmUser(
                    id: existing?.id ?? Self.stableLocalId(prefix: "user", serviceId: serviceId, sourceId: sourceUserId),
                    sourceUserId: sourceUserId,
                    email: emptyToNil(row[emailColumn]?.display),
                    displayName: Self.displayName(from: row),
                    contactStatus: existing?.contactStatus ?? "not_contacted",
                    amplitudeProfile: existing?.amplitudeProfile,
                    supabaseProfile: row,
                    aiSummary: existing?.aiSummary,
                    lastSyncedAt: syncedAt,
                    createdAt: emptyToNil(row["created_at"]?.display) ?? emptyToNil(row["inserted_at"]?.display) ?? existing?.createdAt ?? syncedAt
                )
                let localRow = LocalCrmUserRow(serviceId: serviceId, user: crmUser)
                if let existingIndex {
                    snapshot.crmUsers[existingIndex] = localRow
                } else {
                    snapshot.crmUsers.append(localRow)
                }
            }
        }
    }

    private func userTableForSync(serviceId: String, table: LocalServiceTable, rows: [[String: JSONScalar]]) async throws -> LocalServiceTable {
        let configuredIdColumn = table.columnMap["user_id"] ?? "id"
        let rowColumns = Set(rows.flatMap { Array($0.keys) })
        guard !rowColumns.isEmpty, !rowColumns.contains(configuredIdColumn) else {
            return table
        }
        guard let fallback = Self.preferredUserIdColumn(in: rowColumns) else {
            throw CrmRepositoryError.functionMessage("유저 ID 컬럼 '\(configuredIdColumn)'이 \(table.sourceSchema).\(table.sourceTable) 응답에 없습니다. 서비스를 다시 만들거나 고유 ID 컬럼을 다시 선택하세요.")
        }

        var resolved = table
        resolved.columnMap["user_id"] = fallback
        try await store.mutate { snapshot in
            guard let index = snapshot.serviceTables.firstIndex(where: { $0.id == table.id && $0.serviceId == serviceId }) else { return }
            snapshot.serviceTables[index].columnMap["user_id"] = fallback
        }
        return resolved
    }

    private func upsertMirroredRows(serviceTableId: String, table: LocalServiceTable, rows: [[String: JSONScalar]]) async throws {
        let pkColumn = table.columnMap["pk"] ?? "id"
        try await store.mutate { snapshot in
            for data in rows {
                let sourcePk = data[pkColumn]?.display.trimmingCharacters(in: .whitespacesAndNewlines) ?? UUID().uuidString
                let row = MirroredRow(
                    id: Self.stableLocalId(prefix: "row", serviceId: serviceTableId, sourceId: sourcePk),
                    sourcePk: sourcePk,
                    data: data
                )
                if let index = snapshot.mirroredRows.firstIndex(where: { $0.serviceTableId == serviceTableId && $0.row.sourcePk == sourcePk }) {
                    snapshot.mirroredRows[index] = LocalMirroredRow(serviceTableId: serviceTableId, row: row)
                } else {
                    snapshot.mirroredRows.append(LocalMirroredRow(serviceTableId: serviceTableId, row: row))
                }
            }
        }
    }

    private static func preferredUserIdColumn(in columnNames: Set<String>) -> String? {
        for candidate in ["id", "user_id", "userId", "uid", "uuid"] {
            if let match = columnNames.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return match
            }
        }
        return nil
    }

    private func updateService(serviceId: String, transform: @Sendable (Service) -> Service) async throws {
        try await store.mutate { snapshot in
            guard let index = snapshot.services.firstIndex(where: { $0.id == serviceId }) else { return }
            snapshot.services[index] = transform(snapshot.services[index])
        }
    }

    private func upsertBrief(serviceId: String, brief: ServiceBrief) async throws {
        try await store.mutate { snapshot in
            if let index = snapshot.serviceBriefs.firstIndex(where: { $0.serviceId == serviceId }) {
                snapshot.serviceBriefs[index].brief = brief
            } else {
                snapshot.serviceBriefs.append(LocalServiceBriefRow(serviceId: serviceId, brief: brief))
            }
        }
    }

    private func supabaseToken(accountId: String) async throws -> String {
        let snapshot = try await store.loadSnapshot()
        if let connection = snapshot.supabaseOAuth?.first(where: { $0.accountId == accountId }) {
            return try await supabaseOAuthToken(connection)
        }

        guard let token = try secrets.read(Self.supabaseSecretKey(accountId)), !token.isEmpty else {
            throw CrmRepositoryError.functionMessage("Supabase 접근 토큰이 Keychain에 없습니다. 계정을 다시 연결하세요.")
        }
        return token
    }

    private static func supabaseSecretKey(_ accountId: String) -> String { "supabase_pat:\(accountId)" }
    private static func supabaseOAuthAccessTokenKey(_ accountId: String) -> String { "supabase_oauth_access:\(accountId)" }
    private static func supabaseOAuthRefreshTokenKey(_ accountId: String) -> String { "supabase_oauth_refresh:\(accountId)" }
    private static func amplitudeAPIKey(_ accountId: String) -> String { "amplitude_api_key:\(accountId)" }
    private static func amplitudeSecretKey(_ accountId: String) -> String { "amplitude_secret_key:\(accountId)" }
    private static func axiomSecretKey(_ accountId: String) -> String { "axiom_token:\(accountId)" }
    private static func claudeAccessTokenKey(_ accountId: String) -> String { "claude_oauth_access:\(accountId)" }
    private static func claudeRefreshTokenKey(_ accountId: String) -> String { "claude_oauth_refresh:\(accountId)" }

    private static let aiUnsupportedMessage = "Claude OAuth 연결이 필요합니다."

    private static func stableLocalId(prefix: String, serviceId: String, sourceId: String) -> String {
        "local:\(prefix):\(serviceId):\(sourceId)"
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func parseISO8601(_ value: String) -> Date? {
        ConnectumDateParser.parse(value)
    }

    private func supabaseOAuthToken(_ connection: LocalSupabaseOAuthConnection) async throws -> String {
        guard let accessToken = try secrets.read(connection.accessTokenKey), !accessToken.isEmpty else {
            throw CrmRepositoryError.functionMessage("Supabase OAuth access token이 Keychain에 없습니다. 계정을 다시 연결하세요.")
        }
        guard Self.needsTokenRefresh(connection.expiresAt) else {
            return accessToken
        }
        guard let refreshTokenKey = connection.refreshTokenKey,
              let refreshToken = try secrets.read(refreshTokenKey),
              !refreshToken.isEmpty else {
            throw CrmRepositoryError.supabaseReauthorizationRequired
        }

        let tokens = try await supabaseOAuthAPI.refresh(refreshToken: refreshToken)
        try secrets.save(tokens.accessToken, for: connection.accessTokenKey)
        if let rotatedRefreshToken = tokens.refreshToken {
            try secrets.save(rotatedRefreshToken, for: refreshTokenKey)
        }
        try await store.mutate { snapshot in
            guard var connections = snapshot.supabaseOAuth,
                  let index = connections.firstIndex(where: { $0.accountId == connection.accountId }) else {
                return
            }
            connections[index].expiresAt = tokens.expiresAt
            if let accountName = tokens.accountName {
                connections[index].accountName = accountName
                if let accountIndex = snapshot.supabaseAccounts.firstIndex(where: { $0.id == connection.accountId }) {
                    let old = snapshot.supabaseAccounts[accountIndex]
                    snapshot.supabaseAccounts[accountIndex] = ConnAccount(
                        id: old.id,
                        label: old.label,
                        accountName: accountName,
                        projectName: old.projectName,
                        datasets: old.datasets
                    )
                }
            }
            snapshot.supabaseOAuth = connections
        }
        return tokens.accessToken
    }

    private static func needsTokenRefresh(_ expiresAt: String) -> Bool {
        guard let date = parseISO8601(expiresAt) else { return true }
        return date.timeIntervalSinceNow <= 5 * 60
    }

    private static func displayName(from row: [String: JSONScalar]) -> String? {
        ["display_name", "full_name", "name"].compactMap { emptyToNil(row[$0]?.display) }.first
    }
}

struct LocalClaudeOAuthTokenProvider: Sendable {
    private let store: LocalConnectumStore
    private let secrets: SecretStoring
    private let claudeOAuthAPI: ClaudeOAuthAPIProviding

    init(
        store: LocalConnectumStore = .shared,
        secrets: SecretStoring = KeychainSecretStore(),
        claudeOAuthAPI: ClaudeOAuthAPIProviding = URLSessionClaudeOAuthAPI()
    ) {
        self.store = store
        self.secrets = secrets
        self.claudeOAuthAPI = claudeOAuthAPI
    }

    func validAccessToken() async throws -> String {
        let snapshot = try await store.loadSnapshot()
        guard let connection = snapshot.claudeOAuth else {
            throw CrmRepositoryError.functionMessage("Claude 계정이 연결되어 있지 않습니다.")
        }
        guard let accessToken = try secrets.read(connection.accessTokenKey), !accessToken.isEmpty else {
            throw CrmRepositoryError.functionMessage("Claude access token이 Keychain에 없습니다. 다시 연결하세요.")
        }
        guard needsRefresh(connection.expiresAt) else {
            return accessToken
        }
        guard let refreshTokenKey = connection.refreshTokenKey,
              let refreshToken = try secrets.read(refreshTokenKey),
              !refreshToken.isEmpty else {
            throw CrmRepositoryError.functionMessage("Claude 연결이 만료됐습니다. 다시 연결하세요.")
        }

        let config = SupabaseClientProvider.claudeConfig()
        let tokens = try await claudeOAuthAPI.refresh(refreshToken: refreshToken, clientId: config.clientId)
        try secrets.save(tokens.accessToken, for: connection.accessTokenKey)
        if let rotatedRefreshToken = tokens.refreshToken {
            try secrets.save(rotatedRefreshToken, for: refreshTokenKey)
        }
        try await store.mutate { snapshot in
            guard var updated = snapshot.claudeOAuth,
                  updated.accountId == connection.accountId else { return }
            updated.expiresAt = tokens.expiresAt
            updated.scope = config.scope
            snapshot.claudeOAuth = updated
        }
        return tokens.accessToken
    }

    private func needsRefresh(_ expiresAt: String) -> Bool {
        guard let date = Self.parseISO8601(expiresAt) else { return true }
        return date.timeIntervalSinceNow <= 5 * 60
    }

    private static func parseISO8601(_ value: String) -> Date? {
        ConnectumDateParser.parse(value)
    }
}

private func emptyToNil(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}
