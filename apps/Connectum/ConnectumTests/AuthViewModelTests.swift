import XCTest
@testable import Connectum

final class AuthViewModelTests: XCTestCase {
    @MainActor
    func testSuccessfulSignInSetsAuthenticated() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(())))
        vm.email = "a@b.com"; vm.password = "secret"
        await vm.signIn()
        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testFailedSignInShowsError() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .failure(AuthError.invalid)))
        vm.email = "a@b.com"; vm.password = "wrong"
        await vm.signIn()
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testEmptyFieldsBlockSignIn() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(())))
        await vm.signIn()
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNotNil(vm.errorMessage)
    }
}

enum AuthError: Error { case invalid }

// Sendable test double: `AuthProviding` is Sendable, so the fake stores a
// concrete Sendable error rather than a `Result<Void, any Error>`.
struct FakeAuth: AuthProviding {
    let result: Result<Void, AuthError>
    func signIn(email: String, password: String) async throws {
        if case .failure(let e) = result { throw e }
    }
}
