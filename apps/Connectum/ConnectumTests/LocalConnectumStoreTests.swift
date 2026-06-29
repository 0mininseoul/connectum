import XCTest
@testable import Connectum

final class LocalConnectumStoreTests: XCTestCase {
    func testSnapshotRoundTripsThroughJSONFile() async throws {
        let store = LocalConnectumStore(fileURL: try temporaryStoreURL())
        let service = Service(
            id: "service-1",
            name: "Acme",
            supabaseProjectRef: "project-ref",
            supabaseProjectName: "Acme Prod",
            supabaseAccountId: "account-1"
        )
        let table = LocalServiceTable(
            id: "table-1",
            serviceId: service.id,
            sourceSchema: "public",
            sourceTable: "users",
            role: "user_table",
            columnMap: ["user_id": "id", "email": "email"],
            cursorColumn: "created_at",
            displayColumns: ["email", "name"]
        )
        let user = CrmUser(
            id: "user-1",
            sourceUserId: "source-1",
            email: "youngmin@example.com",
            displayName: "Youngmin",
            contactStatus: "not_contacted",
            amplitudeProfile: nil,
            supabaseProfile: ["name": .string("Youngmin")],
            aiSummary: nil,
            lastSyncedAt: "2026-06-24T00:00:00Z",
            createdAt: "2026-06-23T00:00:00Z"
        )

        try await store.replaceSnapshot(LocalConnectumStore.Snapshot(
            services: [service],
            supabaseAccounts: [ConnAccount(id: "account-1", label: "Supabase", accountName: "Acme")],
            serviceTables: [table],
            crmUsers: [LocalCrmUserRow(serviceId: service.id, user: user)]
        ))

        let loaded = try await store.loadSnapshot()
        XCTAssertEqual(loaded.services, [service])
        XCTAssertEqual(loaded.supabaseAccounts.map(\.id), ["account-1"])
        XCTAssertEqual(loaded.serviceTables, [table])
        XCTAssertEqual(loaded.crmUsers.map(\.user), [user])
    }

    func testDeleteServiceRemovesServiceScopedData() async throws {
        let store = LocalConnectumStore(fileURL: try temporaryStoreURL())
        let repo = LocalCrmRepository(store: store, secrets: InMemorySecretStore(), supabaseAPI: FakeSupabaseManagementAPI())
        let service = Service(id: "service-1", name: "Acme", supabaseProjectRef: "project-ref", supabaseAccountId: "account-1")
        let other = Service(id: "service-2", name: "Other", supabaseProjectRef: "other-ref", supabaseAccountId: "account-1")
        let user = CrmUser(
            id: "user-1",
            sourceUserId: "source-1",
            email: nil,
            displayName: nil,
            contactStatus: "not_contacted",
            amplitudeProfile: nil,
            supabaseProfile: nil,
            aiSummary: nil,
            lastSyncedAt: nil,
            createdAt: nil
        )

        try await store.replaceSnapshot(LocalConnectumStore.Snapshot(
            services: [service, other],
            serviceTables: [
                LocalServiceTable(id: "table-1", serviceId: service.id, sourceSchema: "public", sourceTable: "users", role: "user_table", columnMap: [:], cursorColumn: "created_at", displayColumns: []),
                LocalServiceTable(id: "table-2", serviceId: other.id, sourceSchema: "public", sourceTable: "users", role: "user_table", columnMap: [:], cursorColumn: "created_at", displayColumns: []),
            ],
            crmUsers: [LocalCrmUserRow(serviceId: service.id, user: user)],
            notes: [LocalNoteBlock(id: "note-1", crmUserId: user.id, type: "text", text: "memo", position: 1)],
            kpis: [LocalKPI(serviceId: service.id, definition: .system(.totalUsers, position: 0))]
        ))

        try await repo.deleteService(serviceId: service.id)

        let loaded = try await store.loadSnapshot()
        XCTAssertEqual(loaded.services.map(\.id), [other.id])
        XCTAssertEqual(loaded.serviceTables.map(\.id), ["table-2"])
        XCTAssertTrue(loaded.crmUsers.isEmpty)
        XCTAssertTrue(loaded.notes.isEmpty)
        XCTAssertTrue(loaded.kpis.isEmpty)
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("connectum-local-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("store.json")
    }
}
