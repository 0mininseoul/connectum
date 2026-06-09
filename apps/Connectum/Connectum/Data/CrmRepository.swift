import Foundation
import Supabase

enum CrmRepositoryError: LocalizedError {
    case supabaseReauthorizationRequired
    case functionMessage(String)

    var errorDescription: String? {
        switch self {
        case .supabaseReauthorizationRequired:
            return "Supabase 권한을 다시 승인해야 합니다."
        case .functionMessage(let message):
            return message
        }
    }
}

private struct FunctionErrorBody: Decodable {
    let code: String?
    let message: String?
    let error: String?
    let requiredScope: String?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case error
        case requiredScope = "required_scope"
    }
}

protocol CrmDataProviding: Sendable {
    func fetchServices() async throws -> [Service]
    func syncService(serviceId: String) async throws
    func deleteService(serviceId: String) async throws
    func fetchUsers(serviceId: String) async throws -> [CrmUser]
    func excludeUser(crmUserId: String, reason: String?) async throws
    func fetchEvents(crmUserId: String, limit: Int) async throws -> [CrmUserEvent]
    func setContactStatus(crmUserId: String, status: String) async throws
    func regenerateSummary(crmUserId: String) async throws -> String
    func fetchChannelRecords(crmUserId: String) async throws -> [ChannelRecord]
    func addChannelRecord(crmUserId: String, channel: String, occurredAt: String, body: String) async throws
    func fetchNoteBlocks(crmUserId: String) async throws -> [NoteBlock]
    func addNoteBlock(crmUserId: String, text: String) async throws
    func updateNoteBlock(id: String, text: String) async throws
    func deleteNoteBlock(id: String) async throws
    func fetchHistory(crmUserId: String) async throws -> [HistoryEntry]
    func addHistory(crmUserId: String, entryDate: String, memo: String, imageData: Data?, fileExt: String) async throws
    func fetchMetrics(serviceId: String) async throws -> DashboardMetrics
    func confirmDashboardKPI(serviceId: String, title: String, prompt: String) async throws -> DashboardKPIConfirmation
    func fetchViews() async throws -> [SavedView]
    func createView(name: String, config: ViewConfig) async throws
    func fetchSupabaseAccounts() async throws -> [ConnAccount]
    func fetchAmplitudeAccounts() async throws -> [ConnAccount]
    func fetchAxiomAccounts() async throws -> [ConnAccount]
    func supabaseOAuthAuthorizeURL(state: String) async throws -> URL
    func connectSupabaseOAuth(code: String, state: String) async throws
    func connectSupabasePAT(pat: String, label: String) async throws
    func connectAmplitude(apiKey: String, secretKey: String, region: String, projectName: String, accountName: String) async throws
    func connectAxiom(token: String, accountName: String) async throws -> [String]
    func deleteSupabaseAccount(id: String) async throws
    func deleteAmplitudeAccount(id: String) async throws
    func deleteAxiomAccount(id: String) async throws
    func updateServiceSupabaseAccount(serviceId: String, accountId: String) async throws
    func fetchSupabaseAccountProfile(id: String) async throws -> String?
    func listAxiomDatasets(accountId: String) async throws -> [String]
    func listProjects(supabaseAccountId: String) async throws -> [ProjectInfo]
    func listTables(supabaseAccountId: String, projectRef: String) async throws -> [TableInfo]
    func createService(name: String, supabaseAccountId: String, projectRef: String, projectName: String?, tables: [ServiceTableSpec], amplitudeAccountId: String?, amplitudeProjectName: String?, axiomAccountId: String?, axiomDataset: String?) async throws
    func listColumns(supabaseAccountId: String, projectRef: String, schema: String, table: String) async throws -> [ColumnInfo]
    func fetchDisplayColumns(serviceId: String) async throws -> [String]
    func updateDisplayColumns(serviceId: String, columns: [String]) async throws
    func fetchAIAccount() async throws -> AIAccount?
    func connectClaude(code: String, codeVerifier: String, redirectURI: String) async throws
    func disconnectClaude(id: String) async throws
}

struct CrmRepository: CrmDataProviding {
    let client: SupabaseClient
    init(client: SupabaseClient = SupabaseClientProvider.shared) { self.client = client }

