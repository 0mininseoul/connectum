import XCTest
import SwiftUI
@testable import Connectum

final class DesignTokenTests: XCTestCase {
    func testCanvasHexMatchesRaycast() {
        XCTAssertEqual(Palette.canvas.hexString, "07080A")
    }
    func testSurfaceLadderIsDistinct() {
        let ladder = [Palette.canvas, Palette.surface, Palette.surfaceElevated, Palette.surfaceCard]
        let hexes = Set(ladder.map { $0.hexString })
        XCTAssertEqual(hexes.count, 4, "surface ladder steps must be distinct")
    }
    func testSpacingBaseIsEightPointScale() {
        XCTAssertEqual(Spacing.sm, 8)
        XCTAssertEqual(Spacing.xl, 24)
    }
    func testRadiusScale() {
        XCTAssertEqual(Radius.button, 8)
        XCTAssertEqual(Radius.card, 10)
    }
}
