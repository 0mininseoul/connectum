import XCTest
import SwiftUI
import AppKit
@testable import Connectum

final class DesignTokenTests: XCTestCase {
    func testCanvasHexMatchesThemes() {
        XCTAssertEqual(Palette.canvas.hexString(appearance: .darkAqua), "07080A")
        XCTAssertEqual(Palette.canvas.hexString(appearance: .aqua), "F5F6F8")
    }

    func testSurfaceLadderIsDistinctInBothThemes() {
        let ladder = [Palette.canvas, Palette.surface, Palette.surfaceElevated, Palette.surfaceCard]
        let darkHexes = Set(ladder.map { $0.hexString(appearance: .darkAqua) })
        let lightHexes = Set(ladder.map { $0.hexString(appearance: .aqua) })
        XCTAssertEqual(darkHexes.count, 4, "dark surface ladder steps must be distinct")
        XCTAssertEqual(lightHexes.count, 2, "light surface ladder should keep canvas distinct from card surfaces")
    }

    func testCTAContrastFlipsWithTheme() {
        XCTAssertEqual(Palette.ctaFill.hexString(appearance: .darkAqua), "FFFFFF")
        XCTAssertEqual(Palette.ctaText.hexString(appearance: .darkAqua), "000000")
        XCTAssertEqual(Palette.ctaFill.hexString(appearance: .aqua), "111315")
        XCTAssertEqual(Palette.ctaText.hexString(appearance: .aqua), "FFFFFF")
    }

    func testSpacingBaseIsEightPointScale() {
        XCTAssertEqual(Spacing.sm, 8)
        XCTAssertEqual(Spacing.xl, 24)
    }
    func testRadiusScale() {
        XCTAssertEqual(Radius.button, 8)
        XCTAssertEqual(Radius.card, 8)
    }
}