    private func normalizeFunctionError(_ error: Error) -> Error {
        guard case let FunctionsError.httpError(_, data) = error else { return error }
        guard let body = try? JSONDecoder().decode(FunctionErrorBody.self, from: data) else { return error }
        if body.code == "supabase_scope_missing"
            || body.requiredScope == "database:read"
            || body.requiredScope == "database:write" {
            return CrmRepositoryError.supabaseReauthorizationRequired
        }
        if let message = body.message ?? body.error, !message.isEmpty {
            return CrmRepositoryError.functionMessage(message)
        }
        return error
    }

    func fetchServices() async throws -> [Service] {
        do {
            return try await client.from("service")
                .select("id,name,supabase_project_ref,supabase_project_name,supabase_account_id,amplitude_account_id,amplitude_project_name,axiom_account_id,axiom_dataset")
                .order("name")
                .execute()
                .value
        } catch {
            return try await client.from("service")
                .select("id,name,supabase_project_ref,supabase_account_id,amplitude_account_id,axiom_account_id,axiom_dataset")
                .order("name")
                .execute()
                .value
        }
    }
    func syncService(serviceId: String) async throws {
        struct Body: Encodable { let service_id: String }
        struct Resp: Decodable {}
        do {
            let _: Resp = try await client.functions.invoke(
                "sync",
                options: FunctionInvokeOptions(body: Body(service_id: serviceId))
            )
        } catch {
            throw normalizeFunctionError(error)
        }
    }
    func deleteService(serviceId: String) async throws {
        try await client.from("service")
            .delete()
            .eq("id", value: serviceId)
            .execute()
    }
    func fetchUsers(serviceId: String) async throws -> [CrmUser] {
        try await client.from("crm_user")
            .select("id,source_user_id,email,display_name,contact_status,amplitude_profile,supabase_profile,ai_summary,last_synced_at,created_at")
            .eq("service_id", value: serviceId)
            .neq("contact_status", value: "excluded")
            .order("created_at", ascending: false)
            .limit(1000)
            .execute().value
    }
    func excludeUser(crmUserId: String, reason: String? = nil) async throws {
        struct Upd: Encodable {
            let contact_status: String
            let updated_at: String
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
        try await client.from("crm_user")
            .update(Upd(contact_status: "excluded", updated_at: stamp))
            .eq("id", value: crmUserId)
            .execute()
    }
    func fetchEvents(crmUserId: String, limit: Int = 50) async throws -> [CrmUserEvent] {
        try await client.from("crm_user_event")
            .select("id,event_type,event_time,os,browser,platform")
            .eq("crm_user_id", value: crmUserId)
            .order("event_time", ascending: false)
            .limit(limit)
            .execute().value
    }
    func setContactStatus(crmUserId: String, status: String) async throws {
        try await client.from("crm_user")
            .update(["contact_status": status])
            .eq("id", value: crmUserId)
            .execute()
    }
    func regenerateSummary(crmUserId: String) async throws -> String {
        struct Body: Encodable { let crm_user_id: String; let force: Bool }
        struct Resp: Decodable { let ai_summary: String? }
        let resp: Resp = try await client.functions.invoke(
            "summarize-user",
            options: FunctionInvokeOptions(body: Body(crm_user_id: crmUserId, force: true))
        )
        return resp.ai_summary ?? ""
    }
    func fetchChannelRecords(crmUserId: String) async throws -> [ChannelRecord] {
        let rows: [PageBlockRow] = try await client.from("page_block")
            .select("id,content")
            .eq("crm_user_id", value: crmUserId)
            .eq("type", value: "channel_record")
            .order("position", ascending: false)
            .execute().value
        return rows.map { $0.asChannelRecord }
    }
    func addChannelRecord(crmUserId: String, channel: String, occurredAt: String, body: String) async throws {
        struct NewBlock: Encodable {
            let crm_user_id: String; let type: String; let position: Double
            let content: [String: String]
        }
        let block = NewBlock(
            crm_user_id: crmUserId, type: "channel_record", position: Date().timeIntervalSince1970,
            content: ["channel": channel, "occurred_at": occurredAt, "body": body])
        try await client.from("page_block").insert(block).execute()
    }
    func fetchNoteBlocks(crmUserId: String) async throws -> [NoteBlock] {
        let rows: [NoteBlockRow] = try await client.from("page_block")
            .select("id,type,content")
            .eq("crm_user_id", value: crmUserId)
            .eq("type", value: "text")
            .order("position", ascending: true)
            .execute().value
        return rows.map { $0.asNote }
    }
    func addNoteBlock(crmUserId: String, text: String) async throws {
        struct NewBlock: Encodable { let crm_user_id: String; let type: String; let position: Double; let content: [String: String] }
        try await client.from("page_block")
            .insert(NewBlock(crm_user_id: crmUserId, type: "text", position: Date().timeIntervalSince1970, content: ["text": text]))
            .execute()
    }
    func updateNoteBlock(id: String, text: String) async throws {
        struct Upd: Encodable { let content: [String: String] }
        try await client.from("page_block").update(Upd(content: ["text": text])).eq("id", value: id).execute()
    }
    func deleteNoteBlock(id: String) async throws {
        try await client.from("page_block").delete().eq("id", value: id).execute()
    }
    func fetchHistory(crmUserId: String) async throws -> [HistoryEntry] {
        try await client.from("history_entry")
            .select("id,entry_date,image_url,memo")
            .eq("crm_user_id", value: crmUserId)
            .order("entry_date", ascending: false)
            .execute().value
    }
    func addHistory(crmUserId: String, entryDate: String, memo: String, imageData: Data?, fileExt: String) async throws {
        var imageUrl: String? = nil
        if let data = imageData {
            let path = "\(crmUserId)/\(UUID().uuidString).\(fileExt)"
            let contentType = fileExt.lowercased() == "png" ? "image/png" : "image/jpeg"
            _ = try await client.storage.from("history").upload(path, data: data, options: FileOptions(contentType: contentType, upsert: true))
            imageUrl = try client.storage.from("history").getPublicURL(path: path).absoluteString
        }
        struct NewEntry: Encodable { let crm_user_id: String; let entry_date: String; let image_url: String?; let memo: String; let position: Double }
        try await client.from("history_entry")
            .insert(NewEntry(crm_user_id: crmUserId, entry_date: entryDate, image_url: imageUrl, memo: memo, position: Date().timeIntervalSince1970))
            .execute()
    }
    func fetchMetrics(serviceId: String) async throws -> DashboardMetrics {
        func count(_ build: (PostgrestFilterBuilder) -> PostgrestFilterBuilder) async throws -> Int {
            let q = client.from("crm_user")
                .select("*", head: true, count: .exact)
                .eq("service_id", value: serviceId)
                .neq("contact_status", value: "excluded")
            let res = try await build(q).execute()
            return res.count ?? 0
        }
        let total = try await count { $0 }
        let contacted = try await count { $0.eq("contact_status", value: "contacted") }
        let profiled = try await count { $0.neq("amplitude_profile", value: "{}") }
        let weekAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7*24*3600))
        let recent = try await count { $0.gte("created_at", value: weekAgo) }
        return DashboardMetrics(total: total, contacted: contacted, profiled: profiled, recentSignups: recent)
    }
    func confirmDashboardKPI(serviceId: String, title: String, prompt: String) async throws -> DashboardKPIConfirmation {
        struct Body: Encodable {
            let service_id: String
            let title: String
            let prompt: String
        }
        return try await client.functions.invoke(
            "kpi-confirm",
            options: FunctionInvokeOptions(body: Body(service_id: serviceId, title: title, prompt: prompt))
        )
    }
    func fetchViews() async throws -> [SavedView] {
        try await client.from("view").select("id,name,config").order("created_at", ascending: true).execute().value
    }
    func createView(name: String, config: ViewConfig) async throws {
        struct NewView: Encodable { let name: String; let scope: String; let config: ViewConfig }
        try await client.from("view").insert(NewView(name: name, scope: "workspace", config: config)).execute()
    }
    func fetchSupabaseAccounts() async throws -> [ConnAccount] {
        do {
            return try await client.from("supabase_account").select("id,label,account_name").order("created_at").execute().value
        } catch {
            return try await client.from("supabase_account").select("id,label").order("created_at").execute().value
        }
    }
    func fetchAmplitudeAccounts() async throws -> [ConnAccount] {
        do {
            return try await client.from("amplitude_account").select("id,label,account_name,project_name").order("created_at").execute().value
        } catch {
            return try await client.from("amplitude_account").select("id,label").order("created_at").execute().value
        }
    }
    func fetchAxiomAccounts() async throws -> [ConnAccount] {
        do {
            return try await client.from("axiom_account").select("id,label,account_name,datasets").order("created_at").execute().value
        } catch {
            return try await client.from("axiom_account").select("id,label").order("created_at").execute().value
        }
    }
    func supabaseOAuthAuthorizeURL(state: String) async throws -> URL {
        struct B: Encodable { let state: String; let redirect_uri: String }
        struct R: Decodable { let authorize_url: String }
        let response: R = try await client.functions.invoke(
            "oauth-supabase-start",
            options: FunctionInvokeOptions(body: B(state: state, redirect_uri: SupabaseOAuthFlow.redirectURI))
        )
        guard let url = URL(string: response.authorize_url) else {
            throw URLError(.badURL)
        }
        return url
    }
    func connectSupabaseOAuth(code: String, state: String) async throws {
        struct B: Encodable { let code: String; let state: String; let label: String }
        struct R: Decodable { let account_id: String? }
        let _: R = try await client.functions.invoke(
            "oauth-supabase",
            options: FunctionInvokeOptions(body: B(code: code, state: state, label: "Supabase"))
        )
    }
    func connectSupabasePAT(pat: String, label: String) async throws {
        struct B: Encodable { let pat: String; let label: String }
        struct R: Decodable { let account_id: String? }
        let _: R = try await client.functions.invoke("supabase-connect-pat", options: FunctionInvokeOptions(body: B(pat: pat, label: label)))
    }
    func connectAmplitude(apiKey: String, secretKey: String, region: String, projectName: String, accountName: String) async throws {
        struct B: Encodable {
            let api_key: String
            let secret_key: String
            let region: String
            let project_name: String?
            let account_name: String?
            let label: String
        }
        struct R: Decodable { let account_id: String? }
        let cleanProject = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAccount = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackLabel = cleanAccount.isEmpty ? (cleanProject.isEmpty ? "Amplitude" : cleanProject) : cleanAccount
        let _: R = try await client.functions.invoke(
            "amplitude-connect",
            options: FunctionInvokeOptions(body: B(
                api_key: apiKey,
                secret_key: secretKey,
                region: region,
                project_name: cleanProject.isEmpty ? nil : cleanProject,
                account_name: cleanAccount.isEmpty ? nil : cleanAccount,
                label: fallbackLabel
            ))
        )
    }
    func connectAxiom(token: String, accountName: String) async throws -> [String] {
        struct B: Encodable { let token: String; let account_name: String?; let label: String }
        struct R: Decodable { let account_id: String?; let datasets: [String]? }
        let cleanAccount = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let r: R = try await client.functions.invoke(
            "axiom-connect",
            options: FunctionInvokeOptions(body: B(
                token: token,
                account_name: cleanAccount.isEmpty ? nil : cleanAccount,
                label: cleanAccount.isEmpty ? "Axiom" : cleanAccount
            ))
        )
        return r.datasets ?? []
    }
    func deleteSupabaseAccount(id: String) async throws {
        try await client.from("supabase_account").delete().eq("id", value: id).execute()
    }
    func deleteAmplitudeAccount(id: String) async throws {
        try await client.from("amplitude_account").delete().eq("id", value: id).execute()
    }
    func deleteAxiomAccount(id: String) async throws {
        try await client.from("axiom_account").delete().eq("id", value: id).execute()
    }
    func updateServiceSupabaseAccount(serviceId: String, accountId: String) async throws {
        struct Upd: Encodable { let supabase_account_id: String }
        try await client.from("service")
            .update(Upd(supabase_account_id: accountId))
            .eq("id", value: serviceId)
            .execute()
    }
    func fetchSupabaseAccountProfile(id: String) async throws -> String? {
        struct B: Encodable { let account_id: String }
        struct R: Decodable { let account_name: String? }
        let r: R = try await client.functions.invoke(
            "supabase-account-profile",
            options: FunctionInvokeOptions(body: B(account_id: id))
        )
        return r.account_name
    }
    func listAxiomDatasets(accountId: String) async throws -> [String] {
        struct B: Encodable { let account_id: String }
        struct R: Decodable { let datasets: [String]? }
        let r: R = try await client.functions.invoke(
            "axiom-list-datasets",
            options: FunctionInvokeOptions(body: B(account_id: accountId))
        )
        return r.datasets ?? []
    }
    func listProjects(supabaseAccountId: String) async throws -> [ProjectInfo] {
        struct B: Encodable { let account_id: String }
        struct R: Decodable { let projects: [ProjectInfo] }
        let r: R = try await client.functions.invoke("supabase-list-projects", options: FunctionInvokeOptions(body: B(account_id: supabaseAccountId)))
        return r.projects
    }
    func listTables(supabaseAccountId: String, projectRef: String) async throws -> [TableInfo] {
        struct B: Encodable { let account_id: String; let project_ref: String }
        struct R: Decodable { let tables: [TableInfo] }
        do {
            let r: R = try await client.functions.invoke("supabase-list-tables", options: FunctionInvokeOptions(body: B(account_id: supabaseAccountId, project_ref: projectRef)))
            return r.tables
        } catch {
            throw normalizeFunctionError(error)
        }
    }
    func createService(name: String, supabaseAccountId: String, projectRef: String, projectName: String?, tables: [ServiceTableSpec], amplitudeAccountId: String?, amplitudeProjectName: String?, axiomAccountId: String?, axiomDataset: String?) async throws {
        struct NewService: Encodable {
            let name: String; let supabase_account_id: String; let supabase_project_ref: String
            let supabase_project_name: String?
            let amplitude_account_id: String?; let amplitude_project_name: String?
            let axiom_account_id: String?; let axiom_dataset: String?
        }
        struct LegacyService: Encodable {
            let name: String; let supabase_account_id: String; let supabase_project_ref: String
            let amplitude_account_id: String?; let axiom_account_id: String?; let axiom_dataset: String?
        }
        struct CreatedId: Decodable { let id: String }
        let created: CreatedId
        do {
            created = try await client.from("service")
                .insert(NewService(
                    name: name,
                    supabase_account_id: supabaseAccountId,
                    supabase_project_ref: projectRef,
                    supabase_project_name: projectName,
                    amplitude_account_id: amplitudeAccountId,
                    amplitude_project_name: amplitudeProjectName,
                    axiom_account_id: axiomAccountId,
                    axiom_dataset: axiomDataset
                ))
                .select("id").single().execute().value
        } catch {
            created = try await client.from("service")
                .insert(LegacyService(
                    name: name,
                    supabase_account_id: supabaseAccountId,
                    supabase_project_ref: projectRef,
                    amplitude_account_id: amplitudeAccountId,
                    axiom_account_id: axiomAccountId,
                    axiom_dataset: axiomDataset
                ))
                .select("id").single().execute().value
        }
        struct NewTable: Encodable {
            let service_id: String; let source_schema: String; let source_table: String
            let role: String; let column_map: [String: String]; let cursor_column: String
            let display_columns: [String]
        }
        let rows: [NewTable] = tables.map { t in
            let cm = t.role == "user_table" ? ["user_id": t.userIdCol, "email": t.emailCol] : ["pk": "id"]
            return NewTable(service_id: created.id, source_schema: t.schema, source_table: t.table, role: t.role,
                            column_map: cm, cursor_column: "created_at",
                            display_columns: t.role == "user_table" ? t.displayColumns : [])
        }
        if !rows.isEmpty { try await client.from("service_table").insert(rows).execute() }
    }

    func listColumns(supabaseAccountId: String, projectRef: String, schema: String, table: String) async throws -> [ColumnInfo] {
        struct B: Encodable { let account_id: String; let project_ref: String; let schema: String; let table: String }
        struct R: Decodable { let columns: [ColumnInfo] }
        do {
            let r: R = try await client.functions.invoke(
                "supabase-list-columns",
                options: FunctionInvokeOptions(body: B(account_id: supabaseAccountId, project_ref: projectRef, schema: schema, table: table)))
            return r.columns
        } catch {
            throw normalizeFunctionError(error)
        }
    }

    func fetchDisplayColumns(serviceId: String) async throws -> [String] {
        struct Row: Decodable { let display_columns: [String] }
        let rows: [Row] = try await client.from("service_table")
            .select("display_columns").eq("service_id", value: serviceId).eq("role", value: "user_table")
            .execute().value
        return rows.first?.display_columns ?? []
    }
    func updateDisplayColumns(serviceId: String, columns: [String]) async throws {
        struct Upd: Encodable { let display_columns: [String] }
        try await client.from("service_table")
            .update(Upd(display_columns: columns))
            .eq("service_id", value: serviceId).eq("role", value: "user_table")
            .execute()
    }
    func fetchAIAccount() async throws -> AIAccount? {
        let rows: [AIAccount] = try await client.from("ai_account")
            .select("id,label,account_name").order("created_at").limit(1).execute().value
        return rows.first
    }
    func connectClaude(code: String, codeVerifier: String, redirectURI: String) async throws {
        struct B: Encodable { let code: String; let code_verifier: String; let redirect_uri: String }
        struct R: Decodable { let account_id: String? }
        let _: R = try await client.functions.invoke(
            "ai-connect",
            options: FunctionInvokeOptions(body: B(code: code, code_verifier: codeVerifier, redirect_uri: redirectURI)))
    }
    func disconnectClaude(id: String) async throws {
        try await client.from("ai_account").delete().eq("id", value: id).execute()
    }
}
