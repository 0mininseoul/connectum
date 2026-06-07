import XCTest
@testable import Connectum

final class LocalizationTests: XCTestCase {
    // The Localizable.xcstrings catalog ships inside the app (Bundle.main here).
    // Resolving the per-language .lproj sub-bundle is the reliable way to assert a
    // specific language's value at runtime — passing only `locale:` does not switch
    // the strings table when the bundle's preferred localization is the dev region.
    private func bundle(for language: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let langBundle = Bundle(path: path) else {
            return .main
        }
        return langBundle
    }

    func testKoreanLoginTitle() {
        let s = String(localized: "auth.login.title", bundle: bundle(for: "ko"))
        XCTAssertEqual(s, "로그인")
    }
    func testEnglishLoginTitle() {
        let s = String(localized: "auth.login.title", bundle: bundle(for: "en"))
        XCTAssertEqual(s, "Sign in")
    }
}
