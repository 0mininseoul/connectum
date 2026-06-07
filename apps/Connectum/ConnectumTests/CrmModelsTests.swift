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

    func testDecodeChannelRecordRow() throws {
        let json = """
        {"id":"33333333-3333-3333-3333-333333333333",
         "content":{"channel":"email","occurred_at":"2026-06-01","body":"온보딩 안내 메일 발송"}}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(PageBlockRow.self, from: json)
        let rec = row.asChannelRecord
        XCTAssertEqual(rec.id, "33333333-3333-3333-3333-333333333333")
        XCTAssertEqual(rec.channel, "email")
        XCTAssertEqual(rec.occurredAt, "2026-06-01")
        XCTAssertEqual(rec.body, "온보딩 안내 메일 발송")
    }

    func testDecodeHistoryEntry() throws {
        let json = """
        {"id":"44444444-4444-4444-4444-444444444444","entry_date":"2026-06-01","image_url":"https://x/y.jpg","memo":"인터뷰 메모"}
        """.data(using: .utf8)!
        let e = try JSONDecoder().decode(HistoryEntry.self, from: json)
        XCTAssertEqual(e.entryDate, "2026-06-01")
        XCTAssertEqual(e.imageUrl, "https://x/y.jpg")
        XCTAssertEqual(e.memo, "인터뷰 메모")
    }

    func testDecodeSavedView() throws {
        let json = """
        {"id":"55555555-5555-5555-5555-555555555555","name":"미컨택만",
         "config":{"contactFilter":"not_contacted","profiledOnly":true,"sortKey":"email","sortAsc":true}}
        """.data(using: .utf8)!
        let v = try JSONDecoder().decode(SavedView.self, from: json)
        XCTAssertEqual(v.name, "미컨택만")
        XCTAssertEqual(v.config.contactFilter, "not_contacted")
        XCTAssertTrue(v.config.profiledOnly)
        XCTAssertEqual(v.config.sortKey, "email")
    }
}
