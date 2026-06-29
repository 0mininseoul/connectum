import Foundation
import Supabase

enum CrmRepositoryError: LocalizedError {
    case supabaseReauthorizationRequired
    case functionMessage(String)

    var errorDescription: String? {
        switch self {
        case .supabaseReauthorizationRequired:
            return "Supabase 연결이 만료됐습니다. 다시 연결하세요."
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
    let results: [String: FunctionSyncResult]?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case error
        case requiredScope = "required_scope"
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try? container.decode(String.self, forKey: .code)
        message = try? container.decode(String.self, forKey: .message)
        error = try? container.decode(String.self, forKey: .error)
        requiredScope = try? container.decode(String.self, forKey: .requiredScope)
        results = try? container.decode([String: FunctionSyncResult].self, forKey: .results)
    }

    var requiresSupabaseReauthorization: Bool {
        isSupabaseReauthorizationSignal(code: code, requiredScope: requiredScope, message: message ?? error)
            || syncFailureMessages.contains { isSupabaseReauthorizationMessage($0) }
    }

    var syncFailureMessages: [String] {
        results?.flatMap { serviceName, result in
            result.failureMessages.map { "\(serviceName) \($0)" }
        } ?? []
    }
}

private struct FunctionSyncResult: Decodable {
    let supabase: FunctionStepResult?
    let amplitude: FunctionStepResult?

    var failureMessages: [String] {
        [
            ("Supabase", supabase),
            ("Amplitude", amplitude),
        ].compactMap { source, result in
            result?.failureMessage(source: source)
        }
    }
}

private struct FunctionStepResult: Decodable {
    let status: Int?
    let body: FunctionStepBody?

    func failureMessage(source: String) -> String? {
        guard let status, status >= 400 else { return nil }
        let message = body?.message ?? body?.error ?? "HTTP \(status)"
        return "\(source): \(message)"
    }
}

private struct FunctionStepBody: Decodable {
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

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            code = nil
            message = nil
            error = value
            requiredScope = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try? container.decode(String.self, forKey: .code)
        message = try? container.decode(String.self, forKey: .message)
        error = try? container.decode(String.self, forKey: .error)
        requiredScope = try? container.decode(String.self, forKey: .requiredScope)
    }
}

private func isSupabaseReauthorizationSignal(code: String?, requiredScope: String?, message: String?) -> Bool {
    code == "supabase_reauthorization_required"
        || code == "supabase_scope_missing"
        || requiredScope == "database:read"
        || requiredScope == "database:write"
        || isSupabaseReauthorizationMessage(message)
}

