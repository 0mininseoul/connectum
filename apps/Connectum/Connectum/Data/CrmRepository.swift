import Foundation
import Supabase

protocol CrmDataProviding: Sendable {
    func fetchServices() async throws -> [Service]
    func fetchUsers(serviceId: String) async throws -> [CrmUser]
    func fetchEvents(crmUserId: String, limit: Int) async throws -> [CrmUserEvent]
    func setContactStatus(crmUserId: String, status: String) async throws
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
}
