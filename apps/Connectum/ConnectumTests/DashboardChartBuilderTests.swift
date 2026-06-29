import XCTest
@testable import Connectum

final class DashboardChartBuilderTests: XCTestCase {
    func testBuildsCumulativeTotalUsersBySignupDate() throws {
        let users = [
            user(id: "1", status: "new", createdAt: "2026-06-01T10:00:00Z"),
            user(id: "2", status: "contacted", createdAt: "2026-06-02T11:00:00Z"),
            user(id: "3", status: "new", createdAt: "2026-06-02T12:00:00Z"),
        ]

        let points = DashboardChartBuilder.series(
            for: .totalUsers,
            metrics: DashboardMetrics(total: 3, contacted: 1, profiled: 0, recentSignups: 0),
            users: users
        )

        XCTAssertEqual(points.map(\.value), [1, 3])
        XCTAssertEqual(points.map { isoDay($0.date) }, ["2026-06-01", "2026-06-02"])
    }

    func testBuildsCumulativeContactRateBySignupDate() throws {
        let users = [
            user(id: "1", status: "contacted", createdAt: "2026-06-01T10:00:00Z"),
            user(id: "2", status: "new", createdAt: "2026-06-02T11:00:00Z"),
            user(id: "3", status: "contacted", createdAt: "2026-06-02T12:00:00Z"),
        ]

        let points = DashboardChartBuilder.series(
            for: .contactRate,
            metrics: DashboardMetrics(total: 3, contacted: 2, profiled: 0, recentSignups: 0),
            users: users
        )

        XCTAssertEqual(points.map { Int($0.value.rounded()) }, [100, 67])
        XCTAssertEqual(points.map { isoDay($0.date) }, ["2026-06-01", "2026-06-02"])
    }

    func testBuildsCumulativeSeriesFromSupabaseTimestamp() throws {
        let users = [
            user(id: "1", status: "new", createdAt: "2026-06-28 19:46:12.214321"),
            user(id: "2", status: "contacted", createdAt: "2026-06-29 13:36:27.405822"),
            user(id: "3", status: "new", createdAt: "2026-06-29 13:55:34.412345"),
        ]

        let points = DashboardChartBuilder.series(
            for: .totalUsers,
            metrics: DashboardMetrics(total: 3, contacted: 1, profiled: 0, recentSignups: 0),
            users: users
        )

        XCTAssertEqual(points.map(\.value), [1, 3])
        XCTAssertEqual(points.map { isoDay($0.date) }, ["2026-06-28", "2026-06-29"])
    }

    func testFallsBackToCurrentMetricWhenUsersHaveNoDates() throws {
        let points = DashboardChartBuilder.series(
            for: .contacted,
            metrics: DashboardMetrics(total: 3, contacted: 2, profiled: 0, recentSignups: 0),
            users: [user(id: "1", status: "contacted", createdAt: nil)]
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].value, 2)
    }

    private func user(id: String, status: String, createdAt: String?) -> CrmUser {
        CrmUser(
            id: id,
            sourceUserId: "source-\(id)",
            email: nil,
            displayName: nil,
            contactStatus: status,
            amplitudeProfile: nil,
            supabaseProfile: nil,
            aiSummary: nil,
            lastSyncedAt: nil,
            createdAt: createdAt
        )
    }

    private func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