private func isSupabaseReauthorizationMessage(_ message: String?) -> Bool {
    guard let message else { return false }
    return message.contains("Supabase OAuth refresh failed")
        || message.contains("No such refresh token found")
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
    func previewKPI(serviceId: String, title: String, prompt: String) async throws -> KPIPreview
    func recomputeKPI(serviceId: String, spec: KPISpec) async throws -> Double
    func fetchKPIs(serviceId: String) async throws -> [DashboardKPIDefinition]
    func seedSystemKPIs(serviceId: String) async throws
    func insertKPI(serviceId: String, title: String, prompt: String, spec: KPISpec, unit: String, value: Double, position: Double) async throws
    func deleteKPIRow(id: String) async throws
    func renameKPIRow(id: String, title: String) async throws
    func updateKPIValue(id: String, value: Double) async throws
    func updateKPIPosition(id: String, position: Double) async throws
    func fetchViews() async throws -> [SavedView]
    func createView(name: String, config: ViewConfig) async throws
    func fetchSupabaseAccounts() async throws -> [ConnAccount]
    func fetchAmplitudeAccounts() async throws -> [ConnAccount]
    func fetchAxiomAccounts() async throws -> [ConnAccount]
    func supabaseOAuthAuthorizeURL(state: String) async throws -> URL
    func connectSupabaseOAuth(code: String, state: String) async throws
    func connectSupabasePAT(pat: String, label: String) async throws
    func connectAmplitude(projectName: String, apiKey: String, secretKey: String, region: String) async throws
    func connectAxiom(token: String) async throws -> [String]
    func deleteSupabaseAccount(id: String) async throws
    func deleteAmplitudeAccount(id: String) async throws
    func deleteAxiomAccount(id: String) async throws
    func updateServiceSupabaseAccount(serviceId: String, accountId: String) async throws
    func updateServiceAmplitudeAccount(serviceId: String, accountId: String) async throws
    func updateServiceAxiomAccount(serviceId: String, accountId: String, dataset: String?) async throws
    func fetchSupabaseAccountProfile(id: String) async throws -> String?
    func listAxiomDatasets(accountId: String) async throws -> [String]
    func listProjects(supabaseAccountId: String) async throws -> [ProjectInfo]
    func listTables(supabaseAccountId: String, projectRef: String) async throws -> [TableInfo]
    @discardableResult
    func createService(name: String, supabaseAccountId: String, projectRef: String, projectName: String?, tables: [ServiceTableSpec], amplitudeAccountId: String?, amplitudeProjectName: String?, axiomAccountId: String?, axiomDataset: String?) async throws -> String
    func listColumns(supabaseAccountId: String, projectRef: String, schema: String, table: String) async throws -> [ColumnInfo]
    func fetchDisplayColumns(serviceId: String) async throws -> [String]
    func updateDisplayColumns(serviceId: String, columns: [String]) async throws
    func fetchServiceTables(serviceId: String) async throws -> [ServiceTableInfo]
    func addRelatedTable(serviceId: String, schema: String, table: String) async throws
    func removeServiceTable(id: String) async throws
    func fetchMirroredRows(serviceTableId: String, limit: Int) async throws -> [MirroredRow]
    func fetchAIAccount() async throws -> AIAccount?
    func connectClaude(code: String, state: String?, codeVerifier: String, redirectURI: String) async throws
    func disconnectClaude(id: String) async throws
    func fetchChatMessages(serviceId: String) async throws -> [ChatMessage]
    func saveChatMessage(serviceId: String, role: String, content: String) async throws
    func fetchServiceBrief(serviceId: String) async throws -> ServiceBrief?
    func synthesizeBrief(serviceId: String, document: String?, transcript: [[String: String]]?, currentSections: BriefSections?, userPrompt: String?) async throws -> ServiceBrief
    func interviewStep(serviceId: String, transcript: [[String: String]], targetSections: [String]?) async throws -> InterviewStep
    func fetchLatestRelease() async throws -> AppRelease?
}

typealias CrmRepository = LocalCrmRepository

struct HostedSupabaseCrmRepository: CrmDataProviding {
    let client: SupabaseClient
    init(client: SupabaseClient = SupabaseClientProvider.shared) { self.client = client }

