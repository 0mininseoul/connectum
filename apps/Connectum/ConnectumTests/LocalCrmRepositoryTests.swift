import XCTest
@testable import Connectum

struct FakeSupabaseManagementAPI: SupabaseManagementAPIProviding {
    var projects: [ProjectInfo] = [ProjectInfo(ref: "project-ref", name: "Acme Prod", region: "ap-northeast-2")]
    var tables: [TableInfo] = [TableInfo(schema: "public", table: "users")]
    var columns: [ColumnInfo] = [
        ColumnInfo(column: "id", type: "uuid"),
        ColumnInfo(column: "email", type: "text"),
        ColumnInfo(column: "name", type: "text"),
        ColumnInfo(column: "created_at", type: "timestamptz"),
    ]
    var rowsByTable: [String: [[String: JSONScalar]]] = [
        "public.users": [
            [
                "id": .string("source-1"),
                "email": .string("youngmin@example.com"),
                "name": .string("Youngmin"),
                "created_at": .string("2026-06-23T00:00:00Z"),
            ],
            [
                "id": .string("source-2"),
                "email": .string("team@example.com"),
                "name": .string("Team"),
                "created_at": .string("2026-06-24T00:00:00Z"),
            ],
        ]
    ]

    func listProjects(token: String) async throws -> [ProjectInfo] {
        projects
    }

    func listTables(token: String, projectRef: String) async throws -> [TableInfo] {
        tables
    }

    func listColumns(token: String, projectRef: String, schema: String, table: String) async throws -> [ColumnInfo] {
        columns
    }

    func readRows(token: String, projectRef: String, schema: String, table: String, cursorColumn: String?, limit: Int) async throws -> [[String: JSONScalar]] {
        Array((rowsByTable["\(schema).\(table)"] ?? []).prefix(limit))
    }
}

struct FakeClaudeOAuthAPI: ClaudeOAuthAPIProviding {
    var exchanged = ClaudeOAuthTokens(
        accessToken: "access-token",
        refreshToken: "refresh-token",
        expiresAt: "2099-01-01T00:00:00Z"
    )
    var refreshed = ClaudeOAuthTokens(
        accessToken: "new-access-token",
        refreshToken: "new-refresh-token",
        expiresAt: "2099-01-02T00:00:00Z"
    )

    func exchangeCode(code: String, state: String?, codeVerifier: String, redirectURI: String, clientId: String) async throws -> ClaudeOAuthTokens {
        exchanged
    }

    func refresh(refreshToken: String, clientId: String) async throws -> ClaudeOAuthTokens {
        refreshed
    }
}

struct FakeSupabaseOAuthAPI: SupabaseOAuthAPIProviding {
    var tokens = SupabaseOAuthTokens(
        accessToken: "oauth-access-token",
        refreshToken: "oauth-refresh-token",
        expiresAt: "2099-01-01T00:00:00Z",
        accountName: "Youngmin Supabase"
    )

    func authorizeURL(state: String) async throws -> URL {
        URL(string: "https://api.supabase.com/v1/oauth/authorize?state=\(state)")!
    }

    func exchangeCode(code: String, state: String) async throws -> SupabaseOAuthTokens {
        tokens
    }

    func refresh(refreshToken: String) async throws -> SupabaseOAuthTokens {
        tokens
    }
}

final class LocalCrmRepositoryTests: XCTestCase {
    func testConnectCreateSyncAndComputeLocalData() async throws {
        let store = LocalConnectumStore(fileURL: try temporaryStoreURL())
        let repo = LocalCrmRepository(
            store: store,
            secrets: InMemorySecretStore(),
            supabaseAPI: FakeSupabaseManagementAPI()
        )

        try await repo.connectSupabasePAT(pat: "sbp_test", label: "Acme Supabase")
        let accounts = try await repo.fetchSupabaseAccounts()
        let account = try XCTUnwrap(accounts.first)
        let projects = try await repo.listProjects(supabaseAccountId: account.id)
        XCTAssertEqual(projects.map(\.ref), ["project-ref"])

        let serviceId = try await repo.createService(
            name: "Acme",
            supabaseAccountId: account.id,
            projectRef: "project-ref",
            projectName: "Acme Prod",
            tables: [
                ServiceTableSpec(
                    schema: "public",
                    table: "users",
                    role: "user_table",
                    userIdCol: "id",
                    emailCol: "email",
                    displayColumns: ["name"]
                )
            ],
            amplitudeAccountId: nil,
            amplitudeProjectName: nil,
            axiomAccountId: nil,
            axiomDataset: nil
        )

        try await repo.syncService(serviceId: serviceId)

        var users = try await repo.fetchUsers(serviceId: serviceId)
        XCTAssertEqual(users.map(\.sourceUserId).sorted(), ["source-1", "source-2"])
        XCTAssertEqual(users.first { $0.sourceUserId == "source-1" }?.email, "youngmin@example.com")
        let displayColumns = try await repo.fetchDisplayColumns(serviceId: serviceId)
        XCTAssertEqual(displayColumns, ["name"])

        let firstUser = try XCTUnwrap(users.first { $0.sourceUserId == "source-1" })
        try await repo.setContactStatus(crmUserId: firstUser.id, status: "contacted")
        users = try await repo.fetchUsers(serviceId: serviceId)
        XCTAssertEqual(users.first { $0.sourceUserId == "source-1" }?.contactStatus, "contacted")

        let metrics = try await repo.fetchMetrics(serviceId: serviceId)
        XCTAssertEqual(metrics.total, 2)
        XCTAssertEqual(metrics.contacted, 1)

        let preview = try await repo.previewKPI(serviceId: serviceId, title: "컨택률", prompt: "contact rate")
        XCTAssertEqual(preview.unit, "percent")
        XCTAssertEqual(Int(preview.value.rounded()), 50)
    }

