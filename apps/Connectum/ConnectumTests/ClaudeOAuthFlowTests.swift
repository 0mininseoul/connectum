import XCTest
@testable import Connectum

final class ClaudeOAuthFlowTests: XCTestCase {
    func testCodeChallengeIsBase64URLSHA256() throws {
        let pkce = ClaudePKCE.generate()
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43)
        XCTAssertFalse(pkce.challenge.contains("="))
        XCTAssertFalse(pkce.challenge.contains("+"))
        XCTAssertFalse(pkce.challenge.contains("/"))
        // Deterministic S256 challenge for a known verifier.
        XCTAssertEqual(ClaudePKCE.challenge(for: "abc123"), "bKE9UspwyIPg8LsQHkJaiehiTeUdstI5JZOvaoQRgJA")
    }

    func testAuthorizeURLContainsPKCEParams() throws {
        let url = ClaudeOAuthFlow.authorizeURL(
            authorizeURL: "https://claude.ai/oauth/authorize",
            clientId: "cid", redirectURI: "http://127.0.0.1:53682/callback",
            scope: "user:inference", state: "st", codeChallenge: "chal")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(q["response_type"], "code")
        XCTAssertEqual(q["code_challenge"], "chal")
        XCTAssertEqual(q["code_challenge_method"], "S256")
        XCTAssertEqual(q["client_id"], "cid")
        XCTAssertEqual(q["redirect_uri"], "http://127.0.0.1:53682/callback")
    }
}
