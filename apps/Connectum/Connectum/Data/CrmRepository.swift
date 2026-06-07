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
}
