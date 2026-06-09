import XCTest
@testable import Connectum

final class SupabaseOAuthFlowTests: XCTestCase {
    func testCallbackParserExtractsCodeAndState() throws {
        let request = "GET /callback?code=abc123&state=state-1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"

        let callback = try SupabaseOAuthCallbackParser.parse(request)

        XCTAssertEqual(callback.code, "abc123")
        XCTAssertEqual(callback.state, "state-1")
    }

    func testCallbackParserRejectsMismatchedPath() {
        let request = "GET /other?code=abc123&state=state-1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"

        XCTAssertThrowsError(try SupabaseOAuthCallbackParser.parse(request))
    }

    func testGeneratedStateIsURLSafeAndUnique() {
        let first = SupabaseOAuthState.generate()
        let second = SupabaseOAuthState.generate()

        XCTAssertNotEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.count, 32)
        XCTAssertNil(first.range(of: #"[^A-Za-z0-9_-]"#, options: .regularExpression))
    }

    func testGeneratedStateCanCarryLoopbackURL() {
        let state = SupabaseOAuthState.generate(
            loopbackURL: URL(string: "http://127.0.0.1:54321/callback")!
        )

        XCTAssertTrue(state.hasPrefix("connectum."))
        XCTAssertNil(state.range(of: #"[^A-Za-z0-9_.-]"#, options: .regularExpression))
    }

    func testLoopbackReceiverCancelResumesWaiter() async {
        let receiver = SupabaseOAuthLoopbackReceiver()
        let port = try! SupabaseOAuthLoopbackReceiver.availablePort()
        let expectation = expectation(description: "receiver cancellation resumes waiter")
        let task = Task {
            do {
                _ = try await receiver.waitForCallback(expectedState: "state", port: port, timeout: 30)
                XCTFail("cancelled receiver should not return a callback")
            } catch {
                expectation.fulfill()
            }
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        receiver.cancel()
        await fulfillment(of: [expectation], timeout: 1)
        task.cancel()
    }
}