    func testSyncFallsBackToUserIdWhenConfiguredIdColumnIsMissing() async throws {
        let store = LocalConnectumStore(fileURL: try temporaryStoreURL())
        let repo = LocalCrmRepository(
            store: store,
            secrets: InMemorySecretStore(),
            supabaseAPI: FakeSupabaseManagementAPI(
                tables: [TableInfo(schema: "public", table: "user_private_profiles")],
                columns: [
                    ColumnInfo(column: "user_id", type: "uuid"),
                    ColumnInfo(column: "email", type: "text"),
                    ColumnInfo(column: "created_at", type: "timestamptz"),
                ],
                rowsByTable: [
                    "public.user_private_profiles": [
                        [
                            "user_id": .string("source-1"),
                            "email": .string("youngmin@example.com"),
                            "created_at": .string("2026-06-24T00:00:00Z"),
                        ],
                    ],
                ]
            )
        )

        try await repo.connectSupabasePAT(pat: "sbp_test", label: "Acme Supabase")
        let accounts = try await repo.fetchSupabaseAccounts()
        let account = try XCTUnwrap(accounts.first)
        let serviceId = try await repo.createService(
            name: "Acme",
            supabaseAccountId: account.id,
            projectRef: "project-ref",
            projectName: "Acme Prod",
            tables: [
                ServiceTableSpec(
                    schema: "public",
                    table: "user_private_profiles",
                    role: "user_table",
                    userIdCol: "id",
                    emailCol: "email",
                    displayColumns: ["email"]
                )
            ],
            amplitudeAccountId: nil,
            amplitudeProjectName: nil,
            axiomAccountId: nil,
            axiomDataset: nil
        )

        try await repo.syncService(serviceId: serviceId)

        let users = try await repo.fetchUsers(serviceId: serviceId)
        XCTAssertEqual(users.map(\.sourceUserId), ["source-1"])
    }

    func testClaudeOAuthStoresLocalAIAccount() async throws {
        let secrets = InMemorySecretStore()
        let repo = LocalCrmRepository(
            store: LocalConnectumStore(fileURL: try temporaryStoreURL()),
            secrets: secrets,
            supabaseAPI: FakeSupabaseManagementAPI(),
            claudeOAuthAPI: FakeClaudeOAuthAPI()
        )

        try await repo.connectClaude(code: "code", state: "state", codeVerifier: "verifier", redirectURI: ClaudeOAuthFlow.manualRedirectURI)
        let connectedAccount = try await repo.fetchAIAccount()
        let account = try XCTUnwrap(connectedAccount)

        XCTAssertEqual(account.label, "Claude")
        XCTAssertNotNil(try secrets.read("claude_oauth_access:\(account.id)"))
        XCTAssertNotNil(try secrets.read("claude_oauth_refresh:\(account.id)"))

        try await repo.disconnectClaude(id: account.id)
        let disconnectedAccount = try await repo.fetchAIAccount()
        XCTAssertNil(disconnectedAccount)
        XCTAssertNil(try secrets.read("claude_oauth_access:\(account.id)"))
        XCTAssertNil(try secrets.read("claude_oauth_refresh:\(account.id)"))
    }

    func testSupabaseOAuthStoresTokensLocally() async throws {
        let secrets = InMemorySecretStore()
        let repo = LocalCrmRepository(
            store: LocalConnectumStore(fileURL: try temporaryStoreURL()),
            secrets: secrets,
            supabaseAPI: FakeSupabaseManagementAPI(),
            supabaseOAuthAPI: FakeSupabaseOAuthAPI()
        )

        let authorizeURL = try await repo.supabaseOAuthAuthorizeURL(state: "state")
        XCTAssertEqual(authorizeURL.host, "api.supabase.com")

        try await repo.connectSupabaseOAuth(code: "code", state: "state")
        let accounts = try await repo.fetchSupabaseAccounts()
        let account = try XCTUnwrap(accounts.first)

        XCTAssertEqual(account.label, "Youngmin Supabase")
        XCTAssertNotNil(try secrets.read("supabase_oauth_access:\(account.id)"))
        XCTAssertNotNil(try secrets.read("supabase_oauth_refresh:\(account.id)"))
        let projectRefs = try await repo.listProjects(supabaseAccountId: account.id).map(\.ref)
        XCTAssertEqual(projectRefs, ["project-ref"])
    }

    func testSupabaseOAuthDoesNotUseProjectNameAsAccountName() async throws {
        let repo = LocalCrmRepository(
            store: LocalConnectumStore(fileURL: try temporaryStoreURL()),
            secrets: InMemorySecretStore(),
            supabaseAPI: FakeSupabaseManagementAPI(projects: [
                ProjectInfo(ref: "archy-ref", name: "Archy", region: "ap-northeast-2")
            ]),
            supabaseOAuthAPI: FakeSupabaseOAuthAPI(tokens: SupabaseOAuthTokens(
                accessToken: "oauth-access-token",
                refreshToken: "oauth-refresh-token",
                expiresAt: "2099-01-01T00:00:00Z",
                accountName: nil
            ))
        )

        try await repo.connectSupabaseOAuth(code: "code", state: "state")
        let accounts = try await repo.fetchSupabaseAccounts()
        let account = try XCTUnwrap(accounts.first)

        XCTAssertEqual(account.label, "Supabase")
        XCTAssertNil(account.accountName)
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("connectum-local-repo-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("store.json")
    }
}
