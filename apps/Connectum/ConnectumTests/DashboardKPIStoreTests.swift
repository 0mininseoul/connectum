import XCTest
@testable import Connectum

final class DashboardKPIStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DashboardKPIStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testInitialStateContainsOnlyCoreSystemKPIs() {
        let state = DashboardKPIState.initial

        XCTAssertEqual(state.items.map(\.kind), [.totalUsers, .contactRate, .contacted])
        XCTAssertEqual(state.items.map(\.title), ["전체 유저", "컨택률", "컨택 완료"])
        XCTAssertFalse(state.items.contains { $0.title == "프로필 보유" })
        XCTAssertFalse(state.items.contains { $0.title == "최근 7일 가입" })
    }

    func testStorePersistsCustomKPIAndLayoutPerService() {
        let store = DashboardKPIStore(defaults: defaults)
        let custom = DashboardKPIDefinition.custom(
            title: "활성 유저",
            prompt: "최근 30일 동안 제품 이벤트가 있는 유저 수",
            confirmation: DashboardKPIConfirmation(
                title: "활성 유저",
                summary: "최근 30일 활동 유저를 집계합니다.",
                calculationPlan: "crm_user_event에서 최근 30일 이벤트가 있는 고유 유저를 계산합니다.",
                chartPlan: "날짜별 고유 활성 유저 수를 표시합니다.",
                warnings: []
            )
        )
        let state = DashboardKPIState(items: [
            custom,
            DashboardKPIDefinition.system(.totalUsers),
            DashboardKPIDefinition.system(.contactRate),
            DashboardKPIDefinition.system(.contacted),
        ])

        store.save(state, serviceId: "service-a")

        let loaded = store.load(serviceId: "service-a")
        XCTAssertEqual(loaded.items.map(\.id), state.items.map(\.id))
        XCTAssertEqual(loaded.items.first?.title, "활성 유저")
        XCTAssertEqual(loaded.items.first?.prompt, "최근 30일 동안 제품 이벤트가 있는 유저 수")
        XCTAssertEqual(loaded.items.first?.confirmation?.calculationPlan, "crm_user_event에서 최근 30일 이벤트가 있는 고유 유저를 계산합니다.")
        XCTAssertEqual(store.load(serviceId: "service-b").items.map(\.kind), [.totalUsers, .contactRate, .contacted])
    }

    func testStorePersistsDeletedCards() {
        let store = DashboardKPIStore(defaults: defaults)
        let state = DashboardKPIState(items: [
            DashboardKPIDefinition.system(.totalUsers),
            DashboardKPIDefinition.system(.contacted),
        ])

        store.save(state, serviceId: "service-a")

        let loaded = store.load(serviceId: "service-a")
        XCTAssertEqual(loaded.items.map(\.kind), [.totalUsers, .contacted])
        XCTAssertFalse(loaded.items.contains { $0.kind == .contactRate })
    }
}
