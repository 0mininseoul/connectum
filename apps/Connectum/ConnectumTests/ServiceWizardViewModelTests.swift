import XCTest
@testable import Connectum

@MainActor
final class ServiceWizardViewModelTests: XCTestCase {
    func testSelectUserTableDefaultsUserIdColumnToUserIdWhenIdColumnIsMissing() async throws {
        let store = LocalConnectumStore(fileURL: try temporaryStoreURL())
        let repo = LocalCrmRepository(
            store: store,
            secrets: InMemorySecretStore(),
            supabaseAPI: FakeSupabaseManagementAPI(
                projects: [ProjectInfo(ref: "project-ref", name: "Acme Prod", region: "ap-northeast-2")],
                tables: [TableInfo(schema: "public", table: "user_private_profiles")],
                columns: [
                    ColumnInfo(column: "user_id", type: "uuid"),
                    ColumnInfo(column: "email", type: "text"),
                    ColumnInfo(column: "name", type: "text"),
                    ColumnInfo(column: "created_at", type: "timestamptz"),
                ],
                rowsByTable: [:]
            )
        )
        try await repo.connectSupabasePAT(pat: "sbp_test", label: "Acme Supabase")

        let vm = ServiceWizardViewModel(repo: repo)
        await vm.load()
        await vm.chooseProject("project-ref")
        await vm.selectUserTable("public.user_private_profiles")

        XCTAssertEqual(vm.userIdCol, "user_id")
        XCTAssertEqual(vm.emailCol, "email")
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("connectum-service-wizard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("store.json")
    }
}