    private func normalizeFunctionError(_ error: Error) -> Error {
        guard case let FunctionsError.httpError(_, data) = error else { return error }
        guard let body = try? JSONDecoder().decode(FunctionErrorBody.self, from: data) else { return error }
        if body.requiresSupabaseReauthorization {
            return CrmRepositoryError.supabaseReauthorizationRequired
        }
        if let message = body.syncFailureMessages.first, !message.isEmpty {
            return CrmRepositoryError.functionMessage(message)
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
    func previewKPI(serviceId: String, title: String, prompt: String) async throws -> KPIPreview {
        struct Body: Encodable { let service_id: String; let title: String; let prompt: String }
        return try await client.functions.invoke(
            "kpi-preview",
            options: FunctionInvokeOptions(body: Body(service_id: serviceId, title: title, prompt: prompt)))
    }
    func recomputeKPI(serviceId: String, spec: KPISpec) async throws -> Double {
        struct Body: Encodable { let service_id: String; let spec: KPISpec }
        struct R: Decodable { let value: Double }
        let r: R = try await client.functions.invoke(
            "kpi-preview",
            options: FunctionInvokeOptions(body: Body(service_id: serviceId, spec: spec)))
        return r.value
    }
    func fetchKPIs(serviceId: String) async throws -> [DashboardKPIDefinition] {
        try await client.from("dashboard_kpi")
            .select("id,kind,title,prompt,spec,unit,value,position")
            .eq("service_id", value: serviceId)
            .order("position", ascending: true)
            .execute().value
    }
    func seedSystemKPIs(serviceId: String) async throws {
        struct Seed: Encodable { let service_id: String; let kind: String; let title: String; let position: Double }
        let seeds = DashboardKPIDefinition.seededSystem.map {
            Seed(service_id: serviceId, kind: $0.kind.rawValue, title: $0.title, position: $0.position)
        }
        try await client.from("dashboard_kpi").insert(seeds).execute()
    }
    func insertKPI(serviceId: String, title: String, prompt: String, spec: KPISpec, unit: String, value: Double, position: Double) async throws {
        struct NewKPI: Encodable {
            let service_id: String; let kind: String; let title: String
            let prompt: String; let spec: KPISpec; let unit: String; let value: Double; let position: Double
        }
        try await client.from("dashboard_kpi").insert(NewKPI(
            service_id: serviceId, kind: "custom", title: title,
            prompt: prompt, spec: spec, unit: unit, value: value, position: position)).execute()
    }
    func deleteKPIRow(id: String) async throws {
        try await client.from("dashboard_kpi").delete().eq("id", value: id).execute()
    }
    func renameKPIRow(id: String, title: String) async throws {
        struct Upd: Encodable { let title: String }
        try await client.from("dashboard_kpi").update(Upd(title: title)).eq("id", value: id).execute()
    }
    func updateKPIValue(id: String, value: Double) async throws {
        struct Upd: Encodable { let value: Double }
        try await client.from("dashboard_kpi").update(Upd(value: value)).eq("id", value: id).execute()
    }
    func updateKPIPosition(id: String, position: Double) async throws {
        struct Upd: Encodable { let position: Double }
        try await client.from("dashboard_kpi").update(Upd(position: position)).eq("id", value: id).execute()
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
    func connectAmplitude(projectName: String, apiKey: String, secretKey: String, region: String) async throws {
        struct B: Encodable {
            let project_name: String
            let api_key: String
            let secret_key: String
            let region: String
        }
        struct R: Decodable { let account_id: String? }
        let _: R = try await client.functions.invoke(
            "amplitude-connect",
            options: FunctionInvokeOptions(body: B(
                project_name: projectName,
                api_key: apiKey,
                secret_key: secretKey,
                region: region
            ))
        )
    }
    func connectAxiom(token: String) async throws -> [String] {
        struct B: Encodable { let token: String }
        struct R: Decodable { let account_id: String?; let datasets: [String]? }
        let r: R = try await client.functions.invoke(
            "axiom-connect",
            options: FunctionInvokeOptions(body: B(token: token))
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
    func updateServiceAmplitudeAccount(serviceId: String, accountId: String) async throws {
        struct Upd: Encodable { let amplitude_account_id: String }
        try await client.from("service")
            .update(Upd(amplitude_account_id: accountId))
            .eq("id", value: serviceId)
            .execute()
    }
    func updateServiceAxiomAccount(serviceId: String, accountId: String, dataset: String?) async throws {
        struct Upd: Encodable { let axiom_account_id: String; let axiom_dataset: String? }
        try await client.from("service")
            .update(Upd(axiom_account_id: accountId, axiom_dataset: dataset))
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
    @discardableResult
    func createService(name: String, supabaseAccountId: String, projectRef: String, projectName: String?, tables: [ServiceTableSpec], amplitudeAccountId: String?, amplitudeProjectName: String?, axiomAccountId: String?, axiomDataset: String?) async throws -> String {
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
        return created.id
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

    func fetchServiceTables(serviceId: String) async throws -> [ServiceTableInfo] {
        try await client.from("service_table")
            .select("id,source_schema,source_table,role")
            .eq("service_id", value: serviceId)
            .order("role", ascending: false)   // user_table before related
            .order("source_table", ascending: true)
            .execute().value
    }

    func addRelatedTable(serviceId: String, schema: String, table: String) async throws {
        struct NewTable: Encodable {
            let service_id: String
            let source_schema: String
            let source_table: String
            let role = "related"
            let column_map: [String: String] = ["pk": "id"]
            let cursor_column = "created_at"
            let display_columns: [String] = []
        }
        try await client.from("service_table")
            .insert(NewTable(service_id: serviceId, source_schema: schema, source_table: table))
            .execute()
    }

    func removeServiceTable(id: String) async throws {
        // mirrored_row has ON DELETE CASCADE, so the synced rows go with it.
        try await client.from("service_table").delete().eq("id", value: id).execute()
    }

    func fetchMirroredRows(serviceTableId: String, limit: Int = 500) async throws -> [MirroredRow] {
        try await client.from("mirrored_row")
            .select("id,source_pk,data")
            .eq("service_table_id", value: serviceTableId)
            .limit(limit)
            .execute().value
    }
    func fetchAIAccount() async throws -> AIAccount? {
        let rows: [AIAccount] = try await client.from("ai_account")
            .select("id,label,account_name").order("created_at").limit(1).execute().value
        return rows.first
    }
    func connectClaude(code: String, state: String?, codeVerifier: String, redirectURI: String) async throws {
        struct B: Encodable { let code: String; let state: String?; let code_verifier: String; let redirect_uri: String }
        struct R: Decodable { let account_id: String? }
        let _: R = try await client.functions.invoke(
            "ai-connect",
            options: FunctionInvokeOptions(body: B(code: code, state: state, code_verifier: codeVerifier, redirect_uri: redirectURI)))
    }
    func disconnectClaude(id: String) async throws {
        try await client.from("ai_account").delete().eq("id", value: id).execute()
    }
    func fetchChatMessages(serviceId: String) async throws -> [ChatMessage] {
        struct Row: Decodable { let role: String; let content: String }
        let rows: [Row] = try await client.from("ai_message")
            .select("role,content")
            .eq("service_id", value: serviceId)
            .order("created_at", ascending: true)
            .limit(500)
            .execute().value
        return rows.map { ChatMessage(role: $0.role == "user" ? .user : .assistant, text: $0.content) }
    }
    func saveChatMessage(serviceId: String, role: String, content: String) async throws {
        struct NewMsg: Encodable { let service_id: String; let role: String; let content: String }
        try await client.from("ai_message")
            .insert(NewMsg(service_id: serviceId, role: role, content: content))
            .execute()
    }
    func fetchServiceBrief(serviceId: String) async throws -> ServiceBrief? {
        struct Row: Decodable { let sections: BriefSections; let status: String }
        let rows: [Row] = try await client.from("service_brief")
            .select("sections,status").eq("service_id", value: serviceId).limit(1)
            .execute().value
        guard let r = rows.first else { return nil }
        return ServiceBrief(sections: r.sections, status: r.status, gaps: nil)
    }
    func synthesizeBrief(serviceId: String, document: String?, transcript: [[String: String]]?, currentSections: BriefSections?, userPrompt: String?) async throws -> ServiceBrief {
        struct Body: Encodable {
            let service_id: String
            let mode = "synthesize"
            let document: String?
            let transcript: [[String: String]]?
            let current_sections: BriefSections?
            let user_prompt: String?
        }
        do {
            return try await client.functions.invoke(
                "service-brief",
                options: FunctionInvokeOptions(body: Body(
                    service_id: serviceId, document: document, transcript: transcript,
                    current_sections: currentSections, user_prompt: userPrompt)))
        } catch {
            throw normalizeFunctionError(error)
        }
    }
    func interviewStep(serviceId: String, transcript: [[String: String]], targetSections: [String]?) async throws -> InterviewStep {
        struct Body: Encodable {
            let service_id: String
            let mode = "interview_step"
            let transcript: [[String: String]]
            let target_sections: [String]?
        }
        do {
            return try await client.functions.invoke(
                "service-brief",
                options: FunctionInvokeOptions(body: Body(
                    service_id: serviceId, transcript: transcript, target_sections: targetSections)))
        } catch {
            throw normalizeFunctionError(error)
        }
    }
    func fetchLatestRelease() async throws -> AppRelease? {
        let rows: [AppRelease] = try await client.from("app_release")
            .select("version,dmg_url,notes")
            .order("created_at", ascending: false)
            .limit(1)
            .execute().value
        return rows.first
    }
}
