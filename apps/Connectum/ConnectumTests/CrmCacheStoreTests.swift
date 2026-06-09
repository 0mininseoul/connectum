import XCTest
@testable import Connectum

final class CrmCacheStoreTests: XCTestCase {
    func testStoresAndLoadsOperationalDBSnapshot() throws {
        let store = CrmCacheStore(rootURL: try temporaryDirectory())
        let user = CrmUser(
            id: "user-1",
            sourceUserId: "source-1",
            email: "youngmin@example.com",
            displayName: nil,
            contactStatus: "not_contacted",
            amplitudeProfile: nil,
            supabaseProfile: ["name": .string("Youngmin")],
            aiSummary: "가입 후 핵심 액션을 완료했습니다.",
            lastSyncedAt: "2026-06-08T05:00:00Z",
            createdAt: "2026-06-08T04:00:00Z"
        )
        let view = SavedView(
            id: "view-1",
            name: "이름 기준",
            config: ViewConfig(primaryColumn: "name")
        )
        let snapshot = OperationalDBCacheSnapshot(
            serviceId: "service-1",
            cachedAt: Date(timeIntervalSince1970: 1_800_000_000),
            users: [user],
            savedViews: [view],
            displayColumns: ["name", "email"]
        )

        try store.saveOperationalDB(snapshot)

        let loaded = try XCTUnwrap(store.loadOperationalDB(serviceId: "service-1"))
        XCTAssertEqual(loaded.serviceId, "service-1")
        XCTAssertEqual(loaded.cachedAt, snapshot.cachedAt)
        XCTAssertEqual(loaded.users, [user])
        XCTAssertEqual(loaded.savedViews, [view])
        XCTAssertEqual(loaded.displayColumns, ["name", "email"])
    }

    func testStoresAndLoadsDashboardMetricsSnapshot() throws {
        let store = CrmCacheStore(rootURL: try temporaryDirectory())
        let snapshot = DashboardMetricsCacheSnapshot(
            serviceId: "service-2",
            cachedAt: Date(timeIntervalSince1970: 1_800_000_100),
            metrics: DashboardMetrics(total: 10, contacted: 4, profiled: 7, recentSignups: 3)
        )

        try store.saveDashboardMetrics(snapshot)

        let loaded = try XCTUnwrap(store.loadDashboardMetrics(serviceId: "service-2"))
        XCTAssertEqual(loaded.serviceId, "service-2")
        XCTAssertEqual(loaded.cachedAt, snapshot.cachedAt)
        XCTAssertEqual(loaded.metrics, snapshot.metrics)
    }

    func testRemoveServiceClearsOperationalAndDashboardSnapshots() throws {
        let store = CrmCacheStore(rootURL: try temporaryDirectory())
        try store.saveOperationalDB(OperationalDBCacheSnapshot(
            serviceId: "service-3",
            cachedAt: Date(),
            users: [],
            savedViews: [],
            displayColumns: []
        ))
        try store.saveDashboardMetrics(DashboardMetricsCacheSnapshot(
            serviceId: "service-3",
            cachedAt: Date(),
            metrics: DashboardMetrics(total: 1, contacted: 0, profiled: 0, recentSignups: 1)
        ))

        try store.removeService(serviceId: "service-3")

        XCTAssertNil(try store.loadOperationalDB(serviceId: "service-3"))
        XCTAssertNil(try store.loadDashboardMetrics(serviceId: "service-3"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("connectum-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
