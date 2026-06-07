import Foundation
import Supabase

protocol CrmDataProviding: Sendable {
    func fetchServices() async throws -> [Service]
    func fetchUsers(serviceId: String) async throws -> [CrmUser]
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
    func fetchViews() async throws -> [SavedView]
    func createView(name: String, config: ViewConfig) async throws
    func fetchSupabaseAccounts() async throws -> [ConnAccount]
    func fetchAmplitudeAccounts() async throws -> [ConnAccount]
    func fetchAxiomAccounts() async throws -> [ConnAccount]
    func connectSupabasePAT(pat: String, label: String) async throws
    func connectAmplitude(apiKey: String, secretKey: String, region: String, label: String) async throws
    func connectAxiom(token: String, label: String) async throws -> [String]
    func listProjects(supabaseAccountId: String) async throws -> [ProjectInfo]
    func listTables(supabaseAccountId: String, projectRef: String) async throws -> [TableInfo]
    func createService(name: String, supabaseAccountId: String, projectRef: String, tables: [ServiceTableSpec], amplitudeAccountId: String?, axiomAccountId: String?) async throws
}

struct CrmRepository: CrmDataProviding {
    let client: SupabaseClient
    init(client: SupabaseClient = SupabaseClientProvider.shared) { self.client = client }

    func fetchServices() async throws -> [Service] {
        try await client.from("service")
            .select("id,name,supabase_project_ref").order("name").execute().value
    }
    func fetchUsers(serviceId: String) async throws -> [CrmUser] {
        try await client.from("crm_user")
            .select("id,source_user_id,email,display_name,contact_status,amplitude_profile,ai_summary,last_synced_at,created_at")
            .eq("service_id", value: serviceId)
            .order("created_at", ascending: false)
            .limit(1000)
            .execute().value
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
            let q = client.from("crm_user").select("*", head: true, count: .exact).eq("service_id", value: serviceId)
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
    func fetchViews() async throws -> [SavedView] {
        try await client.from("view").select("id,name,config").order("created_at", ascending: true).execute().value
    }
    func createView(name: String, config: ViewConfig) async throws {
        struct NewView: Encodable { let name: String; let scope: String; let config: ViewConfig }
        try await client.from("view").insert(NewView(name: name, scope: "workspace", config: config)).execute()
    }
    func fetchSupabaseAccounts() async throws -> [ConnAccount] {
        try await client.from("supabase_account").select("id,label").order("created_at").execute().value
    }
    func fetchAmplitudeAccounts() async throws -> [ConnAccount] {
        try await client.from("amplitude_account").select("id,label").order("created_at").execute().value
    }
    func fetchAxiomAccounts() async throws -> [ConnAccount] {
        try await client.from("axiom_account").select("id,label").order("created_at").execute().value
    }
    func connectSupabasePAT(pat: String, label: String) async throws {
        struct B: Encodable { let pat: String; let label: String }
        struct R: Decodable { let account_id: String? }
        let _: R = try await client.functions.invoke("supabase-connect-pat", options: FunctionInvokeOptions(body: B(pat: pat, label: label)))
    }
    func connectAmplitude(apiKey: String, secretKey: String, region: String, label: String) async throws {
        struct B: Encodable { let api_key: String; let secret_key: String; let region: String; let label: String }
        struct R: Decodable { let account_id: String? }
        let _: R = try await client.functions.invoke("amplitude-connect", options: FunctionInvokeOptions(body: B(api_key: apiKey, secret_key: secretKey, region: region, label: label)))
    }
    func connectAxiom(token: String, label: String) async throws -> [String] {
        struct B: Encodable { let token: String; let label: String }
        struct R: Decodable { let account_id: String?; let datasets: [String]? }
        let r: R = try await client.functions.invoke("axiom-connect", options: FunctionInvokeOptions(body: B(token: token, label: label)))
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
        let r: R = try await client.functions.invoke("supabase-list-tables", options: FunctionInvokeOptions(body: B(account_id: supabaseAccountId, project_ref: projectRef)))
        return r.tables
    }
    func createService(name: String, supabaseAccountId: String, projectRef: String, tables: [ServiceTableSpec], amplitudeAccountId: String?, axiomAccountId: String?) async throws {
        struct NewService: Encodable {
            let name: String; let supabase_account_id: String; let supabase_project_ref: String
            let amplitude_account_id: String?; let axiom_account_id: String?
        }
        struct CreatedId: Decodable { let id: String }
        let created: CreatedId = try await client.from("service")
            .insert(NewService(name: name, supabase_account_id: supabaseAccountId, supabase_project_ref: projectRef,
                               amplitude_account_id: amplitudeAccountId, axiom_account_id: axiomAccountId))
            .select("id").single().execute().value
        struct NewTable: Encodable {
            let service_id: String; let source_schema: String; let source_table: String
            let role: String; let column_map: [String: String]; let cursor_column: String
        }
        let rows: [NewTable] = tables.map { t in
            let cm = t.role == "user_table" ? ["user_id": t.userIdCol, "email": t.emailCol] : ["pk": "id"]
            return NewTable(service_id: created.id, source_schema: t.schema, source_table: t.table, role: t.role, column_map: cm, cursor_column: "created_at")
        }
        if !rows.isEmpty { try await client.from("service_table").insert(rows).execute() }
    }
}
