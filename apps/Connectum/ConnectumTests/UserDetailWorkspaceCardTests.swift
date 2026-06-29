import XCTest
@testable import Connectum

final class UserDetailWorkspaceCardTests: XCTestCase {
    func testDecodedOrderDropsUnknownCardsAndAppendsMissingDefaults() {
        let raw = #"["notes","unknown","aiSummary"]"#

        let order = UserDetailWorkspaceCard.decodedOrder(from: raw)

        XCTAssertEqual(order, [.notes, .aiSummary, .contactRecords, .profile, .recentEvents])
    }

    func testMovePersistsValidEncodedOrder() {
        var order = UserDetailWorkspaceCard.defaultOrder

        UserDetailWorkspaceCard.move(&order, from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(order, [.contactRecords, .notes, .aiSummary, .profile, .recentEvents])
        XCTAssertEqual(
            UserDetailWorkspaceCard.encoded(order),
            #"["contactRecords","notes","aiSummary","profile","recentEvents"]"#
        )
    }

    func testReorderedTowardLaterTargetPlacesCardAfterTarget() {
        let order = UserDetailWorkspaceCard.defaultOrder

        let reordered = UserDetailWorkspaceCard.reordered(order, moving: .aiSummary, to: .notes)

        XCTAssertEqual(reordered, [.contactRecords, .notes, .aiSummary, .profile, .recentEvents])
    }

    func testReorderedTowardEarlierTargetPlacesCardBeforeTarget() {
        let order = UserDetailWorkspaceCard.defaultOrder

        let reordered = UserDetailWorkspaceCard.reordered(order, moving: .profile, to: .contactRecords)

        XCTAssertEqual(reordered, [.aiSummary, .profile, .contactRecords, .notes, .recentEvents])
    }
}
