import XCTest
@testable import Connectum

final class CrmModelsTests: XCTestCase {
    func testDecodeCrmUserWithAmplitudeProfile() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","source_user_id":"u1","email":"a@b.com",
         "display_name":null,"contact_status":"not_contacted",
         "amplitude_profile":{"os":"Chrome Mobile","country":"South Korea","region":"Seoul","device_family":"Android","last_event_time":"2026-06-07T12:00:00Z"},
         "ai_summary":null,"last_synced_at":null,"created_at":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let u = try JSONDecoder().decode(CrmUser.self, from: json)
        XCTAssertEqual(u.email, "a@b.com")
        XCTAssertEqual(u.contactStatus, "not_contacted")
        XCTAssertEqual(u.amplitudeProfile?.os, "Chrome Mobile")
        XCTAssertEqual(u.amplitudeProfile?.country, "South Korea")
        XCTAssertNil(u.aiSummary)
    }

    func testDecodeCrmUserWithEmptyProfile() throws {
        let json = """
        {"id":"22222222-2222-2222-2222-222222222222","source_user_id":"u2","email":null,
         "display_name":null,"contact_status":"contacted","amplitude_profile":{},
         "ai_summary":"3 line summary","last_synced_at":null,"created_at":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let u = try JSONDecoder().decode(CrmUser.self, from: json)
        XCTAssertEqual(u.contactStatus, "contacted")
        XCTAssertNil(u.amplitudeProfile?.os)
        XCTAssertEqual(u.aiSummary, "3 line summary")
    }
}
