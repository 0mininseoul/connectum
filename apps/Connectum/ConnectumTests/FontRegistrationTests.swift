import XCTest
import AppKit
@testable import Connectum

// Verifies the bundled Paperlogy weights actually register at runtime (via the
// app's ATSApplicationFontsPath). If a PostScript name is wrong or the font isn't
// copied into Contents/Resources/Fonts, NSFont(name:) returns nil and this fails.
final class FontRegistrationTests: XCTestCase {
    func testPaperlogyWeightsAreRegistered() {
        for name in ["Paperlogy-4Regular", "Paperlogy-5Medium", "Paperlogy-6SemiBold"] {
            XCTAssertNotNil(NSFont(name: name, size: 16),
                            "font '\(name)' should be bundled and registered")
        }
    }
}
